import Foundation
import Observation

@MainActor
@Observable
final class GlobalShortcutStore {
    nonisolated static let defaultsKey = "notchdo.globalQuickCaptureShortcut"
    nonisolated static let aiCaptureDefaultsKey = "notchdo.globalAICaptureShortcut"

    private(set) var shortcut: GlobalShortcut
    private(set) var registrationError: String?
    var onPerformShortcut: (@MainActor () -> Void)?
    /// The other NotchDo shortcut, so the two can never be assigned the same keys.
    var siblingShortcut: (@MainActor () -> GlobalShortcut?)?

    private let registration: any GlobalShortcutRegistration
    private let userDefaults: UserDefaults?
    private let storageKey: String

    init() {
        registration = CarbonGlobalShortcutRegistration()
        userDefaults = .standard
        storageKey = Self.defaultsKey
        shortcut = Self.loadShortcut(from: .standard, key: Self.defaultsKey, fallback: .default)
        _ = registerCurrentShortcut()
    }

    init(
        registration: any GlobalShortcutRegistration,
        userDefaults: UserDefaults?,
        storageKey: String = GlobalShortcutStore.defaultsKey,
        defaultShortcut: GlobalShortcut = .default
    ) {
        self.registration = registration
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        shortcut = Self.loadShortcut(from: userDefaults, key: storageKey, fallback: defaultShortcut)
        _ = registerCurrentShortcut()
    }

    /// The AI Capture shortcut (⌃⌥E by default). It uses its own hot key id and defaults key
    /// so it can coexist with the Quick Capture shortcut.
    static func aiCapture() -> GlobalShortcutStore {
        GlobalShortcutStore(
            registration: CarbonGlobalShortcutRegistration(id: 2),
            userDefaults: .standard,
            storageKey: aiCaptureDefaultsKey,
            defaultShortcut: .aiCapture
        )
    }

    @discardableResult
    func setShortcut(_ candidate: GlobalShortcut) -> Bool {
        guard candidate.isValid else {
            registrationError = "Include Command, Control, or Option with a letter, number, Space, or function key."
            return false
        }

        guard candidate != siblingShortcut?() else {
            registrationError = "That shortcut is already used by another NotchDo shortcut."
            return false
        }

        let previous = shortcut
        shortcut = candidate
        guard registerCurrentShortcut() else {
            shortcut = previous
            _ = registerCurrentShortcut()
            registrationError = "That shortcut is already used by another app."
            return false
        }

        if let data = try? JSONEncoder().encode(candidate) {
            userDefaults?.set(data, forKey: storageKey)
        }
        return true
    }

    func beginRecording() {
        registration.unregister()
    }

    func endRecording() {
        _ = registerCurrentShortcut()
    }

    private func registerCurrentShortcut() -> Bool {
        let didRegister = registration.register(shortcut) { [weak self] in
            self?.onPerformShortcut?()
        }
        registrationError = didRegister ? nil : "That shortcut is already used by another app."
        return didRegister
    }

    private static func loadShortcut(
        from userDefaults: UserDefaults?,
        key: String,
        fallback: GlobalShortcut
    ) -> GlobalShortcut {
        guard let data = userDefaults?.data(forKey: key),
              let decoded = try? JSONDecoder().decode(GlobalShortcut.self, from: data),
              decoded.isValid else { return fallback }
        return decoded
    }
}
