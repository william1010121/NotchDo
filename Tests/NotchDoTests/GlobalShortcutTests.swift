import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import NotchDo

@Suite("Global shortcut", .serialized)
@MainActor
struct GlobalShortcutTests {
    @Test("Shortcut display order and Carbon flags are deterministic")
    func formattingAndCarbonFlags() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: [.command, .shift, .capsLock]
        )

        #expect(shortcut.displayName == "⇧⌘K")
        #expect(shortcut.modifiers == [.command, .shift])
        #expect(shortcut.carbonModifiers == UInt32(cmdKey | shiftKey))
    }

    @Test("A shortcut requires a supported key and modifier")
    func validation() {
        #expect(!GlobalShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: []).isValid)
        #expect(!GlobalShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: [.shift]).isValid)
        #expect(!GlobalShortcut(keyCode: 999, modifiers: [.command]).isValid)
        #expect(GlobalShortcut.default.isValid)
    }

    @Test("A new shortcut registers, persists, and invokes its action")
    func registrationAndPersistence() throws {
        let suite = "NotchDoTests.globalShortcut.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let registration = FakeGlobalShortcutRegistration()
        let store = GlobalShortcutStore(registration: registration, userDefaults: defaults)
        var invocationCount = 0
        store.onPerformShortcut = { invocationCount += 1 }
        let replacement = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: [.command, .option]
        )

        #expect(store.setShortcut(replacement))
        registration.invoke()

        #expect(store.shortcut == replacement)
        #expect(registration.registeredShortcuts == [.default, replacement])
        #expect(invocationCount == 1)
        let data = try #require(defaults.data(forKey: GlobalShortcutStore.defaultsKey))
        #expect(try JSONDecoder().decode(GlobalShortcut.self, from: data) == replacement)
    }

    @Test("A conflicting replacement restores the previously active shortcut")
    func conflictingShortcutRollback() {
        let registration = FakeGlobalShortcutRegistration()
        let store = GlobalShortcutStore(registration: registration, userDefaults: nil)
        let replacement = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: [.control, .shift]
        )
        registration.rejectedShortcuts = [replacement]
        var invocationCount = 0
        store.onPerformShortcut = { invocationCount += 1 }

        #expect(!store.setShortcut(replacement))
        #expect(store.shortcut == .default)
        #expect(store.registrationError != nil)
        #expect(registration.registeredShortcuts == [.default, replacement, .default])
        registration.invoke()
        #expect(invocationCount == 1)
    }

    @Test("Recording temporarily releases and restores the active shortcut")
    func recordingLifecycle() {
        let registration = FakeGlobalShortcutRegistration()
        let store = GlobalShortcutStore(registration: registration, userDefaults: nil)

        store.beginRecording()
        store.endRecording()

        #expect(registration.unregisterCount == 1)
        #expect(registration.registeredShortcuts == [.default, .default])
    }

    @Test("AI Capture defaults to Control–Option–E")
    func aiCaptureDefault() {
        #expect(GlobalShortcut.aiCapture.displayName == "⌃⌥E")
        #expect(GlobalShortcut.aiCapture.isValid)
        #expect(GlobalShortcut.aiCapture != .default)
    }

    @Test("Stores with different keys keep independent shortcuts")
    func independentStores() throws {
        let suite = "NotchDoTests.globalShortcut.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let quickRegistration = FakeGlobalShortcutRegistration()
        let aiRegistration = FakeGlobalShortcutRegistration()
        let quick = GlobalShortcutStore(registration: quickRegistration, userDefaults: defaults)
        let ai = GlobalShortcutStore(
            registration: aiRegistration,
            userDefaults: defaults,
            storageKey: GlobalShortcutStore.aiCaptureDefaultsKey,
            defaultShortcut: .aiCapture
        )
        let replacement = GlobalShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: [.command, .option])

        #expect(quick.shortcut == .default)
        #expect(ai.shortcut == .aiCapture)
        #expect(ai.setShortcut(replacement))

        #expect(quick.shortcut == .default)
        #expect(defaults.data(forKey: GlobalShortcutStore.defaultsKey) == nil)
        let data = try #require(defaults.data(forKey: GlobalShortcutStore.aiCaptureDefaultsKey))
        #expect(try JSONDecoder().decode(GlobalShortcut.self, from: data) == replacement)

        let reloaded = GlobalShortcutStore(
            registration: FakeGlobalShortcutRegistration(),
            userDefaults: defaults,
            storageKey: GlobalShortcutStore.aiCaptureDefaultsKey,
            defaultShortcut: .aiCapture
        )
        #expect(reloaded.shortcut == replacement)
    }

    @Test("A shortcut already used by the sibling NotchDo shortcut is rejected")
    func siblingConflict() {
        let registration = FakeGlobalShortcutRegistration()
        let store = GlobalShortcutStore(registration: registration, userDefaults: nil)
        store.siblingShortcut = { .aiCapture }

        #expect(!store.setShortcut(.aiCapture))
        #expect(store.shortcut == .default)
        #expect(store.registrationError != nil)
        #expect(registration.registeredShortcuts == [.default])
    }
}
