package com.opencapture.openpocketcine.feed

import android.content.Context
import android.util.Log
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.openpocketcine.assists.FalseColorScale
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.lut.LutCatalog
import java.io.File
import java.util.LinkedHashMap
import com.opencapture.opencine.media.MonitorLUTCube
import com.opencapture.opencine.media.ScopeTapPolicy
import com.opencapture.opencine.media.MonitorLUTExposureCompensation

private const val TAG = "OpcFeedFx"

internal typealias FeedEffectsRenderPlan = com.opencapture.opencine.media.FeedEffectsRenderPlan

internal object FeedEffectsRenderPlanFactory {
    fun create(
        context: Context,
        assist: LiveAssistState,
        lutSelection: String,
        colorMode: Int,
        iso: Int,
        family: String,
        cameraName: String?,
        playback: Boolean = false,
        previewTool: LiveAssistTool? = null,
        isPhoto: Boolean = false,
    ): FeedEffectsRenderPlan {
        val shown: (LiveAssistTool) -> Boolean =
            if (previewTool != null) {
                { it == previewTool }
            } else if (playback) {
                { assist.isPlaybackVisible(it) }
            } else {
                { assist.isVisible(it) }
            }
        val lutOn = shown(LiveAssistTool.LUT)
        val peaking = shown(LiveAssistTool.PEAK)
        val falseColor = shown(LiveAssistTool.FALSE)
        val zebra = shown(LiveAssistTool.ZEBRA)
        val inspectorDemand = assist.inspectorScopeDemand?.takeIf { it.playback == playback && previewTool == null }
        val inspector = inspectorDemand?.tool
        val previewOwner = inspectorDemand?.takeIf {
            it.tool in listOf(LiveAssistTool.LUT, LiveAssistTool.PEAK, LiveAssistTool.FALSE, LiveAssistTool.ZEBRA, LiveAssistTool.DESQ)
        }?.owner
        val evMeter = !playback && assist.evMeterFromPicture && shown(LiveAssistTool.EV)
        val inspectorOnly = inspector != null && !evMeter && listOf(LiveAssistTool.WAVE, LiveAssistTool.PARADE,
            LiveAssistTool.HISTO, LiveAssistTool.VECTOR, LiveAssistTool.LIGHTS, LiveAssistTool.ND).none(shown)
        val waveform = shown(LiveAssistTool.WAVE) || inspector == LiveAssistTool.WAVE
        val parade = shown(LiveAssistTool.PARADE) || inspector == LiveAssistTool.PARADE
        val histogram = shown(LiveAssistTool.HISTO) || inspector == LiveAssistTool.HISTO
        val vectorscope = shown(LiveAssistTool.VECTOR) || inspector == LiveAssistTool.VECTOR
        val trafficLights = shown(LiveAssistTool.LIGHTS) || inspector == LiveAssistTool.LIGHTS
        val look =
            LutLookResolver.resolve(
                selection = lutSelection,
                lutOn = lutOn,
                colorMode = colorMode,
                family = family,
                cameraName = cameraName,
                isPhoto = isPhoto,
            )
        val lutCube = lutCube(context, look, assist.lutExposureStops, colorMode)
        // Same gate as iOS `FeedPresentPolicy.appliesSplitComparison` (#218).
        val split =
            assist.splitComparison && lutCube != null && lutOn &&
                (!falseColor || assist.falseColorScale == FalseColorScale.LIMITS)
        val scalars =
            if (SwiftCore.isAvailable) {
                SwiftCore.feedAssistScalars(
                    colorMode,
                    iso,
                    assist.zebraHighlightIRE.toFloat(),
                    assist.zebraMidtoneIRE.toFloat(),
                )
            } else {
                null
            }
        val highlightCode = scalars?.getOrNull(0) ?: (assist.zebraHighlightIRE / 100.0).toFloat()
        val midtoneCode = scalars?.getOrNull(1) ?: (assist.zebraMidtoneIRE / 100.0).toFloat()
        val midtoneHalf = scalars?.getOrNull(2) ?: (5.0 / 255.0).toFloat()
        val gateScale = scalars?.getOrNull(3) ?: 1f
        val paint =
            if (falseColor) {
                falseColorCube(paint = true, assist.falseColorScale, colorMode, iso, assist.falseColorRec709)
            } else {
                null
            }
        val weight =
            if (falseColor) {
                falseColorCube(paint = false, assist.falseColorScale, colorMode, iso, assist.falseColorRec709)
            } else {
                null
            }
        val peakRgb = assist.peakingColor.rgb
        val hiRgb = assist.zebraHighlightColor.rgb
        val midRgb = assist.zebraMidtoneColor.rgb
        return FeedEffectsRenderPlan(
            lutCube = lutCube,
            falseColorPaint = paint,
            falseColorWeight = weight,
            peaking = peaking,
            peakingColor =
                floatArrayOf(peakRgb.first.toFloat(), peakRgb.second.toFloat(), peakRgb.third.toFloat()),
            peakingRatioThreshold = assist.peakingSensitivity.ratioThreshold.toFloat(),
            peakingNoiseGate = (assist.peakingSensitivity.noiseGate * gateScale).toFloat(),
            zebraHighlightOn = zebra && assist.zebraHighlight,
            zebraHighlightCode = highlightCode,
            zebraHighlightColor =
                floatArrayOf(hiRgb.first.toFloat(), hiRgb.second.toFloat(), hiRgb.third.toFloat()),
            zebraMidtoneOn = zebra && assist.zebraMidtone,
            zebraMidtoneCode = midtoneCode,
            zebraMidtoneHalf = midtoneHalf,
            zebraMidtoneColor =
                floatArrayOf(midRgb.first.toFloat(), midRgb.second.toFloat(), midRgb.third.toFloat()),
            splitComparison = split,
            splitVertical = assist.splitVertical,
            scopeTap =
                ScopeTapPolicy(
                    inspectorOnly = inspectorOnly,
                    previewOwner = previewOwner,
                    playback = playback,
                    waveform = waveform,
                    parade = parade,
                    histogram = histogram,
                    vectorscope = vectorscope,
                    trafficLights = trafficLights,
                    ndMeter = shown(LiveAssistTool.ND),
                    evMeter = evMeter,
                    trafficThreshold = assist.crushClipCompensation.pixelFractionThreshold,
                    transfer = MonitorTransfer.fromColorMode(colorMode),
                    iso = iso.takeIf { it in 50..102_400 },
                    allowsTransferInference = playback || !isPhoto,
                    vectorLut =
                        if (vectorscope) {
                            lutCube
                                ?: when (colorMode) {
                                    CameraCommands.COLOR_DLOG,
                                    CameraCommands.COLOR_DLOG2,
                                    ->
                                        lutCube(
                                            context,
                                            LutLookResolver.resolve(
                                                LutCatalog.AUTO,
                                                lutOn = true,
                                                colorMode = colorMode,
                                                family = family,
                                                cameraName = cameraName,
                                                isPhoto = isPhoto,
                                            ),
                                            assist.lutExposureStops,
                                            colorMode,
                                        )
                                    else -> null
                                }
                        } else {
                            null
                        },
                ),
        )
    }

