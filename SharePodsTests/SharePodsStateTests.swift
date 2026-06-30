import XCTest
@testable import SharePods

@MainActor
final class SharePodsStateTests: XCTestCase {
    func testMergeDevicesPrefersLiveOutputAndSortsConnectedFirst() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let liveDevices = [
            AudioOutputDevice(uid: "alpha", name: "Alpha", lastSeen: base, isConnected: true),
            AudioOutputDevice(uid: "charlie", name: "Charlie", lastSeen: base, isConnected: true)
        ]
        let knownDevices = [
            AudioOutputDevice(uid: "bravo", name: "Bravo", lastSeen: base.addingTimeInterval(-3_600), isConnected: false),
            AudioOutputDevice(uid: "delta", name: "Delta", lastSeen: base.addingTimeInterval(-120), isConnected: false)
        ]

        let merged = SharePodsState.mergeDevices(
            liveDevices: liveDevices,
            knownDevices: knownDevices,
            sharingDeviceUIDs: ["charlie"]
        )

        XCTAssertEqual(merged.map(\.uid), ["alpha", "charlie", "delta", "bravo"])
        XCTAssertTrue(merged.first { $0.uid == "charlie" }?.isSharing ?? false)
        XCTAssertFalse(merged.last?.isConnected ?? true)
    }

    func testModeDerivationPrioritizesIssueSharingReadyAndIdle() {
        let connectedDevices = [
            AudioOutputDevice(uid: "alpha", name: "Alpha", isConnected: true),
            AudioOutputDevice(uid: "bravo", name: "Bravo", isConnected: true)
        ]
        let idleDevices = [
            AudioOutputDevice(uid: "alpha", name: "Alpha", isConnected: true)
        ]

        XCTAssertEqual(
            SharePodsState.mode(for: connectedDevices, sharingDeviceUIDs: [], issueMessage: nil),
            .ready
        )
        XCTAssertEqual(
            SharePodsState.mode(for: connectedDevices, sharingDeviceUIDs: ["alpha", "bravo"], issueMessage: nil),
            .sharing
        )
        XCTAssertEqual(
            SharePodsState.mode(for: connectedDevices, sharingDeviceUIDs: [], issueMessage: "Boom"),
            .issue
        )
        XCTAssertEqual(
            SharePodsState.mode(for: idleDevices, sharingDeviceUIDs: [], issueMessage: nil),
            .idle
        )
    }

    func testAutoShareGateRequiresEnabledRegisteredPairAndConnectedDevices() {
        let connectedUIDs: Set<String> = ["alpha", "bravo"]
        let registeredPair = RegisteredDevicePair(firstUID: "alpha", secondUID: "bravo")

        XCTAssertTrue(
            SharePodsState.shouldAutoShare(
                autoShareEnabled: true,
                registeredPair: registeredPair,
                connectedUIDs: connectedUIDs,
                sharingDeviceUIDs: [],
                issueMessage: nil
            )
        )
        XCTAssertFalse(
            SharePodsState.shouldAutoShare(
                autoShareEnabled: false,
                registeredPair: registeredPair,
                connectedUIDs: connectedUIDs,
                sharingDeviceUIDs: [],
                issueMessage: nil
            )
        )
        XCTAssertFalse(
            SharePodsState.shouldAutoShare(
                autoShareEnabled: true,
                registeredPair: registeredPair,
                connectedUIDs: ["alpha"],
                sharingDeviceUIDs: [],
                issueMessage: nil
            )
        )
        XCTAssertFalse(
            SharePodsState.shouldAutoShare(
                autoShareEnabled: true,
                registeredPair: registeredPair,
                connectedUIDs: connectedUIDs,
                sharingDeviceUIDs: ["alpha", "bravo"],
                issueMessage: nil
            )
        )
        XCTAssertFalse(
            SharePodsState.shouldAutoShare(
                autoShareEnabled: true,
                registeredPair: registeredPair,
                connectedUIDs: connectedUIDs,
                sharingDeviceUIDs: [],
                issueMessage: "Boom"
            )
        )
    }

    func testKnownDevicesStoreRoundTripsThroughIsolatedUserDefaults() {
        let suiteName = "SharePodsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = KnownDevicesStore(userDefaults: defaults)
        let lastSeen = Date(timeIntervalSince1970: 1_234_567)
        let device = AudioOutputDevice(uid: "alpha", name: "Alpha", lastSeen: lastSeen, isConnected: true)

        store.autoShareEnabled = true
        store.previousOutputUID = "system-output"
        store.registeredPair = RegisteredDevicePair(firstUID: "alpha", secondUID: "bravo")
        store.upsertKnownDevices([device])

        let reloadedStore = KnownDevicesStore(userDefaults: defaults)
        let reloadedDevices = reloadedStore.loadKnownDevices()

        XCTAssertEqual(reloadedStore.autoShareEnabled, true)
        XCTAssertEqual(reloadedStore.previousOutputUID, "system-output")
        XCTAssertEqual(
            reloadedStore.registeredPair,
            RegisteredDevicePair(firstUID: "alpha", secondUID: "bravo")
        )
        XCTAssertEqual(reloadedDevices.count, 1)
        XCTAssertEqual(reloadedDevices.first?.uid, "alpha")
        XCTAssertEqual(reloadedDevices.first?.name, "Alpha")
        XCTAssertEqual(reloadedDevices.first?.lastSeen, lastSeen)
        XCTAssertFalse(reloadedDevices.first?.isConnected ?? true)
    }
}
