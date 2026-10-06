package com.opencapture.openpocketcine

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorFalseColorSelection
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.openpocketcine.assists.StoredCenter
import com.opencapture.openpocketcine.assists.createLiveAssistState
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Real app storage composition, with an isolated native preferences domain. */
@RunWith(AndroidJUnit4::class)
class AssistStoreOwnershipTest {
    @Test fun actualFactoryReloadsLegacyStateAndKeepsPinsPlaybackAndPlacementIndependent() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
        val domain = "assist-owner-test." + UUID.randomUUID()
        val domains = mutableSetOf<String>()
        val context = object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
                val key = "$domain.$name"
                domains += key
                return base.getSharedPreferences(key, mode)
            }
        }
        try {
            assertEquals(null, OperatorPrefs.assistEncoded(context))
            OperatorPrefs.setAssistEncoded(context,
                """{"tools":["WAVE"],"falseColorScale":"CineStop","waveCenter":{"xFraction":0.25,"yFraction":0.75},"audioCenter":{"xFraction":0.1,"yFraction":0.2}}""")
            OperatorPrefs.setCleanViewPinnedTools(context, emptySet())
            OperatorPrefs.setPlaybackVisibleAssistTools(context, setOf("FALSE"))
            val before = OperatorPrefs.assistEncoded(context)
            val state = createLiveAssistState(context)
            assertEquals(before, OperatorPrefs.assistEncoded(context), "Opening the owner must not rewrite legacy JSON")
            assertEquals(MonitorFalseColorSelection.STOPS, state.falseColorScale)
            assertEquals(StoredCenter(0.25, 0.75), state.waveCenter)
            assertEquals(StoredCenter(0.1, 0.2), state.audioCenterFor(false))
            assertEquals(state.audioCenterFor(false), state.audioCenterFor(true))
            assertTrue(state.pinned.isEmpty())
            assertTrue(state.isPlaybackVisible(MonitorAssistTool.FALSE))
            assertFalse(state.isOn(MonitorAssistTool.FALSE))
            state.storeCenter(MonitorAssistTool.WAVE, StoredCenter(0.6, 0.4), portrait = true)
            state.storeAudioCenter(StoredCenter(0.2, 0.3), portrait = false)
            state.storeAudioCenter(StoredCenter(0.8, 0.7), portrait = true)
            state.updateAudioShowDB(true)
            state.togglePin(MonitorAssistTool.WAVE)
            state.togglePlayback(MonitorAssistTool.FALSE)
            val restored = createLiveAssistState(context)
            assertEquals(StoredCenter(0.25, 0.75), restored.waveCenter)
            assertEquals(StoredCenter(0.6, 0.4), restored.waveCenterPortrait)
            assertEquals(StoredCenter(0.2, 0.3), restored.audioCenterFor(false))
            assertEquals(StoredCenter(0.8, 0.7), restored.audioCenterFor(true))
            assertTrue(restored.audioShowDB && restored.isOn(MonitorAssistTool.WAVE))
            assertEquals(setOf("WAVE"), OperatorPrefs.cleanViewPinnedTools(context))
            assertFalse(restored.isPlaybackVisible(MonitorAssistTool.FALSE))
            val encoded = JSONObject(requireNotNull(OperatorPrefs.assistEncoded(context)))
            assertEquals("CineStop", encoded.getString("falseColorScale"))
            assertEquals(1, encoded.getInt("audioCentersSchema"))
        } finally {
            domains.forEach { base.deleteSharedPreferences(it) }
        }
    }
}
