"""The shipped Color Recovery bodies must differ only in the two LUT leaves.

These are replayed verbatim at the camera, and the write is a full-configuration
replace. If a regeneration ever captures the two states from different moments,
the extra differing leaves would silently reapply unrelated settings.
"""

import json
import struct
import unittest
from pathlib import Path

BODIES = Path(__file__).resolve().parent.parent / "Apps/Apple/OpenInstaCine/RecoveryBodies.json"
EXPECTED_DIFF = {"/iq_ilog_lut/enable", "/iq_ilog_lut/lut_type"}


def leaves(obj, prefix=""):
    out = {}
    for key, value in obj.items():
        if isinstance(value, dict):
            out.update(leaves(value, f"{prefix}/{key}"))
        else:
            out[f"{prefix}/{key}"] = value
    return out


def configuration(entry):
    body = bytes.fromhex(entry["body"])
    length = struct.unpack_from("<I", body, 8)[0]
    return body[:8], json.loads(body[12 : 12 + length])


class RecoveryBodies(unittest.TestCase):
    def setUp(self):
        if not BODIES.exists():
            self.skipTest("RecoveryBodies.json is not on this install")
        self.data = json.loads(BODIES.read_text())

    def test_both_states_present(self):
        self.assertEqual(set(self.data), {"on", "off"})

    def test_states_match_their_lut_values(self):
        for state, expected in (("on", "kILogStandard"), ("off", "kStandard")):
            _, config = configuration(self.data[state])
            lut = config["iq_ilog_lut"]
            self.assertIs(lut["enable"], state == "on")
            self.assertEqual(lut["lut_type"], expected)
            self.assertEqual(config["iq_color_mode"]["color_mode"], "kIlog")

    def test_only_the_two_recovery_leaves_differ(self):
        on_token, on_config = configuration(self.data["on"])
        off_token, off_config = configuration(self.data["off"])
        on_leaves, off_leaves = leaves(on_config), leaves(off_config)
        self.assertEqual(set(on_leaves), set(off_leaves), "the two bodies describe different shapes")
        differing = {k for k in on_leaves if on_leaves[k] != off_leaves[k]}
        self.assertEqual(differing, EXPECTED_DIFF)
        self.assertEqual(on_token, off_token, "opaque token differs between the two bodies")


if __name__ == "__main__":
    unittest.main()
