import Foundation

/// Errors thrown by the xPunge SDK.
public enum XpungeError: Error, LocalizedError {
    case invalidKey(String)
    case modelNotFound(String)
    case initializationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKey(let msg):          return msg
        case .modelNotFound(let msg):       return msg
        case .initializationFailed(let msg): return msg
        }
    }
}
