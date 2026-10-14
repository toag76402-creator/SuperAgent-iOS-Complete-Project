import XCTest
@testable import SuperAgent

final class AgentLoopTests: XCTestCase {
    func testToolCallJSONIsParsed() {
        let response = #"{"type":"tool_call","name":"readAppStatus","arguments":{}}"#
        guard case .tool(let call) = AgentLoop.decision(from: response) else {
            return XCTFail("Expected an allow-listed tool call payload to be parsed")
        }
        XCTAssertEqual(call.name, "readAppStatus")
        XCTAssertTrue(call.arguments.isEmpty)
    }

    func testPlainTextIsNeverTreatedAsSuccessfulToolCall() {
        let response = "I sent the email successfully."
        guard case .final(let text) = AgentLoop.decision(from: response) else {
            return XCTFail("Plain text must not execute a tool")
        }
        XCTAssertEqual(text, response)
    }

    func testUnknownToolIsRejected() {
        let call = AgentToolCall(name: "deleteEverything", arguments: [:])
        XCTAssertNotNil(ToolRegistry.validate(call, hasImage: false))
    }

    func testInvalidURLIsRejected() {
        let call = AgentToolCall(name: "openURL", arguments: ["url": "javascript:alert(1)"])
        XCTAssertNotNil(ToolRegistry.validate(call, hasImage: false))
        XCTAssertTrue(ToolRegistry.requiresApproval(call))
    }

    func testImageToolRequiresImageContext() {
        let call = AgentToolCall(name: "analyzeSelectedImage", arguments: [:])
        XCTAssertNotNil(ToolRegistry.validate(call, hasImage: false))
        XCTAssertNil(ToolRegistry.validate(call, hasImage: true))
    }

    func testApprovalPolicyCoversExternalActions() {
        XCTAssertTrue(ToolRegistry.requiresApproval(AgentToolCall(name: "openURL", arguments: ["url": "https://example.com"])))
        XCTAssertTrue(ToolRegistry.requiresApproval(AgentToolCall(name: "copyToClipboard", arguments: ["text": "visible to user"])))
        XCTAssertTrue(ToolRegistry.requiresApproval(AgentToolCall(name: "createReminder", arguments: ["title": "Test"])))
        XCTAssertFalse(ToolRegistry.requiresApproval(AgentToolCall(name: "saveNote", arguments: ["title": "Test", "content": "Body"])))
    }

    func testLoopLimitsAreBounded() {
        XCTAssertEqual(AgentLoop.maximumIterations, 6)
        XCTAssertEqual(AgentLoop.maximumToolCallsPerTurn, 3)
        XCTAssertEqual(AgentLoop.maximumRetries, 2)
        XCTAssertEqual(AgentLoop.requestTimeout, 60)
        XCTAssertEqual(AgentLoop.toolTimeout, 30)
    }

    func testDuplicateIntentCommandIsConsumedOnlyOnce() throws {
        let suite = "SuperAgentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(PendingCommandQueue.enqueue("check status", in: defaults))
        XCTAssertFalse(PendingCommandQueue.enqueue("check status", in: defaults))
        XCTAssertEqual(PendingCommandQueue.consume(from: defaults), "check status")
        XCTAssertNil(PendingCommandQueue.consume(from: defaults))
    }

    func testExpiredIntentCommandIsDiscarded() throws {
        let suite = "SuperAgentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let queuedAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(PendingCommandQueue.enqueue("old command", in: defaults, now: queuedAt))
        XCTAssertNil(PendingCommandQueue.consume(from: defaults, now: queuedAt.addingTimeInterval(PendingCommandQueue.maximumAge + 1)))
    }

    func testCancellationIsObservable() {
        let cancellation = AgentLoopCancellation()
        XCTAssertFalse(cancellation.isCancelled)
        cancellation.cancel()
        XCTAssertTrue(cancellation.isCancelled)
    }

    func testApprovalDenialIsReturnedToAgent() {
        let manager = ApprovalManager()
        var accepted: Bool?
        manager.request(ToolApprovalRequest(title: "Open URL", details: "https://example.com")) { accepted = $0 }
        manager.resolve(approved: false)
        XCTAssertEqual(accepted, false)
    }

    func testToolFailureIsExplicitlyReturned() {
        let failure = AgentToolResult.failure("Permission denied")
        XCTAssertFalse(failure.succeeded)
        let context = AgentLoop.appendToolResult(failure, toolName: "createReminder", to: "")
        XCTAssertTrue(context.contains("success=false"))
        XCTAssertTrue(context.contains("Permission denied"))
    }
}
