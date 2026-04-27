import XCTest
@testable import CCRMenuBar

final class ProxyServiceTests: XCTestCase {
    func testStripTerminalControlSequencesRemovesANSIAndCopiedBoldSuffix() {
        XCTAssertEqual(
            ProxyService.stripTerminalControlSequences(from: "\u{001B}[1mclaude-opus-4-7\u{001B}[0m"),
            "claude-opus-4-7"
        )
        XCTAssertEqual(
            ProxyService.stripTerminalControlSequences(from: "claude-opus-4-7[1m]"),
            "claude-opus-4-7"
        )
    }

    func testSanitizedJSONBodyForCCRRewritesOnlyModelField() throws {
        let input = #"{"model":"claude-opus-4-7\u001B[1m","messages":[{"role":"user","content":"hi"}]}"#
        let output = ProxyService.sanitizedJSONBodyForCCR(Data(input.utf8))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(output)) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "claude-opus-4-7")
        XCTAssertNotNil(object["messages"])
    }

    func testSanitizedJSONBodyForCCRUsesAdaptiveThinkingForOpus47() throws {
        let input = #"{"model":"claude-sonnet-4-6","thinking":{"type":"enabled","budget_tokens":12000},"anthropic_beta":["interleaved-thinking-2025-05-14","claude-code-20250219"],"messages":[{"role":"user","content":"hi"}]}"#
        let output = ProxyService.sanitizedJSONBodyForCCR(Data(input.utf8), useAdaptiveThinking: true)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(output)) as? [String: Any])
        let thinking = try XCTUnwrap(object["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "adaptive")
        XCTAssertNil(thinking["budget_tokens"])

        let outputConfig = try XCTUnwrap(object["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "high")

        let betas = try XCTUnwrap(object["anthropic_beta"] as? [String])
        XCTAssertEqual(betas, ["claude-code-20250219"])
    }

    func testRemovingInterleavedThinkingBetaKeepsOtherBetas() {
        XCTAssertEqual(
            ProxyService.removingInterleavedThinkingBeta(from: "claude-code-20250219, interleaved-thinking-2025-05-14"),
            "claude-code-20250219"
        )
    }

    func testSanitizedJSONBodyForCCRSanitizesOpenAIProviderFields() throws {
        let input = #"{"model":"claude-sonnet-4-6","stream":true,"max_tokens":1024,"metadata":{"source":"claude-code"},"system":[{"type":"text","text":"You are concise."}],"context_management":{"edits":true},"output_config":{"effort":"high"},"thinking":{"type":"enabled","budget_tokens":8000},"anthropic_beta":["claude-code-20250219"],"tools":[{"name":"Read","description":"Read file","input_schema":{"type":"object"}}],"tool_choice":{"type":"tool","name":"Read"},"messages":[{"role":"user","content":"hi"},{"role":"assistant","content":[{"type":"text","text":"I will read."},{"type":"tool_use","id":"call_123","name":"Read","input":{"file_path":"/tmp/a.txt"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"call_123","content":"ok"},{"type":"text","text":"continue"}]}]}"#
        let output = ProxyService.sanitizedJSONBodyForCCR(
            Data(input.utf8),
            sanitizeForOpenAIProvider: true,
            forceModel: "OpenAI,gpt-5.5"
        )

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(output)) as? [String: Any])
        XCTAssertNil(object["context_management"])
        XCTAssertNil(object["output_config"])
        XCTAssertNil(object["thinking"])
        XCTAssertNil(object["anthropic_beta"])
        XCTAssertNil(object["metadata"])
        XCTAssertNil(object["system"])
        XCTAssertEqual(object["model"] as? String, "OpenAI,gpt-5.5")
        XCTAssertNil(object["max_tokens"])
        XCTAssertEqual(object["max_completion_tokens"] as? Int, 1024)
        XCTAssertEqual(object["stream"] as? Bool, false)

        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.first?["content"] as? String, "You are concise.")
        XCTAssertEqual(messages[2]["role"] as? String, "assistant")
        XCTAssertEqual(messages[2]["content"] as? String, "I will read.")
        let toolCalls = try XCTUnwrap(messages[2]["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(toolCalls.first?["id"] as? String, "call_123")
        let toolFunction = try XCTUnwrap(toolCalls.first?["function"] as? [String: Any])
        XCTAssertEqual(toolFunction["name"] as? String, "Read")
        XCTAssertEqual(messages[3]["role"] as? String, "tool")
        XCTAssertEqual(messages[3]["tool_call_id"] as? String, "call_123")

        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "Read")

        let toolChoice = try XCTUnwrap(object["tool_choice"] as? [String: Any])
        XCTAssertEqual(toolChoice["type"] as? String, "function")
    }

    func testOpenAIChatResponseConvertsToAnthropicSSE() throws {
        let input = #"{"id":"chatcmpl_123","model":"gpt-5.5","choices":[{"message":{"role":"assistant","content":"merhaba"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":2}}"#
        let output = try XCTUnwrap(ProxyService.openAIChatResponseToAnthropicSSE(Data(input.utf8)))
        let text = try XCTUnwrap(String(data: output, encoding: .utf8))

        XCTAssertTrue(text.contains("event: message_start"))
        XCTAssertTrue(text.contains("event: content_block_delta"))
        XCTAssertTrue(text.contains("\"text\":\"merhaba\""))
        XCTAssertTrue(text.contains("event: message_stop"))
    }

    func testSanitizedJSONBodyForOpenAIProviderLimitsToolsAndKeepsReferencedTool() throws {
        let tools = (0..<184).map { index in
            #"{"name":"Tool\#(index)","input_schema":{"type":"object"}}"#
        }.joined(separator: ",")
        let input = #"{"model":"claude-sonnet-4-6","messages":[{"role":"assistant","content":[{"type":"tool_use","id":"call_999","name":"Tool180","input":{}}]}],"tools":[\#(tools)]}"#
        let output = ProxyService.sanitizedJSONBodyForCCR(Data(input.utf8), sanitizeForOpenAIProvider: true)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(output)) as? [String: Any])
        let limitedTools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        XCTAssertEqual(limitedTools.count, 128)

        let names = limitedTools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any] else { return nil }
            return function["name"] as? String
        }
        XCTAssertTrue(names.contains("Tool180"))
    }

    func testOpenAIToolCallResponseConvertsToAnthropicToolUseSSE() throws {
        let input = #"{"id":"chatcmpl_123","model":"gpt-5.5","choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_123","type":"function","function":{"name":"Read","arguments":"{\"file_path\":\"/tmp/a.txt\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}"#
        let output = try XCTUnwrap(ProxyService.openAIChatResponseToAnthropicSSE(Data(input.utf8)))
        let text = try XCTUnwrap(String(data: output, encoding: .utf8))

        XCTAssertTrue(text.contains("\"type\":\"tool_use\""))
        XCTAssertTrue(text.contains("\"id\":\"call_123\""))
        XCTAssertTrue(text.contains("\"name\":\"Read\""))
        XCTAssertTrue(text.contains("\"type\":\"input_json_delta\""))
        XCTAssertTrue(text.contains(#"\"file_path\":\"\/tmp\/a.txt\""#))
        XCTAssertTrue(text.contains("\"stop_reason\":\"tool_use\""))
    }

    func testHeaderValueTreatsBlankSessionAsMissing() {
        let request = ProxyHTTPRequest(
            method: "GET",
            path: "/_api/current",
            httpVersion: "HTTP/1.1",
            headers: [("X-CCR-Session", "   ")],
            body: nil
        )

        XCTAssertNil(request.headerValue("X-CCR-Session"))
    }
}
