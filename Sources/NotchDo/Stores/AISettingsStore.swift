import Foundation
import Observation

/// User preferences for the AI workspace, backed by `UserDefaults`.
@MainActor
@Observable
final class AISettingsStore {
    private enum Key {
        static let permissionMode = "notchdo.ai.permissionMode"
        static let maxConcurrent = "notchdo.ai.maxConcurrent"
        static let publishArtifacts = "notchdo.ai.publishArtifacts"
        static let notifyOnFinish = "notchdo.ai.notifyOnFinish"
        static let serverEnabled = "notchdo.ai.serverEnabled"
        static let serverPort = "notchdo.ai.serverPort"
        static let claudePath = "notchdo.ai.claudePath"
    }

    private let defaults: UserDefaults

    /// Called after any setting changes, so running services can pick it up.
    @ObservationIgnored var onChange: (() -> Void)?

    private(set) var settings: AISettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var settings = AISettings()
        if let raw = defaults.string(forKey: Key.permissionMode),
           let mode = AIPermissionMode(rawValue: raw) {
            settings.permissionMode = mode
        }
        let concurrent = defaults.integer(forKey: Key.maxConcurrent)
        if AISettings.maxConcurrentRange.contains(concurrent) { settings.maxConcurrent = concurrent }
        settings.publishArtifacts = defaults.object(forKey: Key.publishArtifacts) as? Bool ?? true
        settings.notifyOnFinish = defaults.object(forKey: Key.notifyOnFinish) as? Bool ?? true
        settings.serverEnabled = defaults.object(forKey: Key.serverEnabled) as? Bool ?? true
        let port = defaults.integer(forKey: Key.serverPort)
        if (1024...65_535).contains(port) { settings.serverPort = port }
        settings.claudePathOverride = defaults.string(forKey: Key.claudePath) ?? ""
        self.settings = settings
    }

    func setPermissionMode(_ mode: AIPermissionMode) {
        settings.permissionMode = mode
        defaults.set(mode.rawValue, forKey: Key.permissionMode)
        onChange?()
    }

    func setMaxConcurrent(_ value: Int) {
        let clamped = min(max(value, AISettings.maxConcurrentRange.lowerBound), AISettings.maxConcurrentRange.upperBound)
        settings.maxConcurrent = clamped
        defaults.set(clamped, forKey: Key.maxConcurrent)
        onChange?()
    }

    func setPublishArtifacts(_ value: Bool) {
        settings.publishArtifacts = value
        defaults.set(value, forKey: Key.publishArtifacts)
        onChange?()
    }

    func setNotifyOnFinish(_ value: Bool) {
        settings.notifyOnFinish = value
        defaults.set(value, forKey: Key.notifyOnFinish)
        onChange?()
    }

    func setServerEnabled(_ value: Bool) {
        settings.serverEnabled = value
        defaults.set(value, forKey: Key.serverEnabled)
        onChange?()
    }

    func setServerPort(_ value: Int) {
        guard (1024...65_535).contains(value) else { return }
        settings.serverPort = value
        defaults.set(value, forKey: Key.serverPort)
        onChange?()
    }

    func setClaudePathOverride(_ value: String) {
        settings.claudePathOverride = value
        defaults.set(value, forKey: Key.claudePath)
        onChange?()
    }
}
