package com.opencapture.openinstacine.luna

import kotlin.test.*
import org.junit.Test

/** Fixtures copied from Adapters/Insta360Protocol LunaControlTests / ProtocolTests (captured official-app bytes). */
class LunaControlTest {
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
    private fun f(bits: Int) = java.lang.Float.intBitsToFloat(bits).toDouble()

    @Test fun zoomMatchesSwiftEncoder() {
        assertEquals("0a01351216a20100aa0100f80101a903000000000000f03fc005011807", hex(LunaControl.zoom(1.0).body))
        assertEquals("0a01351216a20100aa0100f80101a9030000000000001840c005011807", hex(LunaControl.zoom(6.0).body))
        assertEquals(LunaControl.SET_PHOTOGRAPHY_OPTIONS, LunaControl.zoom(2.0).code)
        assertFailsWith<IllegalArgumentException> { LunaControl.zoom(15.5) }
    }

    @Test fun gimbalMatchesSwiftEncoder() {
        assertEquals("0801120310c601", hex(LunaControl.gimbalStick(1.0, 0.0).body))
        assertEquals("0801120308c601", hex(LunaControl.gimbalStick(0.0, 1.0).body))
        assertEquals("0801120308c501", hex(LunaControl.gimbal(1, upDown = -99).body))
        assertEquals("08021200", hex(LunaControl.gimbal(2).body))
        assertEquals(LunaControl.GIMBAL_CONTROL, LunaControl.gimbal(3).code)
        assertFailsWith<IllegalArgumentException> { LunaControl.gimbal(1, upDown = 100) }
    }

    @Test fun tapFocusMatchesSwiftEncoder() {
        val request = LunaControl.tapFocus(f(0x3ED8_6FB6), f(0x3D5E_0A00), f(0x3E1E_412A), f(0x3E8C_ABB3))
        assertEquals("0a015e1225a20100aa0100f80101c00501f20516080115b66fd83e1d000a5e3d252a411e3e2db3ab8c3e1807", hex(request.body))
        val zeroY = LunaControl.tapFocus(f(0x3E8B_A2E9), 0.0, f(0x3E1E_412A), f(0x3E32_4079))
        assertEquals("0a015e1220a20100aa0100f80101c00501f20511080115e9a28b3e252a411e3e2d7940323e1807", hex(zeroY.body))
    }

    @Test fun trackingMatchesSwiftEncoder() {
        val track = LunaControl.openTracking(f(0x3F05_3C82), 0.0, f(0x3E04_A790), f(0x3E68_09A7), nowMillis = 1_789_558_454_687)
        assertEquals(LunaControl.OPEN_TRACKING, track.code)
        assertEquals("089ff3fbcf8a3415823c053f2590a7043e2da709683e", hex(track.body))
        assertEquals(0, LunaControl.cancelTracking.body.size)
    }
}
