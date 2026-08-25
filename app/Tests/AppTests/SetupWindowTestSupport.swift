import AppKit
import XCTest
@testable import App

struct SetupWindowLayoutSnapshot: CustomStringConvertible {
    let contentSize: NSSize
    let fittingSize: NSSize
    let rootFrame: NSRect
    let contentBounds: NSRect
    let documentVisibleRect: NSRect
    let rootMaxY: CGFloat
    let pendingWindowUpdate: Bool
    let pendingWindowCompletion: Bool

    var hasPendingDeferredWork: Bool {
        pendingWindowUpdate || pendingWindowCompletion
    }

    var description: String {
        "contentSize=\(contentSize) fittingSize=\(fittingSize) rootFrame=\(rootFrame) "
            + "contentBounds=\(contentBounds) documentVisibleRect=\(documentVisibleRect) "
            + "rootMaxY=\(rootMaxY) pendingWindowUpdate=\(pendingWindowUpdate) "
            + "pendingWindowCompletion=\(pendingWindowCompletion)"
    }

    func isStable(with other: SetupWindowLayoutSnapshot, accuracy: CGFloat = 0.01) -> Bool {
        func close(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
            abs(lhs - rhs) <= accuracy
        }

        func close(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
            close(lhs.width, rhs.width) && close(lhs.height, rhs.height)
        }

        func close(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
            close(lhs.origin.x, rhs.origin.x)
                && close(lhs.origin.y, rhs.origin.y)
                && close(lhs.size.width, rhs.size.width)
                && close(lhs.size.height, rhs.size.height)
        }

        return close(contentSize, other.contentSize)
            && close(fittingSize, other.fittingSize)
            && close(rootFrame, other.rootFrame)
            && close(contentBounds, other.contentBounds)
            && close(documentVisibleRect, other.documentVisibleRect)
            && close(rootMaxY, other.rootMaxY)
    }
}

enum SetupWindowTestSupport {
    private static let maximumLayoutPasses = 20
    private static let runLoopPumpDuration: TimeInterval = 0.001

    @discardableResult
    static func settle(
        _ window: NSWindow, file: StaticString = #filePath, line: UInt = #line
    ) -> SetupWindowLayoutSnapshot? {
        var previous: SetupWindowLayoutSnapshot?
        for _ in 0..<maximumLayoutPasses {
            // Do not force a layout here: the test must expose the stale clip left by a window
            // resize inside `layout()`. Let AppKit's own cycle run; the fixed point, not this
            // short pump interval, is the termination condition.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: runLoopPumpDuration))
            guard let current = snapshot(in: window) else {
                XCTFail("the window has no scroll/document layout to settle", file: file, line: line)
                return nil
            }
            if let last = previous, current.isStable(with: last) {
                if current.hasPendingDeferredWork {
                    print(
                        "SETUP_LAYOUT_SETTLE_WAIT pendingWindowUpdate=\(current.pendingWindowUpdate) "
                            + "pendingWindowCompletion=\(current.pendingWindowCompletion)"
                    )
                    // Keep the outer comparison baseline current even while deferred work keeps
                    // the geometry unchanged; relying on that equality is an accidental property
                    // of this pass, not part of the fixed-point contract.
                    previous = current
                    continue
                }
                return current
            }
            previous = current
        }
        XCTFail(
            "layout did not reach a fixed point in \(maximumLayoutPasses) passes; last snapshot: \(String(describing: previous))",
            file: file, line: line
        )
        return previous
    }

    private static func snapshot(in window: NSWindow) -> SetupWindowLayoutSnapshot? {
        guard let scroll = window.contentView as? NSScrollView,
              let document = scroll.documentView as? FittedContentStackView
        else { return nil }
        return SetupWindowLayoutSnapshot(
            contentSize: window.contentRect(forFrameRect: window.frame).size,
            fittingSize: document.fittingSize,
            rootFrame: document.frame,
            contentBounds: scroll.contentView.bounds,
            documentVisibleRect: scroll.documentVisibleRect,
            rootMaxY: document.frame.maxY,
            pendingWindowUpdate: document.deferredWindowUpdatePendingForTesting,
            pendingWindowCompletion: document.deferredWindowCompletionPendingForTesting
        )
    }
}
