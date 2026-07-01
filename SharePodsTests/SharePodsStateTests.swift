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

    func testHeadphonesAndSpeakersStayVisibleButOnlyHeadphonesAutoSelect() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.outputDevices = [
            AudioOutputDevice(uid: "airpods", name: "Winnie AirPods", isConnected: true, transport: .bluetooth),
            AudioOutputDevice(uid: "speaker", name: "MacBook Pro Speakers", isConnected: true, transport: .builtIn),
            AudioOutputDevice(uid: "blackhole", name: "BlackHole 2ch", isConnected: true, transport: .virtual),
            AudioOutputDevice(uid: "monitor", name: "Studio Display", isConnected: true, transport: .displayPort)
        ]

        let state = SharePodsState(store: store, coreAudio: coreAudio)

        XCTAssertEqual(state.visibleDevices.map(\.uid), ["airpods", "speaker"])
        XCTAssertEqual(state.otherOutputDevices.map(\.uid), ["blackhole", "monitor"])
        XCTAssertEqual(state.selectedDeviceUIDs, Set(["airpods"]))
        XCTAssertFalse(state.canStartSharing)
    }

    func testVirtualDeviceNamedLikeHeadphonesStaysHiddenAndUnselected() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.outputDevices = [
            AudioOutputDevice(uid: "airpods", name: "Winnie AirPods", isConnected: true, transport: .bluetooth),
            AudioOutputDevice(uid: "virtual-airpods", name: "Virtual AirPods Output", isConnected: true, transport: .virtual)
        ]

        let state = SharePodsState(store: store, coreAudio: coreAudio)

        XCTAssertEqual(state.visibleDevices.map(\.uid), ["airpods"])
        XCTAssertEqual(state.selectedDeviceUIDs, Set(["airpods"]))
        XCTAssertFalse(state.canStartSharing)
    }

    func testCoreAudioDeviceChangeRefreshesVisibleDevices() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.outputDevices = [
            AudioOutputDevice(uid: "airpods", name: "Winnie AirPods", isConnected: true, transport: .bluetooth)
        ]
        let state = SharePodsState(store: store, coreAudio: coreAudio)

        coreAudio.outputDevices.append(
            AudioOutputDevice(uid: "beats", name: "Beats Fit Pro", isConnected: true, transport: .bluetooth)
        )
        coreAudio.simulateDeviceChange()

        XCTAssertEqual(Set(state.visibleDevices.map(\.uid)), Set(["airpods", "beats"]))
        XCTAssertEqual(state.selectedDeviceUIDs, Set(["airpods", "beats"]))
        XCTAssertTrue(state.canStartSharing)
    }


    func testExactlyTwoBluetoothHeadphonesAutoSelectForSharing() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.outputDevices = [
            AudioOutputDevice(uid: "airpods", name: "Winnie AirPods", isConnected: true, transport: .bluetooth),
            AudioOutputDevice(uid: "beats", name: "Beats Fit Pro", isConnected: true, transport: .bluetooth),
            AudioOutputDevice(uid: "speaker", name: "MacBook Pro Speakers", isConnected: true, transport: .builtIn)
        ]

        let state = SharePodsState(store: store, coreAudio: coreAudio)

        XCTAssertEqual(state.selectedDeviceUIDs, Set(["airpods", "beats"]))
        XCTAssertTrue(state.canStartSharing)
    }

    func testStartSharingLoadsReadableSharedVolumes() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.readableVolumes = ["alpha": 0.25, "bravo": 0.75]
        let state = SharePodsState(store: store, coreAudio: coreAudio)

        state.startSharing()

        XCTAssertEqual(state.mode, .sharing)
        XCTAssertEqual(state.sharedDeviceVolumes["alpha"] ?? Float(-1), 0.25, accuracy: 0.0001)
        XCTAssertEqual(state.sharedDeviceVolumes["bravo"] ?? Float(-1), 0.75, accuracy: 0.0001)
    }

    func testSettingSharedVolumeWritesOnlyThatUID() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.readableVolumes = ["alpha": 0.25, "bravo": 0.75]
        let state = SharePodsState(store: store, coreAudio: coreAudio)

        state.startSharing()
        XCTAssertTrue(state.setSharedVolume(0.6, for: "alpha"))

        XCTAssertEqual(coreAudio.volumeWrites.count, 1)
        XCTAssertEqual(coreAudio.volumeWrites.first?.uid ?? "", "alpha")
        XCTAssertEqual(coreAudio.volumeWrites.first?.volume ?? Float(-1), 0.6, accuracy: 0.0001)
        XCTAssertEqual(state.sharedDeviceVolumes["alpha"] ?? Float(-1), 0.6, accuracy: 0.0001)
        XCTAssertEqual(state.sharedDeviceVolumes["bravo"] ?? Float(-1), 0.75, accuracy: 0.0001)
    }

    func testMissingSharedVolumeDataDoesNotBlockSharing() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.readableVolumes = ["alpha": 0.25]
        let state = SharePodsState(store: store, coreAudio: coreAudio)

        state.startSharing()

        XCTAssertEqual(state.mode, .sharing)
        XCTAssertEqual(state.sharedDeviceVolumes["alpha"] ?? Float(-1), 0.25, accuracy: 0.0001)
        XCTAssertNil(state.sharedDeviceVolumes["bravo"])
    }

    func testStartSharingUsesSelectedSpeakerWhenUserChoosesIt() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.outputDevices = [
            AudioOutputDevice(uid: "airpods", name: "Winnie AirPods", isConnected: true, transport: .bluetooth),
            AudioOutputDevice(uid: "speaker", name: "MacBook Pro Speakers", isConnected: true, transport: .builtIn)
        ]
        let state = SharePodsState(store: store, coreAudio: coreAudio)

        state.toggleDeviceSelection("speaker")
        state.startSharing()

        XCTAssertEqual(coreAudio.startedUIDs, ["airpods", "speaker"])
        XCTAssertEqual(state.mode, .sharing)
    }

    func testStaleRegisteredPairDoesNotBlockManualSpeakerSelection() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        store.registeredPair = RegisteredDevicePair(firstUID: "monitor", secondUID: "display")

        let coreAudio = TestCoreAudioManager()
        coreAudio.outputDevices = [
            AudioOutputDevice(uid: "airpods", name: "Winnie AirPods", isConnected: true, transport: .bluetooth),
            AudioOutputDevice(uid: "speaker", name: "MacBook Pro Speakers", isConnected: true, transport: .builtIn),
            AudioOutputDevice(uid: "monitor", name: "31.5 Monitor", isConnected: true, transport: .aggregate),
            AudioOutputDevice(uid: "display", name: "ARZOPA-315", isConnected: true, transport: .displayPort)
        ]

        let state = SharePodsState(store: store, coreAudio: coreAudio)
        state.toggleDeviceSelection("speaker")
        state.startSharing()

        XCTAssertEqual(coreAudio.startedUIDs, ["airpods", "speaker"])
    }

    func testLaunchTearsDownOrphanedSharePodsAggregateOutput() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        store.previousOutputUID = "speaker"

        let coreAudio = TestCoreAudioManager()
        coreAudio.currentOutputUID = SharePodsAudioConstants.aggregateUID
        _ = SharePodsState(store: store, coreAudio: coreAudio)

        XCTAssertEqual(coreAudio.stopCallCount, 1)
        XCTAssertEqual(coreAudio.currentOutputUID, "speaker")
    }

    func testLaunchTearsDownInactiveSharePodsAggregateEvenWhenSystemOutputAlreadyRestored() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.currentOutputUID = "speaker"
        coreAudio.hasSharePodsAggregate = true
        _ = SharePodsState(store: store, coreAudio: coreAudio)

        XCTAssertEqual(coreAudio.stopCallCount, 1)
        XCTAssertEqual(coreAudio.currentOutputUID, "speaker")
    }

    func testModeDerivationPrioritizesIssueSharingReadyAndIdle() {
        let connectedDevices = [
            AudioOutputDevice(uid: "alpha", name: "Alpha", isConnected: true, transport: .bluetooth),
            AudioOutputDevice(uid: "bravo", name: "Bravo", isConnected: true, transport: .bluetooth)
        ]
        let idleDevices = [
            AudioOutputDevice(uid: "alpha", name: "Alpha", isConnected: true, transport: .bluetooth)
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

    func testVolumeKeysAdjustSharingDevicesOnlyWhileSharing() {
        let (store, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let coreAudio = TestCoreAudioManager()
        coreAudio.readableVolumes = ["alpha": 0.25, "bravo": 0.75]
        let state = SharePodsState(store: store, coreAudio: coreAudio)

        state.startSharing()
        state.adjustSharedVolume(by: 0.1)

        XCTAssertEqual(state.sharedDeviceVolumes["alpha"] ?? Float(-1), 0.35, accuracy: 0.0001)
        XCTAssertEqual(state.sharedDeviceVolumes["bravo"] ?? Float(-1), 0.85, accuracy: 0.0001)

        state.stopSharing()
        XCTAssertTrue(state.sharedDeviceVolumes.isEmpty)

        state.adjustSharedVolume(by: -0.1)

        XCTAssertEqual(coreAudio.volumeAdjustments.count, 1)
        XCTAssertEqual(Set(coreAudio.volumeAdjustments.first?.uids ?? []), Set(["alpha", "bravo"]))
        XCTAssertEqual(coreAudio.volumeAdjustments.first?.delta ?? Float(-1), 0.1, accuracy: 0.0001)
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
        AudioOutputDevice(uid: "alpha", name: "Alpha", isConnected: true, transport: .bluetooth),
        AudioOutputDevice(uid: "bravo", name: "Bravo", isConnected: true, transport: .bluetooth)
    ]
    var readableVolumes: [String: Float] = [:]
    var refreshError: Error?
    var currentOutputUID: String? = "system-output"
    var stopError: Error?
    var hasSharePodsAggregate = false
    private(set) var stopCallCount = 0
    private(set) var startedUIDs: [String] = []
    private(set) var volumeAdjustments: [(uids: [String], delta: Float)] = []
    private(set) var volumeReads: [String] = []
    private(set) var volumeWrites: [(uid: String, volume: Float)] = []
    private var deviceChangeHandler: (@MainActor () -> Void)?

    func refreshOutputDevices() throws -> [AudioOutputDevice] {
        if let refreshError {
            throw refreshError
        }

        return outputDevices
    }

    func setDeviceChangeHandler(_ handler: @escaping @MainActor () -> Void) {
        deviceChangeHandler = handler
    }

    @MainActor func simulateDeviceChange() {
        deviceChangeHandler?()
    }

    func currentDefaultOutputDeviceUID() throws -> String? {
        currentOutputUID
    }

    func volume(for uid: String) throws -> Float? {
        volumeReads.append(uid)
        return readableVolumes[uid]
    }

    func setVolume(_ volume: Float, for uid: String) throws {
        let clampedVolume = min(1, max(0, volume))
        volumeWrites.append((uid, clampedVolume))
        readableVolumes[uid] = clampedVolume
    }

    func removeSharePodsAggregateIfNeeded(restoring previousOutputUID: String?) throws -> Bool {
        guard hasSharePodsAggregate || currentOutputUID == SharePodsAudioConstants.aggregateUID else {
            return false
        }

        stopCallCount += 1
        if let stopError {
            throw stopError
        }

        hasSharePodsAggregate = false
        if currentOutputUID == SharePodsAudioConstants.aggregateUID {
            currentOutputUID = previousOutputUID
        }
        return true
    }

    func startSharing(using subdeviceUIDs: [String]) throws {
        startedUIDs = subdeviceUIDs
        currentOutputUID = SharePodsAudioConstants.aggregateUID
    }

    func adjustVolume(for subdeviceUIDs: [String], by delta: Float) throws {
        volumeAdjustments.append((subdeviceUIDs, delta))
        for uid in subdeviceUIDs {
            guard let currentVolume = readableVolumes[uid] else {
                continue
            }

            readableVolumes[uid] = min(1, max(0, currentVolume + delta))
        }
    }

    func stopSharing(restoring previousOutputUID: String?) throws {
        stopCallCount += 1
        if let stopError {
            throw stopError
        }

        currentOutputUID = previousOutputUID
    }
}
