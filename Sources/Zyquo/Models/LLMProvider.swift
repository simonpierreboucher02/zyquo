import Foundation

// MARK: - Provider Protocol

public protocol LLMProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var supportedModels: [ModelDescriptor] { get }

    func send(
        request: LLMRequest,
        cancellation: Task<Void, Never>?
    ) -> AsyncThrowingStream<LLMEvent, Error>
}

// MARK: - Request

// MARK: - Thinking Configuration

public enum ThinkingConfig: Sendable, Equatable {
    case disabled
    case adaptive
    case enabled(budgetTokens: Int)
}

public struct LLMRequest: Sendable {
    public let model: String
    public let systemPrompt: String?
    public let messages: [LLMMessage]
    public let tools: [ToolSchema]
    public let toolChoice: ToolChoice
    public let maxTokens: Int
    public let temperature: Double?
    public let thinking: ThinkingConfig
    public let enableCaching: Bool
    public let metadata: [String: String]

    public init(
        model: String,
        systemPrompt: String? = nil,
        messages: [LLMMessage],
        tools: [ToolSchema] = [],
        toolChoice: ToolChoice = .auto,
        maxTokens: Int = 4096,
        temperature: Double? = nil,
        thinking: ThinkingConfig = .disabled,
        enableCaching: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.thinking = thinking
        self.enableCaching = enableCaching
        self.metadata = metadata
    }
}

// MARK: - Message

public struct LLMMessage: Sendable {
    public let role: Role
    public let content: [ContentBlock]

    public enum Role: String, Sendable, Codable {
        case user
        case assistant
        case tool
    }

    public init(role: Role, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String) -> LLMMessage {
        LLMMessage(role: .user, content: [.text(text)])
    }

    public static func assistant(_ text: String) -> LLMMessage {
        LLMMessage(role: .assistant, content: [.text(text)])
    }
}

// MARK: - Content Blocks

public enum ContentBlock: Sendable {
    case text(String)
    case thinking(text: String)
    case toolUse(id: String, name: String, input: [String: JSONValue])
    case toolResult(toolUseId: String, content: String, isError: Bool)
    case image(mediaType: String, data: Data)
}

public enum JSONValue: Sendable, Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s) }
        else if let n = try? container.decode(Double.self) { self = .number(n) }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if container.decodeNil() { self = .null }
        else if let a = try? container.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? container.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var asBool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
}

// MARK: - Events

public enum LLMEvent: Sendable {
    case messageStart(MessageMeta)
    case textDelta(String)
    case thinkingDelta(String)
    case toolUseStart(ToolUseMeta)
    case toolUseInputDelta(String)
    case toolUseEnd
    case usage(TokenUsage)
    case messageStop(StopReason)
    case error(ProviderError)
}

public struct MessageMeta: Sendable {
    public let id: String
    public let model: String

    public init(id: String, model: String) {
        self.id = id
        self.model = model
    }
}

public struct ToolUseMeta: Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct TokenUsage: Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }
}

public enum StopReason: String, Sendable {
    case endTurn = "end_turn"
    case toolUse = "tool_use"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
}

// MARK: - Tool Schema

public struct ToolSchema: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: [String: JSONValue]

    public init(name: String, description: String, inputSchema: [String: JSONValue]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

// MARK: - Tool Choice

public enum ToolChoice: Sendable {
    case auto
    case any
    case none
    case specific(name: String)
}

// MARK: - Model Descriptor

// MARK: - Thinking Capability

public enum ThinkingCapability: Sendable, Equatable {
    case none
    case adaptive
    case extended
}

public struct ModelDescriptor: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let contextWindow: Int
    public let maxOutputTokens: Int
    public let inputPricePerMToken: Double
    public let outputPricePerMToken: Double
    public let supportsTools: Bool
    public let supportsStreaming: Bool
    public let supportsThinking: ThinkingCapability

    public init(
        id: String,
        displayName: String,
        contextWindow: Int,
        maxOutputTokens: Int,
        inputPricePerMToken: Double,
        outputPricePerMToken: Double,
        supportsTools: Bool = true,
        supportsStreaming: Bool = true,
        supportsThinking: ThinkingCapability = .none
    ) {
        self.id = id
        self.displayName = displayName
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.inputPricePerMToken = inputPricePerMToken
        self.outputPricePerMToken = outputPricePerMToken
        self.supportsTools = supportsTools
        self.supportsStreaming = supportsStreaming
        self.supportsThinking = supportsThinking
    }
}

// MARK: - Keychain Constants

enum ProviderKeychain {
    static let service = "dev.zyquo.cli"
}
