"""Experimental Mac screen-control endpoint; camera configuration is read first.

The control framing is captured. Soliciting a fresh conversation from an
arbitrary endpoint is experimental and must receive a valid reply before use.
Uses the original KCP C library (path supplied by caller), not a capture replayer.
"""
from __future__ import annotations

import asyncio
import copy
import ctypes as C
import json
from pathlib import Path
import secrets
import struct
import time

from luna_screen_wire import Envelope, decode_envelope, decode_kcp_datagram, decode_rpc


def encode_datagram(payload: bytes) -> bytes:
    if len(payload) > 65535:
        raise ValueError("Datagram too large for the phone UDP pipe")
    return struct.pack('>I', len(payload)) + payload


def decode_datagrams(buffer: bytearray) -> list[bytes]:
    out: list[bytes] = []
    while len(buffer) >= 4:
        size = struct.unpack_from('>I', buffer)[0]
        if size > 65535:
            raise ValueError("Datagram too large for the phone UDP pipe")
        if len(buffer) < 4 + size:
            break
        out.append(bytes(buffer[4:4 + size]))
        del buffer[:4 + size]
    return out


def read_configuration(body: bytes) -> tuple[dict, bytes]:
    if len(body) < 16:
        raise ValueError("Truncated configuration response")
    result, size = struct.unpack_from('<II', body)
    if result != 0 or len(body) != 16 + size:
        raise ValueError("Rejected or malformed configuration response")
    config = json.loads(body[8:8+size])
    if not isinstance(config, dict):
        raise ValueError("Configuration is not an object")
    return config, body[-8:]


def recovery_state(config: dict) -> bool:
    if config.get('iq_color_mode', {}).get('color_mode') != 'kIlog':
        raise ValueError("Camera must already be in I-Log")
    lut = config.get('iq_ilog_lut', {})
    enabled = lut.get('enable')
    if type(enabled) is not bool:
        raise ValueError("Unknown camera recovery state")
    expected = 'kILogStandard' if enabled else 'kStandard'
    if lut.get('lut_type') != expected:
        raise ValueError("Unrecognized camera LUT combination")
    return enabled


def replacement(config: dict, token: bytes, enabled: bool) -> tuple[dict, bytes]:
    recovery_state(config)
    if type(enabled) is not bool or len(token) != 8:
        raise ValueError("Invalid recovery request")
    updated = copy.deepcopy(config)
    updated['iq_ilog_lut']['enable'] = enabled
    updated['iq_ilog_lut']['lut_type'] = 'kILogStandard' if enabled else 'kStandard'
    encoded = json.dumps(updated, separators=(',', ':'), ensure_ascii=False).encode()
    return updated, token + struct.pack('<I', len(encoded)) + encoded


class KCP:
    def __init__(self, library: Path, conversation: int, output):
        lib = self.lib = C.CDLL(str(library))
        self.callback_type = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_int, C.c_void_p, C.c_void_p)
        signatures = {
            'ikcp_create': ([C.c_uint32, C.c_void_p], C.c_void_p),
            'ikcp_release': ([C.c_void_p], None),
            'ikcp_setoutput': ([C.c_void_p, self.callback_type], None),
            'ikcp_nodelay': ([C.c_void_p,C.c_int,C.c_int,C.c_int,C.c_int], C.c_int),
            'ikcp_wndsize': ([C.c_void_p,C.c_int,C.c_int], C.c_int),
            'ikcp_update': ([C.c_void_p,C.c_uint32], None),
            'ikcp_send': ([C.c_void_p,C.c_void_p,C.c_int], C.c_int),
            'ikcp_input': ([C.c_void_p,C.c_void_p,C.c_long], C.c_int),
            'ikcp_peeksize': ([C.c_void_p], C.c_int),
            'ikcp_recv': ([C.c_void_p,C.c_void_p,C.c_int], C.c_int),
        }
        for name,(args,ret) in signatures.items():
            fn = getattr(lib,name); fn.argtypes=args; fn.restype=ret
        self.pointer = lib.ikcp_create(conversation,None)
        if not self.pointer:
            raise MemoryError('KCP allocation failed')
        self.output = self.callback_type(lambda p,n,k,u: (output(C.string_at(p,n)),0)[1])
        lib.ikcp_setoutput(self.pointer,self.output)
        lib.ikcp_nodelay(self.pointer,1,20,2,1)
        lib.ikcp_wndsize(self.pointer,256,256)
        self.conversation=conversation
        self.peer_una=0

    def jump_send(self, nxt: int):
        """If the camera is resuming a conversation, skip to its next expected send sequence."""
        if not self.pointer or nxt <= 0:
            return
        fields = C.cast(self.pointer, C.POINTER(C.c_uint32))
        snd_nxt = fields[5]
        if nxt > snd_nxt:
            fields[4] = nxt
            fields[5] = nxt

    def jump_recv(self, nxt: int):
        """Accept a resumed conversation's incoming sequence.

        Mirror of jump_send: the camera also resumes its own send sequence, so a
        fresh endpoint expecting zero would discard its replies as far-future
        segments and never deliver them to the application.
        """
        if not self.pointer or nxt <= 0:
            return
        fields = C.cast(self.pointer, C.POINTER(C.c_uint32))
        if fields[6] == 0 or nxt > fields[6]:
            fields[6] = nxt

    def update(self):
        self.lib.ikcp_update(self.pointer,int(time.monotonic()*1000)&0xffffffff)

    def send(self,data):
        if self.lib.ikcp_send(self.pointer,data,len(data)) < 0:
            raise ValueError('KCP send rejected')

    def input(self,data):
        if self.lib.ikcp_input(self.pointer,data,len(data)) < 0:
            raise ValueError('KCP input rejected')
        messages=[]
        while (size:=self.lib.ikcp_peeksize(self.pointer)) >= 0:
            if size > 1024*1024:
                raise ValueError('Oversized control response')
            buf=C.create_string_buffer(max(size,1))
            count=self.lib.ikcp_recv(self.pointer,buf,size)
            if count<0: break
            messages.append(buf.raw[:count])
        return messages

    def close(self):
        if self.pointer:
            self.lib.ikcp_release(self.pointer); self.pointer=None


