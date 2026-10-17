import Foundation

/// JSON shapes served to the progress page. Keys are sorted so unchanged data compares equal.
enum ProgressJSON {
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func tasks(_ tasks: [AITask]) -> Data {
        (try? encoder.encode(tasks)) ?? Data("[]".utf8)
    }

    struct Detail: Encodable {
        var task: AITask
        var result: String?
    }

    static func detail(_ task: AITask, result: String?) -> Data {
        (try? encoder.encode(Detail(task: task, result: result))) ?? Data("{}".utf8)
    }

    struct Events: Encodable {
        var lines: [String]
        var next: Int
    }

    static func events(_ lines: [String], after offset: Int) -> Data {
        (try? encoder.encode(Events(lines: lines, next: offset + lines.count))) ?? Data("{}".utf8)
    }

    /// One Server-Sent Events frame.
    static func sseFrame(event: String, data: Data) -> Data {
        var frame = Data("event: \(event)\ndata: ".utf8)
        frame.append(data)
        frame.append(Data("\n\n".utf8))
        return frame
    }
}