    private fun lutCube(
        context: Context,
        source: LutLookSource,
        exposureStops: Double,
        colorMode: Int,
    ): MonitorLUTCube? {
        val snapped = MonitorLUTExposureCompensation.snap(exposureStops)
        val exposureColorMode = LutLookResolver.exposureColorMode(source, colorMode)
        val key =
            when (source) {
                is LutLookSource.Asset -> "asset:${source.fileName}:$snapped:$exposureColorMode"
                is LutLookSource.Custom -> "custom:${source.fileName}:$snapped:$exposureColorMode"
                is LutLookSource.Creative -> "creative:${source.name}:$snapped:$exposureColorMode"
                LutLookSource.Off -> return null
            }
        return PackedCubeCache.value(key) {
            if (!SwiftCore.isAvailable) {
                Log.w(TAG, "LUT pack needs the Swift core")
                return@value null
            }
            if (source is LutLookSource.Creative) {
                return@value SwiftCore.packCreativeLut(source.name, snapped, exposureColorMode)
            }
            val utf8 =
                when (source) {
                    is LutLookSource.Asset ->
                        runCatching {
                            context.assets.open(LutCatalog.assetPath(source.fileName)).use { it.readBytes() }
                        }.getOrNull()
                    is LutLookSource.Custom -> {
                        if (!LutCatalog.isSafeFileName(source.fileName)) return@value null
                        val file = File(LutCatalog.customDirectory(context.filesDir), source.fileName)
                        if (!file.isFile) return@value null
                        runCatching { file.readBytes() }.getOrNull()
                    }
                    is LutLookSource.Creative, LutLookSource.Off -> null
                } ?: return@value null
            SwiftCore.packImportedLut(utf8, snapped, exposureColorMode)
        }
    }

    private fun falseColorCube(
        paint: Boolean,
        scale: FalseColorScale,
        colorMode: Int,
        iso: Int,
        rec709: Boolean,
    ): MonitorLUTCube? {
        if (!SwiftCore.isAvailable) return null
        // 4…7 = each scale read through the official Rec.709 look (Swift `FeedEffectsWire`).
        val ordinal =
            when (scale) {
                FalseColorScale.STOPS -> if (rec709) 4 else 0
                FalseColorScale.IRE -> if (rec709) 5 else 1
                FalseColorScale.LIMITS -> if (rec709) 6 else 2
                FalseColorScale.SCENE_STOPS -> if (rec709) 7 else 3
            }
        val kind = if (paint) "paint" else "weight"
        return PackedCubeCache.value("$kind:$ordinal:$colorMode:$iso") {
            if (paint) {
                SwiftCore.packFalseColorPaint(ordinal, colorMode, iso)
            } else {
                SwiftCore.packFalseColorWeight(ordinal, colorMode, iso)
            }
        }
    }
}

private object PackedCubeCache {
    private const val MAX_ENTRIES = 8
    private val cubes =
        object : LinkedHashMap<String, MonitorLUTCube>(MAX_ENTRIES, 0.75f, true) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<String, MonitorLUTCube>?,
            ): Boolean = size > MAX_ENTRIES
        }

    fun value(key: String, bake: () -> ByteArray?): MonitorLUTCube? =
        synchronized(cubes) {
            cubes[key]
                ?: bake()?.let(MonitorLUTCube::fromPacked)?.also { cubes[key] = it }
        }
}