class ScreenMedia(asyncio.DatagramProtocol):
    """Answer the camera's media-channel bootstrap.

    A real screen answers the camera on the media port pair as well as the
    control pair, within milliseconds, and keeps a KCP endpoint per media
    conversation. A control-only client leaves that unanswered, and the camera
    then repeats its hello about once a second instead of about every thirty.
    This responder exists to complete bring-up; it does not decode media.
    """

    def __init__(self, library: Path, log, peer=('192.168.42.1', 6002)):
        self.library = library
        self.log = log
        self.peer = peer
        self.transport = None
        self.kcps: dict[int, KCP] = {}
        self.hellos = 0
        self.conversations: list[int] = []

    def connection_made(self, transport):
        self.transport = transport

    def error_received(self, error):
        self.log('ERR', repr(error).encode())

    def send_udp(self, data):
        self.log('MTX', data)
        if self.transport is not None:
            self.transport.sendto(data, self.peer)

    def datagram_received(self, data, addr):
        if addr != self.peer:
            return
        self.log('MRX', data)
        try:
            if len(data) == 25 and data[:1] == b'\x02':
                envelope = decode_envelope(data)
                if envelope.kind != 2 or len(envelope.payload) != 13:
                    return
                flag, transaction, conversation, tail = struct.unpack('<BIII', envelope.payload)
                if flag != 0:
                    return
                self.hellos += 1
                # ponytail: captured screen answered camera tail 9 with 8 on this
                # channel; fall back through neighbours if the camera repeats.
                offsets = (1, 2, 0, 3)
                reply_tail = max(0, tail - offsets[(self.hellos - 1) % len(offsets)])
                self.send_udp(Envelope(
                    2, 0x0800, 0,
                    struct.pack('<BIII', 1, transaction, conversation, reply_tail)).encode())
                if conversation not in self.kcps:
                    kcp = KCP(self.library, conversation, self.send_udp)
                    kcp.update()
                    self.kcps[conversation] = kcp
                    self.conversations.append(conversation)
                return
            if len(data) < 24:
                return
            conversation = struct.unpack_from('<I', data)[0]
            kcp = self.kcps.get(conversation)
            if kcp is None:
                return
            kcp.input(data)          # drains and lets KCP queue transport ACKs
        except (ValueError, struct.error):
            return

    async def pump(self):
        while True:
            for kcp in list(self.kcps.values()):
                kcp.update()
            await asyncio.sleep(.01)

    async def listen(self, local_ip='0.0.0.0', local_port=6023):
        await asyncio.get_running_loop().create_datagram_endpoint(
            lambda: self, local_addr=(local_ip, local_port))
        self.task = asyncio.create_task(self.pump())


