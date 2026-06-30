import Foundation

struct AudioOutputDevice: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case connected = "Connected"
        case disconnected = "Disconnected"
        case sharing = "Sharing"
    }

    let uid: String
    var name: String
    var lastSeen: Date
    var isConnected: Bool
    var isSharing: Bool

    var id: String { uid }

    var status: Status {
        if isSharing {
            return .sharing
        }

        return isConnected ? .connected : .disconnected
    }

    init(
        uid: String,
        name: String,
        lastSeen: Date = Date(),
        isConnected: Bool,
        isSharing: Bool = false
    ) {
        self.uid = uid
        self.name = name
        self.lastSeen = lastSeen
        self.isConnected = isConnected
        self.isSharing = isSharing
    }
}
