import CoreAudio
import Foundation

/// A thin CoreAudio wrapper for the input side: list the microphones, read and set the
/// system default input, and read/write a device's input volume. Listing does not touch
/// the microphone permission — that only bites when we actually open a stream to record.
enum AudioDevices {
    struct InputDevice: Identifiable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    // MARK: - Property address helper

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    // MARK: - Enumeration

    /// Every device that has at least one input channel, so the picker only ever offers
    /// something you can actually record from.
    static func inputDevices() -> [InputDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInput(id), let name = name(of: id) else { return nil }
            return InputDevice(id: id, uid: uid(of: id) ?? "\(id)", name: name)
        }
    }

    /// True when the device exposes input channels.
    static func hasInput(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bufferList) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    // MARK: - Names

    static func name(of id: AudioDeviceID) -> String? {
        stringProperty(id, kAudioObjectPropertyName)
    }

    static func uid(of id: AudioDeviceID) -> String? {
        stringProperty(id, kAudioDevicePropertyDeviceUID)
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        return status == noErr ? (value as String) : nil
    }

    // MARK: - Default input

    static var defaultInputID: AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return (status == noErr && id != 0) ? id : nil
    }

    static var defaultInputName: String? { defaultInputID.flatMap { name(of: $0) } }

    /// Sets the Mac's default input device. BlarneyKey records from whatever this is, so a
    /// pick in Settings flows straight through to real dictation.
    @discardableResult
    static func setDefaultInput(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var value = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &value) == noErr
    }

    // MARK: - Input volume

    /// The volume elements worth trying: the master, then the first two channels. Some
    /// devices expose a single master control, others only per-channel.
    private static let volumeElements: [AudioObjectPropertyElement] =
        [kAudioObjectPropertyElementMain, 1, 2]

    /// Current input volume 0…1, from the first element that reports one. Nil when the
    /// device has no adjustable input volume (many USB and aggregate devices).
    static func inputVolume(of id: AudioDeviceID) -> Float? {
        for element in volumeElements {
            var addr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: element)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &volume) == noErr {
                return Float(volume)
            }
        }
        return nil
    }

    /// Whether the input volume can actually be changed, so the slider only shows when it
    /// will do something.
    static func inputVolumeSettable(of id: AudioDeviceID) -> Bool {
        volumeElements.contains { isVolumeSettable(id, element: $0) }
    }

    /// Writes the volume to every settable element, so a two-channel device moves together.
    static func setInputVolume(_ value: Float, of id: AudioDeviceID) {
        var clamped = Float32(max(0, min(1, value)))
        for element in volumeElements where isVolumeSettable(id, element: element) {
            var addr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: element)
            AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &clamped)
        }
    }

    private static func isVolumeSettable(_ id: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var addr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: element)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &addr, &settable) == noErr && settable.boolValue
    }
}

/// Watches CoreAudio for the two things that change which microphone is live: the set of
/// devices (one unplugged or plugged in) and the system default input, which macOS reassigns
/// on its own when the current default disappears — a Bluetooth headset going flat, a USB mic
/// pulled out. BlarneyKey records from whatever the default is at the moment it starts, so
/// dictation already follows that reassignment; this just lets the Settings UI re-read the
/// list and selection instead of showing a device that is no longer there.
final class InputDeviceObserver {
    private var block: AudioObjectPropertyListenerBlock?
    private let selectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultInputDevice
    ]

    init(onChange: @escaping () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { onChange() }
        }
        self.block = block
        forEachAddress { addr in
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        }
    }

    func stop() {
        guard let block else { return }
        forEachAddress { addr in
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        }
        self.block = nil
    }

    deinit { stop() }

    private func forEachAddress(_ body: (inout AudioObjectPropertyAddress) -> Void) {
        for selector in selectors {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            body(&addr)
        }
    }
}
