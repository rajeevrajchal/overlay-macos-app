import Foundation

/// Domain-level description of where the user stands with a design-source
/// connection (Figma today). Deliberately UI-framework-agnostic: view models
/// publish it, and both the SwiftUI presentation layer and any future test
/// harness read it without importing AppKit/SwiftUI.
///
/// Accessibility note: every case must be renderable as **icon + text**, never
/// color alone — see `symbolName` / `label` below, which the views consume.
enum FigmaConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(workspace: String)
    case failed(reason: String)

    /// SF Symbol that reads the state without relying on color.
    var symbolName: String {
        switch self {
        case .disconnected: return "link"
        case .connecting:   return "arrow.triangle.2.circlepath"
        case .connected:    return "checkmark.circle.fill"
        case .failed:       return "exclamationmark.triangle.fill"
        }
    }

    /// Plain-language status line, safe to expose to VoiceOver verbatim.
    var label: String {
        switch self {
        case .disconnected:            return "Not connected"
        case .connecting:              return "Connecting…"
        case .connected(let handle):   return "Connected as \(handle)"
        case .failed(let reason):      return reason
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
}
