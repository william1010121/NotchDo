import Foundation
import Testing
@testable import NotchDo

@Suite("Line buffer")
struct LineBufferTests {
    @Test("Lines split across chunks are joined")
    func splitChunks() {
        let buffer = LineBuffer()

        #expect(buffer.append(Data("{\"a\":".utf8)).isEmpty)
        #expect(buffer.append(Data("1}\n{\"b\":2}\n{\"c".utf8)) == ["{\"a\":1}", "{\"b\":2}"])
        #expect(buffer.append(Data("\":3}\n".utf8)) == ["{\"c\":3}"])
        #expect(buffer.flush() == nil)
    }

    @Test("An unterminated final line is returned by flush")
    func flushRemainder() {
        let buffer = LineBuffer()
        _ = buffer.append(Data("one\ntwo".utf8))

        #expect(buffer.flush() == "two")
        #expect(buffer.flush() == nil)
    }

    @Test("Multi-byte characters survive being split across chunks")
    func multibyte() {
        let buffer = LineBuffer()
        let bytes = Array("設計\n".utf8)

        #expect(buffer.append(Data(bytes[0..<4])).isEmpty)
        #expect(buffer.append(Data(bytes[4...])) == ["設計"])
    }
}
