import MetalKit
import MonitorUI
import OpenCineCameraControls

@MainActor
func scopeDisplay(_ view: MTKView) -> MonitorScopeDisplayOptions {
    InstaLivePicture.scopeDisplay(view)
}
