//
//  ChatViewModel.swift
//  Kagi Assistant
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@Observable
@MainActor
final class ChatViewModel {
    var threads: [ChatThread] = []
    var selectedThreadID: UUID? {
        didSet {
            removeEmptyThread(id: oldValue)
            // Persist the kagi thread ID so we can restore it on next launch
            if let selectedThreadID,
               let thread = threads.first(where: { $0.id == selectedThreadID }) {
                UserDefaults.standard.set(thread.kagiThreadId, forKey: "lastThreadKagiId")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastThreadKagiId")
            }
        }
    }
    var isAuthenticated = false
    var isLoading = false
    var isStreaming = false
    var errorMessage: String?
    var sessionToken: String = ""
    var userEmail: String?
    private var allProfiles: [KagiProfile] = []
    var profiles: [KagiProfile] {
        allProfiles.filter { !($0.name ?? "").contains("(reasoning)") }
    }
    var selectedProfile: KagiProfile? = {
        guard let data = UserDefaults.standard.data(forKey: "selectedProfile"),
              let profile = try? JSONDecoder().decode(KagiProfile.self, from: data)
        else { return nil }
        return profile
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(selectedProfile) {
                UserDefaults.standard.set(data, forKey: "selectedProfile")
            }
            thinkingEnabled = false
        }
    }
    var thinkingEnabled: Bool = false

    var selectedModelHasThinkingVariant: Bool {
        guard let name = selectedProfile?.name else { return false }
        return allProfiles.contains { ($0.name ?? "").contains("(reasoning)") && Self.baseModelName($0.name ?? "") == name }
    }

    var effectiveProfile: KagiProfile? {
        guard thinkingEnabled, let name = selectedProfile?.name else { return selectedProfile }
        return allProfiles.first { ($0.name ?? "").contains("(reasoning)") && Self.baseModelName($0.name ?? "") == name } ?? selectedProfile
    }

    /// Strips "(reasoning)" (and surrounding whitespace collapse) from a model name.
    private static func baseModelName(_ name: String) -> String {
        name.replacingOccurrences(of: "(reasoning)", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
    var internetAccess: Bool = UserDefaults.standard.object(forKey: "internetAccess") as? Bool ?? true {
        didSet { UserDefaults.standard.set(internetAccess, forKey: "internetAccess") }
    }
    var composerAttachments: [ChatAttachment] = []
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
            allProfiles = []
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

        await MainActor.run {
            self.allProfiles = foundProfiles
            if self.selectedProfile == nil, let first = foundProfiles.first {
                self.selectedProfile = first
            }
        }
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

            // Restore last selected thread, or create a new chat
            if selectedThreadID == nil || !threads.contains(where: { $0.id == selectedThreadID }) {
                if let lastKagiId = UserDefaults.standard.string(forKey: "lastThreadKagiId"),
                   let restored = threads.first(where: { $0.kagiThreadId == lastKagiId }) {
                    selectedThreadID = restored.id
                } else if threads.isEmpty {
                    createThread()
                } else {
                    selectedThreadID = threads.first?.id
                }
            }
        }

        // Load messages for the restored thread if needed
        if let id = await MainActor.run(body: { selectedThreadID }),
           let thread = await MainActor.run(body: { threads.first(where: { $0.id == id }) }),
           thread.kagiThreadId != nil, thread.messages.isEmpty {
            await selectThread(thread)
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
                let documentAttachments: [ChatAttachment] = dto.documents?.compactMap { document -> ChatAttachment? in
                    guard let name = document.name, !name.isEmpty else { return nil }

                    var thumbnailData: Data? = nil
                    var thumbnailMimeType: String? = nil
                    if let dataURI = document.data, !dataURI.isEmpty,
                       dataURI.hasPrefix("data:image/"),
                       let semiIndex = dataURI.firstIndex(of: ";"),
                       let commaIndex = dataURI.firstIndex(of: ",") {
                        let mimeType = String(dataURI[dataURI.index(dataURI.startIndex, offsetBy: 5)..<semiIndex])
                        let base64String = String(dataURI[dataURI.index(after: commaIndex)...])
                        thumbnailData = Data(base64Encoded: base64String)
                        thumbnailMimeType = mimeType
                    }

                    return ChatAttachment(
                        name: name,
                        mimeType: document.mime ?? "application/octet-stream",
                        data: nil,
                        thumbnailData: thumbnailData,
                        thumbnailMimeType: thumbnailMimeType
                    )
                } ?? []

                let prompt = dto.prompt ?? ""
                if !prompt.isEmpty || !documentAttachments.isEmpty {
                    messages.append(ChatMessage(
                        role: .user,
                        content: prompt,
                        attachments: documentAttachments
                    ))
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
        guard let allResults = try? await api.searchThreads(query: query),
              !allResults.isEmpty else { return }

        // Deduplicate by thread_id, keep top 10
        var seen = Set<String>()
        let results = allResults.filter { seen.insert($0.thread_id).inserted }.prefix(10)

        // Reuse already-loaded threads where possible, otherwise create with
        // a placeholder name — selectThread will fetch the real title.
        let matchedThreads: [ChatThread] = results.map { result in
            if let existing = threads.first(where: { $0.kagiThreadId == result.thread_id }) {
                return existing
            }
            return ChatThread(name: "Loading…", kagiThreadId: result.thread_id)
        }

        await MainActor.run {
            threads = matchedThreads
            selectedThreadID = matchedThreads.first?.id
        }

        // Fetch titles for all newly created threads concurrently
        await withTaskGroup(of: (String, String).self) { group in
            for thread in matchedThreads {
                guard thread.messages.isEmpty, let kagiId = thread.kagiThreadId else { continue }
                let threadId = thread.id.uuidString
                group.addTask { [api] in
                    let title = (try? await api.fetchThread(threadId: kagiId).title) ?? ""
                    return (threadId, title)
                }
            }
            for await (threadIdStr, title) in group {
                guard !title.isEmpty else { continue }
                await MainActor.run {
                    if let idx = self.threads.firstIndex(where: { $0.id.uuidString == threadIdStr }) {
                        self.threads[idx].name = title
                    }
                }
            }
        }

        if let first = matchedThreads.first {
            await selectThread(first)
        }
    }

    // MARK: - Send Message

    func sendMessage(_ content: String, attachments: [ChatAttachment] = []) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty || !attachments.isEmpty,
              let index = threads.firstIndex(where: { $0.id == selectedThreadID }) else {
            return
        }

        let userMessage = ChatMessage(role: .user, content: content, attachments: attachments)
        threads[index].messages.append(userMessage)

        // Update thread name from first message
        if threads[index].messages.count == 1 {
            if !trimmedContent.isEmpty {
                threads[index].name = String(trimmedContent.prefix(30))
            } else if let firstAttachment = attachments.first {
                threads[index].name = firstAttachment.name
            }
        }

        guard isAuthenticated else {
            let response = ChatMessage(role: .assistant, content: "Please log in with your Kagi session token to use the assistant.")
            threads[index].messages.append(response)
            return
        }

        // Start streaming response
        let threadId = threads[index].kagiThreadId
        let branchId = threads[index].branchId
        let profile = effectiveProfile
        let model = profile?.model ?? profile?.name ?? "gemini-3-1-flash-lite"
        let profileId = profile?.id
        let internet = internetAccess
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
                    model: model,
                    profileId: profileId,
                    internetAccess: internet,
                    attachments: attachments
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
                                    if let tid = info.id {
                                        self.threads[idx].kagiThreadId = tid
                                        if self.threads[idx].id == self.selectedThreadID {
                                            UserDefaults.standard.set(tid, forKey: "lastThreadKagiId")
                                        }
                                    }
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

    // MARK: - Empty Thread Cleanup

    private func removeEmptyThread(id: UUID?) {
        guard let id, id != selectedThreadID,
              let index = threads.firstIndex(where: { $0.id == id }) else { return }
        let thread = threads[index]
        if thread.messages.isEmpty && thread.kagiThreadId == nil {
            threads.remove(at: index)
        }
    }

    // MARK: - Private Helpers

    func addAttachments(from urls: [URL]) {
        let newAttachments = urls.compactMap(loadAttachment(from:))
        var seenKeys = Set(composerAttachments.map(attachmentKey(for:)))
        let uniqueAttachments = newAttachments.filter { attachment in
            let key = attachmentKey(for: attachment)
            return seenKeys.insert(key).inserted
        }
        composerAttachments.append(contentsOf: uniqueAttachments)
    }

    func removeComposerAttachment(_ attachment: ChatAttachment) {
        composerAttachments.removeAll { $0.id == attachment.id }
    }

    func clearComposerAttachments() {
        composerAttachments.removeAll()
    }

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
    }

    private func loadAttachment(from url: URL) -> ChatAttachment? {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey, .nameKey])
            let contentType = resourceValues?.contentType ?? UTType(filenameExtension: url.pathExtension)
            let mimeType = resourceValues?.contentType?.preferredMIMEType
                ?? UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            let data = try Data(contentsOf: url)
            let thumbnail = makeThumbnail(for: data, contentType: contentType, mimeType: mimeType)
            return ChatAttachment(
                name: resourceValues?.name ?? url.lastPathComponent,
                mimeType: mimeType,
                data: data,
                thumbnailData: thumbnail?.data,
                thumbnailMimeType: thumbnail?.mimeType
            )
        } catch {
            errorMessage = "Failed to attach \(url.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    private func attachmentKey(for attachment: ChatAttachment) -> String {
        "\(attachment.name)|\(attachment.mimeType)|\(attachment.byteCount ?? 0)"
    }

    private func makeThumbnail(for data: Data, contentType: UTType?, mimeType: String) -> (data: Data, mimeType: String)? {
        let isImageType = contentType?.conforms(to: .image) == true || mimeType.hasPrefix("image/")
        guard isImageType else { return nil }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        if let webPData = encodeThumbnail(thumbnail, uti: UTType.webP.identifier as CFString) {
            return (webPData, "image/webp")
        }
        if let pngData = encodeThumbnail(thumbnail, uti: UTType.png.identifier as CFString) {
            return (pngData, "image/png")
        }
        return nil
    }

    private func encodeThumbnail(_ image: CGImage, uti: CFString) -> Data? {
        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(destinationData, uti, 1, nil) else {
            return nil
        }

        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.8
        ]
        CGImageDestinationAddImage(destination, image, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destinationData as Data
    }
}
