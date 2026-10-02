package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.SavedCamerasStore
import com.opencapture.opencine.appkit.StoredString
import com.opencapture.opencine.core.CameraDeviceID
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.insta360.luna.LunaFailures
import org.json.JSONArray
import org.json.JSONObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The saved-camera migration of this app (SHELL-02 design 4, tests 1-6) through the store the app
 * builds ([AppModel.camerasStore]), over golden legacy records the shipping encoder wrote
 * (`src/test/resources/saved-cameras`, from `SharedPreferencesSavedCameraStore.encode` before it
 * was deleted). The iOS twin runs in OpenInstaCineTests.
 */
class SavedCamerasMigrationTest {
    private class Prefs(vararg seed: Pair<String, String>) {
        val values = mutableMapOf(*seed)
        val writes = mutableListOf<String>()
        fun at(key: String) = object : StoredString {
            override fun read() = values[key]
            override fun write(value: String) {
                values[key] = value
                writes += key
            }
        }
        fun store() = AppModel.camerasStore(at("document"), at("legacy"))
    }

    private fun fixture(name: String) = checkNotNull(javaClass.getResource("/saved-cameras/$name.json")).readText()

    private fun upgraded(legacy: String = fixture("legacy")): Pair<Prefs, SavedCamerasStore> {
        val prefs = Prefs("legacy" to legacy)
        return prefs to prefs.store().also { it.load() }
    }

    /** The decoder every earlier build runs (`SharedPreferencesSavedCameraStore.decode`): records without an id are skipped. */
    private fun oldRecords(raw: String): List<JSONObject> {
        val array = JSONArray(raw)
        return (0 until array.length()).map { array.getJSONObject(it) }.filter { it.optString("id").isNotEmpty() }
    }

    private val a = "7C:2D:1A:00:00:01"
    private val b = "7C:2D:1A:00:00:02"
    private val c = "7C:2D:1A:00:00:03"
    private val d = "7C:2D:1A:00:00:04"

    @Test
    fun upgradeImportsEveryCameraAndLeavesLegacyAlone() {
        val (prefs, store) = upgraded()
        assertEquals(fixture("legacy"), prefs.values["legacy"])
        assertEquals(listOf("document"), prefs.writes, "a read writes only the document")
        assertEquals(listOf(a, b, c), store.cameras.map { it.id })
        assertTrue(store.cameras.all { it.integration == LunaFailures.INTEGRATION && it.device == null })
        assertTrue(store.cameras.all { it.model == "Insta360 Luna Ultra" && it.routes.all { r -> r.bluetooth } })

        val first = store.cameras[0]
        assertEquals("A cam", first.name)
        assertEquals("Luna Ultra 1A2B3C", first.advertisedName)
        assertEquals(listOf("ap"), first.routes.map { it.key })
        assertEquals("LUNA-1A2B3C", first.routes[0].network)
        assertEquals(first.routes[0].id, first.preferredRoute)
        assertEquals(1_759_307_200_250L, first.lastConnected)

        // Station setups an earlier shell stored round-trip as routes.
        val second = store.cameras[1]
        assertNull(second.name)
        assertEquals(listOf(RouteKind.CAMERA_ACCESS_POINT, RouteKind.INFRASTRUCTURE_NETWORK, RouteKind.PHONE_HOTSPOT), second.routes.map { it.kind })
        assertEquals(listOf("LUNA-4D5E6F", "Studio", "Rig phone"), second.routes.map { it.network })
        assertEquals(second.routes[0].id, second.preferredRoute)

        val third = store.cameras[2]
        assertEquals(listOf("ap"), third.routes.map { it.key })
        assertNull(third.routes[0].network)
        assertNull(third.preferredRoute)
        assertEquals(1_757_307_200_500L, third.lastConnected)
    }

    @Test
    fun migrationIsIdempotent() {
        val (prefs, first) = upgraded()
        val document = prefs.values["document"]
        repeat(2) {
            val again = prefs.store().also { it.load() }
            assertEquals(first.cameras, again.cameras)
        }
        assertEquals(document, prefs.values["document"])
        assertEquals(fixture("legacy"), prefs.values["legacy"])
        assertEquals(listOf("document"), prefs.writes)
    }

