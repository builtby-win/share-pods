import Foundation

struct RegisteredDevicePair: Codable, Equatable {
    let firstUID: String
    let secondUID: String

    var orderedUIDs: [String] {
        [firstUID, secondUID]
    }

    func isConnected(in connectedUIDs: Set<String>) -> Bool {
        connectedUIDs.contains(firstUID) && connectedUIDs.contains(secondUID)
    }
}

private struct KnownDeviceRecord: Codable, Equatable {
    let uid: String
    var name: String
    var lastSeen: Date
}

final class KnownDevicesStore {
    private enum Key {
        static let knownDevices = "sharepods.knownDevices"
        static let registeredPair = "sharepods.registeredPair"
        static let autoShareEnabled = "sharepods.autoShareEnabled"
        static let previousOutputUID = "sharepods.previousOutputUID"
    }

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var autoShareEnabled: Bool {
        get {
            userDefaults.bool(forKey: Key.autoShareEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: Key.autoShareEnabled)
        }
    }

    var previousOutputUID: String? {
        get {
            userDefaults.string(forKey: Key.previousOutputUID)
        }
        set {
            userDefaults.set(newValue, forKey: Key.previousOutputUID)
        }
    }

    var registeredPair: RegisteredDevicePair? {
        get {
            guard let data = userDefaults.data(forKey: Key.registeredPair) else {
                return nil
            }

            return try? decoder.decode(RegisteredDevicePair.self, from: data)
        }
        set {
            if let newValue {
                if let data = try? encoder.encode(newValue) {
                    userDefaults.set(data, forKey: Key.registeredPair)
                }
            } else {
                userDefaults.removeObject(forKey: Key.registeredPair)
            }
        }
    }

    func loadKnownDevices() -> [AudioOutputDevice] {
        guard let data = userDefaults.data(forKey: Key.knownDevices),
              let records = try? decoder.decode([KnownDeviceRecord].self, from: data) else {
            return []
        }

        return records
            .sorted { left, right in
                if left.lastSeen != right.lastSeen {
                    return left.lastSeen > right.lastSeen
                }

                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
            .map { record in
                AudioOutputDevice(
                    uid: record.uid,
                    name: record.name,
                    lastSeen: record.lastSeen,
                    isConnected: false
                )
            }
    }

    func upsertKnownDevices(_ devices: [AudioOutputDevice]) {
        var latestRecordsByUID: [String: KnownDeviceRecord] = [:]

        if let data = userDefaults.data(forKey: Key.knownDevices),
           let existingRecords = try? decoder.decode([KnownDeviceRecord].self, from: data) {
            for record in existingRecords {
                latestRecordsByUID[record.uid] = record
            }
        }

        for device in devices {
            let record = KnownDeviceRecord(uid: device.uid, name: device.name, lastSeen: device.lastSeen)
            if let existing = latestRecordsByUID[device.uid] {
                latestRecordsByUID[device.uid] = KnownDeviceRecord(
                    uid: record.uid,
                    name: record.name.isEmpty ? existing.name : record.name,
                    lastSeen: max(existing.lastSeen, record.lastSeen)
                )
            } else {
                latestRecordsByUID[device.uid] = record
            }
        }

        let sortedRecords = latestRecordsByUID.values.sorted { left, right in
            if left.lastSeen != right.lastSeen {
                return left.lastSeen > right.lastSeen
            }

            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        if let data = try? encoder.encode(sortedRecords) {
            userDefaults.set(data, forKey: Key.knownDevices)
        }
    }
}
