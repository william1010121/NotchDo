import Foundation

struct HTTPResponse: Equatable, Sendable {
    var status: Int
    var headers: [String: String] = [:]
    var body = Data()

    static let securityHeaders = [
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "Cross-Origin-Resource-Policy": "same-origin"
    ]

    static func json(_ data: Data, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: data)
    }

    static func html(_ text: String) -> HTTPResponse {
        HTTPResponse(
            status: 200,
            headers: [
                "Content-Type": "text/html; charset=utf-8",
                "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
            ],
            body: Data(text.utf8)
        )
    }

    static func text(_ text: String, status: Int) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data(text.utf8))
    }

    var reason: String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 421: "Misdirected Request"
        case 431: "Request Header Fields Too Large"
        default: "Error"
        }
    }

    /// Serialized as HTTP/1.1 with `Connection: close`. `includeBody` is false for HEAD.
    func serialized(includeBody: Bool = true) -> Data {
        var merged = Self.securityHeaders
        for (key, value) in headers { merged[key] = value }
        merged["Content-Length"] = String(body.count)
        merged["Connection"] = "close"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for key in merged.keys.sorted() { head += "\(key): \(merged[key]!)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + (includeBody ? body : Data())
    }

    /// Headers that open a Server-Sent Events stream; the body follows as frames.
    static func eventStreamHead() -> Data {
        var merged = securityHeaders
        merged["Content-Type"] = "text/event-stream; charset=utf-8"
        merged["Connection"] = "keep-alive"
        var head = "HTTP/1.1 200 OK\r\n"
        for key in merged.keys.sorted() { head += "\(key): \(merged[key]!)\r\n" }
        head += "\r\n"
        return Data(head.utf8)
    }
}
