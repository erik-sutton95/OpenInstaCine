import json
import struct
import unittest

from luna_screen_live import decode_datagrams, encode_datagram, read_configuration, recovery_state, replacement


class RecoveryConfigurationTests(unittest.TestCase):
    def configuration(self):
        return {'iq_color_mode':{'color_mode':'kIlog'},
                'iq_ilog_lut':{'enable':True,'lut_type':'kILogStandard','lut_level':100},
                'exposure':{'auto':False,'iso':640},
                'unknown_future_property':{'nested':[1,'preserve me',{'value':True}]}}

    def test_only_recovery_fields_change_and_token_is_preserved(self):
        before=self.configuration();original=json.dumps(before,sort_keys=True)
        token=b'\x80\x00\x01\x02\x03\x04\x05\xff'
        updated,body=replacement(before,token,False)
        self.assertEqual(json.dumps(before,sort_keys=True),original)
        self.assertEqual(body[:8],token)
        self.assertEqual(struct.unpack_from('<I',body,8)[0],len(body)-12)
        self.assertEqual(json.loads(body[12:]),updated)
        restored=json.loads(body[12:]);restored['iq_ilog_lut']['enable']=True;restored['iq_ilog_lut']['lut_type']='kILogStandard'
        self.assertEqual(restored,before)
        self.assertFalse(recovery_state(updated))

    def test_unknown_or_non_ilog_state_does_not_become_false(self):
        for change in ['missing','wrong-type','wrong-lut','not-ilog']:
            config=self.configuration()
            if change=='missing':del config['iq_ilog_lut']['enable']
            if change=='wrong-type':config['iq_ilog_lut']['enable']=0
            if change=='wrong-lut':config['iq_ilog_lut']['lut_type']='futureLut'
            if change=='not-ilog':config['iq_color_mode']['color_mode']='kStandard'
            with self.subTest(change=change),self.assertRaises(ValueError):replacement(config,bytes(8),False)

    def test_readback_requires_success_exact_length_and_opaque_token(self):
        config=self.configuration();encoded=json.dumps(config).encode();token=b'opaque!!'
        response=struct.pack('<II',0,len(encoded))+encoded+token
        self.assertEqual(read_configuration(response),(config,token))
        for invalid in [response[:-1],response+b'\x00',struct.pack('<I',1)+response[4:]]:
            with self.assertRaises(ValueError):read_configuration(invalid)

    def test_udp_pipe_framing_round_trips_and_rejects_oversize(self):
        first = encode_datagram(b'\x02hello')
        second = encode_datagram(b'world')
        buffer = bytearray(first + second[:3])
        self.assertEqual(decode_datagrams(buffer), [b'\x02hello'])
        self.assertEqual(bytes(buffer), second[:3])
        buffer.extend(second[3:])
        self.assertEqual(decode_datagrams(buffer), [b'world'])
        self.assertEqual(buffer, bytearray())
        with self.assertRaises(ValueError):
            encode_datagram(b'x' * 65536)


if __name__=='__main__':unittest.main()
