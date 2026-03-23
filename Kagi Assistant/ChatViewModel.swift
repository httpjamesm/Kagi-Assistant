//
//  ChatViewModel.swift
//  Kagi Assistant
//

import SwiftUI

@Observable
final class ChatViewModel {
    var threads: [ChatThread] = []
    var selectedThreadID: UUID?
    var isAuthenticated = false
    var isLoading = false
    var isStreaming = false
    var errorMessage: String?
    var sessionToken: String = ""
    var userEmail: String?
    var profiles: [KagiProfile] = []
    var selectedModel: String = "gemini-3-1-flash-lite"
    var currentTraceId: String?

    private let api = KagiAPIClient.shared
    private var streamTask: Task<Void, Never>?

    var selectedThread: ChatThread? {
        get {
            threads.first { $0.id == selectedThreadID }
        }
        set {
            if let newValue, let index = threads.firstIndex(where: { $0.id == newValue.id }) {
                threads[index] = newValue
            }
        }
    }

    init() {
        // Try to restore saved session
        if let saved = UserDefaults.standard.string(forKey: "kagi_session"), !saved.isEmpty {
            sessionToken = saved
            Task { await login(token: saved) }
        }
    }

    // MARK: - Auth

    func login(token: String) async {
        await api.setSession(token)
        do {
            let valid = try await api.validateSession()
            await MainActor.run {
                self.isAuthenticated = valid
                if valid {
                    self.sessionToken = token
                    UserDefaults.standard.set(token, forKey: "kagi_session")
                    self.errorMessage = nil
                } else {
                    self.errorMessage = "Invalid session token."
                }
            }
            if valid {
                await fetchEmail()
                await fetchProfiles()
                await fetchThreads()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Login failed: \(error.localizedDescription)"
            }
        }
    }

    func logout() async {
        _ = try? await api.logout()
        await api.clearSession()
        await MainActor.run {
            isAuthenticated = false
            sessionToken = ""
            userEmail = nil
            profiles = []
            threads = []
            selectedThreadID = nil
            UserDefaults.standard.removeObject(forKey: "kagi_session")
        }
    }

    private func fetchEmail() async {
        let email = try? await api.fetchEmail()
        await MainActor.run { self.userEmail = email }
    }

    // MARK: - Profiles

    func fetchProfiles() async {
        var foundProfiles: [KagiProfile] = []
        do {
            for try await chunk in await api.fetchProfiles() {
                if chunk.header == "profiles.json", let data = chunk.data.data(using: .utf8) {
                    print("[DEBUG] Raw profiles.json payload:\n\(chunk.data.prefix(2000))")
                    struct ProfilesWrapper: Decodable { let profiles: [KagiProfile] }
                    if let wrapper = try? JSONDecoder().decode(ProfilesWrapper.self, from: data) {
                        foundProfiles = wrapper.profiles
                        for p in foundProfiles {
                            print("[DEBUG] Profile — id: \(p.id ?? "nil"), name: \(p.name ?? "nil"), model: \(p.model ?? "nil"), model_name: \(p.model_name ?? "nil"), provider: \(p.model_provider ?? "nil")")
                        }
                    } else {
                        print("[DEBUG] Failed to decode ProfilesWrapper")
                    }
                }
            }
        } catch {}

        // Sort: kagi provider first
        foundProfiles.sort { a, b in
            let aIsKagi = a.model_provider == "kagi"
            let bIsKagi = b.model_provider == "kagi"
            if aIsKagi != bIsKagi { return aIsKagi }
            return (a.name ?? "") < (b.name ?? "")
        }

        await MainActor.run { self.profiles = foundProfiles }
    }

    // MARK: - Thread Management

    func createThread() {
        let thread = ChatThread(name: "New Chat")
        threads.insert(thread, at: 0)
        selectedThreadID = thread.id
    }

    func deleteThread(_ thread: ChatThread) {
        // Delete remotely if it has a kagi ID
        if let kagiId = thread.kagiThreadId {
            Task {
                do {
                    for try await _ in await api.deleteThread(threadId: kagiId, title: thread.name) {}
                } catch {}
            }
        }

        threads.removeAll { $0.id == thread.id }
        if selectedThreadID == thread.id {
            selectedThreadID = threads.first?.id
        }
    }

