import CoreAudio
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

    func testAggregateDescriptionMirrorsAudioAndDriftCorrectsSecondaryDevices() {
        let description = CoreAudioManager.aggregateDeviceDescription(for: ["alpha", "bravo", "charlie"])
        let subdevices = description[kAudioAggregateDeviceSubDeviceListKey as String] as? [[String: Any]]

        XCTAssertEqual(description[kAudioAggregateDeviceUIDKey as String] as? String, SharePodsAudioConstants.aggregateUID)
        XCTAssertEqual(description[kAudioAggregateDeviceNameKey as String] as? String, SharePodsAudioConstants.aggregateName)
        XCTAssertEqual(description[kAudioAggregateDeviceMainSubDeviceKey as String] as? String, "alpha")
        XCTAssertEqual((description[kAudioAggregateDeviceIsStackedKey as String] as? NSNumber)?.intValue, 0)
        XCTAssertEqual(subdevices?.count, 3)
        XCTAssertEqual(subdevices?[0][kAudioSubDeviceUIDKey as String] as? String, "alpha")
        XCTAssertEqual((subdevices?[0][kAudioSubDeviceDriftCompensationKey as String] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((subdevices?[1][kAudioSubDeviceDriftCompensationKey as String] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((subdevices?[2][kAudioSubDeviceDriftCompensationKey as String] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(
            (subdevices?[1][kAudioSubDeviceDriftCompensationQualityKey as String] as? NSNumber)?.uint32Value,
            kAudioAggregateDriftCompensationMediumQuality
        )
    }

    func testSuccessfulRefreshClearsTransientOperationIssue() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.refreshError = CoreAudioError.deviceEnumerationFailed(-1)
        let state = SharePodsState(store: store, coreAudio: coreAudio)

        XCTAssertEqual(state.mode, .issue)

        coreAudio.refreshError = nil
        state.refresh()

        XCTAssertNil(state.issueMessage)
        XCTAssertEqual(state.mode, .ready)
        XCTAssertEqual(store.loadKnownDevices().map(\.uid), ["alpha", "bravo"])
    }

    func testStopSharingFailurePreservesRetryState() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        let state = SharePodsState(store: store, coreAudio: coreAudio)

        state.startSharing()
        XCTAssertEqual(state.mode, .sharing)

        coreAudio.stopError = CoreAudioError.defaultOutputWriteFailed(-1)
        state.stopSharing()

        XCTAssertEqual(state.mode, .issue)
        XCTAssertTrue(state.isSharingActive)
        XCTAssertEqual(state.devices.filter(\.isSharing).count, 2)

        state.reset()
        XCTAssertEqual(coreAudio.stopCallCount, 2)
        XCTAssertTrue(state.isSharingActive)
    }

    func testSuccessfulStopSharingClearsSharingState() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        let state = SharePodsState(store: store, coreAudio: coreAudio)

        state.startSharing()
        state.stopSharing()

        XCTAssertEqual(coreAudio.stopCallCount, 1)
        XCTAssertFalse(state.isSharingActive)
        XCTAssertEqual(state.devices.filter(\.isSharing).count, 0)
        XCTAssertEqual(state.mode, .ready)
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

    private func makeIsolatedStore() -> (KnownDevicesStore, () -> Void) {
        let suiteName = "SharePodsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        return (
            KnownDevicesStore(userDefaults: defaults),
            { defaults.removePersistentDomain(forName: suiteName) }
        )
    }
}

private final class TestCoreAudioManager: CoreAudioManaging {
    var outputDevices = [
        AudioOutputDevice(uid: "alpha", name: "Alpha", isConnected: true),
        AudioOutputDevice(uid: "bravo", name: "Bravo", isConnected: true)
    ]
    var refreshError: Error?
    var currentOutputUID: String? = "system-output"
    var stopError: Error?
    private(set) var stopCallCount = 0

    func refreshOutputDevices() throws -> [AudioOutputDevice] {
        if let refreshError {
            throw refreshError
        }

        return outputDevices
    }

    func currentDefaultOutputDeviceUID() throws -> String? {
        currentOutputUID
    }

    func startSharing(using subdeviceUIDs: [String]) throws {}

    func stopSharing(restoring previousOutputUID: String?) throws {
        stopCallCount += 1
        if let stopError {
            throw stopError
        }
    }
}
