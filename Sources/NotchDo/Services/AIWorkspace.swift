import Foundation

/// The on-disk workspace Claude works in: `~/Desktop/NotchDo/` by default.
///
/// NotchDo owns `.notchdo/` (task records, port file). Everything else is the AI's working area.
/// `bootstrap()` is idempotent and never overwrites a `CLAUDE.md` the user has edited.
struct AIWorkspace: Sendable {
    let rootURL: URL

    init(rootURL: URL = AIWorkspace.defaultRootURL) {
        self.rootURL = rootURL
    }

    static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Desktop", directoryHint: .isDirectory)
            .appending(path: "NotchDo", directoryHint: .isDirectory)
    }

    /// The workspace the app uses. The demo build works in a temporary folder so it never
    /// touches the user's real Desktop.
    static var appDefault: AIWorkspace {
        #if NOTCHDO_DEMO
        AIWorkspace(rootURL: FileManager.default.temporaryDirectory
            .appending(path: "notchdo-demo-workspace", directoryHint: .isDirectory))
        #else
        AIWorkspace()
        #endif
    }

    var projectsURL: URL { rootURL.appending(path: "projects", directoryHint: .isDirectory) }
    var internalURL: URL { rootURL.appending(path: ".notchdo", directoryHint: .isDirectory) }
    var tasksURL: URL { internalURL.appending(path: "tasks", directoryHint: .isDirectory) }
    var portFileURL: URL { internalURL.appending(path: "port", directoryHint: .notDirectory) }
    var claudeInstructionsURL: URL { rootURL.appending(path: "CLAUDE.md", directoryHint: .notDirectory) }

    func taskURL(id: UUID) -> URL {
        tasksURL.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    func bootstrap(fileManager: FileManager = .default) throws {
        for directory in [rootURL, projectsURL, tasksURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard !fileManager.fileExists(atPath: claudeInstructionsURL.path) else { return }
        try Self.defaultInstructions.write(
            to: claudeInstructionsURL,
            atomically: true,
            encoding: .utf8
        )
    }

    static let defaultInstructions = """
    # NotchDo AI Workspace

    This folder is the working area for tasks delegated from NotchDo. You can edit this file; \
    NotchDo creates it only when it is missing.

    - Put deliverables in `projects/<short-name>/`. Create the folder if it does not exist.
    - Do not create, edit, or delete files outside this folder unless the task says so explicitly.
    - `.notchdo/` is managed by the NotchDo app. Only write there when a task asks you to.
    - Keep the final reply short: what you did, where the files are, and anything that needs \
    the user's decision.
    """ + "\n"
}
