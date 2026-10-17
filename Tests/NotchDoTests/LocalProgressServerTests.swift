import Foundation
import Network
import Testing
@testable import NotchDo

/// Binds real loopback sockets; each test uses a free port.
@Suite("Local progress server", .serialized)
@MainActor
struct LocalProgressServerTests {
    private let task = AITask(prompt: "Stream me", createdAt: fixedDate(2026, 10, 17))

    private func makeServer(tasks: [AITask]? = nil) -> (LocalProgressServer, FakeProgressDataSource, URL) {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "NotchDoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = FakeProgressDataSource(tasks: tasks ?? [task])
        let server = LocalProgressServer(
            source: source,
            workspace: AIWorkspace(rootURL: base.appending(path: "NotchDo", directoryHint: .isDirectory))
        )
        return (server, source, base)
    }

    private func waitForRunning(_ server: LocalProgressServer) async -> UInt16? {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while clock.now < deadline {
            if case .running(let port) = server.state { return port }
            if case .failed = server.state { return nil }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }

    @Test("It listens on loopback, serves the API, and records its port")
    func servesOnLoopback() async throws {
        let (server, _, base) = makeServer()
        defer { server.stop(); try? FileManager.default.removeItem(at: base) }

        server.start(preferredPort: 0)
        let port = try #require(await waitForRunning(server))

        let (health, healthResponse) = try await session().data(from: #require(URL(string: "http://127.0.0.1:\(port)/healthz")))
        #expect(String(decoding: health, as: UTF8.self) == "ok")
        #expect((healthResponse as? HTTPURLResponse)?.statusCode == 200)

        let (data, _) = try await session().data(from: #require(URL(string: "http://127.0.0.1:\(port)/api/tasks")))
        let list = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(list.first?["title"] as? String == "Stream me")

        #expect(server.url?.absoluteString == "http://127.0.0.1:\(port)/")
        let portFile = AIWorkspace(rootURL: base.appending(path: "NotchDo", directoryHint: .isDirectory)).portFileURL
        #expect(try String(contentsOf: portFile, encoding: .utf8) == String(port))
    }

    @Test("A request with a foreign Host header is refused")
    func rejectsForeignHost() async throws {
        let (server, _, base) = makeServer()
        defer { server.stop(); try? FileManager.default.removeItem(at: base) }
        server.start(preferredPort: 0)
        let port = try #require(await waitForRunning(server))

        var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/api/tasks")))
        request.setValue("attacker.example", forHTTPHeaderField: "Host")
        let (_, response) = try await session().data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 421)
    }

    @Test("POST is refused")
    func rejectsPost() async throws {
        let (server, _, base) = makeServer()
        defer { server.stop(); try? FileManager.default.removeItem(at: base) }
        server.start(preferredPort: 0)
        let port = try #require(await waitForRunning(server))

        var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/api/tasks")))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        let (_, response) = try await session().data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 405)
    }

    @Test("A busy preferred port falls back to a free one")
    func portFallback() async throws {
        let (first, _, base1) = makeServer()
        let (second, _, base2) = makeServer()
        defer {
            first.stop(); second.stop()
            try? FileManager.default.removeItem(at: base1)
            try? FileManager.default.removeItem(at: base2)
        }
        first.start(preferredPort: 0)
        let taken = try #require(await waitForRunning(first))

        second.start(preferredPort: Int(taken))
        let actual = try #require(await waitForRunning(second))

        #expect(actual != taken)
    }

    @Test("The event stream sends the current tasks and then changes")
    func serverSentEvents() async throws {
        let (server, source, base) = makeServer()
        defer { server.stop(); try? FileManager.default.removeItem(at: base) }
        server.start(preferredPort: 0)
        let port = try #require(await waitForRunning(server))

        var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/api/stream")))
        request.timeoutInterval = 10
        let (bytes, response) = try await session().bytes(for: request)
        #expect((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true)

        var titles: [String] = []
        var updated = task
        updated.status = .running
        updated.title = "Changed"
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = try #require(try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [[String: Any]])
            titles.append(json.first?["title"] as? String ?? "")
            if titles.count == 1 {
                source.setTasks([updated])
            } else {
                break
            }
        }

        #expect(titles == ["Stream me", "Changed"])
    }

    @Test("Stopping closes the port and removes the port file")
    func stop() async throws {
        let (server, _, base) = makeServer()
        defer { try? FileManager.default.removeItem(at: base) }
        server.start(preferredPort: 0)
        let port = try #require(await waitForRunning(server))

        server.stop()

        #expect(server.state == .stopped)
        #expect(server.url == nil)
        let portFile = AIWorkspace(rootURL: base.appending(path: "NotchDo", directoryHint: .isDirectory)).portFileURL
        #expect(!FileManager.default.fileExists(atPath: portFile.path))
        await #expect(throws: (any Error).self) {
            _ = try await session().data(from: #require(URL(string: "http://127.0.0.1:\(port)/healthz")))
        }
    }
}
