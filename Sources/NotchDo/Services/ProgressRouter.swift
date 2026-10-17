import Foundation

enum ProgressRoute: Equatable, Sendable {
    case response(HTTPResponse)
    /// Keep the connection open and push task updates.
    case eventStream
}

/// Maps requests to responses. Read-only by design: a web page elsewhere in the browser can
/// make requests to localhost, so nothing here may create or change a task.
struct ProgressRouter: Sendable {
    let source: any ProgressDataSource
    /// Host header values this server answers to, e.g. `127.0.0.1:47821`. Anything else is
    /// refused, which blocks DNS-rebinding pages from reading task data.
    let allowedHosts: @Sendable () -> Set<String>

    func route(_ request: HTTPRequest) async -> ProgressRoute {
        guard let host = request.headers["host"]?.lowercased(), allowedHosts().contains(host) else {
            return .response(.text("Unrecognized host.", status: 421))
        }
        guard request.method == "GET" || request.method == "HEAD" else {
            var response = HTTPResponse.text("Read-only.", status: 405)
            response.headers["Allow"] = "GET, HEAD"
            return .response(response)
        }

        let parts = request.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.isEmpty { return .response(.html(ProgressPageAssets.indexHTML)) }
        if parts == ["healthz"] { return .response(.text("ok", status: 200)) }
        guard parts.first == "api" else { return notFound }

        switch parts.count {
        case 2 where parts[1] == "tasks":
            return .response(.json(ProgressJSON.tasks(await source.tasks())))
        case 2 where parts[1] == "stream":
            return .eventStream
        case 3 where parts[1] == "tasks":
            guard let id = UUID(uuidString: parts[2]), let task = await source.task(id: id) else { return notFound }
            return .response(.json(ProgressJSON.detail(task, result: await source.result(for: id))))
        case 4 where parts[1] == "tasks" && parts[3] == "events":
            guard let id = UUID(uuidString: parts[2]), await source.task(id: id) != nil else { return notFound }
            let offset = max(0, Int(request.query["after"] ?? "") ?? 0)
            return .response(.json(ProgressJSON.events(await source.eventLines(for: id, after: offset), after: offset)))
        default:
            return notFound
        }
    }

    private var notFound: ProgressRoute {
        .response(.text("Not found.", status: 404))
    }
}
