/// Per-integration presentation and media addressing for one camera session. Replaces the
/// launch-time globals brands used to set (labels, media host and path rules), so two sessions
/// with different cameras never read each other's configuration.
public struct CameraProfile: Sendable, Equatable {
    public var shootingModeLabels: [ShootingMode: String]
    public var colorModeLabels: [ColorMode: String]
    public var gimbalModeLabels: [GimbalMode: String]
    public var media: MediaHTTP.Route

    public init(
        shootingModeLabels: [ShootingMode: String] = [:], colorModeLabels: [ColorMode: String] = [:],
        gimbalModeLabels: [GimbalMode: String] = [:], media: MediaHTTP.Route = .dji
    ) {
        self.shootingModeLabels = shootingModeLabels
        self.colorModeLabels = colorModeLabels
        self.gimbalModeLabels = gimbalModeLabels
        self.media = media
    }

    /// DJI names and the DJI SoftAP `/v2` media route.
    public static let dji = CameraProfile()
}