    func renameThread(_ thread: ChatThread, to name: String) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index].name = name
        }
    }

    // MARK: - Thread Loading

    func fetchThreads() async {
        var entries: [KagiThreadEntry] = []
        do {
            for try await chunk in await api.fetchThreadList() {
                if chunk.header == "thread_list.html" {
                    if let wrapper = KagiThreadListWrapper.parse(from: chunk.data),
                       let html = wrapper.html {
                        entries = KagiHTMLParser.parseThreadList(html: html)
                    } else {
                        entries = KagiHTMLParser.parseThreadList(html: chunk.data)
                    }
                }
            }
        } catch {}

        // Keep any unsaved local threads (no kagiThreadId yet) at the top,
        // then replace the rest with what the API returned
        let localOnly = threads.filter { $0.kagiThreadId == nil && !$0.messages.isEmpty }
        let remoteThreads = entries.map { entry in
            // Preserve already-loaded thread if it exists
            if let existing = threads.first(where: { $0.kagiThreadId == entry.id }) {
                return existing
            }
            return ChatThread(name: entry.title, kagiThreadId: entry.id)
        }

        await MainActor.run {
            self.threads = localOnly + remoteThreads
            // Keep selection if still valid, otherwise select first
            if let selected = selectedThreadID, !threads.contains(where: { $0.id == selected }) {
                selectedThreadID = threads.first?.id
            }
        }
    }

    func selectThread(_ thread: ChatThread) async {
        await MainActor.run { selectedThreadID = thread.id }

        // If this thread has a kagi ID but no messages loaded yet, fetch them
        guard let kagiId = thread.kagiThreadId,
              thread.messages.isEmpty else { return }

        await MainActor.run { isLoading = true }
        do {
            let (title, dtos) = try await api.fetchThread(threadId: kagiId)
            var messages: [ChatMessage] = []
            for dto in dtos {
                if let prompt = dto.prompt, !prompt.isEmpty {
                    messages.append(ChatMessage(role: .user, content: prompt))
                }
                let content = dto.reply ?? ""
                if !content.isEmpty {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: content,
                        kagiMessageId: dto.id,
                        citations: dto.extractCitations()
                    ))
                }
            }

            await MainActor.run {
                if let idx = self.threads.firstIndex(where: { $0.id == thread.id }) {
                    self.threads[idx].messages = messages
                    if !title.isEmpty { self.threads[idx].name = title }
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load thread: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func searchAndSelectThread(query: String) async {
        let results = (try? await api.searchThreads(query: query)) ?? []
        guard let first = results.first else { return }

        // Find or create the thread
        if let existing = threads.first(where: { $0.kagiThreadId == first.thread_id }) {
            await selectThread(existing)
        } else {
            let thread = ChatThread(name: first.title, kagiThreadId: first.thread_id)
            await MainActor.run {
                threads.insert(thread, at: 0)
            }
            await selectThread(thread)
        }
    }

    // MARK: - Send Message

    func sendMessage(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = threads.firstIndex(where: { $0.id == selectedThreadID }) else {
            return
        }

        let userMessage = ChatMessage(role: .user, content: content)
        threads[index].messages.append(userMessage)

        // Update thread name from first message
        if threads[index].messages.count == 1 {
            threads[index].name = String(content.prefix(30))
        }

        guard isAuthenticated else {
            let response = ChatMessage(role: .assistant, content: "Please log in with your Kagi session token to use the assistant.")
            threads[index].messages.append(response)
            return
        }

        // Start streaming response
        let threadId = threads[index].kagiThreadId
        let branchId = threads[index].branchId
        let model = selectedModel
        let threadUUID = threads[index].id

        // Add placeholder assistant message
        let assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        threads[index].messages.append(assistantMsg)
        let assistantMsgId = assistantMsg.id

        isStreaming = true
        currentTraceId = nil

        streamTask = Task { [weak self] in
            guard let self else { return }

            var accumulatedText = ""

            do {
                let stream = await api.sendPrompt(
                    prompt: content,
                    threadId: threadId,
                    branchId: branchId,
                    model: model
                )

                for try await chunk in stream {
                    guard !Task.isCancelled else { break }

                    switch chunk.header {
                    case "hi":
                        if let data = chunk.data.data(using: .utf8),
                           let hi = try? JSONDecoder().decode(KagiHiPayload.self, from: data) {
                            await MainActor.run { self.currentTraceId = hi.trace }
                        }

                    case "thread.json":
                        if let data = chunk.data.data(using: .utf8),
                           let info = try? JSONDecoder().decode(KagiThreadInfo.self, from: data) {
                            await MainActor.run {
                                if let idx = self.threads.firstIndex(where: { $0.id == threadUUID }) {
                                    if let tid = info.id { self.threads[idx].kagiThreadId = tid }
                                    if let title = info.title, !title.isEmpty { self.threads[idx].name = title }
                                }
                            }
                        }

                    case "location.json":
                        if let data = chunk.data.data(using: .utf8),
                           let loc = try? JSONDecoder().decode(KagiLocationInfo.self, from: data) {
                            await MainActor.run {
                                if let idx = self.threads.firstIndex(where: { $0.id == threadUUID }) {
                                    self.threads[idx].branchId = loc.branch_id
                                }
                            }
                        }

                    case "tokens.json":
                        if let data = chunk.data.data(using: .utf8),
                           let tokens = try? JSONDecoder().decode(KagiTokensPayload.self, from: data) {
                            accumulatedText = tokens.content
                            let text = accumulatedText
                            await MainActor.run {
                                self.updateStreamingMessage(threadUUID: threadUUID, messageId: assistantMsgId, content: text)
                            }
                        }

                    case "new_message.json":
                        if let data = chunk.data.data(using: .utf8),
                           let msg = try? JSONDecoder().decode(KagiMessageDTO.self, from: data) {
                            let finalContent = msg.reply ?? accumulatedText
                            let citations = msg.extractCitations()
                            let kagiMsgId = msg.id
                            await MainActor.run {
                                self.finalizeStreamingMessage(
                                    threadUUID: threadUUID,
                                    messageId: assistantMsgId,
                                    content: finalContent,
                                    kagiMessageId: kagiMsgId,
                                    citations: citations
                                )
                            }
                        }

                    case "error":
                        await MainActor.run {
                            self.updateStreamingMessage(threadUUID: threadUUID, messageId: assistantMsgId, content: "Error: \(chunk.data)")
                            self.finalizeStreamingMessage(threadUUID: threadUUID, messageId: assistantMsgId, content: "Error: \(chunk.data)", kagiMessageId: nil, citations: [])
                        }

                    default:
                        break
                    }
                }

                // If stream ended without new_message.json, finalize with accumulated text
                await MainActor.run {
                    if let idx = self.threads.firstIndex(where: { $0.id == threadUUID }),
                       let msgIdx = self.threads[idx].messages.firstIndex(where: { $0.id == assistantMsgId }),
                       self.threads[idx].messages[msgIdx].isStreaming {
                        self.threads[idx].messages[msgIdx].isStreaming = false
                        if self.threads[idx].messages[msgIdx].content.isEmpty {
                            self.threads[idx].messages[msgIdx].content = accumulatedText.isEmpty ? "No response received." : accumulatedText
                        }
                    }
                    self.isStreaming = false
                    self.currentTraceId = nil
                }

            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.finalizeStreamingMessage(
                            threadUUID: threadUUID,
                            messageId: assistantMsgId,
                            content: accumulatedText.isEmpty ? "Error: \(error.localizedDescription)" : accumulatedText,
                            kagiMessageId: nil,
                            citations: []
                        )
                        self.isStreaming = false
                        self.currentTraceId = nil
                    }
                }
            }
        }
    }

    func stopGeneration() {
        guard let traceId = currentTraceId else {
            streamTask?.cancel()
            isStreaming = false
            return
        }
        Task {
            try? await api.stopGeneration(traceId: traceId)
            streamTask?.cancel()
            await MainActor.run {
                self.isStreaming = false
                self.currentTraceId = nil
            }
        }
    }

    // MARK: - Private Helpers

    private func updateStreamingMessage(threadUUID: UUID, messageId: UUID, content: String) {
        if let idx = threads.firstIndex(where: { $0.id == threadUUID }),
           let msgIdx = threads[idx].messages.firstIndex(where: { $0.id == messageId }) {
            threads[idx].messages[msgIdx].content = content
            print("[ViewModel] updateStreamingMessage — content length: \(content.count)")
        }
    }

    private func finalizeStreamingMessage(threadUUID: UUID, messageId: UUID, content: String, kagiMessageId: String?, citations: [KagiCitation]) {
        if let idx = threads.firstIndex(where: { $0.id == threadUUID }),
           let msgIdx = threads[idx].messages.firstIndex(where: { $0.id == messageId }) {
            threads[idx].messages[msgIdx].content = content
            threads[idx].messages[msgIdx].kagiMessageId = kagiMessageId
            threads[idx].messages[msgIdx].citations = citations
            threads[idx].messages[msgIdx].isStreaming = false
        }
        isStreaming = false
        currentTraceId = nil
    }
}
