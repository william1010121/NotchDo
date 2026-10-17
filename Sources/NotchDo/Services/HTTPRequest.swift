import Foundation

struct HTTPRequest: Equatable, Sendable {
    var method: String
    var path: String
    var query: [String: String]
    /// Header names are lowercased.
    var headers: [String: String]
}
