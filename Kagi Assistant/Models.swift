//
//  Models.swift
//  Kagi Assistant
//

import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var kagiMessageId: String?
    let role: Role
    var content: String
    let timestamp: Date
    var citations: [KagiCitation]
    var isStreaming: Bool

    enum Role {
        case user
        case assistant
    }

    init(role: Role, content: String, timestamp: Date = .now, kagiMessageId: String? = nil, citations: [KagiCitation] = [], isStreaming: Bool = false) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.kagiMessageId = kagiMessageId
        self.citations = citations
        self.isStreaming = isStreaming
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming
    }
}

struct ChatThread: Identifiable, Equatable {
    let id = UUID()
    var kagiThreadId: String?
    var branchId: String?
    var name: String
    var messages: [ChatMessage]
    let createdAt: Date

    init(name: String, messages: [ChatMessage] = [], createdAt: Date = .now, kagiThreadId: String? = nil) {
        self.name = name
        self.messages = messages
        self.createdAt = createdAt
        self.kagiThreadId = kagiThreadId
    }

    static func == (lhs: ChatThread, rhs: ChatThread) -> Bool {
        lhs.id == rhs.id
    }
}
