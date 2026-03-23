//
//  KagiAPI.swift
//  Kagi Assistant
//

import Foundation

// MARK: - API Types

struct StreamChunk: Sendable {
    let header: String
    let data: String
    let done: Bool
}

struct KagiPromptRequest: Encodable {
    let focus: Focus
    let profile: Profile
    let threads: [ThreadMeta]

    struct Focus: Encodable {
        var thread_id: String?
        var message_id: String?
        var prompt: String
        var branch_id: String?
    }

    struct Profile: Encodable {
        var id: String?
        var internet_access: Bool = true
        var lens_id: String?
        var model: String = "gemini-3-1-flash-lite"
        var personalizations: Bool = false
    }

    struct ThreadMeta: Encodable {
        var tag_ids: [String] = []
        var saved: Bool = true
        var shared: Bool = false
    }
}

struct KagiThreadInfo: Decodable {
    let id: String?
    let title: String?
}

struct KagiLocationInfo: Decodable {
    let branch_id: String?
}

struct KagiTokensPayload: Decodable {
    let token: String?
    let tokens: String?
    let text: String?

    var content: String { text ?? token ?? tokens ?? "" }
}

struct KagiMessageDTO: Decodable {
    let id: String?
    let prompt: String?
    let reply: String?
    let documents: [KagiDocument]?
    let branch_list: [String]?
    let references_html: String?
    let md: String?
    let metadata: String?
    let state: String?
}

struct KagiDocument: Decodable {
    let id: String?
    let name: String?
    let mime: String?
    let data: String?
}

struct KagiThreadListWrapper: Sendable {
    let html: String?
    let has_more: Bool?
    let count: Int?

    /// Parse from raw JSON data, extracting the wrapper fields.
    static func parse(from jsonString: String) -> KagiThreadListWrapper? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return KagiThreadListWrapper(
            html: obj["html"] as? String,
            has_more: obj["has_more"] as? Bool,
            count: obj["count"] as? Int
        )
    }
}

struct KagiProfile: Decodable, Identifiable {
    let id: String?
    let model: String?
    let model_provider: String?
    let name: String?
    let model_name: String?
    let model_input_limit: Int?
    let internet_access: Bool?

    var stableId: String { id ?? model ?? name ?? UUID().uuidString }
}

struct KagiCitation: Sendable {
    let url: String
    let title: String
}

struct KagiThreadEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let excerpt: String
}

struct KagiSearchResult: Decodable {
    let thread_id: String
    let title: String
    let snippet: String?
}

// MARK: - HI payload

struct KagiHiPayload: Decodable {
    let trace: String?
}

// MARK: - API Client

// Restricts all connections to kagi.com only
private final class DomainRestrictedSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    private static let allowedHost = "kagi.com"

    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let host = challenge.protectionSpace.host.lowercased() as String?,
              host == Self.allowedHost || host.hasSuffix(".\(Self.allowedHost)") else {
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.performDefaultHandling, nil)
    }
}

