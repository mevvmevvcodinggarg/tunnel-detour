import Foundation

public enum ActivityMessage {
    public static let ready = "Ready."
    public static let saved = "Settings saved."
    public static let restored = "Defaults restored."
    public static let applying = "Applying settings. Administrator approval may be requested."
    public static let applied = "Settings applied."
    public static let checking = "Checking status."
    public static let checked = "Status check completed."
    public static let repairing = "Refreshing connection. Administrator approval may be requested."
    public static let repaired = "Connection refreshed."
    public static let restoring = "Restoring system settings."
    public static let restoredSystem = "System settings restored."
    public static let removingHelper = "Removing background component. Administrator approval may be requested."
    public static let removedHelper = "Background component removed."

    public static func failure(for error: Error) -> String {
        if let routeError = error as? RouteManagerError,
           case .commandTimedOut = routeError {
            return "Operation timed out."
        }
        if let adaptiveError = error as? AdaptiveControllerError {
            switch adaptiveError {
            case .helperMissing:
                return "Required component is unavailable."
            case .operationFailed:
                return "Settings could not be applied."
            case .timedOut:
                return "Operation timed out."
            }
        }
        return "Operation failed."
    }
}
