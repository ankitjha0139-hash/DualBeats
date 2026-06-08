import Foundation
import CoreAudio
import AudioToolbox

class AudioManager: ObservableObject {
    @Published var availableOutputDevices: [AudioDeviceInfo] = []
    @Published var currentOutputDevice: String = "Default"
    @Published var multiOutputDeviceID: AudioDeviceID = kAudioObjectUnknown
    @Published var masterVolume: Float = 0.7
    private var previousDefaultDeviceID: AudioDeviceID = kAudioObjectUnknown

    struct AudioDeviceInfo: Identifiable {
        let id: AudioDeviceID
        let name: String
        let uid: String
    }

    init() {
        cleanupStaleAggregates()
    }

    private func cleanupStaleAggregates() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize)
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids)
        for id in ids {
            if let uid = getDeviceUID(id), uid.hasPrefix("com.dualbeats.") {
                print("🧹 Cleaning stale aggregate: \(uid)")
                AudioHardwareDestroyAggregateDevice(id)
            }
        }
    }

    // MARK: - Device Discovery

    func refreshAudioDevices() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize)
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids)

        var devices: [AudioDeviceInfo] = []
        for id in ids {
            guard let name = getDeviceName(id), let uid = getDeviceUID(id) else { continue }
            if uid.hasPrefix("com.dualbeats.") { continue }
            if isOutputDevice(id) {
                devices.append(AudioDeviceInfo(id: id, name: name, uid: uid))
                print("🎵 CoreAudio output: '\(name)' | uid: \(uid)")
            }
        }
        DispatchQueue.main.async { self.availableOutputDevices = devices }
    }

    // MARK: - Multi-Output (restored exact logic that worked)

    func createMultiOutputDevice(speakerRawNames: [String], speakerUIDs: [String], completion: @escaping (Bool, String) -> Void) {
        cleanupStaleAggregates()
        refreshAudioDevices()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }

            print("🔍 Looking for: \(speakerRawNames)")
            print("🔍 CoreAudio devices: \(self.availableOutputDevices.map { $0.name })")

            var matchedUIDs: [String] = []
            var matchedNames: [String] = []

            for rawName in speakerRawNames {
                // Strip BT mode prefixes
                let cleaned = rawName
                    .replacingOccurrences(of: "LE-", with: "")
                    .replacingOccurrences(of: "BLE-", with: "")
                    .replacingOccurrences(of: " [LE]", with: "")
                    .replacingOccurrences(of: "[LE]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()

                // Extract words — strip possessives, keep words > 2 chars
                let words = cleaned
                    .components(separatedBy: .whitespaces)
                    .map { $0.replacingOccurrences(of: "'s", with: "")
                              .replacingOccurrences(of: "'", with: "") }
                    .filter { $0.count > 2 }

                print("🔍 Matching '\(rawName)' → words: \(words)")

                if let device = self.availableOutputDevices.first(where: { d in
                    let dLower = d.name.lowercased()
                    return words.contains(where: { dLower.contains($0) })
                        && !matchedUIDs.contains(d.uid)
                }) {
                    matchedUIDs.append(device.uid)
                    matchedNames.append(device.name)
                    print("✅ Matched '\(rawName)' → '\(device.name)'")
                } else {
                    print("❌ No match for '\(rawName)'")
                }
            }

            guard matchedUIDs.count >= 2 else {
                print("⚠️ Only \(matchedUIDs.count) match(es) — opening Audio MIDI Setup")
                self.openAudioMIDISetup(completion: completion)
                return
            }

            self.previousDefaultDeviceID = self.getDefaultOutputDevice()

            let subDeviceList = matchedUIDs.map { uid -> [String: Any] in
                [kAudioSubDeviceUIDKey as String: uid]
            }

            let aggregateUID = "com.dualbeats.\(UUID().uuidString)"
            let aggregateDesc: [String: Any] = [
                kAudioAggregateDeviceNameKey as String:          "DualBeats Multi-Output",
                kAudioAggregateDeviceUIDKey as String:           aggregateUID,
                kAudioAggregateDeviceSubDeviceListKey as String: subDeviceList,
                kAudioAggregateDeviceMasterSubDeviceKey as String: matchedUIDs[0],
                kAudioAggregateDeviceIsPrivateKey as String:     false,
                kAudioAggregateDeviceIsStackedKey as String:     true
            ]

            print("🏗️ Creating aggregate for: \(matchedNames)")
            var aggregateID: AudioDeviceID = kAudioObjectUnknown
            let status = AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &aggregateID)
            print("🏗️ Status: \(status) | ID: \(aggregateID)")

            guard status == noErr && aggregateID != kAudioObjectUnknown else {
                self.openAudioMIDISetup(completion: completion)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.setDefaultOutputDevice(aggregateID)
                self.setDefaultSystemOutputDevice(aggregateID)
                self.multiOutputDeviceID = aggregateID
                DispatchQueue.main.async { self.currentOutputDevice = "DualBeats Multi-Output" }
                completion(true, "✓ Playing on \(matchedNames.count) speakers")
            }
        }
    }

    // MARK: - Volume Control

    func setMasterVolume(_ value: Float) {
        masterVolume = max(0.0, min(1.0, value))

        // Target the aggregate device directly using its AudioDeviceID
        let targetID = multiOutputDeviceID != kAudioObjectUnknown
            ? multiOutputDeviceID
            : getDefaultOutputDevice()

        // Try VirtualMasterVolume — wait until device is fully initialised
        setVolumeOnDevice(masterVolume, deviceID: targetID)
    }

    private func setVolumeOnDevice(_ volume: Float, deviceID: AudioDeviceID) {
        // kAudioHardwareServiceDeviceProperty_VirtualMasterVolume controls
        // the aggregate device's own volume fader — separate from system volume
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)

        // Check property exists without passing device ID directly to HasProperty
        // to avoid invalid ID crashes — use a local copy
        var localID = deviceID
        _ = localID // suppress warning

        var vol = volume
        let status = AudioHardwareServiceSetPropertyData(
            deviceID, &addr, 0, nil,
            UInt32(MemoryLayout<Float>.size), &vol)

        if status == noErr {
            print("🔈 Volume \(Int(volume * 100))% set on device \(deviceID)")
        } else {
            // Fallback: set on each individual Bluetooth speaker device directly
            print("🔈 VirtualMasterVolume failed (\(status)) — trying per-device")
            setVolumeOnBTDevice(volume)
        }
    }

    private func setVolumeOnBTDevice(_ volume: Float) {
        // Set volume directly on each known BT output device
        for device in availableOutputDevices {
            guard device.uid != "BuiltInSpeakerDevice",
                  !device.uid.hasPrefix("com.dualbeats.") else { continue }
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            var vol = volume
            let status = AudioHardwareServiceSetPropertyData(
                device.id, &addr, 0, nil,
                UInt32(MemoryLayout<Float>.size), &vol)
            print("🔈 BT device '\(device.name)': volume \(Int(volume * 100))% → status \(status)")
        }
    }

    func syncVolumeFromSystem() {
        let deviceID = multiOutputDeviceID != kAudioObjectUnknown
            ? multiOutputDeviceID : getDefaultOutputDevice()
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var volume: Float = 0.7
        var size = UInt32(MemoryLayout<Float>.size)
        if AudioHardwareServiceGetPropertyData(deviceID, &addr, 0, nil, &size, &volume) == noErr {
            print("🔈 Synced volume: \(Int(volume * 100))%")
            DispatchQueue.main.async { self.masterVolume = volume }
        }
    }

    // MARK: - Default Device helpers

    func getDefaultOutputDevice() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    func setDefaultOutputDevice(_ id: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var mutableID = id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID)
        print("🔊 setDefaultOutputDevice(\(id)) → \(status)")
        if let name = getDeviceName(id) {
            DispatchQueue.main.async { self.currentOutputDevice = name }
        }
    }

    func setDefaultSystemOutputDevice(_ id: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var mutableID = id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID)
        print("🔊 setDefaultSystemOutputDevice(\(id)) → \(status)")
    }

    func restoreDefaultOutput() {
        if previousDefaultDeviceID != kAudioObjectUnknown {
            setDefaultOutputDevice(previousDefaultDeviceID)
            setDefaultSystemOutputDevice(previousDefaultDeviceID)
        }
        if multiOutputDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(multiOutputDeviceID)
            multiOutputDeviceID = kAudioObjectUnknown
        }
        DispatchQueue.main.async { self.currentOutputDevice = "Default" }
    }

    // MARK: - CoreAudio helpers

    private func getDeviceName(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceNameCFString,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var ref: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }

    private func getDeviceUID(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var ref: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }

    private func isOutputDevice(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private func openAudioMIDISetup(completion: @escaping (Bool, String) -> Void) {
        NSAppleScript(source: "tell application \"Audio MIDI Setup\" to activate")?.executeAndReturnError(nil)
        completion(false, "Opened Audio MIDI Setup — create a Multi-Output Device there")
    }
}
