import Foundation
import Testing
@testable import NotchDo

@Suite("Progress router")
struct ProgressRouterTests {
    private let task = AITask(prompt: "Write docs", createdAt: fixedDate(2026, 10, 17))

    private func router(source: FakeProgressDataSource) -> ProgressRouter {
        ProgressRouter(source: source, allowedHosts: { ["127.0.0.1:5000", "localhost:5000"] })
    }

    private func get(_ path: String, query: [String: String] = [:], host: String? = "127.0.0.1:5000", method: String = "GET") -> HTTPRequest {
        HTTPRequest(method: method, path: path, query: query, headers: host.map { ["host": $0] } ?? [:])
    }

    private func response(_ route: ProgressRoute) -> HTTPResponse? {
        if case .response(let response) = route { return response }
        return nil
    }

    @Test("Requests for other hosts are refused, which blocks DNS rebinding")
    func hostCheck() async {
        let sut = router(source: FakeProgressDataSource(tasks: [task]))

        for host in ["evil.example:5000", "127.0.0.1:6000", "127.0.0.1", nil] {
            let result = response(await sut.route(get("/api/tasks", host: host)))
            #expect(result?.status == 421)
        }
        #expect(response(await sut.route(get("/api/tasks", host: "LocalHost:5000")))?.status == 200)
    }

    @Test("Only GET and HEAD are served")
    func readOnly() async {
        let sut = router(source: FakeProgressDataSource(tasks: [task]))

        for method in ["POST", "PUT", "DELETE", "PATCH"] {
            let result = response(await sut.route(get("/api/tasks", method: method)))
            #expect(result?.status == 405)
            #expect(result?.headers["Allow"] == "GET, HEAD")
        }
        #expect(response(await sut.route(get("/api/tasks", method: "HEAD")))?.status == 200)
    }

    @Test("The index page is HTML with a restrictive content security policy")
    func index() async throws {
        let result = try #require(response(await router(source: FakeProgressDataSource()).route(get("/"))))

        #expect(result.status == 200)
        #expect(result.headers["Content-Type"]?.hasPrefix("text/html") == true)
        let csp = try #require(result.headers["Content-Security-Policy"])
        #expect(csp.contains("default-src 'none'"))
        #expect(csp.contains("frame-ancestors 'none'"))
        #expect(String(decoding: result.body, as: UTF8.self).contains("EventSource"))
    }

    @Test("The task list is JSON")
    func taskList() async throws {
        let result = try #require(response(await router(source: FakeProgressDataSource(tasks: [task])).route(get("/api/tasks"))))
        let decoded = try JSONSerialization.jsonObject(with: result.body) as? [[String: Any]]

        #expect(decoded?.count == 1)
        #expect(decoded?.first?["title"] as? String == "Write docs")
        #expect(decoded?.first?["status"] as? String == "queued")
    }

    @Test("Task detail includes the saved result; unknown or invalid ids are 404")
    func detail() async throws {
        let source = FakeProgressDataSource(tasks: [task], results: [task.id: "All done"])
        let sut = router(source: source)

        let found = try #require(response(await sut.route(get("/api/tasks/\(task.id.uuidString)"))))
        let object = try #require(try JSONSerialization.jsonObject(with: found.body) as? [String: Any])
        #expect(object["result"] as? String == "All done")
        #expect((object["task"] as? [String: Any])?["id"] as? String == task.id.uuidString)

        #expect(response(await sut.route(get("/api/tasks/\(UUID().uuidString)")))?.status == 404)
        #expect(response(await sut.route(get("/api/tasks/not-a-uuid")))?.status == 404)
    }

    @Test("Events are returned after the requested offset with the next offset")
    func events() async throws {
        let source = FakeProgressDataSource(tasks: [task], events: [task.id: ["a", "b", "c"]])
        let sut = router(source: source)

        let result = try #require(response(await sut.route(get("/api/tasks/\(task.id.uuidString)/events", query: ["after": "1"]))))
        let object = try #require(try JSONSerialization.jsonObject(with: result.body) as? [String: Any])

        #expect(object["lines"] as? [String] == ["b", "c"])
        #expect(object["next"] as? Int == 3)

        let badOffset = try #require(response(await sut.route(get("/api/tasks/\(task.id.uuidString)/events", query: ["after": "-5"]))))
        let all = try #require(try JSONSerialization.jsonObject(with: badOffset.body) as? [String: Any])
        #expect((all["lines"] as? [String])?.count == 3)
    }

    @Test("The stream route switches to server-sent events; unknown paths are 404")
    func streamAndUnknown() async {
        let sut = router(source: FakeProgressDataSource())

        #expect(await sut.route(get("/api/stream")) == .eventStream)
        #expect(response(await sut.route(get("/nope")))?.status == 404)
        #expect(response(await sut.route(get("/api")))?.status == 404)
        #expect(response(await sut.route(get("/api/tasks/x/y/z")))?.status == 404)
    }

    @Test("Responses never allow cross-origin reads")
    func noCORS() async throws {
        let result = try #require(response(await router(source: FakeProgressDataSource()).route(get("/healthz"))))
        let wire = String(decoding: result.serialized(), as: UTF8.self)

        #expect(!wire.lowercased().contains("access-control-allow-origin"))
        #expect(wire.contains("Cross-Origin-Resource-Policy: same-origin"))
        #expect(wire.contains("X-Content-Type-Options: nosniff"))
        #expect(wire.hasPrefix("HTTP/1.1 200 OK\r\n"))
    }

    @Test("A HEAD response keeps Content-Length but sends no body")
    func headResponse() {
        let response = HTTPResponse.text("hello", status: 200)
        let wire = String(decoding: response.serialized(includeBody: false), as: UTF8.self)

        #expect(wire.contains("Content-Length: 5"))
        #expect(wire.hasSuffix("\r\n\r\n"))
    }
}
