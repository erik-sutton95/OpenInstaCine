import Foundation
import XCTest

@testable import Insta360Protocol

private func hex(_ value: String) -> Data {
    var data = Data()
    var index = value.startIndex
    while index < value.endIndex {
        let next = value.index(index, offsetBy: 2)
        data.append(UInt8(value[index..<next], radix: 16)!)
        index = next
    }
    return data
}

final class LunaGimbalPoseTests: XCTestCase {
    func testDecodesCapturedIMUFrame() throws {
        // First 0x30 frame of the 2026-09-29 take, two records.
        let payload = hex(
            "3097db22000000000097db220000000000000000000000803f00000000000077bf0000000000feefbf00000000000000008aad84fa0a7451bf8aad84fa0a74513f98db220000000000000000000080803f00000000000075bf000000000002f0bf00000000000000008aad84fa0a74513f8aad84fa0a74513f")
        let frame = try UCD2Frame.plain(type: UCD2Frame.mediaType, sequence: 0, payload: payload)
        let samples = try XCTUnwrap(LunaMediaPacket(frame: frame).imuSamples)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[1].milliseconds, samples[0].milliseconds + 1)
        XCTAssertEqual(samples[0].accel.z, -1.0, accuracy: 0.01, "level and still: 1 g down")
        XCTAssertLessThan(abs(samples[0].gyro.z), 0.01)
    }

    private func samples(
        seconds: Double, gyro: SIMD3<Double>, accel: SIMD3<Double> = SIMD3(0, 0, -1), start: UInt64
    ) -> [LunaIMUSample] {
        (0..<Int(seconds * 1000)).map {
            LunaIMUSample(milliseconds: start + UInt64($0), accel: accel, gyro: gyro)
        }
    }

    func testIntegratesPanAndLearnsBias() {
        var pose = LunaGimbalPoseEstimator()
        let bias = SIMD3<Double>(0, 0, 0.002)
        pose.ingest(samples(seconds: 2, gyro: bias, start: 0))
        XCTAssertEqual(pose.gyroBias.z, 0.002, accuracy: 0.0005, "still head teaches the bias")
        pose.zeroYaw()
        // 20 °/s to the right for 1 s, commanded.
        let rate = 20 * Double.pi / 180
        pose.ingest(samples(seconds: 1, gyro: SIMD3(0, 0, rate) + bias, start: 2000), commanding: true)
        XCTAssertEqual(pose.yawDeg, 20, accuracy: 0.5)
        pose.ingest(samples(seconds: 5, gyro: bias, start: 3000))
        XCTAssertEqual(pose.yawDeg, 20, accuracy: 0.5, "bias does not drift yaw")
    }

    func testPitchFollowsGravity() {
        var pose = LunaGimbalPoseEstimator()
        // Tilted up 30°: gravity has +x (sin 30) and −z (cos 30) components.
        let up30 = SIMD3<Double>(0.5, 0, -0.866)
        XCTAssertEqual(LunaGimbalPoseEstimator.gravityPitchDeg(up30), 30, accuracy: 0.1)
        pose.ingest(samples(seconds: 5, gyro: .zero, accel: up30, start: 0))
        XCTAssertEqual(pose.pitchDeg, 30, accuracy: 0.5)
    }

    func testSteerIsProportionalClampedAndRestsInDeadband() {
        let near = LunaGimbalSteer.toward(yawError: 0.2, pitchError: -0.1)
        XCTAssertTrue(near.isRest)
        let small = LunaGimbalSteer.toward(yawError: 10, pitchError: -4)
        XCTAssertEqual(small.leftRight, 48)  // 30 °/s / 0.62
        XCTAssertEqual(small.upDown, -24)  // −12 °/s / 0.49
        // Still panning at full speed 5° short: the lead says the head will arrive, so back off.
        let coasting = LunaGimbalSteer.toward(
            yawError: 5, pitchError: 0, previous: LunaGimbalSteer(leftRight: 99, upDown: 0))
        XCTAssertLessThan(coasting.leftRight, 0)
        let far = LunaGimbalSteer.toward(yawError: 170, pitchError: 90)
        XCTAssertEqual(far.leftRight, 99)
        XCTAssertEqual(far.upDown, 99)
    }
}
