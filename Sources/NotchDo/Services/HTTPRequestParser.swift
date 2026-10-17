import Foundation

enum HTTPParseResult: Equatable, Sendable {
    /// The header block is not complete yet; read more.
    case incomplete
    case request(HTTPRequest)
    case malformed
    case tooLarge
}

/// Parses the request line and headers of one HTTP/1.1 request. Bodies are not supported:
/// the progress server only answers GET and HEAD.
enum HTTPRequestParser {
    static let maxHeaderBytes = 16_384
    private static let terminator = Data("\r\n\r\n".utf8)

    static func parse(_ data: Data) -> HTTPParseResult {
        guard let end = data.range(of: terminator) else {
            return data.count > maxHeaderBytes ? .tooLarge : .incomplete
        }
        guard end.lowerBound <= maxHeaderBytes else { return .tooLarge }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else {
            return .malformed
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1."),
              requestLine[1].hasPrefix("/"),
              let components = URLComponents(string: String(requestLine[1])) else { return .malformed }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .malformed }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .malformed }
            headers[name] = value
        }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return .request(HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: components.percentEncodedPath.removingPercentEncoding ?? components.path,
            query: query,
            headers: headers
        ))
    }
}
