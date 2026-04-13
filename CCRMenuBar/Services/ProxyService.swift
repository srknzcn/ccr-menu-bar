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
        headers.first(where: { $0.0.lowercased() == name.lowercased() })?.1
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

        let sessionToken = json["session"] as? String

        if presetName.isEmpty || presetName.lowercased() == "default" {
            if let token = sessionToken {
                DispatchQueue.main.async { self.sessionPresets.removeValue(forKey: token) }
            } else {
                DispatchQueue.main.async { self.currentPreset = nil }
            }
            return buildJSONResponse(status: 200, json: #"{"ok":true,"preset":null,"message":"Switched to default config"}"#)
        }

        // Look up by display name or filesystem name
        let nameMap = DispatchQueue.main.sync { PresetManager.shared.presetNameMap }
        let presets = DispatchQueue.main.sync { PresetManager.shared.presets }

        func applyPreset(_ fsName: String) {
            if let token = sessionToken {
                DispatchQueue.main.async { self.sessionPresets[token] = fsName }
            } else {
                DispatchQueue.main.async { self.currentPreset = fsName }
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

        guard let url = URL(string: "http://127.0.0.1:\(ccrPort)\(targetPath)") else {
            let errorResponse = buildHTTPResponse(status: 502, statusText: "Bad Gateway",
                                                   headers: [("Content-Type", "application/json"), ("Connection", "close")],
                                                   body: Data(#"{"error":"Invalid upstream URL"}"#.utf8))
            clientConnection.send(content: errorResponse, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                clientConnection.cancel()
            })
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = 600  // 10 min, match CCR timeout

        // Copy headers, skip hop-by-hop
        let hopByHop: Set<String> = ["connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
                                      "te", "trailers", "transfer-encoding", "upgrade", "host"]
        for (name, value) in request.headers {
            if !hopByHop.contains(name.lowercased()) {
                urlRequest.setValue(value, forHTTPHeaderField: name)
            }
        }
        urlRequest.setValue("127.0.0.1:\(ccrPort)", forHTTPHeaderField: "Host")

        // Create streaming delegate
        let delegate = StreamingProxyDelegate(clientConnection: clientConnection)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: urlRequest)
        delegate.session = session
        task.resume()
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
