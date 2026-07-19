import Foundation
import XCTest
@testable import flutter_vless_tunnel_support

final class TunnelRuntimeSupportTests: XCTestCase {
    func testLifecycleRejectsImmediateWorkerExit() {
        let lifecycle = TunnelProcessLifecycle()
        lifecycle.beginStart()

        DispatchQueue.global().async {
            lifecycle.markThreadEntered()
            lifecycle.markExited(code: -1)
        }

        XCTAssertEqual(
            lifecycle.waitForStableStartup(gracePeriod: 0.05),
            .exited(-1)
        )
    }

    func testLifecycleWaitsForExpectedShutdown() {
        let lifecycle = TunnelProcessLifecycle()
        lifecycle.beginStart()
        lifecycle.markThreadEntered()

        XCTAssertEqual(
            lifecycle.waitForStableStartup(gracePeriod: 0.01),
            .running
        )
        XCTAssertTrue(lifecycle.isRunning)

        lifecycle.requestStop()
        XCTAssertFalse(lifecycle.markExited(code: 0))
        XCTAssertTrue(lifecycle.waitForExit(timeout: 0.01))
        XCTAssertTrue(lifecycle.isStopRequested)
    }

    func testLifecycleMarksUnrequestedExitAsUnexpected() {
        let lifecycle = TunnelProcessLifecycle()
        lifecycle.beginStart()
        lifecycle.markThreadEntered()

        XCTAssertTrue(lifecycle.markExited(code: 9))
    }

    func testWatchdogRequiresConsecutiveFailures() {
        var policy = TunnelWatchdogFailurePolicy(failureThreshold: 3)

        XCTAssertFalse(policy.record(success: false))
        XCTAssertFalse(policy.record(success: false))
        XCTAssertFalse(policy.record(success: true))
        XCTAssertEqual(policy.consecutiveFailures, 0)
        XCTAssertFalse(policy.record(success: false))
        XCTAssertFalse(policy.record(success: false))
        XCTAssertTrue(policy.record(success: false))
    }

    func testFileLogRotatesAndReturnsOnlyBoundedTail() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("tunnel.log")
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<100 {
            try TunnelFileLog.append(
                "line-\(index)-xxxxxxxxxxxxxxxxxxxxxxxx",
                to: url,
                maxFileBytes: 512,
                retainedBytes: 256
            )
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        let tail = try TunnelFileLog.tail(of: url, maxBytes: 180, maxLines: 3)

        XCTAssertLessThanOrEqual(size, 512)
        XCTAssertFalse(tail.contains("line-0-"))
        XCTAssertTrue(tail.contains("line-99-"))
        XCTAssertLessThanOrEqual(tail.split(separator: "\n").count, 3)
    }
}
