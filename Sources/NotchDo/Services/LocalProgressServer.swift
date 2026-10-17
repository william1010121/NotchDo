import Foundation
import Network
import Observation
import OSLog

/// Serves the AI progress page on 127.0.0.1 only. Uses Network.framework directly so the
/// package stays dependency-free; the protocol surface is a handful of read-only GET routes.
@MainActor
@Observable
final class LocalProgressServer {
    enum State: Equatable {
        case stopped
        case starting
        case running(port: UInt16)
        case failed(String)
    }

    private static let logger = Logger(subsystem: "com.luku.NotchDo", category: "LocalProgressServer")
    nonisolated private static let maxConnections = 32

    private(set) var state: State = .stopped

    var url: URL? {
        guard case .running(let port) = state else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/")
    }

    @ObservationIgnored private let source: any ProgressDataSource
    @ObservationIgnored private let workspace: AIWorkspace
    @ObservationIgnored private let queue = DispatchQueue(label: "com.luku.NotchDo.progress-server")
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let tracker = ConnectionTracker()
    @ObservationIgnored private let hostBox = HostBox()

    init(source: any ProgressDataSource, workspace: AIWorkspace) {
        self.source = source
        self.workspace = workspace
    }

    /// Starts on `preferredPort`, or on a free port when that one is taken. Restarts if running.
    func start(preferredPort: Int) {
        stop()
        generation += 1
        state = .starting
        let attempt = generation
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: preferredPort)) else {
            state = .failed("Invalid port \(preferredPort).")
            return
        }
        listen(on: port, fallbackToAnyPort: true, attempt: attempt)
    }

    func stop() {
        generation += 1
        listener?.cancel()
        listener = nil
        tracker.cancelAll()
        hostBox.set([])
        try? FileManager.default.removeItem(at: workspace.portFileURL)
        state = .stopped
    }

    // MARK: - Listening

    private func listen(on port: NWEndpoint.Port, fallbackToAnyPort: Bool, attempt: Int) {
        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters)
        } catch {
            fail(error, port: port, fallbackToAnyPort: fallbackToAnyPort, attempt: attempt)
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in self?.listenerStateChanged(newState, port: port, fallbackToAnyPort: fallbackToAnyPort, attempt: attempt) }
        }
        listener.start(queue: queue)
    }

    private func listenerStateChanged(
        _ newState: NWListener.State,
        port: NWEndpoint.Port,
        fallbackToAnyPort: Bool,
        attempt: Int
    ) {
        guard attempt == generation else { return }
        switch newState {
        case .ready:
            guard let actual = listener?.port?.rawValue else { return }
            hostBox.set(["127.0.0.1:\(actual)", "localhost:\(actual)"])
            state = .running(port: actual)
            try? FileManager.default.createDirectory(at: workspace.internalURL, withIntermediateDirectories: true)
            try? String(actual).write(to: workspace.portFileURL, atomically: true, encoding: .utf8)
            Self.logger.info("Progress server listening on 127.0.0.1:\(actual)")
        case .failed(let error), .waiting(let error):
            listener?.cancel()
            listener = nil
            fail(error, port: port, fallbackToAnyPort: fallbackToAnyPort, attempt: attempt)
        default:
            break
        }
    }

    private func fail(_ error: Error, port: NWEndpoint.Port, fallbackToAnyPort: Bool, attempt: Int) {
        guard attempt == generation else { return }
        if fallbackToAnyPort {
            Self.logger.notice("Port \(port.rawValue) unavailable (\(error.localizedDescription, privacy: .public)); using a free port")
            listen(on: .any, fallbackToAnyPort: false, attempt: attempt)
        } else {
            state = .failed(error.localizedDescription)
            Self.logger.error("Progress server failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Connections

    private nonisolated func accept(_ connection: NWConnection) {
        let router = ProgressRouter(source: source, allowedHosts: { [hostBox] in hostBox.get() })
        let handler = ProgressConnection(connection: connection, router: router, source: source, tracker: tracker)
        // The tracker owns the handler until the connection ends.
        guard tracker.add(connection, owner: handler, limit: Self.maxConnections) else {
            connection.cancel()
            return
        }
        handler.start(on: queue)
    }
}

/// Host header values currently accepted, readable from connection threads.
private final class HostBox: @unchecked Sendable {
    private let lock = NSLock()
    private var hosts: Set<String> = []

    func set(_ value: Set<String>) { lock.withLock { hosts = value } }
    func get() -> Set<String> { lock.withLock { hosts } }
}

/// Keeps live connections so they can be capped and closed on stop.
final class ConnectionTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [ObjectIdentifier: (connection: NWConnection, owner: AnyObject)] = [:]

    func add(_ connection: NWConnection, owner: AnyObject, limit: Int) -> Bool {
        lock.withLock {
            guard connections.count < limit else { return false }
            connections[ObjectIdentifier(connection)] = (connection, owner)
            return true
        }
    }

    func remove(_ connection: NWConnection) {
        lock.withLock { _ = connections.removeValue(forKey: ObjectIdentifier(connection)) }
    }

    func cancelAll() {
        let all = lock.withLock {
            defer { connections.removeAll() }
            return connections.values.map(\.connection)
        }
        all.forEach { $0.cancel() }
    }
}
