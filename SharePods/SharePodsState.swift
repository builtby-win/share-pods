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
            return "2 devices connected"
        case .sharing:
            return "Sharing audio"
        case .issue:
            return "Device disconnected"
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "Connect another audio device to share audio."
        case .ready:
            return "Ready to route audio to both connected devices."
        case .sharing:
            return "System audio is being shared across connected devices."
        case .issue:
            return "One device disconnected. Reset the mock state to continue."
        }
    }

    var menuBarSystemImage: String {
        switch self {
        case .idle:
            return "airpodspro"
        case .ready:
            return "airpodspro.chargingcase.wireless"
        case .sharing:
            return "shareplay"
        case .issue:
            return "exclamationmark.triangle"
        }
    }
}

@MainActor
final class SharePodsState: ObservableObject {
    @Published private(set) var devices: [MockDevice]
    @Published var autoShareNextTime: Bool
    @Published private(set) var hasIssue: Bool

    init(
        devices: [MockDevice] = MockDevice.initialDevices,
        autoShareNextTime: Bool = false,
        hasIssue: Bool = false
    ) {
        self.devices = devices
        self.autoShareNextTime = autoShareNextTime
        self.hasIssue = hasIssue
    }

    var connectedDevices: [MockDevice] {
        devices.filter { $0.isConnected }
    }

    var sortedDevices: [MockDevice] {
        devices.sorted { left, right in
            if left.isConnected != right.isConnected {
                return left.isConnected && !right.isConnected
            }

            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    var mode: SharePodsMode {
        if hasIssue {
            return .issue
        }

        if devices.contains(where: { $0.isSharing }) {
            return .sharing
        }

        if connectedDevices.count >= 2 {
            return .ready
        }

        return .idle
    }

    func addSecondDevice() {
        guard let index = devices.firstIndex(where: { !$0.isConnected }) else {
            return
        }

        devices[index].isConnected = true
        hasIssue = false
    }

    func startSharing() {
        guard connectedDevices.count >= 2 else {
            return
        }

        hasIssue = false
        for index in devices.indices {
            devices[index].isSharing = devices[index].isConnected
        }
    }

    func stopSharing() {
        hasIssue = false
        for index in devices.indices {
            devices[index].isSharing = false
        }
    }

    func simulateDisconnect() {
        guard let index = devices.firstIndex(where: { $0.isConnected && ($0.isSharing || connectedDevices.count >= 2) }) else {
            return
        }

        let wasSharing = devices.contains(where: { $0.isSharing })
        devices[index].isConnected = false
        devices[index].isSharing = false
        hasIssue = wasSharing
    }

    func reset() {
        devices = MockDevice.initialDevices
        autoShareNextTime = false
        hasIssue = false
    }
}