    @Test
    fun mirrorRoundTripDecodesWithTheOldDecoder() {
        val (prefs, store) = upgraded(fixture("legacy-bad-record"))
        val cameras = store.cameras.toMutableList()
        cameras[0] = cameras[0].copy(name = "Renamed")
        cameras[1] = cameras[1].copy(lastConnected = 1_760_000_000_000L)
        cameras.removeAt(2)
        val added = SavedCamera(
            id = d, integration = LunaFailures.INTEGRATION, advertisedName = "Luna Ultra AABBCC",
            model = "Insta360 Luna Ultra", lastConnected = 1_760_000_001_000L,
        )
        store.save(listOf(added) + cameras)

        val legacy = checkNotNull(prefs.values["legacy"])
        val old = oldRecords(legacy).associateBy { it.getString("id") }
        assertEquals(setOf(a, b, d), old.keys)
        assertEquals("Renamed", old.getValue(a).getString("customName"))
        assertEquals("cameraWiFi", old.getValue(a).getString("lastSetup"))
        assertEquals(1_760_000_000_000L, old.getValue(b).getLong("lastConnectedAt"))
        assertEquals("Studio", old.getValue(b).getString("wifiSSID"))
        assertEquals("Luna Ultra AABBCC", old.getValue(d).getString("advertisedName"))
        assertFalse(old.getValue(d).has("customName"))
        val broken = JSONArray(legacy).let { array -> (0 until array.length()).map { array.getJSONObject(it) } }
            .single { !it.has("id") }
        assertTrue(broken.getJSONObject("futureField").getBoolean("kept"), "an unreadable record and its unknown fields survive")

        // The mirror is the new merge base: a reload keeps the document as saved.
        val again = prefs.store().also { it.load() }
        assertEquals(store.cameras, again.cameras)
        assertEquals(legacy, prefs.values["legacy"])
    }

    @Test
    fun downgradeEditsMergeBackOnUpgrade() {
        val (prefs, store) = upgraded()
        val serial = CameraDeviceID.durable("SN-1", LunaFailures.INTEGRATION)
        val ap = store.cameras[0].routes[0].copy(title = "Field")
        store.save(listOf(store.cameras[0].copy(device = serial, routes = listOf(ap))) + store.cameras.drop(1))
        assertEquals(fixture("legacy"), prefs.values["legacy"], "document-only edits leave the legacy records alone")

        // The older build renames B, forgets C, pairs D, adds a Wi-Fi setup on A and connects over it.
        prefs.values["legacy"] = fixture("legacy-downgrade-edits")
        val upgraded = prefs.store().also { it.load() }.cameras.associateBy { it.id }
        assertEquals(setOf(a, b, d), upgraded.keys)
        assertEquals("B cam", upgraded.getValue(b).name)
        val first = upgraded.getValue(a)
        assertEquals(serial, first.device)
        assertEquals(ap, first.routes[0], "route id and title survive")
        assertEquals(listOf("ap", "wifi"), first.routes.map { it.key })
        assertEquals("Office", first.routes[1].network)
        assertEquals(first.routes[1].id, first.preferredRoute)
        val fourth = upgraded.getValue(d)
        assertEquals("LUNA-AABBCC", fourth.routes.single().network)
        assertEquals(fourth.routes[0].id, fourth.preferredRoute)
    }

    @Test
    fun aBadRecordIsKeptAndNeverOverwritten() {
        val (prefs, store) = upgraded(fixture("legacy-bad-record"))
        assertEquals(listOf(a, b, c), store.cameras.map { it.id }, "the unreadable record is skipped, the others load")
        store.save(store.cameras.map { if (it.id == c) it.copy(name = "C cam") else it })
        val raw = JSONArray(checkNotNull(prefs.values["legacy"]))
        val records = (0 until raw.length()).map { raw.getJSONObject(it) }
        assertEquals(4, records.size)
        assertEquals("Broken", records.single { !it.has("id") }.getString("advertisedName"))
        assertEquals("C cam", records.single { it.optString("id") == c }.getString("customName"))
    }

    @Test
    fun aFutureDocumentIsNeverWritten() {
        val future = """{"version":2,"cameras":[],"legacy":{}}"""
        val prefs = Prefs("legacy" to fixture("legacy"), "document" to future)
        val store = prefs.store().also { it.load() }
        assertFalse(store.writesDocument)
        assertEquals(listOf(a, b, c), store.cameras.map { it.id }, "this build runs from legacy")
        store.save(store.cameras.map { if (it.id == a) it.copy(name = "Later") else it })
        assertEquals(future, prefs.values["document"])
        assertEquals("Later", oldRecords(checkNotNull(prefs.values["legacy"])).single { it.getString("id") == a }.getString("customName"))
        assertEquals(listOf("legacy"), prefs.writes)
    }
}
