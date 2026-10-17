import Foundation
import Testing
@testable import NotchDo

@Suite("Claude executable locator")
struct ClaudeExecutableLocatorTests {
    private let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)

    private func locator(
        executables: Set<String>,
        shell: String? = nil
    ) -> ClaudeExecutableLocator {
        ClaudeExecutableLocator(
            homeDirectory: home,
            isExecutable: { executables.contains($0) },
            loginShellLookup: { shell }
        )
    }

    @Test("Known install locations are tried in order")
    func candidateOrder() {
        let both = locator(executables: ["/Users/tester/.local/bin/claude", "/opt/homebrew/bin/claude"])
        let brewOnly = locator(executables: ["/opt/homebrew/bin/claude"])

        #expect(both.locate()?.path == "/Users/tester/.local/bin/claude")
        #expect(brewOnly.locate()?.path == "/opt/homebrew/bin/claude")
    }

    @Test("The login shell is the last resort")
    func shellFallback() {
        let found = locator(executables: ["/custom/claude"], shell: "/custom/claude")
        let missing = locator(executables: [], shell: "/custom/claude")

        #expect(found.locate()?.path == "/custom/claude")
        #expect(missing.locate() == nil)
    }

    @Test("A user-provided path wins and is not silently replaced when invalid")
    func override() {
        let sut = locator(executables: ["/mine/claude", "/opt/homebrew/bin/claude"])

        #expect(sut.locate(override: "/mine/claude")?.path == "/mine/claude")
        #expect(sut.locate(override: "/typo/claude") == nil)
        #expect(sut.locate(override: "  ")?.path == "/opt/homebrew/bin/claude")
    }
}
