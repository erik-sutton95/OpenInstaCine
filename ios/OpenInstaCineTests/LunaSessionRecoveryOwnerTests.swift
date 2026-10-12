import Foundation
import OpenInstaViewCore
import Testing

@testable import OpenInstaCine

/// SIMULATED transport over the actual Luna app recovery owner, on manual time.
@Suite("Luna composed session recovery") @MainActor
struct LunaSessionRecoveryOwnerTests {
  @MainActor private final class Peer {
    let clock = Clock()
    var picture: (TimeInterval?, TimeInterval?) = (nil, nil)
    var connects = 0
    var live = true
    func session(controlsOnly: Bool = false) -> CameraSession {
      let session = CameraSession(backend: AppModel.makeBackend(), controlsOnly: controlsOnly)
      session.sessionRecoveryPeers = .init(
        cameraID: UUID(),
        connect: { [unowned self, weak session] in
          connects += 1
          session?.phase = live ? .live : .joiningWifi
          return true
        }, progress: { .running },
        picture: { [unowned self] in (picture.0, picture.1) }, timing: clock.timing)
      return session
    }
  }

  @Test func controlWithoutPictureKeepsRecoveryAndHeldMonitor() async {
    let peer = Peer()
    let session = peer.session()
    defer {
      session.cancelSessionRecovery()
      session.decoder.close()
    }
    session.beginSessionRecovery(reason: "SIMULATED control-only")
    #expect(await peer.clock.drive { peer.connects == 1 })
    peer.clock.advance(to: 5)
    await peer.clock.settle()
    #expect(session.sessionRecovery == .retrying(attempt: 1, maxAttempts: 8))
    #expect(session.holdsMonitor)
    #expect(session.sessionRecoveryCardGraceElapsed)
  }

  @Test func staleAndUnknownPicturesCannotRecoverButFreshPictureCan() async {
    let peer = Peer()
    peer.clock.time = 100
    peer.picture = (99, 99)
    let session = peer.session()
    defer {
      session.cancelSessionRecovery()
      session.decoder.close()
    }
    session.beginSessionRecovery(reason: "SIMULATED picture proof")
    #expect(await peer.clock.drive { peer.connects == 1 })
    peer.clock.advance(to: 101)
    await peer.clock.settle()
    #expect(session.sessionRecovery.isRecovering)
    peer.picture = (nil, 101)
    peer.clock.advance(to: 102)
    await peer.clock.settle()
    #expect(session.holdsMonitor)
    peer.picture = (102, 102)
    #expect(await peer.clock.drive { session.sessionRecovery == .idle })
    #expect(!session.holdsMonitor)
    #expect(!session.sessionRecoveryCardGraceElapsed)
  }

  @Test func hungTransportHandsToOperatorAt180SecondsAndStaysStopped() async {
    let peer = Peer()
    peer.live = false
    let session = peer.session()
    defer {
      session.cancelSessionRecovery()
      session.decoder.close()
    }
    session.beginSessionRecovery(reason: "SIMULATED hung connection")
    #expect(
      await peer.clock.drive {
        if case .waitingForOperator = session.sessionRecovery { return true }
        return false
      })
    #expect(abs(peer.clock.time - 180) < 1e-6)
    let connects = peer.connects
    peer.clock.advance(to: 400)
    await peer.clock.settle()
    session.beginSessionRecovery(reason: "SIMULATED duplicate reporter")
    #expect(peer.connects == connects)
    #expect(session.holdsMonitor)
  }

  @Test func cardGraceAndDropStormUseSharedOwnerAndOperatorRetry() async {
    let peer = Peer()
    let session = peer.session()
    defer {
      session.cancelSessionRecovery()
      session.decoder.close()
    }
    for _ in 0..<2 {
      let before = peer.connects
      session.beginSessionRecovery(reason: "SIMULATED drop")
      #expect(await peer.clock.drive { peer.connects > before })
      #expect(!session.sessionRecoveryCardGraceElapsed)
      peer.clock.advance(to: peer.clock.time + 0.05)
      peer.picture = (peer.clock.time, peer.clock.time)
      #expect(await peer.clock.drive { session.sessionRecovery == .idle })
    }
    session.beginSessionRecovery(reason: "SIMULATED storm")
    #expect(session.sessionRecovery == .pausedAfterRepeatedDrops(drops: 3))
    #expect(session.sessionRecoveryCardGraceElapsed)
    session.retrySessionRecovery()
    #expect(await peer.clock.drive { peer.connects == 3 })
    #expect(session.sessionRecovery == .retrying(attempt: 1, maxAttempts: 8))
  }

  @Test func borrowedBackendRefusesRecoveryAndCancelRetiresTimers() async {
    let peer = Peer()
    let borrowed = peer.session(controlsOnly: true)
    borrowed.beginSessionRecovery(reason: "SIMULATED borrowed owner")
    #expect(borrowed.sessionRecovery == .idle)
    #expect(peer.connects == 0)
    borrowed.decoder.close()
    let session = peer.session()
    defer { session.decoder.close() }
    session.beginSessionRecovery(reason: "SIMULATED cancellation")
    #expect(await peer.clock.drive { peer.connects == 1 })
    session.cancelSessionRecovery()
    peer.clock.advance(to: 400)
    await peer.clock.settle()
    #expect(session.sessionRecovery == .idle)
    #expect(!session.holdsMonitor)
    #expect(peer.connects == 1)
  }

  @MainActor final class Clock {
    private struct Sleeper {
      let id: UUID
      let at: Double
      let continuation: CheckedContinuation<Void, Error>
    }
    private let origin = ContinuousClock().now
    var time = 0.0
    private(set) var pauses: [Double] = []
    private var sleepers: [Sleeper] = []
    var backoffs: [Double] { pauses.filter { [0.5, 1, 2, 4, 8].contains($0) } }
    var timing: SessionRecoveryEpisode.Timing {
      .init(
        monotonicNow: { [unowned self] in origin.advanced(by: .seconds(time)) },
        uptime: { [unowned self] in time }, wallNow: { [unowned self] in time },
        sleep: { [unowned self] in try await pause($0) }, jitter: { 0.5 })
    }

    func pause(_ duration: Duration) async throws {
      try Task.checkCancellation()
      let id = UUID()
      let seconds =
        Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1e18
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          pauses.append(seconds)
          sleepers.append(.init(id: id, at: time + seconds, continuation: continuation))
        }
      } onCancel: {
        Task { @MainActor in
          guard let index = self.sleepers.firstIndex(where: { $0.id == id }) else {
            return
          }
          self.sleepers.remove(at: index).continuation.resume(
            throwing: CancellationError())
        }
      }
    }

    func advance(to end: Double) {
      time = max(time, end)
      let ready = sleepers.filter { $0.at <= time + 1e-9 }
      sleepers.removeAll { $0.at <= time + 1e-9 }
      for sleeper in ready { sleeper.continuation.resume() }
    }

    func settle() async { for _ in 0..<64 { await Task.yield() } }

    func drive(until done: () -> Bool) async -> Bool {
      for _ in 0..<20_000 {
        await settle()
        if done() { return true }
        guard let next = sleepers.map(\.at).min() else { return done() }
        advance(to: next)
      }
      return done()
    }
  }
}
