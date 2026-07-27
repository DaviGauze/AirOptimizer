import XCTest
@testable import AirOptimizer

final class ProcessManagerTests: XCTestCase {
    func testListProcessesIncludesCurrentProcess() {
        let manager = ProcessManager()
        let processes = manager.listProcesses()
        XCTAssertTrue(processes.contains { $0.pid == getpid() })
    }

    func testCriticalProcessCannotBeTerminated() {
        let manager = ProcessManager()
        XCTAssertThrowsError(try manager.terminate(pid: 1, name: "launchd", signal: .sigterm)) { error in
            guard case ProcessManagerError.criticalProcessProtected = error else {
                XCTFail("Expected criticalProcessProtected, got \(error)")
                return
            }
        }
    }

    func testProcessExistsForCurrentProcess() {
        let manager = ProcessManager()
        XCTAssertTrue(manager.processExists(pid: getpid()))
    }

    func testProcessExistsIsFalseForUnlikelyPID() {
        let manager = ProcessManager()
        XCTAssertFalse(manager.processExists(pid: 999_999))
    }

    /// Spawna um processo filho real (`/bin/sleep`) e confirma que
    /// `terminate(signal: .sigkill)` realmente o mata — cobre o caminho
    /// exercido pelo botão "Forçar Parada" da UI, e não só a validação de
    /// processo crítico.
    func testSigkillTerminatesRealProcess() throws {
        let manager = ProcessManager()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sleep")
        task.arguments = ["30"]
        try task.run()
        let pid = task.processIdentifier

        XCTAssertTrue(manager.processExists(pid: pid))

        XCTAssertTrue(try manager.terminate(pid: pid, name: "sleep", signal: .sigkill))

        task.waitUntilExit()
        XCTAssertEqual(task.terminationReason, .uncaughtSignal)
        XCTAssertFalse(manager.processExists(pid: pid))
    }
}

final class CriticalProcessGuardTests: XCTestCase {
    func testProtectsKnownSystemProcesses() {
        XCTAssertTrue(CriticalProcessGuard.isCritical(pid: 100, name: "WindowServer"))
        XCTAssertTrue(CriticalProcessGuard.isCritical(pid: 100, name: "finder"))
        XCTAssertTrue(CriticalProcessGuard.isCritical(pid: 1, name: "anything"))
    }

    func testAllowsRegularApps() {
        XCTAssertFalse(CriticalProcessGuard.isCritical(pid: 12345, name: "Safari"))
    }
}
