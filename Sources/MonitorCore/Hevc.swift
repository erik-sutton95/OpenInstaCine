import Foundation

/// Standard HEVC / H.265 NAL typing and Annex-B splitting.
/// Backend-specific envelope/marker removal and native decoding live outside this module.
public enum Hevc {
    /// HEVC NAL unit type from the first byte of the 2-byte NAL header: `(b >> 1) & 0x3f`.
    public static func nalType(_ firstByte: UInt8) -> Int { Int((firstByte >> 1) & 0x3f) }

    // Named types we care about.
    public static let vps = 32, sps = 33, pps = 34
    public static let idr = 20  // IDR_N_LP
    /// BLA_W_LP — Pocket 4 / 4 Pro live GOP start is often this, not type 20.
    public static let blaWLP = 16
    public static let craNut = 21
    public static func isVCL(_ t: Int) -> Bool { t <= 31 }  // 0..31 = coded slice NALs
    /// HEVC IRAP pictures (BLA 16–18, IDR 19–20, CRA 21). Holding IDR for type
    /// 20 only froze the canvas on a live BLA GOP (`feed: freeze`, UDP young).
    public static func isIRAP(_ t: Int) -> Bool { (16...21).contains(t) }
    public static func isKeyframeNal(_ t: Int) -> Bool {
        t == vps || t == sps || t == pps || isIRAP(t)
    }

    /// UDP-queue pending cap must not drop the AU that latches format.
    public static func accessUnitCarriesKeyframe(_ annexB: [UInt8]) -> Bool {
        nalUnits(annexB).contains { !$0.isEmpty && isKeyframeNal(nalType($0[0])) }
    }

    /// Split an Annex-B buffer into raw NAL units (start codes removed). Handles 3- and 4-byte
    /// start codes by trimming a trailing zero that belongs to the next start code.
    public static func nalUnits(_ annexB: [UInt8]) -> [[UInt8]] {
        var starts: [Int] = []
        var i = 0
        while i + 3 <= annexB.count {
            if annexB[i] == 0, annexB[i + 1] == 0, annexB[i + 2] == 1 {
                starts.append(i + 3)
                i += 3
            } else {
                i += 1
            }
        }
        var nals: [[UInt8]] = []
        for (k, s) in starts.enumerated() {
            var e = (k + 1 < starts.count) ? starts[k + 1] - 3 : annexB.count
            while e > s && annexB[e - 1] == 0 { e -= 1 }  // ponytail: drops a genuine trailing 0x00 too; harmless for decode
            if e > s { nals.append(Array(annexB[s..<e])) }
        }
        return nals
    }
}
