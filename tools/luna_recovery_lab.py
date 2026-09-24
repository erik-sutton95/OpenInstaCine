#!/usr/bin/env python3
"""Local-only Mac 720p viewer and experimental camera recovery control.

Requires camera Wi-Fi already joined. HTTP is loopback-only and writes require
a per-run token. No LUT is applied by the viewer. Closing the window stops live
preview. Device control stays in the separate screen-protocol adapter.
"""
import argparse
import asyncio
import contextlib
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import secrets
import signal
import struct
import subprocess
import threading
import time
from urllib.parse import urlparse, parse_qs

from luna_tcp import Session, PREFIX, LIVE_BODY
from luna_wire import one, options, blob, integer, photography_get, photography_set
from luna_screen_live import ScreenControl, ScreenMedia, recovery_state

ROOT=Path(__file__).resolve().parent.parent


class Lab:
    def __init__(self,folder,library,control_ip):
        self.folder=folder;self.library=library;self.control_ip=control_ip
        self.status={'live':False,'closed':False,'control_ready':False,'recovery':None,'frames':0,'dimensions':None,'message':'Connecting to camera'}
        self.token=secrets.token_urlsafe(32);self.frame=None;self.condition=threading.Condition()
        self.last_poll=None;self.stop=asyncio.Event();self.control=None;self.tcp=None
        self.saturation=None;self.calibration={};self.media=None
        self.loop=asyncio.get_running_loop();self.write_lock=asyncio.Lock()
        self.udp_log=(folder/'screen-control.jsonl').open('w')

    def log_udp(self,direction,data):
        # The media responder keeps receiving after shutdown closes this file.
        if self.udp_log.closed: return
        try:
            self.udp_log.write(json.dumps({'utc':datetime.now(timezone.utc).isoformat(),'direction':direction,'data':data.hex()})+'\n')
            self.udp_log.flush()
        except ValueError:
            pass

    async def change(self,enabled):
        if type(enabled) is not bool:raise ValueError('Expected a Boolean recovery state')
        async with self.write_lock:
            self.status['message']='Sending iq_ilog_lut.enable='+('true' if enabled else 'false')
            if not (self.control and self.control.kcp):
                self.status['message']='No screen conversation; nothing sent'
                raise ConnectionError('No screen conversation')
            result=await self.control.set_recovery(enabled)
            self.status['recovery']=enabled
            self.status['control_ready']=True
            self.status['accepted']=result['accepted']
            self.status['camera_sequence']=result['sequence_after']
            self.status.pop('control_error',None)
            asyncio.create_task(self.calibrate(enabled))
            self.status['message']=(
                ('Camera accepted ' if result['accepted'] else 'NOT accepted: ')
                + ('ON' if enabled else 'OFF')
                + ' (commanded state; camera sends no readback)')
        return dict(self.status)

    async def connect_control(self):
        self.control=ScreenControl(self.library,self.log_udp)
        try:
            self.media=ScreenMedia(self.library,self.log_udp)
            await self.media.listen(local_ip=self.control_ip, local_port=6023)
            await self.control.connect(
                local_ip=self.control_ip, solicit=False, listen_seconds=22)
            try:
                primed=await self.control.prime()
                self.status['camera_sequence']=primed
            except Exception:
                pass
            try:
                await asyncio.wait_for(self.control.app_seen.wait(), 3)
            except asyncio.TimeoutError:
                pass
            try:
                await self.control.start_session()
            except (asyncio.TimeoutError, RuntimeError):
                # Resumed conversations already passed this start; still try GET.
                pass
            try:
                config,token=await self.control.get_configuration()
                self.status['recovery']=recovery_state(config)
                (self.folder/'initial-screen-config.json').write_text(json.dumps(config,indent=2))
            except Exception:
                self.status['recovery']=None
            self.status['control_ready']=bool(self.control and self.control.kcp)
            self.status.pop('control_error',None)
            self.status['message']='Press the button to send iq_ilog_lut.enable. Watch the picture.'
        except Exception as error:
            self.status['control_failure']=type(error).__name__
            self.status['recovery']=None
            self.status['control_ready']=bool(self.control and self.control.kcp)
            if not self.status['control_ready']:
                self.status['control_error']='Screen UDP hello failed. Button will still try a SET.'
            else:
                self.status.pop('control_error',None)
            self.status['message']='Press the button to send iq_ilog_lut.enable. Watch the picture.'

    async def watch_stats(self):
        """Infer Recovery state from the picture, since the camera never reports it.

        ffmpeg prints one signalstats block per second to its log alongside the
        display stream (its file output is buffered and never flushes live). Saturation separates the two states cleanly, but its absolute
        value depends on the scene, so classification calibrates against the
        readings observed right after each commanded change rather than a fixed
        threshold.
        """
        path = self.folder / 'decoder.log'   # metadata=print goes to the log stream
        while not path.exists():
            if self.stop.is_set():
                return
            await asyncio.sleep(0.3)
        handle = path.open()
        handle.seek(0, 2)
        while not self.stop.is_set():
            line = handle.readline()
            if not line:
                await asyncio.sleep(0.2)
                continue
            if 'SATAVG=' in line:
                try:
                    self.saturation = float(line.strip().split('SATAVG=')[1])
                except ValueError:
                    continue
                self.status['saturation'] = round(self.saturation, 2)
                self.status['detected'] = self.classify()

    def classify(self):
        """Nearest calibrated reading; None until both states have been seen."""
        if self.saturation is None:
            return None
        on, off = self.calibration.get(True), self.calibration.get(False)
        if on is None or off is None:
            return None
        return bool(abs(self.saturation - on) < abs(self.saturation - off))

    async def calibrate(self, enabled):
        # The camera's encoder, the stream and the 1 fps sampler all add lag, so
        # settle first, then take the median of several readings rather than one.
        await asyncio.sleep(4.0)
        samples = []
        for _ in range(4):
            if self.saturation is not None:
                samples.append(self.saturation)
            await asyncio.sleep(1.0)
        if samples:
            samples.sort()
            self.calibration[enabled] = samples[len(samples) // 2]
            self.status['calibrated'] = sorted(
                f"{'on' if k else 'off'}={v:.2f}" for k, v in self.calibration.items())
            self.status['detected'] = self.classify()

    async def frames(self,reader):
        pending=bytearray()
        while data:=await reader.read(65536):
            pending.extend(data)
            if len(pending)>8*1024*1024:raise RuntimeError('Video decoder output exceeded its bound')
            while True:
                start=pending.find(b'\xff\xd8');end=pending.find(b'\xff\xd9',max(start+2,0))
                if start<0 or end<0:break
                jpeg=bytes(pending[start:end+2]);del pending[:end+2]
                # SOF JPEG dimensions, without decoding or altering the image.
                pos=2;dimensions=None
                while pos+4<=len(jpeg):
                    if jpeg[pos]!=255:break
                    marker=jpeg[pos+1];length=int.from_bytes(jpeg[pos+2:pos+4],'big')
                    if marker in (0xc0,0xc1,0xc2):
                        height=int.from_bytes(jpeg[pos+5:pos+7],'big');width=int.from_bytes(jpeg[pos+7:pos+9],'big');dimensions=(width,height);break
                    if length<2:break
                    pos+=2+length
                if dimensions:
                    self.status['dimensions']=f'{dimensions[0]} × {dimensions[1]}'
                    if dimensions!=(1280,720):self.status['message']='Camera supplied an unexpected preview size'
                with self.condition:
                    self.frame=jpeg;self.status['frames']+=1;self.status['live']=True;self.last_video=time.monotonic();self.condition.notify_all()

    async def run(self):
        tasks=[];process=decoder=None;started=False
        try:
            process=await asyncio.create_subprocess_exec('/usr/bin/nc','-G','6','192.168.42.1','6666',stdin=asyncio.subprocess.PIPE,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE)
            tcp=self.tcp=Session(process.stdout,process.stdin,self.folder,record_media=False)
            tasks.append(asyncio.create_task(tcp.receive()));await tcp.send(PREFIX)
            await asyncio.wait_for(tcp.greeting.wait(),8)
            if tcp.failure:raise tcp.failure
            tasks.append(asyncio.create_task(tcp.keepalive()))
            info=one(await tcp.request(8,options([48,30])),2)
            if one(info,48,b'').decode()!='Insta360 Luna Ultra':raise RuntimeError('Unexpected camera model')
            self.status['firmware']=one(info,30,b'').decode()
            ident=json.loads((ROOT/'.local/luna-client-identity.json').read_text())['authorization_id'].encode()
            if one(await tcp.request(39,blob(1,ident)+integer(2,1)+blob(3,ident)),1,0)!=0:raise RuntimeError('Camera identity is not authorized')
            (self.folder/'capture-status.pb').write_bytes(await tcp.request(15))
            await tcp.request(9, photography_set([35], integer(35, 2), 7))
            await tcp.request(10, photography_get([35, 73], 7))
            self.status['color_mode'] = 2
            decoder_log=(self.folder/'decoder.log').open('w')
            decoder=await asyncio.create_subprocess_exec('/opt/homebrew/bin/ffmpeg','-hide_banner','-loglevel','info','-nostats','-flags','low_delay','-probesize','32768','-analyzeduration','0','-f','hevc','-i','pipe:0','-an','-filter_complex','[0:v]split=2[disp][stat];[stat]fps=1,signalstats,metadata=print[s]','-map','[disp]','-c:v','mjpeg','-q:v','3','-f','image2pipe','pipe:1','-map','[s]','-f','null','-',stdin=asyncio.subprocess.PIPE,stdout=asyncio.subprocess.PIPE,stderr=decoder_log)
            tcp.video_sink=decoder.stdin;tasks.append(asyncio.create_task(self.frames(decoder.stdout)))
            tasks.append(asyncio.create_task(self.watch_stats()))
            started=True;await tcp.request(1,LIVE_BODY)
            self.status['message']='Receiving phone preview'
            tasks.append(asyncio.create_task(self.connect_control()))
            while not self.stop.is_set():
                try:await asyncio.wait_for(self.stop.wait(),1)
                except asyncio.TimeoutError:pass
                if tcp.failure:raise tcp.failure
                if decoder.returncode is not None:raise RuntimeError('Video decoder exited')
                if self.last_poll and time.monotonic()-self.last_poll>15:self.stop.set()
                if self.status['frames'] and time.monotonic()-self.last_video>3:self.status['live']=False
                (self.folder/'status.json').write_text(json.dumps(self.status,indent=2)+'\n')
        except Exception as error:
            self.status['message']='Camera connection failed: '+type(error).__name__
            self.status['video_error']=self.status['message']
            print(self.status['message'],flush=True)
        finally:
            if self.control:await self.control.close()
            if self.tcp and started:
                try:
                    await self.tcp.request(2)
                    self.status['stop_acknowledged']=True
                except Exception:self.status['stop_acknowledged']=False
            for task in tasks:task.cancel()
            await asyncio.gather(*tasks,return_exceptions=True)
            if self.tcp:
                self.status.update(phone_video_messages=self.tcp.media[0x20],
                                   bad_checksums=self.tcp.parser.bad_checksums,
                                   rejected_headers=self.tcp.parser.rejected_headers,
                                   pending_receive_bytes=len(self.tcp.parser.pending))
                self.tcp.writer.close();self.tcp.close_files()
            for child in [decoder,process]:
                if child and child.returncode is None:
                    with contextlib.suppress(ProcessLookupError):child.terminate()
                    try:await asyncio.wait_for(child.wait(),3)
                    except asyncio.TimeoutError:child.kill();await child.wait()
            if decoder:decoder_log.close()
            self.udp_log.close();self.status.update(live=False,closed=True,control_ready=False)
            if not self.status.get('video_error'):
                self.status['message']='Disconnected from camera'
            (self.folder/'status.json').write_text(json.dumps(self.status,indent=2)+'\n')
            with self.condition:self.condition.notify_all()


def handler(lab):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def authorized(self):
            supplied=self.headers.get('X-Lab-Token') or parse_qs(urlparse(self.path).query).get('token',[''])[0]
            return secrets.compare_digest(supplied,lab.token)
        def data(self,code,data,kind='application/json'):
            self.send_response(code);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(data)
        def do_GET(self):
            path=urlparse(self.path).path
            if not self.authorized():return self.data(403,b'{}')
            if path=='/':
                lab.last_poll=time.monotonic()
                page=(ROOT/'tools/luna_recovery_lab.html').read_text().replace('__TOKEN__',lab.token)
                return self.data(200,page.encode(),'text/html; charset=utf-8')
            if path=='/status':
                lab.last_poll=time.monotonic();return self.data(200,json.dumps(lab.status).encode())
            if path=='/stream':
                self.send_response(200);self.send_header('Content-Type','multipart/x-mixed-replace; boundary=frame');self.send_header('Cache-Control','no-store');self.end_headers();last=None
                try:
                    while not lab.status['closed']:
                        with lab.condition:
                            lab.condition.wait_for(lambda:lab.frame is not last or lab.status['closed'],timeout=2)
                            frame=lab.frame
                        if frame is None or frame is last:continue
                        last=frame;self.wfile.write(b'--frame\r\nContent-Type: image/jpeg\r\nContent-Length: '+str(len(frame)).encode()+b'\r\n\r\n'+frame+b'\r\n');self.wfile.flush()
                except (BrokenPipeError,ConnectionResetError):pass
                return
            self.data(404,b'{}')
        def do_POST(self):
            if not self.authorized():return self.data(403,b'{}')
            path=urlparse(self.path).path
            try:
                size=int(self.headers.get('Content-Length','0'))
                if not 0<=size<=1024:raise ValueError('Invalid request size')
                body=json.loads(self.rfile.read(size))
                if path=='/disconnect':
                    lab.loop.call_soon_threadsafe(lab.stop.set);return self.data(200,b'{}')
                if path!='/recovery':return self.data(404,b'{}')
                task=asyncio.run_coroutine_threadsafe(lab.change(body.get('enabled')),lab.loop)
                self.data(200,json.dumps(task.result(timeout=18)).encode())
            except Exception as error:self.data(409,json.dumps({'error':str(error)}).encode())
    return Handler


async def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--control-ip', default='')
    parser.add_argument('--kcp-library',type=Path,default=ROOT/'.local/luna-recovery-live/vendor/libkcp.dylib')
    parser.add_argument('--restore-dhcp',action='store_true',help='Restore a task-owned manual Wi-Fi address on exit')
    args=parser.parse_args();os.umask(0o077)
    folder=ROOT/'captures'/(datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')+'-luna-recovery-live');folder.mkdir(mode=0o700)
    control_ip = args.control_ip.strip() or subprocess.run(
        ['/usr/sbin/ipconfig', 'getifaddr', 'en0'], capture_output=True, text=True
    ).stdout.strip()
    if not control_ip.startswith('192.168.42.'):
        raise SystemExit('Join the camera Wi-Fi on en0 first; ethernet can stay the default route.')
    lab=Lab(folder,args.kcp_library,control_ip)
    server=ThreadingHTTPServer(('127.0.0.1',0),handler(lab));server.daemon_threads=True
    threading.Thread(target=server.serve_forever,daemon=True).start()
    info={'pid':os.getpid(),'folder':str(folder),'url':f'http://127.0.0.1:{server.server_port}/?token={lab.token}'}
    (ROOT/'.local/active-recovery-lab.json').write_text(json.dumps(info))
    for sig in (signal.SIGINT,signal.SIGTERM):lab.loop.add_signal_handler(sig,lab.stop.set)
    print('Mac test service started;', folder.relative_to(ROOT), flush=True)
    print(info['url'], flush=True)
    try:
        await lab.run()
        await asyncio.sleep(2)  # Let the window display the final disconnected state.
    finally:
        await asyncio.to_thread(server.shutdown)
        if args.restore_dhcp:
            state_path=ROOT/'.local/luna-recovery-live/manual-ip-state.json'
            if state_path.exists():
                owned=json.loads(state_path.read_text())
                current=subprocess.run(['ipconfig','getifaddr','en0'],capture_output=True,text=True).stdout.strip()
                if owned.get('owned') and current==owned.get('manual_address'):
                    result=subprocess.run(['/usr/sbin/networksetup','-setdhcp','Wi-Fi'],capture_output=True,text=True)
                    owned.update(owned=False,restored_to_dhcp=result.returncode==0)
                    state_path.write_text(json.dumps(owned))
                    (folder/'network-cleanup.json').write_text(json.dumps(owned))

if __name__=='__main__':asyncio.run(main())
