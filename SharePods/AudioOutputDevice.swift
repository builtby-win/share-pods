import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case connected = "Connected"
        case disconnected = "Disconnected"
        case sharing = "Sharing"
    }

    enum Transport: String, Codable, Equatable {
        case aggregate
        case bluetooth
        case bluetoothLE
        case builtIn
        case displayPort
        case hdmi
        case usb
        case virtual
        case unknown
    }

    let uid: String
    var name: String
    var lastSeen: Date
    var isConnected: Bool
    var isSharing: Bool
    var transport: Transport

    var id: String { uid }

    var status: Status {
        if isSharing {
            return .sharing
        }

        return isConnected ? .connected : .disconnected
    }

    var isHeadphones: Bool {
        guard transport != .virtual, transport != .aggregate else {
            return false
        }

        if transport == .bluetooth || transport == .bluetoothLE {
            return true
        }

        return name.localizedCaseInsensitiveContains("airpods")
            || name.localizedCaseInsensitiveContains("beats")
            || name.localizedCaseInsensitiveContains("headphones")
            || name.localizedCaseInsensitiveContains("headset")
    }

    var isSpeaker: Bool {
        guard transport != .virtual, transport != .aggregate else {
            return false
        }

        return name.localizedCaseInsensitiveContains("speaker")
    }

    var isVisibleShareOutput: Bool {
        isHeadphones || isSpeaker
    }

    var shouldAutoSelectForSharing: Bool {
        isConnected && isHeadphones
    }

    var isSelectableForSharing: Bool {
        isConnected && isVisibleShareOutput
    }

    var shareListRank: Int {
        if isHeadphones {
            return 0
        }

        if isSpeaker {
            return 1
        }

        return 2
    }

    var systemImageName: String {
        if isHeadphones {
            return "airpodspro"
        }

        if isSpeaker {
            return "speaker.wave.2"
        }

        return "hifispeaker"
    }

    init(
        uid: String,
        name: String,
        lastSeen: Date = Date(),
        isConnected: Bool,
        isSharing: Bool = false,
        transport: Transport = .unknown
    ) {
        self.uid = uid
        self.name = name
        self.lastSeen = lastSeen
        self.isConnected = isConnected
        self.isSharing = isSharing
        self.transport = transport
    }
}

extension AudioOutputDevice.Transport {
    init(coreAudioTransportType: UInt32) {
        switch coreAudioTransportType {
        case kAudioDeviceTransportTypeAggregate:
            self = .aggregate
        case kAudioDeviceTransportTypeBluetooth:
            self = .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            self = .bluetoothLE
        case kAudioDeviceTransportTypeBuiltIn:
            self = .builtIn
        case kAudioDeviceTransportTypeDisplayPort:
            self = .displayPort
        case kAudioDeviceTransportTypeHDMI:
            self = .hdmi
        case kAudioDeviceTransportTypeUSB:
            self = .usb
        case kAudioDeviceTransportTypeVirtual:
            self = .virtual
        default:
            self = .unknown
        }
    }
}
