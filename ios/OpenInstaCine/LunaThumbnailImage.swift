import CoreImage
import CoreVideo
import Insta360Protocol
import UIKit

/// Camera thumbnails arrive as raw NV12 (cmd 11 type 2). Convert once to a cached JPEG.
enum LunaThumbnailImage {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func jpeg(_ thumb: LunaThumbnail) -> Data? {
        let width = thumb.width
        let height = thumb.height
        let lumaBytes = width * height
        guard width > 0, height > 0, thumb.nv12.count >= lumaBytes + lumaBytes / 2 else {
            return nil
        }
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard
            CVPixelBufferCreate(
                nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes,
                &buffer) == kCVReturnSuccess, let buffer
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        thumb.nv12.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for plane in 0..<2 {
                guard let dest = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { continue }
                let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
                let rows = plane == 0 ? height : height / 2
                let source = base.advanced(by: plane == 0 ? 0 : lumaBytes)
                for row in 0..<rows {
                    memcpy(
                        dest.advanced(by: row * rowBytes), source.advanced(by: row * width), width)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        // Same BT.709 limited-range decode as LunaProbe's verified converter.
        CVBufferSetAttachment(
            buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            .shouldPropagate)
        let image = CIImage(cvPixelBuffer: buffer)
        return context.jpegRepresentation(
            of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8])
    }
}
