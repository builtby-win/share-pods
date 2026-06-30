import XCTest
@testable import SharePods

@MainActor
final class SharePodsStateTests: XCTestCase {
    func testMockStateTransitions() {
        let state = SharePodsState()

        XCTAssertEqual(state.mode, .idle)
        XCTAssertEqual(state.connectedDevices.count, 1)
        XCTAssertEqual(state.sortedDevices.first?.name, "Winston's AirPods Pro")

        state.addSecondDevice()
        XCTAssertEqual(state.mode, .ready)
        XCTAssertEqual(state.connectedDevices.count, 2)

        state.startSharing()
        XCTAssertEqual(state.mode, .sharing)
        XCTAssertEqual(state.devices.filter(\.isSharing).count, 2)

        state.simulateDisconnect()
        XCTAssertEqual(state.mode, .issue)
        XCTAssertTrue(state.devices.contains(where: { !$0.isConnected }))

        state.reset()
        XCTAssertEqual(state.mode, .idle)
        XCTAssertEqual(state.connectedDevices.count, 1)
        XCTAssertFalse(state.autoShareNextTime)
    }

    func testAddSecondDeviceDoesNothingWhileSharing() {
        let state = SharePodsState()

        state.addSecondDevice()
        state.startSharing()

        let connectedCount = state.connectedDevices.count
        let sharingCount = state.devices.filter(\.isSharing).count

        state.addSecondDevice()

        XCTAssertEqual(state.mode, .sharing)
        XCTAssertEqual(state.connectedDevices.count, connectedCount)
        XCTAssertEqual(state.devices.filter(\.isSharing).count, sharingCount)
    }
}
