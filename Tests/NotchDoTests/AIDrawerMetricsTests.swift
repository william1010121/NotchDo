import CoreGraphics
import Testing
@testable import NotchDo

@Suite("AI drawer metrics")
struct AIDrawerMetricsTests {
    private let main = CGRect(x: 500, y: 800, width: 440, height: 470)

    @Test("The drawer sits flush against the main panel's right edge with the same height")
    func frame() {
        let drawer = AIDrawerMetrics.frame(besideMainPanel: main)

        #expect(drawer.minX == main.maxX)
        #expect(drawer.minY == main.minY)
        #expect(drawer.height == main.height)
        #expect(drawer.width == AIDrawerMetrics.bodyWidth + AIDrawerMetrics.flareRadius * 2)
    }

    @Test("The pointer may rest on either panel without leaving the notch")
    func tracking() {
        let rect = AIDrawerMetrics.trackingRect(mainFrame: main, tolerance: 3)

        #expect(rect.contains(CGPoint(x: main.midX, y: main.midY)))
        #expect(rect.contains(CGPoint(x: main.maxX + 100, y: main.midY)))
        #expect(rect.contains(CGPoint(x: main.minX - 2, y: main.midY)))
        #expect(!rect.contains(CGPoint(x: main.minX - 20, y: main.midY)))
        #expect(!rect.contains(CGPoint(x: main.maxX + AIDrawerMetrics.width + 20, y: main.midY)))
    }
}
