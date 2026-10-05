import Testing

@testable import OpenPocketViewCore

@Suite struct GamepadOperatorTests {
    @Test func discussion159FaceShoulderAndDpad() {
        #expect(GamepadOperatorMap.face(.a) == .record)
        #expect(GamepadOperatorMap.face(.b) == .recenter)
        #expect(GamepadOperatorMap.face(.x) == .flip)
        #expect(GamepadOperatorMap.face(.y) == .track)
        #expect(GamepadOperatorMap.shoulder(.left) == .zoomChipOut)
        #expect(GamepadOperatorMap.shoulder(.right) == .zoomChipIn)
        #expect(GamepadOperatorMap.dpad(.up) == .isoUp)
        #expect(GamepadOperatorMap.dpad(.down) == .isoDown)
        #expect(GamepadOperatorMap.dpad(.left) == .shutterOpen)
        #expect(GamepadOperatorMap.dpad(.right) == .shutterClose)
    }

    @Test func gimbalStickDefaultsLeftAndIgnoresTheOtherAxes() {
        #expect(GamepadGimbalStick.default == .left)
        #expect(GamepadGimbalStick.parse(nil) == .left)
        #expect(GamepadGimbalStick.parse("") == .left)
        #expect(GamepadGimbalStick.parse("right") == .right)
        #expect(GamepadGimbalStick.fromLabel("Right") == .right)
        #expect(GamepadGimbalStick.fromLabel("Left") == .left)
        let left = GamepadGimbalStick.left.axes(leftX: 0.8, leftY: -0.2, rightX: -1, rightY: 1)
        #expect(left.x == 0.8)
        #expect(left.y == -0.2)
        let right = GamepadGimbalStick.right.axes(leftX: 0.8, leftY: -0.2, rightX: -1, rightY: 1)
        #expect(right.x == -1)
        #expect(right.y == 1)
        #expect(GamepadGimbalStick.restHeldMotion(from: .left, to: .right, driving: true))
        #expect(!GamepadGimbalStick.restHeldMotion(from: .left, to: .left, driving: true))
        #expect(!GamepadGimbalStick.restHeldMotion(from: .left, to: .right, driving: false))
    }

}
