import OpenPocketViewCore

extension LUTSelection {
    static func djiCatalog(isPhotoLive: Bool) -> [LUTSelection] {
        // Luna ships one official cube; the DJI cubes are not bundled in this app.
        isPhotoLive ? [.officialAuto] : [.officialAuto, .iLogRec709]
    }
}
