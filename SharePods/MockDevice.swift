import Foundation

enum MockDeviceStatus: String, CaseIterable {
    case connected = "Connected"
    case disconnected = "Disconnected"
    case sharing = "Sharing"
}

struct MockDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    var batteryPercent: Int?
    var isConnected: Bool
    var isSharing: Bool

    init(
        id: UUID = UUID(),
        name: String,
        batteryPercent: Int?,
        isConnected: Bool,
        isSharing: Bool = false
    ) {
        self.id = id
        self.name = name
        self.batteryPercent = batteryPercent
        self.isConnected = isConnected
        self.isSharing = isSharing
    }

    var status: MockDeviceStatus {
        if isSharing {
            return .sharing
        }

        return isConnected ? .connected : .disconnected
    }

    static let initialDevices: [MockDevice] = [
        MockDevice(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Winston's AirPods Pro",
            batteryPercent: 82,
            isConnected: true
        ),
        MockDevice(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Beats Fit Pro",
            batteryPercent: 74,
            isConnected: false
        ),
        MockDevice(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Living Room HomePod",
            batteryPercent: nil,
            isConnected: false
        )
    ]
}
