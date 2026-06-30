import CoreAudio
import Foundation

enum SharePodsAudioConstants {
    static let aggregateUID = "com.builtbywin.SharePods.aggregate"
    static let aggregateName = "SharePods"
}

enum CoreAudioError: LocalizedError, Equatable {
    case deviceEnumerationFailed(OSStatus)
    case deviceLookupFailed(String)
    case outputDeviceNotFound(String)
    case aggregateCreationFailed(OSStatus)
    case aggregateDestructionFailed(OSStatus)
    case defaultOutputUnavailable(OSStatus)
    case defaultOutputWriteFailed(OSStatus)
    case insufficientDevices

    var errorDescription: String? {
        switch self {
        case .deviceEnumerationFailed(let status):
            return "Couldn’t enumerate CoreAudio devices (status \(status))."
        case .deviceLookupFailed(let name):
            return "Couldn’t read the \(name) for a CoreAudio device."
        case .outputDeviceNotFound(let uid):
            return "CoreAudio could not find the device UID \(uid)."
        case .aggregateCreationFailed(let status):
            return "Couldn’t create the SharePods aggregate device (status \(status))."
        case .aggregateDestructionFailed(let status):
            return "Couldn’t destroy the existing SharePods aggregate device (status \(status))."
        case .defaultOutputUnavailable(let status):
            return "Couldn’t read the current default output device (status \(status))."
        case .defaultOutputWriteFailed(let status):
            return "Couldn’t set the default output device (status \(status))."
        case .insufficientDevices:
            return "Connect two output devices before starting sharing."
        }
    }
}

protocol CoreAudioManaging {
    func refreshOutputDevices() throws -> [AudioOutputDevice]
    func currentDefaultOutputDeviceUID() throws -> String?
    func startSharing(using subdeviceUIDs: [String]) throws
    func stopSharing(restoring previousOutputUID: String?) throws
}

final class CoreAudioManager: CoreAudioManaging {
    func refreshOutputDevices() throws -> [AudioOutputDevice] {
        let deviceIDs = try fetchDeviceIDs()
        let aggregateDeviceID = try translateUIDToDeviceID(SharePodsAudioConstants.aggregateUID)
        let now = Date()

        return deviceIDs.compactMap { deviceID in
            if let aggregateDeviceID, deviceID == aggregateDeviceID {
                return nil
            }

            guard isOutputCapable(deviceID) else {
                return nil
            }

            guard let name = copyStringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName),
                  let uid = copyStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) else {
                return nil
            }

