import Combine
import Foundation

enum SharePodsMode: Equatable {
    case idle
    case ready
    case sharing
    case issue

    var title: String {
        switch self {
        case .idle:
            return "SharePods"
        case .ready:
            return "Ready to share"
        case .sharing:
            return "Sharing audio"
        case .issue:
            return "CoreAudio issue"
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "Connect two output devices to begin sharing."
        case .ready:
            return "The registered pair is connected and ready to route audio."
        case .sharing:
            return "System audio is flowing through the SharePods aggregate device."
        case .issue:
            return "Refresh to check the devices again or Reset to clear the failure."
        }
    }

    var menuBarSystemImage: String {
        switch self {
        case .idle:
            return "speaker.wave.2"
        case .ready:
            return "speaker.wave.2.fill"
        case .sharing:
            return "shareplay"
        case .issue:
            return "exclamationmark.triangle"
        }
    }
}

@MainActor
final class SharePodsState: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice]
    @Published private(set) var autoShareEnabled: Bool
    @Published private(set) var issueMessage: String?
    @Published private(set) var selectedDeviceUIDs: Set<String>
    @Published private(set) var sharedDeviceVolumes: [String: Float]
    private let store: KnownDevicesStore
    private let coreAudio: CoreAudioManaging
    private var sharingDeviceUIDs: Set<String>
    private var refreshTimer: Timer?
    private var operationIssueMessage: String?

    init(
        store: KnownDevicesStore = KnownDevicesStore(),
        coreAudio: CoreAudioManaging = CoreAudioManager()
    ) {
        self.store = store
        self.coreAudio = coreAudio
        self.devices = store.loadKnownDevices()
        self.autoShareEnabled = store.autoShareEnabled
        self.issueMessage = nil
        self.sharingDeviceUIDs = []
        self.operationIssueMessage = nil
        self.selectedDeviceUIDs = []
        self.sharedDeviceVolumes = [:]
        _ = refreshDevices(triggerAutoShare: true)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        coreAudio.setDeviceChangeHandler { [weak self] in
            self?.refresh()
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    var connectedDevices: [AudioOutputDevice] {
        devices.filter { $0.isConnected }
    }

    var sortedDevices: [AudioOutputDevice] {
        devices
    }

    var visibleDevices: [AudioOutputDevice] {
        devices.filter(\.isVisibleShareOutput)
    }

    var otherOutputDevices: [AudioOutputDevice] {
        devices.filter { !$0.isVisibleShareOutput }
    }

    var canStartSharing: Bool {
        Self.selectedPair(from: selectedDeviceUIDs, devices: devices) != nil
    }

    var mode: SharePodsMode {
        Self.mode(for: devices, sharingDeviceUIDs: sharingDeviceUIDs, issueMessage: issueMessage)
    }

    var statusMessage: String {
        issueMessage ?? mode.message
    }

    var isSharingActive: Bool {
        !sharingDeviceUIDs.isEmpty
    }

    func refresh() {
        _ = refreshDevices(triggerAutoShare: true)
    }

    func setAutoShareEnabled(_ enabled: Bool) {
        guard autoShareEnabled != enabled else {
            return
        }

        autoShareEnabled = enabled
        store.autoShareEnabled = enabled

        if enabled {
            _ = refreshDevices(triggerAutoShare: true)
        }
    }

    func toggleDeviceSelection(_ uid: String) {
        guard sharingDeviceUIDs.isEmpty,
              let device = devices.first(where: { $0.uid == uid }),
              device.isSelectableForSharing else {
            return
        }

        if selectedDeviceUIDs.contains(uid) {
            selectedDeviceUIDs.remove(uid)
        } else if selectedDeviceUIDs.count < 2 {
            selectedDeviceUIDs.insert(uid)
        }
    }

    func startSharing() {
        guard refreshDevices(triggerAutoShare: false) else {
            return
        }

        guard let pair = Self.registeredPairForSharing(
            registeredPair: store.registeredPair,
            devices: sortedDevices,
            selectedDeviceUIDs: selectedDeviceUIDs
        ) else {
            return
        }

        do {
            guard let currentDefaultOutputUID = try coreAudio.currentDefaultOutputDeviceUID() else {
                operationIssueMessage = "Couldn’t determine the current default output device."
                updateIssueMessage()
                return
            }

            if currentDefaultOutputUID != SharePodsAudioConstants.aggregateUID {
                store.previousOutputUID = currentDefaultOutputUID
            }

            try coreAudio.startSharing(using: pair.orderedUIDs)
            store.registeredPair = pair
            sharingDeviceUIDs = Set(pair.orderedUIDs)
            selectedDeviceUIDs = Set(pair.orderedUIDs)
            devices = Self.sortDevices(Self.applySharingState(to: devices, sharingDeviceUIDs: sharingDeviceUIDs))
            refreshSharedDeviceVolumes()
            operationIssueMessage = nil
            updateIssueMessage()
            store.upsertKnownDevices(devices)
        } catch {
            operationIssueMessage = error.localizedDescription
            updateIssueMessage()
        }
    }

    func stopSharing() {
        guard !sharingDeviceUIDs.isEmpty else {
            return
        }

        do {
            try coreAudio.stopSharing(restoring: store.previousOutputUID)
            operationIssueMessage = nil
            sharingDeviceUIDs = []
            sharedDeviceVolumes = [:]
            devices = Self.sortDevices(Self.applySharingState(to: devices, sharingDeviceUIDs: sharingDeviceUIDs))
            updateIssueMessage()
            store.upsertKnownDevices(devices)
        } catch {
            operationIssueMessage = error.localizedDescription
            updateIssueMessage()
        }
    }

    @discardableResult
    func adjustSharedVolume(by delta: Float) -> Bool {
        guard !sharingDeviceUIDs.isEmpty else {
            return false
        }

        do {
            try coreAudio.adjustVolume(for: Array(sharingDeviceUIDs), by: delta)
            refreshSharedDeviceVolumes()
            operationIssueMessage = nil
            updateIssueMessage()
            return true
        } catch {
            operationIssueMessage = error.localizedDescription
            updateIssueMessage()
            return false
        }
    }

    @discardableResult
    func setSharedVolume(_ volume: Float, for uid: String) -> Bool {
        let clampedVolume = min(1, max(0, volume))
        guard sharingDeviceUIDs.contains(uid), sharedDeviceVolumes[uid] != nil else {
            return false
        }

        do {
            try coreAudio.setVolume(clampedVolume, for: uid)
            sharedDeviceVolumes[uid] = clampedVolume
            operationIssueMessage = nil
            updateIssueMessage()
            return true
        } catch {
            operationIssueMessage = error.localizedDescription
            updateIssueMessage()
            return false
        }
    }

    func reset() {
        guard sharingDeviceUIDs.isEmpty else {
            stopSharing()
            return
        }

        operationIssueMessage = nil
        devices = Self.sortDevices(Self.applySharingState(to: devices, sharingDeviceUIDs: sharingDeviceUIDs))
        updateIssueMessage()
        _ = refreshDevices(triggerAutoShare: true)
    }

    private func refreshSharedDeviceVolumes() {
        guard !sharingDeviceUIDs.isEmpty else {
            sharedDeviceVolumes = [:]
            return
        }

        var refreshedVolumes: [String: Float] = [:]
        for uid in sharingDeviceUIDs {
            do {
                if let volume = try coreAudio.volume(for: uid) {
                    refreshedVolumes[uid] = volume
                }
            } catch {
                continue
            }
        }

        sharedDeviceVolumes = refreshedVolumes
    }


    static func mergeDevices(
        liveDevices: [AudioOutputDevice],
        knownDevices: [AudioOutputDevice],
        sharingDeviceUIDs: Set<String>
    ) -> [AudioOutputDevice] {
        var knownByUID = Dictionary(uniqueKeysWithValues: knownDevices.map { ($0.uid, $0) })
        let now = Date()

        let mergedLiveDevices = liveDevices.map { liveDevice in
            let knownDevice = knownByUID.removeValue(forKey: liveDevice.uid)
            let bestKnownName = knownDevice?.name.isEmpty == false ? knownDevice?.name : nil
            let lastSeen = max(knownDevice?.lastSeen ?? liveDevice.lastSeen, liveDevice.lastSeen)

            return AudioOutputDevice(
                uid: liveDevice.uid,
                name: liveDevice.name.isEmpty ? (bestKnownName ?? liveDevice.name) : liveDevice.name,
                lastSeen: max(lastSeen, now),
                isConnected: true,
                isSharing: sharingDeviceUIDs.contains(liveDevice.uid),
                transport: liveDevice.transport == .unknown ? (knownDevice?.transport ?? .unknown) : liveDevice.transport
            )
        }

        let mergedDisconnectedDevices = knownByUID.values.map { knownDevice in
            AudioOutputDevice(
                uid: knownDevice.uid,
                name: knownDevice.name,
                lastSeen: knownDevice.lastSeen,
                isConnected: false,
                isSharing: false
            )
        }

        return sortDevices(mergedLiveDevices + mergedDisconnectedDevices)
    }

    static func mode(
        for devices: [AudioOutputDevice],
        sharingDeviceUIDs: Set<String>,
        issueMessage: String?
    ) -> SharePodsMode {
        if issueMessage != nil {
            return .issue
        }

        let connectedUIDs = Set(devices.filter { $0.isConnected }.map(\.uid))
        if !sharingDeviceUIDs.isEmpty, sharingDeviceUIDs.isSubset(of: connectedUIDs) {
            return .sharing
        }

        if devices.filter(\.isSelectableForSharing).count >= 2 {
            return .ready
        }

        return .idle
    }

    static func shouldAutoShare(
        autoShareEnabled: Bool,
        registeredPair: RegisteredDevicePair?,
        connectedUIDs: Set<String>,
        sharingDeviceUIDs: Set<String>,
        issueMessage: String?
    ) -> Bool {
        guard autoShareEnabled,
              issueMessage == nil,
              sharingDeviceUIDs.isEmpty,
              let registeredPair,
              registeredPair.isConnected(in: connectedUIDs) else {
            return false
        }

        return true
    }

    static func registeredPairForSharing(
        registeredPair: RegisteredDevicePair?,
        devices: [AudioOutputDevice],
        selectedDeviceUIDs: Set<String> = []
    ) -> RegisteredDevicePair? {
        if let selectedPair = selectedPair(from: selectedDeviceUIDs, devices: devices) {
            return selectedPair
        }

        let selectableUIDs = Set(devices.filter(\.isSelectableForSharing).map(\.uid))
        if let registeredPair, registeredPair.isConnected(in: selectableUIDs) {
            return registeredPair
        }

        let autoSelectedDevices = devices.filter(\.shouldAutoSelectForSharing)
        guard autoSelectedDevices.count >= 2 else {
            return nil
        }

        return RegisteredDevicePair(
            firstUID: autoSelectedDevices[0].uid,
            secondUID: autoSelectedDevices[1].uid
        )
    }

    static func selectedPair(
        from selectedDeviceUIDs: Set<String>,
        devices: [AudioOutputDevice]
    ) -> RegisteredDevicePair? {
        guard selectedDeviceUIDs.count == 2 else {
            return nil
        }

        let selectedDevices = devices.filter { selectedDeviceUIDs.contains($0.uid) && $0.isSelectableForSharing }
        guard selectedDevices.count == 2 else {
            return nil
        }

        return RegisteredDevicePair(firstUID: selectedDevices[0].uid, secondUID: selectedDevices[1].uid)
    }

    static func sortDevices(_ devices: [AudioOutputDevice]) -> [AudioOutputDevice] {
        devices.sorted { left, right in
            if left.isConnected != right.isConnected {
                return left.isConnected && !right.isConnected
            }

            if left.shareListRank != right.shareListRank {
                return left.shareListRank < right.shareListRank
            }

            if left.lastSeen != right.lastSeen {
                return left.lastSeen > right.lastSeen
            }

            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    static func applySharingState(
        to devices: [AudioOutputDevice],
        sharingDeviceUIDs: Set<String>
    ) -> [AudioOutputDevice] {
        devices.map { device in
            var updatedDevice = device
            updatedDevice.isSharing = device.isConnected && sharingDeviceUIDs.contains(device.uid)
            return updatedDevice
        }
    }

    private func refreshDevices(triggerAutoShare: Bool) -> Bool {
        do {
            try recoverOrphanedSharePodsAggregateIfNeeded()
            let liveDevices = try coreAudio.refreshOutputDevices()
            let knownDevices = store.loadKnownDevices()
            devices = Self.mergeDevices(
                liveDevices: liveDevices,
                knownDevices: knownDevices,
                sharingDeviceUIDs: sharingDeviceUIDs
            )
            store.upsertKnownDevices(devices)
            syncSelectedDevices()
            refreshSharedDeviceVolumes()

            operationIssueMessage = nil
            updateIssueMessage()

            if triggerAutoShare {
                maybeAutoShareIfNeeded()
            }

            return true
        } catch {
            operationIssueMessage = error.localizedDescription
            updateIssueMessage()
            return false
        }
    }

    private func recoverOrphanedSharePodsAggregateIfNeeded() throws {
        guard sharingDeviceUIDs.isEmpty else {
            return
        }

        if try coreAudio.removeSharePodsAggregateIfNeeded(restoring: store.previousOutputUID) {
            store.previousOutputUID = nil
        }
    }

    private func maybeAutoShareIfNeeded() {
        guard Self.shouldAutoShare(
            autoShareEnabled: autoShareEnabled,
            registeredPair: store.registeredPair,
            connectedUIDs: Set(devices.filter(\.isSelectableForSharing).map(\.uid)),
            sharingDeviceUIDs: sharingDeviceUIDs,
            issueMessage: issueMessage
        ) else {
            return
        }

        startSharing()
    }

    private func syncSelectedDevices() {
        let selectableUIDs = Set(devices.filter(\.isSelectableForSharing).map(\.uid))

        if !sharingDeviceUIDs.isEmpty {
            selectedDeviceUIDs = sharingDeviceUIDs.intersection(selectableUIDs)
            return
        }

        selectedDeviceUIDs.formIntersection(selectableUIDs)
        let autoSelection = Self.autoSelectedDeviceUIDs(for: devices, registeredPair: store.registeredPair)
        if selectedDeviceUIDs.isEmpty || (selectedDeviceUIDs.count < 2 && autoSelection.count >= 2) {
            selectedDeviceUIDs = autoSelection
        }
    }

    private static func autoSelectedDeviceUIDs(
        for devices: [AudioOutputDevice],
        registeredPair: RegisteredDevicePair?
    ) -> Set<String> {
        let selectableUIDs = Set(devices.filter(\.isSelectableForSharing).map(\.uid))
        if let registeredPair, registeredPair.isConnected(in: selectableUIDs) {
            return Set(registeredPair.orderedUIDs)
        }

        let headphones = devices.filter(\.shouldAutoSelectForSharing)
        if headphones.count >= 2 {
            return Set(headphones.prefix(2).map(\.uid))
        }

        return Set(headphones.map(\.uid))
    }

    private func updateIssueMessage() {
        issueMessage = operationIssueMessage ?? Self.sharingIssueMessage(
            devices: devices,
            sharingDeviceUIDs: sharingDeviceUIDs
        )
    }

    private static func sharingIssueMessage(
        devices: [AudioOutputDevice],
        sharingDeviceUIDs: Set<String>
    ) -> String? {
        guard !sharingDeviceUIDs.isEmpty else {
            return nil
        }

        let connectedUIDs = Set(devices.filter { $0.isConnected }.map(\.uid))
        guard !sharingDeviceUIDs.isSubset(of: connectedUIDs) else {
            return nil
        }

        return "One of the shared devices is no longer connected."
    }
}
