import CoreGraphics

/// Geometry of the AI drawer: a second fixed panel placed directly to the right of the
/// expanded notch panel. It reuses the notch silhouette (flared top corners), so its
/// frame is the visible body plus one flare radius on each side.
enum AIDrawerMetrics {
    static let bodyWidth: CGFloat = 300
    static let flareRadius: CGFloat = 12
    static var width: CGFloat { bodyWidth + flareRadius * 2 }

    /// Same top and height as the main panel, starting at its right edge.
    static func frame(besideMainPanel main: CGRect) -> CGRect {
        CGRect(x: main.maxX, y: main.minY, width: width, height: main.height)
    }

    /// While expanded, the pointer may rest on either panel without collapsing the notch.
    static func trackingRect(mainFrame: CGRect, tolerance: CGFloat) -> CGRect {
        mainFrame.union(frame(besideMainPanel: mainFrame)).insetBy(dx: -tolerance, dy: -tolerance)
    }
}
