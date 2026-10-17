import Foundation
import Testing
@testable import NotchDo

@Suite("HTTP request parser")
struct HTTPRequestParserTests {
    private func parse(_ text: String) -> HTTPParseResult {
        HTTPRequestParser.parse(Data(text.utf8))
    }

    @Test("A simple GET parses method, path, query, and lowercased headers")
    func simpleGet() {
        let result = parse("GET /api/tasks/abc/events?after=12&x=%20y HTTP/1.1\r\nHost: 127.0.0.1:47821\r\nAccept: */*\r\n\r\n")

        #expect(result == .request(HTTPRequest(
            method: "GET",
            path: "/api/tasks/abc/events",
            query: ["after": "12", "x": " y"],
            headers: ["host": "127.0.0.1:47821", "accept": "*/*"]
        )))
    }

    @Test("An incomplete header block asks for more data")
    func incomplete() {
        #expect(parse("GET / HTTP/1.1\r\nHost: localhost") == .incomplete)
        #expect(parse("") == .incomplete)
    }

    @Test("Malformed request lines and headers are rejected")
    func malformed() {
        #expect(parse("GARBAGE\r\n\r\n") == .malformed)
        #expect(parse("GET / HTTP/2.0 extra\r\n\r\n") == .malformed)
        #expect(parse("GET nopath HTTP/1.1\r\n\r\n") == .malformed)
        #expect(parse("GET / HTTP/1.1\r\nNoColonHeader\r\n\r\n") == .malformed)
        #expect(parse("GET / HTTP/1.1\r\n: empty\r\n\r\n") == .malformed)
    }

    @Test("Oversized headers are refused instead of buffered forever")
    func tooLarge() {
        let huge = "GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPRequestParser.maxHeaderBytes + 10)

        #expect(parse(huge) == .tooLarge)
        #expect(parse(huge + "\r\n\r\n") == .tooLarge)
    }

    @Test("Encoded path characters are decoded once")
    func encodedPath() {
        guard case .request(let request) = parse("GET /a%20b HTTP/1.1\r\nHost: x\r\n\r\n") else {
            Issue.record("Expected a request")
            return
        }
        #expect(request.path == "/a b")
    }
}
