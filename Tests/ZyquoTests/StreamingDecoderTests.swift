import XCTest
@testable import Zyquo

final class StreamingDecoderTests: XCTestCase {

    // MARK: - SSEDecoder

    func testBasicSSEParsing() {
        let decoder = SSEDecoder()
        let raw = "event: message_start\ndata: {\"type\":\"message_start\"}\n\n"
        let events = decoder.decode(raw.data(using: .utf8)!)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, "message_start")
        XCTAssertTrue(events[0].data.contains("message_start"))
    }

    func testMultipleEventsInOneChunk() {
        let decoder = SSEDecoder()
        let raw = """
        event: content_block_delta\ndata: {"delta":{"type":"text_delta","text":"Hello"}}\n\nevent: content_block_delta\ndata: {"delta":{"type":"text_delta","text":" world"}}\n\n
        """
        let events = decoder.decode(raw.data(using: .utf8)!)
        XCTAssertEqual(events.count, 2)
    }

    func testPartialChunkBuffering() {
        let decoder = SSEDecoder()
        let part1 = "event: ping\ndata: "
        let part2 = "{}\n\n"

        let events1 = decoder.decode(part1.data(using: .utf8)!)
        XCTAssertEqual(events1.count, 0)

        let events2 = decoder.decode(part2.data(using: .utf8)!)
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events2[0].type, "ping")
    }

    func testDoneSentinel() {
        let decoder = SSEDecoder()
        let raw = "data: [DONE]\n\n"
        let events = decoder.decode(raw.data(using: .utf8)!)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "[DONE]")
    }

    func testReset() {
        let decoder = SSEDecoder()
        _ = decoder.decode("event: partial\ndata: {".data(using: .utf8)!)
        decoder.reset()
        let events = decoder.decode("event: fresh\ndata: {}\n\n".data(using: .utf8)!)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, "fresh")
    }

    func testEmptyDataLine() {
        let decoder = SSEDecoder()
        let raw = "event: test\ndata:\n\n"
        let events = decoder.decode(raw.data(using: .utf8)!)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "")
    }

    // MARK: - Anthropic Event Parser

    func testParseMessageStart() {
        let json = """
        {"type":"message_start","message":{"id":"msg_123","type":"message","role":"assistant","model":"claude-sonnet-4-6-20250514","content":[],"usage":{"input_tokens":100,"output_tokens":0}}}
        """
        let event = SSEEvent(type: "message_start", data: json)
        let result = AnthropicEventParser.parse(event: event)

        if case .messageStart(let meta) = result {
            XCTAssertEqual(meta.id, "msg_123")
            XCTAssertEqual(meta.model, "claude-sonnet-4-6-20250514")
        } else {
            XCTFail("Expected messageStart, got \(String(describing: result))")
        }
    }

    func testParseTextDelta() {
        let json = """
        {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
        """
        let event = SSEEvent(type: "content_block_delta", data: json)
        let result = AnthropicEventParser.parse(event: event)

        if case .textDelta(let text) = result {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected textDelta")
        }
    }

    func testParseToolUseStart() {
        let json = """
        {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu_abc","name":"shell.run"}}
        """
        let event = SSEEvent(type: "content_block_start", data: json)
        let result = AnthropicEventParser.parse(event: event)

        if case .toolUseStart(let meta) = result {
            XCTAssertEqual(meta.id, "tu_abc")
            XCTAssertEqual(meta.name, "shell.run")
        } else {
            XCTFail("Expected toolUseStart")
        }
    }

    func testParseInputJsonDelta() {
        let json = """
        {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"command\\":"}}
        """
        let event = SSEEvent(type: "content_block_delta", data: json)
        let result = AnthropicEventParser.parse(event: event)

        if case .toolUseInputDelta(let partial) = result {
            XCTAssertTrue(partial.contains("command"))
        } else {
            XCTFail("Expected toolUseInputDelta")
        }
    }

    func testParseMessageDeltaWithStopReason() {
        let json = """
        {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":42}}
        """
        let event = SSEEvent(type: "message_delta", data: json)
        let result = AnthropicEventParser.parse(event: event)

        // message_delta yields usage first (the function returns the first parsed item)
        if case .usage(let usage) = result {
            XCTAssertEqual(usage.outputTokens, 42)
        } else if case .messageStop(let reason) = result {
            XCTAssertEqual(reason, .endTurn)
        } else {
            XCTFail("Expected usage or messageStop")
        }
    }

    func testParsePingReturnsNil() {
        let event = SSEEvent(type: "ping", data: "{}")
        XCTAssertNil(AnthropicEventParser.parse(event: event))
    }

    func testParseContentBlockStopReturnsNil() {
        let event = SSEEvent(type: "content_block_stop", data: "{\"type\":\"content_block_stop\",\"index\":0}")
        XCTAssertNil(AnthropicEventParser.parse(event: event))
    }

    func testParseError() {
        let json = """
        {"type":"error","error":{"type":"overloaded_error","message":"API is overloaded"}}
        """
        let event = SSEEvent(type: "error", data: json)
        let result = AnthropicEventParser.parse(event: event)

        if case .error(let err) = result {
            XCTAssertTrue(err.description.contains("overloaded"))
        } else {
            XCTFail("Expected error event")
        }
    }

    // MARK: - OpenAI Event Parser

    func testOpenAITextDelta() {
        let json = """
        {"id":"chatcmpl-1","object":"chat.completion.chunk","model":"gpt-4","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}
        """
        let event = SSEEvent(type: "message", data: json)
        let result = OpenAIEventParser.parse(event: event)

        if case .textDelta(let text) = result {
            XCTAssertEqual(text, "Hi")
        } else {
            XCTFail("Expected textDelta")
        }
    }

    func testOpenAIFinishReason() {
        let json = """
        {"id":"chatcmpl-1","object":"chat.completion.chunk","model":"gpt-4","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
        """
        let event = SSEEvent(type: "message", data: json)
        let result = OpenAIEventParser.parse(event: event)

        if case .messageStop(let reason) = result {
            XCTAssertEqual(reason, .endTurn)
        } else {
            XCTFail("Expected messageStop")
        }
    }

    func testOpenAIDoneSentinel() {
        let event = SSEEvent(type: "message", data: "[DONE]")
        XCTAssertNil(OpenAIEventParser.parse(event: event))
    }
}
