//
//  ChatViewModel.swift
//  Kagi Assistant
//

import SwiftUI

@Observable
final class ChatViewModel {
    var threads: [ChatThread] = []
    var selectedThreadID: UUID?

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
        let welcome = ChatThread(name: "New Chat")
        threads = [welcome]
        selectedThreadID = welcome.id
    }

    func createThread() {
        let thread = ChatThread(name: "New Chat")
        threads.insert(thread, at: 0)
        selectedThreadID = thread.id
    }

    func deleteThread(_ thread: ChatThread) {
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

    func sendMessage(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = threads.firstIndex(where: { $0.id == selectedThreadID }) else {
            return
        }

        let userMessage = ChatMessage(role: .user, content: content)
        threads[index].messages.append(userMessage)

        // Update the thread name from the first message
        if threads[index].messages.count == 1 {
            let preview = String(content.prefix(30))
            threads[index].name = preview
        }

        // Simulate an assistant response (placeholder for real LLM integration)
        simulateResponse(in: index)
    }

    private func simulateResponse(in threadIndex: Int) {
        let response = ChatMessage(
            role: .assistant,
            content: "This is a placeholder response. Connect an LLM API to get real responses."
        )
        threads[threadIndex].messages.append(response)
    }
}