class ScreenControl(asyncio.DatagramProtocol):
    def __init__(self, library: Path, log, generation=8):
        self.library=library; self.log=log; self.transport=None; self.kcp=None
        self.pending={}; self.ready=asyncio.Event(); self.identifier=secrets.randbelow(0x1000000)
        self.peer=('192.168.42.1',6000); self.failure=None; self.lock=asyncio.Lock()
        self.proposal=None
        self.generation=generation
        self.app_seen=asyncio.Event()
        self.reader=None
        self.writer=None
        self.proxy_task=None
        self.last_kind2=0.0
        self.kind2_replies=0
        # Captured screen reply tails were 3, 4, 8 against camera 4, 6, 10.
        # Current camera hello uses 12; try that family, not a single guess.
        self.tail_candidates=(10, 8, 12, 11, 9, 6, 4, 3, 2, 1, 0, 14, 16)
        self.accepted_tail=None

    def connection_made(self,transport): self.transport=transport
    def error_received(self,error): self.failure=error

    def direct(self,flag,transaction,conversation,tail):
        self.send_udp(Envelope(2,0x0800,0,struct.pack('<BIII',flag,transaction,conversation,tail)).encode())

    def send_udp(self,data):
        self.log('TX',data)
        if self.writer is not None:
            self.writer.write(encode_datagram(data))
            return
        self.transport.sendto(data,self.peer)

    def adopt(self,conversation):
        if self.kcp and self.kcp.conversation != conversation:
            self.failure=ConnectionError('Camera changed control session')
            return
        if not self.kcp:
            self.kcp=KCP(self.library,conversation,self.send_udp)
            self.kcp.update()
            self.ready.set()

    def datagram_received(self,data,addr):
        if addr != self.peer: return
        self.log('RX',data)
        try:
            if len(data)==25 and data[:1] == b'\x02':
                envelope=decode_envelope(data)
                if envelope.kind != 2 or len(envelope.payload)!=13: return
                flag,transaction,conv,tail=struct.unpack('<BIII',envelope.payload)
                if flag == 0:
                    self.last_kind2=time.monotonic()
                    reply_tail=self.tail_candidates[self.kind2_replies % len(self.tail_candidates)]
                    self.kind2_replies += 1
                    self.direct(1,transaction,conv,reply_tail)
                    self.adopt(conv)
                    self.accepted_tail=reply_tail
                elif flag == 1 and self.proposal == (transaction,conv):
                    self.adopt(conv)
                return
            if not self.kcp:return
            try:
                for segment in decode_kcp_datagram(data):
                    if segment.next_unacknowledged > self.kcp.peer_una:
                        self.kcp.peer_una = segment.next_unacknowledged
                    if segment.command == 81 and not self.app_seen.is_set():
                        # Resumed inbound stream: adopt the camera's sequence once.
                        self.kcp.jump_recv(segment.sequence)
                if self.kcp.peer_una:
                    self.kcp.jump_send(self.kcp.peer_una)
            except ValueError:
                pass
            for raw in self.kcp.input(data):
                env=decode_envelope(raw);rpc=decode_rpc(env)
                key=(rpc.service,rpc.method,rpc.identifier,env.source,env.destination)
                pending=self.pending.get(key)
                self.app_seen.set()
                if rpc.category==2 and pending is not None and not pending.done():
                    pending.set_result(rpc.body)
                elif (env.source,env.destination,rpc.service,rpc.method,rpc.category,rpc.body)==(0x07fc,0x0bfb,4,4,0,b''):
                    # Captured clock-query reply shape; local monotonic origin is
                    # experimental, never a fabricated command success reply.
                    body=struct.pack('<IQ',0,time.monotonic_ns())
                    payload=struct.pack('<BHHBI',1,4,4,2,rpc.identifier)+body
                    self.kcp.send(Envelope(0,env.destination,env.source,payload).encode())
        except (ValueError,struct.error):
            # Ignore damaged/unrelated datagrams; never turn them into success.
            return

    async def pump(self):
        while True:
            if self.failure: raise self.failure
            if self.kcp:self.kcp.update()
            await asyncio.sleep(.01)

    async def read_proxy(self):
        buffer = bytearray()
        try:
            while True:
                chunk = await self.reader.read(65536)
                if not chunk:
                    self.failure = ConnectionError('UDP pipe closed')
                    return
                buffer.extend(chunk)
                for datagram in decode_datagrams(buffer):
                    self.datagram_received(datagram, self.peer)
        except Exception as error:
            self.failure = error

    async def connect(self,local_port=6021,solicit=False,local_ip='0.0.0.0',proxy=None,listen_seconds=3):
        if proxy:
            host, port = proxy
            self.reader, self.writer = await asyncio.open_connection(host, port)
            self.proxy_task = asyncio.create_task(self.read_proxy())
        else:
            await asyncio.get_running_loop().create_datagram_endpoint(lambda:self,local_addr=(local_ip,local_port))
        self.task=asyncio.create_task(self.pump())
        if solicit == 'auto':
            try:
                await asyncio.wait_for(self.ready.wait(), listen_seconds)
                return
            except asyncio.TimeoutError:
                solicit = True
        if solicit:
            self.proposal=(secrets.randbelow(0x1000000)+1,secrets.randbelow(0xfffffffe)+1)
            self.direct(0,*self.proposal,self.generation)
        await asyncio.wait_for(self.ready.wait(),4)
        # Kind-2 retries mean the camera rejected the previous reply tail.
        # Wait until hellos stop, or until we have cycled the captured family.
        deadline=time.monotonic()+8
        while time.monotonic() < deadline:
            quiet=time.monotonic()-self.last_kind2
            if self.last_kind2 and quiet >= 1.2:
                break
            await asyncio.sleep(0.1)

    async def prime(self, timeout=4.0):
        """Learn the camera's expected send sequence before issuing real requests.

        The camera resumes a long-lived conversation rather than starting a new
        one: its first ACK reports a next-expected sequence in the thousands,
        while a fresh KCP endpoint starts at zero. An un-primed request is
        therefore acknowledged at the transport layer and then dropped as stale,
        never reaching the camera's application. Sending the captured session
        start first makes the camera reveal that sequence so we can jump to it.
        """
        if not self.kcp:
            raise ConnectionError('No established screen conversation')
        if self.kcp.peer_una:
            self.kcp.jump_send(self.kcp.peer_una)
            return self.kcp.peer_una
        self.identifier=(self.identifier+1)&0x7fffffff
        payload=struct.pack('<BHHBI',1,2,1,0,self.identifier)+struct.pack('<I',2)
        self.kcp.send(Envelope(0,0x0bfb,0x07fc,payload).encode())
        deadline=time.monotonic()+timeout
        while time.monotonic() < deadline:
            if self.kcp.peer_una:
                self.kcp.jump_send(self.kcp.peer_una)
                return self.kcp.peer_una
            await asyncio.sleep(0.05)
        return 0

    async def request(self,service,method,body=b'',source=0x0814,destination=0x0405,timeout=5):
        if self.failure:raise self.failure
        if not self.kcp:raise ConnectionError('No established screen conversation')
        self.identifier=(self.identifier+1)&0x7fffffff
        key=(service,method,self.identifier,destination,source)
        future=asyncio.get_running_loop().create_future();self.pending[key]=future
        payload=struct.pack('<BHHBI',1,service,method,0,self.identifier)+body
        self.kcp.send(Envelope(0,source,destination,payload).encode())
        try:return await asyncio.wait_for(future,timeout)
        finally:self.pending.pop(key,None)

    async def start_session(self):
        # Recovery take: first screen KCP is service 2 / method 1 / body LE32(2).
        try:
            reply = await self.request(2, 1, struct.pack('<I', 2), source=0x0bfb, destination=0x07fc)
        except asyncio.TimeoutError:
            if self.kcp and self.kcp.peer_una:
                self.kcp.jump_send(self.kcp.peer_una)
                reply = await self.request(2, 1, struct.pack('<I', 2), source=0x0bfb, destination=0x07fc)
            else:
                raise
        if reply != struct.pack('<I', 0):
            raise RuntimeError('Camera rejected screen session start')
        return reply

    async def get_configuration(self):
        return read_configuration(await self.request(1,1))

    async def set_recovery(self,enabled):
        """Send the captured full-configuration body for the requested state.

        A partial body with a zeroed token is not accepted. The camera replies to
        nothing here, so acceptance is reported from its advancing next-expected
        sequence rather than from an acknowledgement.
        """
        async with self.lock:
            if not self.kcp:
                raise ConnectionError('No established screen conversation')
            primed=await self.prime()
            if not primed:
                raise ConnectionError("Camera sequence unknown; refusing to send blind")
            path=Path(__file__).resolve().parents[1]/'.local/recovery-set-bodies.json'
            bodies=json.loads(path.read_text())
            body=bytes.fromhex(bodies['on' if enabled else 'off']['body'])
            self.identifier=(self.identifier+1)&0x7fffffff
            payload=struct.pack('<BHHBI',1,1,2,0,self.identifier)+body
            before=self.kcp.peer_una
            self.kcp.send(Envelope(0,0x0814,0x0405,payload).encode())
            deadline=time.monotonic()+1.5
            while time.monotonic()<deadline:
                self.kcp.update()
                if self.kcp.peer_una>before:
                    break          # camera consumed it; no need to keep pumping
                await asyncio.sleep(0.02)
            return {'enabled':enabled,'sequence_before':before,
                    'sequence_after':self.kcp.peer_una,
                    'accepted':self.kcp.peer_una>before}

    async def close(self):
        if hasattr(self,'task'):
            self.task.cancel();await asyncio.gather(self.task,return_exceptions=True)
        if self.proxy_task:
            self.proxy_task.cancel();await asyncio.gather(self.proxy_task,return_exceptions=True)
        if self.writer:
            self.writer.close()
            await self.writer.wait_closed()
            self.writer=None
        if self.transport:
            self.transport.close()
            await asyncio.sleep(0)
        if self.kcp:self.kcp.close()
