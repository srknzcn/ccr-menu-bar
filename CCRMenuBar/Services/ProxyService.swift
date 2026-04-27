import Foundation
import Network

// MARK: - HTTP Request Model

struct ProxyHTTPRequest {
    var method: String
    var path: String
    var httpVersion: String
    var headers: [(String, String)]
    var body: Data?

    var contentLength: Int? {
        headers.first(where: { $0.0.lowercased() == "content-length" })
            .flatMap { Int($0.1) }
    }

    func headerValue(_ name: String) -> String? {
        let value = headers.first(where: { $0.0.lowercased() == name.lowercased() })?.1
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }
}

// MARK: - ProxyService

@MainActor
class ProxyService: ObservableObject {
    @Published var isRunning = false
    @Published var currentPreset: String?  // filesystem-safe name, nil = default (global fallback)
    @Published var proxyPort: UInt16 = 3457
    @Published var errorMessage: String?

    // Per-session preset map: session token → filesystem-safe preset name
    private var sessionPresets: [String: String] = [:]

    private nonisolated(unsafe) var listener: NWListener?
    private let internalQueue = DispatchQueue(label: "com.ccr.proxy", qos: .userInitiated)

    private var ccrPort: Int { ConfigManager.shared.config?.PORT ?? 3456 }

    private nonisolated static var debugLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-code-router/ccm-debug.log")
    }

    func start() {
        let port = proxyPort
        internalQueue.async { [weak self] in
            guard let self else { return }
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
                self.listener = l

                l.stateUpdateHandler = { [weak self] state in
                    DispatchQueue.main.async {
                        switch state {
                        case .ready:
                            self?.isRunning = true
                            self?.errorMessage = nil
                        case .failed(let error):
                            self?.isRunning = false
                            self?.errorMessage = "Proxy failed: \(error.localizedDescription)"
                        case .cancelled:
                            self?.isRunning = false
                        default:
                            break
                        }
                    }
                }

                l.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }

                l.start(queue: self.internalQueue)
            } catch {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.errorMessage = "Failed to start proxy: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: internalQueue)
        receiveHTTPRequest(connection) { [weak self] request in
            guard let self, let request else {
                connection.cancel()
                return
            }

            if request.path.hasPrefix("/_api/") {
                self.handleControlAPI(request, connection: connection)
            } else {
                self.forwardToCCR(request, clientConnection: connection)
            }
        }
    }

    // MARK: - HTTP Request Parsing

    private nonisolated func receiveHTTPRequest(_ connection: NWConnection, completion: @escaping (ProxyHTTPRequest?) -> Void) {
        var buffer = Data()

        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data {
                    buffer.append(data)
                }

                if error != nil {
                    completion(nil)
                    return
                }

                let separator = Data("\r\n\r\n".utf8)
                if let range = buffer.range(of: separator) {
                    let headerData = buffer[buffer.startIndex..<range.lowerBound]
                    let bodyStart = buffer[range.upperBound...]

                    guard let request = self.parseHTTPHeaders(headerData) else {
                        completion(nil)
                        return
                    }

                    let contentLength = request.contentLength ?? 0
                    if contentLength == 0 {
                        completion(request)
                    } else if bodyStart.count >= contentLength {
                        var req = request
                        req.body = Data(bodyStart.prefix(contentLength))
                        completion(req)
                    } else {
                        // Need more body data
                        var bodyBuffer = Data(bodyStart)
                        self.readBody(connection, buffer: &bodyBuffer, needed: contentLength, request: request, completion: completion)
                    }
                } else if isComplete {
                    completion(nil)
                } else {
                    readMore()
                }
            }
        }

        readMore()
    }

    private nonisolated func readBody(_ connection: NWConnection, buffer: inout Data, needed: Int, request: ProxyHTTPRequest, completion: @escaping (ProxyHTTPRequest?) -> Void) {
        var bodyBuffer = buffer
        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data {
                    bodyBuffer.append(data)
                }
                if bodyBuffer.count >= needed {
                    var req = request
                    req.body = Data(bodyBuffer.prefix(needed))
                    completion(req)
                } else if isComplete || error != nil {
                    var req = request
                    req.body = bodyBuffer
                    completion(req)
                } else {
                    readMore()
                }
            }
        }
        readMore()
    }

    private nonisolated func parseHTTPHeaders(_ data: Data) -> ProxyHTTPRequest? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        let lines = str.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])
        let httpVersion = parts.count > 2 ? String(parts[2]) : "HTTP/1.1"

        var headers: [(String, String)] = []
        for line in lines.dropFirst() {
            guard !line.isEmpty else { break }
            if let colonIdx = line.firstIndex(of: ":") {
                let name = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers.append((name, value))
            }
        }

        return ProxyHTTPRequest(method: method, path: path, httpVersion: httpVersion, headers: headers, body: nil)
    }

    // MARK: - Control API

    private nonisolated func handleControlAPI(_ request: ProxyHTTPRequest, connection: NWConnection) {
        let responseData: Data

        switch (request.method, request.path) {
        case ("GET", "/_api/current"):
            responseData = handleGetCurrent(request)

        case ("GET", "/_api/presets"):
            responseData = handleGetPresets()

        case ("POST", "/_api/switch"):
            responseData = handleSwitch(request)

        case ("OPTIONS", _):
            // CORS preflight
            let headers = [
                "Access-Control-Allow-Origin: *",
                "Access-Control-Allow-Methods: GET, POST, OPTIONS",
                "Access-Control-Allow-Headers: Content-Type",
            ].joined(separator: "\r\n")
            let response = "HTTP/1.1 204 No Content\r\n\(headers)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return

        default:
            responseData = buildJSONResponse(status: 404, json: #"{"ok":false,"error":"Not found"}"#)
        }

        connection.send(content: responseData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated func handleGetCurrent(_ request: ProxyHTTPRequest) -> Data {
        // Session-aware: check X-CCR-Session header first
        let sessionToken = request.headerValue("X-CCR-Session")
        let preset: String?
        if let token = sessionToken {
            preset = DispatchQueue.main.sync { self.sessionPresets[token] }
        } else {
            preset = DispatchQueue.main.sync { self.currentPreset }
        }
        if let preset {
            let displayName = DispatchQueue.main.sync {
                PresetManager.shared.displayName(for: preset) ?? preset
            }
            return buildJSONResponse(status: 200, json: #"{"preset":"\#(escapeJSON(displayName))","presetId":"\#(escapeJSON(preset))"}"#)
        } else {
            return buildJSONResponse(status: 200, json: #"{"preset":null,"presetId":null}"#)
        }
    }

    private nonisolated func handleGetPresets() -> Data {
        let presets = DispatchQueue.main.sync { PresetManager.shared.presets }
        let nameMap = DispatchQueue.main.sync { PresetManager.shared.presetNameMap }
        let current = DispatchQueue.main.sync { self.currentPreset }

        var items: [String] = []
        for preset in presets {
            let fsName = nameMap[preset.name] ?? preset.name
            items.append(#"{"name":"\#(escapeJSON(preset.name))","id":"\#(escapeJSON(fsName))"}"#)
        }
        let currentStr = current.map { #""\#(escapeJSON($0))""# } ?? "null"
        let json = #"{"presets":[\#(items.joined(separator: ","))],"current":\#(currentStr)}"#
        return buildJSONResponse(status: 200, json: json)
    }

    private nonisolated func handleSwitch(_ request: ProxyHTTPRequest) -> Data {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let presetName = json["preset"] as? String else {
            return buildJSONResponse(status: 400, json: #"{"ok":false,"error":"Missing 'preset' in body"}"#)
        }

        let rawSessionToken = json["session"] as? String
        let trimmedSessionToken = rawSessionToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionToken = trimmedSessionToken?.isEmpty == false ? trimmedSessionToken : nil
        Self.appendDebug("switch preset=\(presetName) rawSession=\(rawSessionToken ?? "nil") resolvedSession=\(sessionToken ?? "nil")")

        if presetName.isEmpty || presetName.lowercased() == "default" {
            if let token = sessionToken {
                _ = DispatchQueue.main.sync { self.sessionPresets.removeValue(forKey: token) }
            } else {
                DispatchQueue.main.sync { self.currentPreset = nil }
            }
            return buildJSONResponse(status: 200, json: #"{"ok":true,"preset":null,"message":"Switched to default config"}"#)
        }

        // Look up by display name or filesystem name
        let nameMap = DispatchQueue.main.sync { PresetManager.shared.presetNameMap }
        let presets = DispatchQueue.main.sync { PresetManager.shared.presets }

        func applyPreset(_ fsName: String) {
            if let token = sessionToken {
                DispatchQueue.main.sync { self.sessionPresets[token] = fsName }
            } else {
                DispatchQueue.main.sync { self.currentPreset = fsName }
            }
        }

        // Try filesystem name first
        if nameMap.values.contains(presetName) {
            applyPreset(presetName)
            let displayName = nameMap.first(where: { $0.value == presetName })?.key ?? presetName
            return buildJSONResponse(status: 200, json: #"{"ok":true,"preset":"\#(escapeJSON(displayName))","presetId":"\#(escapeJSON(presetName))"}"#)
        }

        // Try display name
        if let fsName = nameMap[presetName] {
            applyPreset(fsName)
            return buildJSONResponse(status: 200, json: #"{"ok":true,"preset":"\#(escapeJSON(presetName))","presetId":"\#(escapeJSON(fsName))"}"#)
        }

        // Try case-insensitive match on display name
        if let match = presets.first(where: { $0.name.lowercased() == presetName.lowercased() }) {
            let fsName = nameMap[match.name] ?? match.name
            applyPreset(fsName)
            return buildJSONResponse(status: 200, json: #"{"ok":true,"preset":"\#(escapeJSON(match.name))","presetId":"\#(escapeJSON(fsName))"}"#)
        }

        // Try case-insensitive match on filesystem name
        if let match = nameMap.values.first(where: { $0.lowercased() == presetName.lowercased() }) {
            applyPreset(match)
            let displayName = nameMap.first(where: { $0.value == match })?.key ?? match
            return buildJSONResponse(status: 200, json: #"{"ok":true,"preset":"\#(escapeJSON(displayName))","presetId":"\#(escapeJSON(match))"}"#)
        }

        return buildJSONResponse(status: 404, json: #"{"ok":false,"error":"Preset '\#(escapeJSON(presetName))' not found"}"#)
    }

    // MARK: - Proxy Forwarding

    private nonisolated func forwardToCCR(_ request: ProxyHTTPRequest, clientConnection: NWConnection) {
        let ccrPort = DispatchQueue.main.sync { self.ccrPort }

        // Resolve session token and actual path
        // Session-based: /s/{token}/v1/messages  → extract token, strip prefix
        // Global fallback: /v1/messages
        var targetPath: String
        var preset: String?

        let path = request.path
        if path.hasPrefix("/s/") {
            let withoutPrefix = String(path.dropFirst(3))  // "{token}/v1/messages"
            if let slashIdx = withoutPrefix.firstIndex(of: "/") {
                let token = String(withoutPrefix[withoutPrefix.startIndex..<slashIdx])
                targetPath = String(withoutPrefix[slashIdx...])  // "/v1/messages"
                preset = DispatchQueue.main.sync { self.sessionPresets[token] }
            } else {
                targetPath = "/"
            }
        } else {
            targetPath = path
            preset = DispatchQueue.main.sync { self.currentPreset }
        }

        // Build upstream URL
        if let preset {
            targetPath = "/preset/\(preset)\(targetPath)"
        }
        let requestModel = Self.modelFromJSONBody(request.body) ?? "nil"
        let sessionTrace = preset.map { "preset=\($0)" } ?? "preset=nil"
        Self.appendDebug("forward path=\(request.path) \(sessionTrace) target=\(targetPath) model=\(requestModel)")

        guard let url = URL(string: "http://127.0.0.1:\(ccrPort)\(targetPath)") else {
            let errorResponse = buildHTTPResponse(status: 502, statusText: "Bad Gateway",
                                                   headers: [("Content-Type", "application/json"), ("Connection", "close")],
                                                   body: Data(#"{"error":"Invalid upstream URL"}"#.utf8))
            clientConnection.send(content: errorResponse, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                clientConnection.cancel()
            })
            return
        }

        let selectedRoute = selectedRouteValue(for: preset, body: request.body)
        let usesOpus47 = selectedRoute?.lowercased().contains("anthropic,claude-opus-4-7") == true
        let usesOpenAIProvider = selectedRoute.map(Self.routeUsesOpenAIProvider) ?? false
        let sanitizedBody = Self.sanitizedJSONBodyForCCR(
            request.body,
            useAdaptiveThinking: usesOpus47,
            sanitizeForOpenAIProvider: usesOpenAIProvider,
            forceModel: usesOpenAIProvider ? selectedRoute : nil
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = sanitizedBody
        urlRequest.timeoutInterval = 600  // 10 min, match CCR timeout

        // Copy headers, skip hop-by-hop
        let hopByHop: Set<String> = ["connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
                                      "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length"]
        for (name, value) in request.headers {
            if !hopByHop.contains(name.lowercased()) {
                let lowerName = name.lowercased()
                let headerValue: String
                if usesOpenAIProvider && lowerName == "anthropic-beta" {
                    headerValue = ""
                } else if usesOpus47 && lowerName == "anthropic-beta" {
                    headerValue = Self.removingInterleavedThinkingBeta(from: value)
                } else {
                    headerValue = value
                }
                if !headerValue.isEmpty {
                    urlRequest.setValue(headerValue, forHTTPHeaderField: name)
                }
            }
        }
        if let sanitizedBody {
            urlRequest.setValue("\(sanitizedBody.count)", forHTTPHeaderField: "Content-Length")
        }
        urlRequest.setValue("127.0.0.1:\(ccrPort)", forHTTPHeaderField: "Host")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 600
        if usesOpenAIProvider {
            let delegate = OpenAIToAnthropicProxyDelegate(clientConnection: clientConnection)
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: urlRequest)
            delegate.session = session
            task.resume()
        } else {
            let delegate = StreamingProxyDelegate(clientConnection: clientConnection)
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: urlRequest)
            delegate.session = session
            task.resume()
        }
    }

    // MARK: - HTTP Response Builders

    private nonisolated func buildJSONResponse(status: Int, json: String) -> Data {
        let body = Data(json.utf8)
        return buildHTTPResponse(
            status: status,
            statusText: httpStatusText(status),
            headers: [
                ("Content-Type", "application/json"),
                ("Access-Control-Allow-Origin", "*"),
                ("Connection", "close"),
            ],
            body: body
        )
    }

    private nonisolated func buildHTTPResponse(status: Int, statusText: String, headers: [(String, String)], body: Data) -> Data {
        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        for (name, value) in headers {
            response += "\(name): \(value)\r\n"
        }
        response += "\r\n"
        var data = Data(response.utf8)
        data.append(body)
        return data
    }

    private nonisolated func httpStatusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 502: return "Bad Gateway"
        default: return "Unknown"
        }
    }

    private nonisolated func escapeJSON(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
           .replacingOccurrences(of: "\n", with: "\\n")
           .replacingOccurrences(of: "\r", with: "\\r")
           .replacingOccurrences(of: "\t", with: "\\t")
    }

    private nonisolated func selectedRouteValue(for preset: String?, body: Data?) -> String? {
        guard let preset else { return nil }
        let router: RouterConfig? = DispatchQueue.main.sync {
            let presetManager = PresetManager.shared
            let displayName = presetManager.displayName(for: preset) ?? preset
            return presetManager.presets.first(where: {
                $0.name == displayName || presetManager.fileSystemName(for: $0.name) == preset
            })?.router
        }
        guard let router else { return nil }
        if Self.bodyRequestsThinking(body), let thinkRoute = router.think {
            return thinkRoute
        }
        return router.default
    }

    private nonisolated static func routeUsesOpenAIProvider(_ route: String) -> Bool {
        route.split(separator: ",", maxSplits: 1).first?.lowercased() == "openai"
    }

    private nonisolated static func bodyRequestsThinking(_ body: Data?) -> Bool {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let thinking = json["thinking"] as? [String: Any],
              let type = thinking["type"] as? String else {
            return false
        }
        return type.lowercased() != "disabled"
    }

    nonisolated static func sanitizedJSONBodyForCCR(
        _ body: Data?,
        useAdaptiveThinking: Bool = false,
        sanitizeForOpenAIProvider: Bool = false,
        forceModel: String? = nil
    ) -> Data? {
        guard let body,
              var json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return body
        }

        var changed = false
        if let model = json["model"] as? String {
            let cleaned = stripTerminalControlSequences(from: model)
            if cleaned != model {
                json["model"] = cleaned
                changed = true
            }
        }

        if useAdaptiveThinking,
           var thinking = json["thinking"] as? [String: Any],
           (thinking["type"] as? String)?.lowercased() == "enabled" {
            let effort = effortForAdaptiveThinking(budgetTokens: thinking["budget_tokens"])
            thinking["type"] = "adaptive"
            thinking.removeValue(forKey: "budget_tokens")
            json["thinking"] = thinking

            var outputConfig = json["output_config"] as? [String: Any] ?? [:]
            if outputConfig["effort"] == nil {
                outputConfig["effort"] = effort
            }
            json["output_config"] = outputConfig

            if var betas = json["anthropic_beta"] as? [String] {
                betas.removeAll { $0 == "interleaved-thinking-2025-05-14" }
                if betas.isEmpty {
                    json.removeValue(forKey: "anthropic_beta")
                } else {
                    json["anthropic_beta"] = betas
                }
            }
            changed = true
        }

        if sanitizeForOpenAIProvider {
            if let forceModel {
                json["model"] = forceModel
                changed = true
            }
            for key in ["context_management", "output_config", "thinking", "anthropic_beta", "metadata"] {
                if json[key] != nil {
                    json.removeValue(forKey: key)
                    changed = true
                }
            }
        }

        if sanitizeForOpenAIProvider, json["stream"] as? Bool == true {
            json["stream"] = false
            changed = true
        }

        if sanitizeForOpenAIProvider, let system = json.removeValue(forKey: "system") {
            if let systemContent = openAISystemContent(from: system), !systemContent.isEmpty {
                var messages = json["messages"] as? [[String: Any]] ?? []
                let systemMessage: [String: Any] = ["role": "system", "content": systemContent]
                if messages.first?["role"] as? String == "system" {
                    messages[0] = systemMessage
                } else {
                    messages.insert(systemMessage, at: 0)
                }
                json["messages"] = messages
            }
            changed = true
        }

        if sanitizeForOpenAIProvider, let messages = json["messages"] as? [[String: Any]] {
            json["messages"] = openAIMessages(fromAnthropicMessages: messages)
            changed = true
        }

        if sanitizeForOpenAIProvider, let tools = json["tools"] as? [[String: Any]] {
            let requiredToolNames = requiredOpenAIToolNames(from: json["messages"] as? [[String: Any]] ?? [])
            json["tools"] = limitedOpenAITools(from: tools, requiredNames: requiredToolNames)
            changed = true
        }

        if sanitizeForOpenAIProvider, let toolChoice = json["tool_choice"] as? [String: Any] {
            json["tool_choice"] = openAIToolChoice(from: toolChoice)
            changed = true
        }

        if sanitizeForOpenAIProvider, let maxTokens = json.removeValue(forKey: "max_tokens") {
            json["max_completion_tokens"] = maxTokens
            changed = true
        }

        guard changed,
              JSONSerialization.isValidJSONObject(json),
              let sanitized = try? JSONSerialization.data(withJSONObject: json) else {
            return body
        }
        return sanitized
    }

    nonisolated static func stripTerminalControlSequences(from value: String) -> String {
        var cleaned = value.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\[[0-?]*[ -/]*m\]?$"#,
            with: "",
            options: .regularExpression
        )
        cleaned.removeAll { scalar in
            scalar.unicodeScalars.allSatisfy { $0.value < 0x20 || $0.value == 0x7F }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func openAISystemContent(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let blocks = value as? [[String: Any]] {
            return blocks.compactMap { block in
                block["text"] as? String
            }.joined(separator: "\n")
        }
        return nil
    }

    private nonisolated static func openAIMessages(fromAnthropicMessages messages: [[String: Any]]) -> [[String: Any]] {
        var output: [[String: Any]] = []

        for message in messages {
            let role = message["role"] as? String
            guard let contentBlocks = message["content"] as? [[String: Any]] else {
                output.append(message)
                continue
            }

            if role == "assistant" {
                var textParts: [String] = []
                var toolCalls: [[String: Any]] = []
                for block in contentBlocks {
                    switch block["type"] as? String {
                    case "text":
                        if let text = block["text"] as? String, !text.isEmpty {
                            textParts.append(text)
                        }
                    case "tool_use":
                        guard let id = block["id"] as? String,
                              let name = block["name"] as? String else { continue }
                        let input = block["input"] ?? [:]
                        let argumentData = try? JSONSerialization.data(withJSONObject: input)
                        let arguments = argumentData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        toolCalls.append([
                            "id": id,
                            "type": "function",
                            "function": [
                                "name": name,
                                "arguments": arguments,
                            ],
                        ])
                    default:
                        continue
                    }
                }
                var converted: [String: Any] = ["role": "assistant"]
                converted["content"] = textParts.isEmpty ? NSNull() : textParts.joined(separator: "\n")
                if !toolCalls.isEmpty {
                    converted["tool_calls"] = toolCalls
                }
                output.append(converted)
                continue
            }

            if role == "user" {
                var userTextBlocks: [[String: Any]] = []
                for block in contentBlocks {
                    switch block["type"] as? String {
                    case "tool_result":
                        let toolUseId = block["tool_use_id"] as? String ?? ""
                        let content = openAIToolResultContent(from: block["content"])
                        output.append([
                            "role": "tool",
                            "tool_call_id": toolUseId,
                            "content": content,
                        ])
                    case "text":
                        var converted = block
                        converted.removeValue(forKey: "cache_control")
                        userTextBlocks.append(converted)
                    case "image":
                        if let converted = openAIImageBlock(fromAnthropicImageBlock: block) {
                            userTextBlocks.append(converted)
                        }
                    default:
                        continue
                    }
                }
                if !userTextBlocks.isEmpty {
                    output.append(["role": "user", "content": userTextBlocks])
                }
                continue
            }

            output.append(message)
        }

        return output
    }

    private nonisolated static func openAIToolResultContent(from value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    private nonisolated static func openAIImageBlock(fromAnthropicImageBlock block: [String: Any]) -> [String: Any]? {
        guard let source = block["source"] as? [String: Any],
              let mediaType = source["media_type"] as? String else {
            return nil
        }
        if let data = source["data"] as? String {
            return [
                "type": "image_url",
                "image_url": ["url": "data:\(mediaType);base64,\(data)"],
            ]
        }
        if let url = source["url"] as? String {
            return [
                "type": "image_url",
                "image_url": ["url": url],
            ]
        }
        return nil
    }

    private nonisolated static func openAITool(from tool: [String: Any]) -> [String: Any] {
        if tool["type"] as? String == "function" {
            return tool
        }
        guard let name = tool["name"] as? String else {
            return tool
        }
        var function: [String: Any] = ["name": name]
        if let description = tool["description"] as? String {
            function["description"] = description
        }
        if let inputSchema = tool["input_schema"] {
            function["parameters"] = inputSchema
        }
        return ["type": "function", "function": function]
    }

    private nonisolated static func limitedOpenAITools(from tools: [[String: Any]], requiredNames: Set<String>, limit: Int = 128) -> [[String: Any]] {
        let converted = tools.map(openAITool(from:))
        guard converted.count > limit else { return converted }

        var selected: [[String: Any]] = []
        var selectedNames = Set<String>()

        for tool in converted {
            guard let name = openAIToolName(tool), requiredNames.contains(name), !selectedNames.contains(name) else {
                continue
            }
            selected.append(tool)
            selectedNames.insert(name)
            if selected.count == limit { return selected }
        }

        for tool in converted {
            guard let name = openAIToolName(tool), !selectedNames.contains(name) else {
                continue
            }
            selected.append(tool)
            selectedNames.insert(name)
            if selected.count == limit { return selected }
        }

        return Array(converted.prefix(limit))
    }

    private nonisolated static func requiredOpenAIToolNames(from messages: [[String: Any]]) -> Set<String> {
        var names = Set<String>()
        for message in messages {
            guard let toolCalls = message["tool_calls"] as? [[String: Any]] else {
                continue
            }
            for toolCall in toolCalls {
                if let function = toolCall["function"] as? [String: Any],
                   let name = function["name"] as? String {
                    names.insert(name)
                }
            }
        }
        return names
    }

    private nonisolated static func openAIToolName(_ tool: [String: Any]) -> String? {
        guard let function = tool["function"] as? [String: Any] else {
            return nil
        }
        return function["name"] as? String
    }

    private nonisolated static func openAIToolChoice(from toolChoice: [String: Any]) -> Any {
        guard let type = toolChoice["type"] as? String else {
            return toolChoice
        }
        switch type {
        case "auto", "none", "required":
            return type
        case "any":
            return "required"
        case "tool":
            if let name = toolChoice["name"] as? String {
                return ["type": "function", "function": ["name": name]]
            }
            return "required"
        default:
            return toolChoice
        }
    }

    nonisolated static func removingInterleavedThinkingBeta(from value: String) -> String {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "interleaved-thinking-2025-05-14" }
            .joined(separator: ",")
    }

    private nonisolated static func effortForAdaptiveThinking(budgetTokens: Any?) -> String {
        let budget: Int?
        if let intValue = budgetTokens as? Int {
            budget = intValue
        } else if let doubleValue = budgetTokens as? Double {
            budget = Int(doubleValue)
        } else if let stringValue = budgetTokens as? String {
            budget = Int(stringValue)
        } else {
            budget = nil
        }

        guard let budget else { return "high" }
        if budget >= 16_384 { return "xhigh" }
        if budget >= 8_192 { return "high" }
        if budget >= 4_096 { return "medium" }
        return "low"
    }

    private nonisolated static func modelFromJSONBody(_ body: Data?) -> String? {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return json["model"] as? String
    }

    nonisolated static func openAIChatResponseToAnthropicSSE(_ body: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return nil
        }

        let message = firstChoice["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        let toolCalls = message?["tool_calls"] as? [[String: Any]] ?? []
        let model = json["model"] as? String ?? "openai"
        let responseId = json["id"] as? String ?? "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let finishReason = firstChoice["finish_reason"] as? String
        let stopReason = openAIStopReasonToAnthropic(finishReason)
        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0

        let messageObject: [String: Any] = [
            "id": responseId,
            "type": "message",
            "role": "assistant",
            "model": model,
            "content": [],
            "stop_reason": NSNull(),
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": inputTokens,
                "output_tokens": 0,
            ],
        ]
        let messageDelta: [String: Any] = [
            "type": "message_delta",
            "delta": [
                "stop_reason": stopReason,
                "stop_sequence": NSNull(),
            ],
            "usage": [
                "output_tokens": outputTokens,
            ],
        ]

        var events: [(String, [String: Any])] = [
            ("message_start", ["type": "message_start", "message": messageObject]),
        ]
        var blockIndex = 0
        if !text.isEmpty {
            events.append(("content_block_start", [
                "type": "content_block_start",
                "index": blockIndex,
                "content_block": ["type": "text", "text": ""],
            ]))
            events.append(("content_block_delta", [
                "type": "content_block_delta",
                "index": blockIndex,
                "delta": ["type": "text_delta", "text": text],
            ]))
            events.append(("content_block_stop", [
                "type": "content_block_stop",
                "index": blockIndex,
            ]))
            blockIndex += 1
        }

        for toolCall in toolCalls {
            guard let function = toolCall["function"] as? [String: Any],
                  let name = function["name"] as? String else {
                continue
            }
            let id = toolCall["id"] as? String ?? "toolu_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            let arguments = function["arguments"] as? String ?? "{}"
            events.append(("content_block_start", [
                "type": "content_block_start",
                "index": blockIndex,
                "content_block": [
                    "type": "tool_use",
                    "id": id,
                    "name": name,
                    "input": [:],
                ],
            ]))
            if !arguments.isEmpty {
                events.append(("content_block_delta", [
                    "type": "content_block_delta",
                    "index": blockIndex,
                    "delta": [
                        "type": "input_json_delta",
                        "partial_json": arguments,
                    ],
                ]))
            }
            events.append(("content_block_stop", [
                "type": "content_block_stop",
                "index": blockIndex,
            ]))
            blockIndex += 1
        }
        events.append(("message_delta", messageDelta))
        events.append(("message_stop", ["type": "message_stop"]))

        var output = Data()
        for (event, payload) in events {
            guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let payloadString = String(data: payloadData, encoding: .utf8) else {
                return nil
            }
            output.append(Data("event: \(event)\n".utf8))
            output.append(Data("data: \(payloadString)\n\n".utf8))
        }
        return output
    }

    private nonisolated static func openAIStopReasonToAnthropic(_ reason: String?) -> String {
        switch reason {
        case "length":
            return "max_tokens"
        case "tool_calls":
            return "tool_use"
        case "content_filter":
            return "stop_sequence"
        default:
            return "end_turn"
        }
    }

    nonisolated static func appendDebug(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let output = "[\(timestamp)] \(line)\n"
        let url = debugLogURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(output.utf8))
            try? handle.close()
        } else {
            try? output.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Streaming Proxy Delegate

private class StreamingProxyDelegate: NSObject, URLSessionDataDelegate {
    let clientConnection: NWConnection
    var headersSent = false
    var session: URLSession?

    init(clientConnection: NWConnection) {
        self.clientConnection = clientConnection
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }

        // Build and send HTTP response headers to client
        var headerStr = "HTTP/1.1 \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))\r\n"

        // Forward response headers, skip hop-by-hop and content-length (we stream without it)
        let skipHeaders: Set<String> = ["connection", "keep-alive", "transfer-encoding", "content-length"]
        for (key, value) in httpResponse.allHeaderFields {
            let name = String(describing: key)
            if !skipHeaders.contains(name.lowercased()) {
                headerStr += "\(name): \(value)\r\n"
            }
        }
        headerStr += "Connection: close\r\n"
        headerStr += "\r\n"

        let headerData = Data(headerStr.utf8)
        clientConnection.send(content: headerData, completion: .contentProcessed { _ in })
        headersSent = true
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Forward each chunk immediately for SSE streaming
        clientConnection.send(content: data, completion: .contentProcessed { _ in })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if !headersSent {
            // CCR not reachable — send error response
            let body = Data(#"{"error":"CCR server not reachable","type":"proxy_error"}"#.utf8)
            var response = "HTTP/1.1 502 Bad Gateway\r\n"
            response += "Content-Type: application/json\r\n"
            response += "Content-Length: \(body.count)\r\n"
            response += "Connection: close\r\n"
            response += "\r\n"
            var data = Data(response.utf8)
            data.append(body)
            clientConnection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.clientConnection.cancel()
                self?.session?.invalidateAndCancel()
            })
        } else {
            clientConnection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.clientConnection.cancel()
                self?.session?.finishTasksAndInvalidate()
            })
        }
    }
}

private class OpenAIToAnthropicProxyDelegate: NSObject, URLSessionDataDelegate {
    let clientConnection: NWConnection
    var session: URLSession?
    private var response: HTTPURLResponse?
    private var body = Data()

    init(clientConnection: NWConnection) {
        self.clientConnection = clientConnection
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        body.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            session.finishTasksAndInvalidate()
        }

        if error != nil {
            sendJSONError(status: 502, json: #"{"error":"CCR server not reachable","type":"proxy_error"}"#)
            return
        }

        let status = response?.statusCode ?? 502
        if status < 200 || status >= 300 {
            sendRaw(status: status, contentType: "application/json", data: body)
            return
        }

        guard let converted = ProxyService.openAIChatResponseToAnthropicSSE(body) else {
            sendJSONError(status: 502, json: #"{"error":"OpenAI response could not be converted to Anthropic SSE","type":"proxy_error"}"#)
            return
        }

        sendRaw(status: 200, contentType: "text/event-stream", data: converted)
    }

    private func sendJSONError(status: Int, json: String) {
        sendRaw(status: status, contentType: "application/json", data: Data(json.utf8))
    }

    private func sendRaw(status: Int, contentType: String, data: Data) {
        var header = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var output = Data(header.utf8)
        output.append(data)
        clientConnection.send(content: output, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.clientConnection.cancel()
        })
    }
}
