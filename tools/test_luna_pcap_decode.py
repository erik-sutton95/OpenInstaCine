import unittest

import luna_pcap_decode as d


class PcapDecodeTest(unittest.TestCase):
    def test_render_double_nested_and_empty(self):
        # field 53 fixed64 2.0 inside field 2, as in the official zoom SET.
        self.assertEqual(d.render(bytes.fromhex("120aa9030000000000000040")), "{2:{53:d2}}")
        self.assertEqual(d.render(b""), "{}")

    def test_annotate_names_types_and_mode_for_requests_only(self):
        body = bytes.fromhex("0a015b1807")  # types [91], field 3 mode 7
        label = d.annotate(9, body, True)
        self.assertIn("91:GIMBAL_OPTIONS", label)
        self.assertIn("mode=7:FUNCTION_MODE_NORMAL_VIDEO", label)
        self.assertEqual(d.annotate(9, body, False), "")


if __name__ == "__main__":
    unittest.main()
