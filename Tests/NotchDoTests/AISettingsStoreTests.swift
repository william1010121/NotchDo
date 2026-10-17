import Foundation
import Testing
@testable import NotchDo

@Suite("AI settings store")
@MainActor
struct AISettingsStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "NotchDoTests.aiSettings.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test("Defaults are the safe, documented values")
    func defaults() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AISettingsStore(defaults: defaults).settings

        #expect(settings.permissionMode == .acceptEdits)
        #expect(settings.maxConcurrent == 1)
        #expect(settings.publishArtifacts)
        #expect(settings.serverEnabled)
        #expect(settings.serverPort == AISettings.defaultPort)
        #expect(settings.claudePathOverride.isEmpty)
    }

    @Test("Changes persist across instances")
    func persistence() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AISettingsStore(defaults: defaults)

        store.setPermissionMode(.plan)
        store.setMaxConcurrent(2)
        store.setPublishArtifacts(false)
        store.setNotifyOnFinish(false)
        store.setServerEnabled(false)
        store.setServerPort(50_000)
        store.setClaudePathOverride("/x/claude")

        let reloaded = AISettingsStore(defaults: defaults).settings
        #expect(reloaded.permissionMode == .plan)
        #expect(reloaded.maxConcurrent == 2)
        #expect(!reloaded.publishArtifacts)
        #expect(!reloaded.notifyOnFinish)
        #expect(!reloaded.serverEnabled)
        #expect(reloaded.serverPort == 50_000)
        #expect(reloaded.claudePathOverride == "/x/claude")
    }

    @Test("Concurrency and port are kept in range")
    func clamping() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AISettingsStore(defaults: defaults)

        store.setMaxConcurrent(99)
        #expect(store.settings.maxConcurrent == 3)
        store.setMaxConcurrent(0)
        #expect(store.settings.maxConcurrent == 1)
        store.setServerPort(80)
        #expect(store.settings.serverPort == AISettings.defaultPort)
    }

    @Test("Artifact is allowed only while publishing is on")
    func allowedTools() {
        var settings = AISettings()
        #expect(settings.allowedTools.contains("Artifact"))
        settings.publishArtifacts = false
        #expect(!settings.allowedTools.contains("Artifact"))
    }
}
