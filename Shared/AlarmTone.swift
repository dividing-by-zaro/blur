import Foundation
import ActivityKit

/// The tones a timer or alarm can ring with.
///
/// `.system` maps to AlarmKit's built-in alarm sound — it is the most reliable
/// option because the system owns the asset, so it is the default everywhere.
/// The named cases resolve to `.caf` files bundled with the **app** target
/// (ActivityKit looks the file up in the app bundle, not the extension).
///
/// `.silent` is a genuinely silent audio file. AlarmKit has no "no sound" option,
/// so the only way to ring silently is to hand it silence. The alarm still fires,
/// still breaks through silent mode visually, and still vibrates.
enum AlarmTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case radiate
    case chime
    case pulse
    case sunrise
    case beacon
    case silent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:  return "Default"
        case .radiate: return "Radiate"
        case .chime:   return "Chime"
        case .pulse:   return "Pulse"
        case .sunrise: return "Sunrise"
        case .beacon:  return "Beacon"
        case .silent:  return "No Tone"
        }
    }

    var symbolName: String {
        switch self {
        case .system:  return "bell.fill"
        case .radiate: return "waveform"
        case .chime:   return "bell.badge.fill"
        case .pulse:   return "dot.radiowaves.left.and.right"
        case .sunrise: return "sun.horizon.fill"
        case .beacon:  return "light.beacon.max.fill"
        case .silent:  return "bell.slash.fill"
        }
    }

    /// File name inside the app bundle, or `nil` for the system sound.
    var fileName: String? {
        switch self {
        case .system:  return nil
        case .radiate: return "blur-radiate.caf"
        case .chime:   return "blur-chime.caf"
        case .pulse:   return "blur-pulse.caf"
        case .sunrise: return "blur-sunrise.caf"
        case .beacon:  return "blur-beacon.caf"
        case .silent:  return "blur-silent.caf"
        }
    }

    /// What AlarmKit actually rings.
    var alertSound: AlertConfiguration.AlertSound {
        guard let fileName else { return .default }
        return .named(fileName)
    }

    /// Tones that can be previewed by tapping. Silence and the system sound are
    /// excluded — one has nothing to hear, the other can't be read from a bundle.
    var isPreviewable: Bool {
        switch self {
        case .system, .silent: return false
        default: return true
        }
    }
}