actor KagiAPIClient {
    static let shared = KagiAPIClient()

    private static let allowedHost = "kagi.com"
    private let baseURL = URL(string: "https://kagi.com")!
    private var sessionToken: String?
    private let decoder = JSONDecoder()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config, delegate: DomainRestrictedSessionDelegate(), delegateQueue: nil)
    }

    private var defaultHeaders: [String: String] {
        [
            "origin": "https://kagi.com",
            "referer": "https://kagi.com/assistant",
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36",
            "cache-control": "no-cache",
        ]
    }

    // MARK: - Session Management

    func setSession(_ token: String) {
        // Handle both raw token and query-style "token=xxx"
        if token.contains("token=") {
            let components = token.components(separatedBy: "token=")
            if let extracted = components.last?.components(separatedBy: "&").first {
                sessionToken = extracted
            } else {
                sessionToken = token
            }
        } else {
            sessionToken = token
        }
    }

    func clearSession() {
        sessionToken = nil
    }

    func hasSession() -> Bool {
        sessionToken != nil
    }

    // MARK: - Auth

    func validateSession() async throws -> Bool {
        let url = baseURL.appendingPathComponent("settings/assistant")
        var request = try makeRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return false
        }

        let html = String(data: data, encoding: .utf8) ?? ""
        return html.contains("custom_instructions_input")
    }

    func fetchEmail() async throws -> String? {
        let url = baseURL.appendingPathComponent("settings/change_email")
        var request = try makeRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await session.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""

        // Parse _0_pass_field value
        if let range = html.range(of: "_0_pass_field") {
            let after = html[range.upperBound...]
            if let valueRange = after.range(of: "value=\""),
               let endQuote = after[valueRange.upperBound...].range(of: "\"") {
                return String(after[valueRange.upperBound..<endQuote.lowerBound])
            }
        }
        return nil
    }

    func logout() async throws -> Bool {
        let url = baseURL.appendingPathComponent("logout")
        var request = try makeRequest(url: url)
        request.httpMethod = "GET"

        let (_, response) = try await session.data(for: request)
        let success = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        if success { clearSession() }
        return success
    }

    // MARK: - Streaming Prompt

    func sendPrompt(
        prompt: String,
        threadId: String? = nil,
        branchId: String? = nil,
        model: String = "claude-3-5-sonnet",
        profileId: String? = nil,
        internetAccess: Bool = true
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let body = KagiPromptRequest(
            focus: .init(thread_id: threadId, prompt: prompt, branch_id: branchId),
            profile: .init(id: profileId, internet_access: internetAccess, model: model),
            threads: [.init()]
        )
        return streamRequest(path: "assistant/prompt", body: body)
    }

    func regenerateMessage(
        prompt: String,
        threadId: String?,
        messageId: String?,
        branchId: String?,
        model: String = "claude-3-5-sonnet",
        profileId: String? = nil
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let body = KagiPromptRequest(
            focus: .init(thread_id: threadId, message_id: messageId, prompt: prompt, branch_id: branchId),
            profile: .init(id: profileId, model: model),
            threads: [.init()]
        )
        return streamRequest(path: "assistant/message_regenerate", body: body)
    }

    // MARK: - Stop Generation

    func stopGeneration(traceId: String) async throws {
        let url = baseURL.appendingPathComponent("assistant/stop/\(traceId)")
        var request = try makeRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.kagi.stream", forHTTPHeaderField: "accept")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw KagiAPIError.requestFailed
        }
    }

    // MARK: - Threads

    func fetchThreadList() -> AsyncThrowingStream<StreamChunk, Error> {
        struct EmptyBody: Encodable {}
        return streamRequest(path: "assistant/thread_list", body: EmptyBody())
    }

    func fetchThread(threadId: String) async throws -> (title: String, messages: [KagiMessageDTO]) {
        let url = baseURL.appendingPathComponent("assistant/\(threadId)")
        var request = try makeRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await session.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""

        // Extract title
        var title = "Chat"
        if let titleStart = html.range(of: "<title>"),
           let titleEnd = html.range(of: "</title>") {
            let raw = String(html[titleStart.upperBound..<titleEnd.lowerBound])
            title = raw.replacingOccurrences(of: " - Kagi Assistant", with: "").trimmingCharacters(in: .whitespaces)
        }

        // Extract messages from #json-message-list
        // Find the element by id, then skip past any other attributes (e.g. hidden) to closing >
        var messages: [KagiMessageDTO] = []
        if let idRange = html.range(of: "id=\"json-message-list\""),
           let tagClose = html[idRange.upperBound...].range(of: ">"),
           let contentEnd = html[tagClose.upperBound...].range(of: "</") {
            var jsonStr = String(html[tagClose.upperBound..<contentEnd.lowerBound])
            jsonStr = decodeHTMLEntities(jsonStr)
            if let jsonData = jsonStr.data(using: .utf8) {
                messages = (try? decoder.decode([KagiMessageDTO].self, from: jsonData)) ?? []
            }
        }

        return (title, messages)
    }

    func deleteThread(threadId: String, title: String = ".") -> AsyncThrowingStream<StreamChunk, Error> {
        struct DeleteBody: Encodable {
            let threads: [ThreadRef]
            struct ThreadRef: Encodable {
                let id: String
                let title: String
                let saved: Bool
                let shared: Bool
                let tag_ids: [String]
            }
        }
        let body = DeleteBody(threads: [.init(id: threadId, title: title, saved: true, shared: false, tag_ids: [])])
        return streamRequest(path: "assistant/thread_delete", body: body)
    }

    func searchThreads(query: String) async throws -> [KagiSearchResult] {
        let url = baseURL.appendingPathComponent("assistant/search")
        var request = try makeRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        struct SearchBody: Encodable {
            let q: String
            let saved: String?
            let shared: String?
            let tag_id: String?
        }
        let body = SearchBody(q: query.uppercased(), saved: nil, shared: nil, tag_id: nil)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await session.data(for: request)
        return try decoder.decode([KagiSearchResult].self, from: data)
    }

    // MARK: - Profiles

    func fetchProfiles() -> AsyncThrowingStream<StreamChunk, Error> {
        struct EmptyBody: Encodable {}
        return streamRequest(path: "assistant/profile_list", body: EmptyBody())
    }

    // MARK: - Auto-save default

    func fetchAutoSave() async throws -> Bool {
        let url = baseURL.appendingPathComponent("assistant")
        var request = try makeRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await session.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""

        if let range = html.range(of: "window.AUTO_SAVE = ") {
            let after = html[range.upperBound...]
            if after.hasPrefix("true") { return true }
            if after.hasPrefix("false") { return false }
        }
        return true // default
    }

    // MARK: - Helpers

    private func makeRequest(url: URL) throws -> URLRequest {
        // Enforce domain restriction
        guard let host = url.host?.lowercased(),
              host == Self.allowedHost || host.hasSuffix(".\(Self.allowedHost)") else {
            throw KagiAPIError.requestFailed
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (key, value) in defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let token = sessionToken {
            request.setValue("kagi_session=\(token)", forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func streamRequest<T: Encodable>(path: String, body: T) -> AsyncThrowingStream<StreamChunk, Error> {
        let request: URLRequest
        do {
            let url = baseURL.appendingPathComponent(path)
            var req = try makeRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.setValue("application/vnd.kagi.stream", forHTTPHeaderField: "accept")
            req.timeoutInterval = 0 // unlimited for streams
            req.httpBody = try JSONEncoder().encode(body)
            request = req
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        let urlSession = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await urlSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.finish(throwing: KagiAPIError.httpError(code))
                        return
                    }

                    var buffer = Data()
                    for try await byte in bytes {
                        if byte == 0x00 {
                            // Process frame
                            if let frame = String(data: buffer, encoding: .utf8), !frame.isEmpty {
                                let trimmedFrame = frame.trimmingCharacters(in: .whitespacesAndNewlines)
                                if let colonIndex = trimmedFrame.firstIndex(of: ":") {
                                    let header = String(trimmedFrame[..<colonIndex])
                                    let data = String(trimmedFrame[trimmedFrame.index(after: colonIndex)...])
                                    continuation.yield(StreamChunk(header: header, data: data, done: false))
                                }
                            }
                            buffer.removeAll()
                        } else {
                            buffer.append(byte)
                        }
                    }

                    // Process any remaining buffer
                    if let frame = String(data: buffer, encoding: .utf8), !frame.isEmpty {
                        let trimmedFrame = frame.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let colonIndex = trimmedFrame.firstIndex(of: ":") {
                            let header = String(trimmedFrame[..<colonIndex])
                            let data = String(trimmedFrame[trimmedFrame.index(after: colonIndex)...])
                            continuation.yield(StreamChunk(header: header, data: data, done: false))
                        }
                    }

                    // Emit done
                    continuation.yield(StreamChunk(header: "done", data: "", done: true))
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(StreamChunk(header: "error", data: error.localizedDescription, done: true))
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
            ("&apos;", "'"), ("&#x2F;", "/"), ("&#47;", "/"),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}

// MARK: - Citation Parsing

extension KagiMessageDTO {
    func extractCitations() -> [KagiCitation] {
        guard let html = references_html, !html.isEmpty else { return [] }
        var citations: [KagiCitation] = []

        // Simple regex-based extraction for <a href="...">title</a> within ol[data-ref-list]
        let pattern = #"<a\s+href="([^"]+)"[^>]*>([^<]+)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            if let urlRange = Range(match.range(at: 1), in: html),
               let titleRange = Range(match.range(at: 2), in: html) {
                citations.append(KagiCitation(url: String(html[urlRange]), title: String(html[titleRange])))
            }
        }
        return citations
    }
}

// MARK: - Thread List HTML Parsing

enum KagiHTMLParser {
    static func parseThreadList(html: String) -> [KagiThreadEntry] {
        var entries: [KagiThreadEntry] = []

        // Match thread entries with data-code attribute
        let pattern = #"class="thread"[^>]*data-code="([^"]+)"[^>]*>.*?class="title"[^>]*>([^<]*)</.*?class="excerpt"[^>]*>([^<]*)<"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return entries
        }

        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            if let idRange = Range(match.range(at: 1), in: html),
               let titleRange = Range(match.range(at: 2), in: html),
               let excerptRange = Range(match.range(at: 3), in: html) {
                entries.append(KagiThreadEntry(
                    id: String(html[idRange]),
                    title: String(html[titleRange]).trimmingCharacters(in: .whitespaces),
                    excerpt: String(html[excerptRange]).trimmingCharacters(in: .whitespaces)
                ))
            }
        }
        return entries
    }
}

// MARK: - Errors

enum KagiAPIError: LocalizedError {
    case noSession
    case requestFailed
    case httpError(Int)
    case invalidResponse
    case streamError(String)

    var errorDescription: String? {
        switch self {
        case .noSession: return "No active session. Please log in."
        case .requestFailed: return "Request failed."
        case .httpError(let code): return "HTTP error \(code)."
        case .invalidResponse: return "Invalid response from server."
        case .streamError(let msg): return msg
        }
    }
}
