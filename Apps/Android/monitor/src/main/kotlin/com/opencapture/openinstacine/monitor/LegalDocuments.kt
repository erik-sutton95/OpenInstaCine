package com.opencapture.openinstacine.monitor

import com.opencapture.opencine.cameracontrols.MonitorLegalDocument
import com.opencapture.opencine.cameracontrols.MonitorLegalDocuments
import com.opencapture.opencine.cameracontrols.MonitorPlatformLegalNotices

private val PRIVACY_BODY =
    """
OpenInstaCine talks to your Insta360 Luna over Bluetooth and the camera's own Wi-Fi. The app has no account. Automatic error reports are optional and off by default.

OpenCapture is the data controller. Privacy or deletion requests: support@opencapture.org.

Optional reliability reports
With your consent, configured builds send crash, hang and feed diagnostics, app/OS/device versions and session health counts through Sentry. Automatic reports exclude all images. No footage, screenshots, raw camera packets or GPS location are included. Sentry receives the connection IP; stored event IP and derived geography are removed. Event storage uses Germany. Some provider processing may occur internationally.
Turn reporting off in Operator Setup at any time without losing app features. This clears pending SDK uploads, but does not delete reports already received. Contact us privately to request deletion. The website policy explains retention, transfers and your rights.

Reporting a problem yourself
Report a problem sends your description and any optional reply email to OpenCapture through Sentry when you tap Send report. Technical details are included only if you choose them and can be reviewed first. You can choose up to three photos or screenshots and review or remove them before sending. Selected images are resized and re-encoded without original filenames or location metadata. Only share images you have permission to send; no images are attached automatically. This one-off submission does not enable automatic reports. Unsent reports stay privately on this phone, expire after 7 days (removed when the app next runs), wait until you leave camera Wi-Fi, and can be removed before delivery. Do not include passwords or other sensitive information in your message.

What stays on this phone
• Saved camera names and last SSID. The camera Wi-Fi password is stored in the Android Keystore on this phone only.
• Operator preferences such as Keep Screen Awake and the last LUT look.
• Imported .cube files you choose to open.

What never leaves the phone
• Live HEVC, camera telemetry, and pairing traffic stay on the local link. We do not operate a cloud.

Third parties
• Apple (or Google) may process permission prompts and OS diagnostics under their own policies. TestFlight or Play betas may send crash reports to the developer under Apple or Google terms.
• Frame.io is optional. If this build is configured and you sign in, clips you pick upload device → Adobe. The token stays in the on-device Keystore.
• Saving a clip or using the share sheet is something you start. Apple or the app you pick then handles that file.
• AF-C face boxes are computed on this phone from the live preview. Face geometry is not uploaded.
• The source is at github.com/erik-sutton95/OpenInstaCine.

Android may ask for location so the app can join the camera Wi-Fi or scan BLE. OpenInstaCine does not use that permission for maps, ads, or a location history.

The full privacy policy is https://opencapture.org/openinstacine/privacy
    """.trimIndent()

/**
 * Insta's legal set: privacy ships with the app and the terms are the web page. Licenses and
 * NOTICE are the repository's LICENSE, THIRD-PARTY-NOTICES.md and NOTICE, staged as resources at
 * build time, with the platform notices; a build missing one shows the unavailable page.
 */
internal val InstaLegalDocuments = MonitorLegalDocuments(
    wordmark = MonitorConfiguration.identity.wordmark,
    privacy = MonitorLegalDocument.Text(PRIVACY_BODY),
    terms = MonitorLegalDocument.Link(OpenPocketCineLinks.TERMS),
    licenses = MonitorLegalDocument.bundledText(listOf(
        MonitorLegalDocument.resource("openinstacine/legal/LICENSE"),
        MonitorLegalDocument.resource("openinstacine/legal/THIRD-PARTY-NOTICES.md"),
        MonitorPlatformLegalNotices.text,
    )),
    notice = MonitorLegalDocument.bundledText(listOf(MonitorLegalDocument.resource("openinstacine/legal/NOTICE"))),
)
