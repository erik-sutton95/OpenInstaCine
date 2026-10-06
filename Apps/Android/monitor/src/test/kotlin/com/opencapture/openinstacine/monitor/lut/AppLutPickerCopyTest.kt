package com.opencapture.openinstacine.monitor.lut

import com.opencapture.opencine.cameracontrols.LutPickerCopy
import com.opencapture.opencine.vocabulary.LutCatalog
import kotlin.test.Test
import kotlin.test.assertEquals

/** The LUT picker words and Auto, as on main. */
class AppLutPickerCopyTest {
    @Test fun cameraLooksSitOnTheCameraTab() {
        assertEquals(
            LutPickerCopy(
                cameraTab = "Camera",
                autoId = LutCatalog.AUTO,
                customHint = "Imported looks land here. Auto keeps the Rec.709 preview unchanged.",
                noLookCaption = "Rec.709 preview · no conversion needed",
                officialCubeCaption = "Camera looks for this color profile",
                cameraLooksCaption = "Camera looks for this color profile",
            ),
            AppLutPickerCopy,
        )
        assertEquals("auto", AppLutPickerCopy.autoId)
    }
}
