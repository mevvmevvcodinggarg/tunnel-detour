import Foundation

public enum SiteRouteState: Equatable {
    case direct
    case privatePath
    case mixed
    case unavailable

    public var displayText: String {
        switch self {
        case .direct:
            return "Direct"
        case .privatePath:
            return "Private path"
        case .mixed:
            return "Mixed"
        case .unavailable:
            return "Unavailable"
        }
    }
}
