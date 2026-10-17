import Foundation
import Network

/// Handles one client connection: read a request, answer it, then close, or hold the
/// connection open as a Server-Sent Events stream.
final class ProgressConnection: @unchecked Sendable {
    private static let requestTimeout: TimeInterval = 10
    private static let pollInterval: Duration = .seconds(1)
    private static let keepAliveEvery = 15

    private let connection: NWConnection
    private let router: ProgressRouter
    private let source: any ProgressDataSource
    private let tracker: ConnectionTracker
    private let lock = NSLock()
    private var buffer = Data()
    private var streamTask: Task<Void, Never>?
    private var finished = false

    init(connection: NWConnection, router: ProgressRouter, source: any ProgressDataSource, tracker: ConnectionTracker) {
        self.connection = connection
        self.router = router
        self.source = source
        self.tracker = tracker
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.finish()
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.requestTimeout) { [weak self] in
            guard let self, !self.hasRequest else { return }
            self.connection.cancel()
        }
        receive()
    }

    private var hasRequest: Bool {
        lock.withLock { streamTask != nil || finished || requestHandled }
    }

    private var requestHandled = false

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.buffer.append(data) }
            switch HTTPRequestParser.parse(self.buffer) {
            case .incomplete:
                if error != nil || isComplete { self.connection.cancel() } else { self.receive() }
            case .request(let request):
                self.lock.withLock { self.requestHandled = true }
                Task { await self.respond(to: request) }
            case .malformed:
                self.send(.text("Bad request.", status: 400))
            case .tooLarge:
                self.send(.text("Request too large.", status: 431))
            }
        }
    }

    private func respond(to request: HTTPRequest) async {
        switch await router.route(request) {
        case .response(let response):
            send(response, includeBody: request.method != "HEAD")
        case .eventStream:
            stream()
        }
    }

    private func send(_ response: HTTPResponse, includeBody: Bool = true) {
        connection.send(
            content: response.serialized(includeBody: includeBody),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] _ in self?.connection.cancel() }
        )
    }

    private func stream() {
        connection.send(content: HTTPResponse.eventStreamHead(), completion: .contentProcessed { _ in })
        let task = Task { [weak self, source] in
            var last: Data?
            var ticks = 0
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = ProgressJSON.tasks(await source.tasks())
                if snapshot != last {
                    last = snapshot
                    self.write(ProgressJSON.sseFrame(event: "tasks", data: snapshot))
                } else if ticks % Self.keepAliveEvery == Self.keepAliveEvery - 1 {
                    self.write(Data(": keep-alive\n\n".utf8))
                }
                ticks += 1
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        lock.withLock { streamTask = task }
    }

    private func write(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.connection.cancel() }
        })
    }

    private func finish() {
        let task: Task<Void, Never>? = lock.withLock {
            finished = true
            defer { streamTask = nil }
            return streamTask
        }
        task?.cancel()
        tracker.remove(connection)
    }
}