            return AudioOutputDevice(uid: uid, name: name, lastSeen: now, isConnected: true)
        }
    }

    func currentDefaultOutputDeviceUID() throws -> String? {
        guard let deviceID = try currentDefaultOutputDeviceID(), deviceID != kAudioObjectUnknown else {
            return nil
        }

        guard let uid = copyStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) else {
            throw CoreAudioError.deviceLookupFailed("device UID")
        }

        return uid
    }

    func startSharing(using subdeviceUIDs: [String]) throws {
        let uniqueUIDs = Array(NSOrderedSet(array: subdeviceUIDs)) as? [String] ?? subdeviceUIDs
        let filteredUIDs = uniqueUIDs.filter { $0 != SharePodsAudioConstants.aggregateUID }
        guard filteredUIDs.count >= 2 else {
            throw CoreAudioError.insufficientDevices
        }

        try destroyExistingAggregateIfNeeded()

        let description = Self.aggregateDeviceDescription(for: filteredUIDs)

        var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        let creationStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        guard creationStatus == noErr else {
            throw CoreAudioError.aggregateCreationFailed(creationStatus)
        }

        try setDefaultOutputDevice(aggregateDeviceID)
    }

    func stopSharing(restoring previousOutputUID: String?) throws {
        guard let previousOutputUID else {
            throw CoreAudioError.outputDeviceNotFound("previous output")
        }

        guard let deviceID = try translateUIDToDeviceID(previousOutputUID) else {
            throw CoreAudioError.outputDeviceNotFound(previousOutputUID)
        }

        try setDefaultOutputDevice(deviceID)
        try destroyExistingAggregateIfNeeded()
    }

    static func aggregateDeviceDescription(for subdeviceUIDs: [String]) -> [String: Any] {
        let subdevices = subdeviceUIDs.enumerated().map { index, uid in
            [
                kAudioSubDeviceUIDKey as String: uid,
                kAudioSubDeviceDriftCompensationKey as String: NSNumber(value: index == 0 ? 0 : 1),
                kAudioSubDeviceDriftCompensationQualityKey as String: NSNumber(
                    value: index == 0
                        ? kAudioAggregateDriftCompensationMinQuality
                        : kAudioAggregateDriftCompensationMediumQuality
                )
            ]
        }

        return [
            kAudioAggregateDeviceUIDKey as String: SharePodsAudioConstants.aggregateUID,
            kAudioAggregateDeviceNameKey as String: SharePodsAudioConstants.aggregateName,
            kAudioAggregateDeviceSubDeviceListKey as String: subdevices,
            kAudioAggregateDeviceIsPrivateKey as String: NSNumber(value: 0),
            kAudioAggregateDeviceIsStackedKey as String: NSNumber(value: 0),
            kAudioAggregateDeviceMainSubDeviceKey as String: subdeviceUIDs[0]
        ]
    }

    private func fetchDeviceIDs() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard sizeStatus == noErr else {
            throw CoreAudioError.deviceEnumerationFailed(sizeStatus)
        }

        guard size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        let dataStatus = deviceIDs.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else {
                return kAudioHardwareIllegalOperationError
            }

            var currentSize = size
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &currentSize,
                baseAddress
            )
        }

        guard dataStatus == noErr else {
            throw CoreAudioError.deviceEnumerationFailed(dataStatus)
        }

        return deviceIDs
    }

    private func currentDefaultOutputDeviceID() throws -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            throw CoreAudioError.defaultOutputUnavailable(status)
        }

        return deviceID
    }

    private func destroyExistingAggregateIfNeeded() throws {
        guard let aggregateDeviceID = try translateUIDToDeviceID(SharePodsAudioConstants.aggregateUID) else {
            return
        }

        let status = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        guard status == noErr else {
            throw CoreAudioError.aggregateDestructionFailed(status)
        }
    }

    private func setDefaultOutputDevice(_ deviceID: AudioObjectID) throws {
        try setSystemOutputDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
        try setSystemOutputDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    private func setSystemOutputDevice(_ deviceID: AudioObjectID, selector: AudioObjectPropertySelector) throws {
        var mutableDeviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &mutableDeviceID
        )

        guard status == noErr else {
            throw CoreAudioError.defaultOutputWriteFailed(status)
        }
    }

    private func isOutputCapable(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard sizeStatus == noErr, size > 0 else {
            return false
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer {
            buffer.deallocate()
        }

        let dataStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer)
        guard dataStatus == noErr else {
            return false
        }

        let bufferList = buffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let outputChannels = buffers.reduce(into: 0) { partialResult, audioBuffer in
            partialResult += Int(audioBuffer.mNumberChannels)
        }

        return outputChannels > 0
    }

    private func copyStringProperty(deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let storage = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        storage.initialize(to: nil)
        defer {
            storage.deinitialize(count: 1)
            storage.deallocate()
        }

        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage)
        guard status == noErr, let value = storage.pointee else {
            return nil
        }

        return value as String
    }

    private func translateUIDToDeviceID(_ uid: String) throws -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableUID = uid as CFString
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &mutableUID) { qualifierPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                qualifierPointer,
                &size,
                &deviceID
            )
        }

        guard status == noErr else {
            throw CoreAudioError.outputDeviceNotFound(uid)
        }

        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }
}
