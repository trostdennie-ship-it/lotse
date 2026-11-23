import Foundation
import CoreAudio

/// Ein Ausgabegerät für Ton (Lautsprecher, Kopfhörer, Monitor).
struct AudioOut: Identifiable, Equatable {
    let id: AudioDeviceID
    var name: String
    var symbol: String
    var current: Bool
}

/// Liest die Ausgabegeräte des Macs und schaltet zwischen ihnen um.
enum AudioOutputs {
    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func current() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    static func list() -> [AudioOut] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        let now = current()
        var out: [AudioOut] = []
        for id in ids {
            // Nur Geräte, die Ton ausgeben können.
            var streams = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }
            var type = UInt32(0)
            var typeSize = UInt32(MemoryLayout<UInt32>.size)
            var t = address(kAudioDevicePropertyTransportType)
            AudioObjectGetPropertyData(id, &t, 0, nil, &typeSize, &type)
            // Virtuelle Geräte (Zoom, Teams, Sammelgeräte) gehören nicht in die Auswahl.
            if type == kAudioDeviceTransportTypeVirtual || type == kAudioDeviceTransportTypeAggregate { continue }
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var n = address(kAudioObjectPropertyName)
            guard AudioObjectGetPropertyData(id, &n, 0, nil, &nameSize, &name) == noErr, let name else { continue }
            let title = name.takeRetainedValue() as String
            out.append(AudioOut(id: id, name: title, symbol: symbol(type, title), current: id == now))
        }
        return out
    }

    private static func symbol(_ type: UInt32, _ name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods") { return "airpods" }
        switch type {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeBuiltIn: return n.contains("kopfhörer") || n.contains("headphone") ? "headphones" : "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeThunderbolt: return "display"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    static func select(_ id: AudioDeviceID) {
        var device = id
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &device)
        log("Ausgabegerät gewechselt (Status \(status))")
    }
}
