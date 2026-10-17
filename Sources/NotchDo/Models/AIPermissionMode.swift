/// How much Claude may do without asking. `claude -p` cannot prompt mid-run, so the
/// scope is fixed up front. Raw values are the CLI's `--permission-mode` names.
enum AIPermissionMode: String, Codable, CaseIterable, Sendable {
    case acceptEdits
    case plan
    case bypassPermissions

    var title: String {
        switch self {
        case .acceptEdits: "Edit files, limited commands"
        case .plan: "Plan only (read-only)"
        case .bypassPermissions: "Full access"
        }
    }

    var detail: String {
        switch self {
        case .acceptEdits: "Edits are accepted and only an allowlist of commands can run. Anything else fails."
        case .plan: "Claude writes a plan and changes nothing."
        case .bypassPermissions: "Claude can run any command, including outside the workspace."
        }
    }
}
