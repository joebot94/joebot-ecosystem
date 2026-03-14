import Foundation

public enum StudioAppearancePreference: String, CaseIterable, Identifiable, Codable {
    case auto
    case retro
    case liquid

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto:
            return "Auto"
        case .retro:
            return "Retro"
        case .liquid:
            return "Liquid"
        }
    }
}

public enum StudioAppearanceResolved: String, Codable {
    case retro
    case liquid
}

public enum StudioAppearance {
    // Future-proof default: auto enables liquid style from major version 26 onward.
    public static func resolve(
        _ preference: StudioAppearancePreference,
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> StudioAppearanceResolved {
        switch preference {
        case .retro:
            return .retro
        case .liquid:
            return .liquid
        case .auto:
            return osVersion.majorVersion >= 26 ? .liquid : .retro
        }
    }
}
