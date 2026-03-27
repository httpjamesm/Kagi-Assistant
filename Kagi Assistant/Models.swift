//
//  Models.swift
//  Kagi Assistant
//

import Foundation

struct ChatAttachment: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let mimeType: String
    let data: Data?
    let thumbnailData: Data?
    let thumbnailMimeType: String?

    var byteCount: Int? {
        data?.count
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var kagiMessageId: String?
    let role: Role
    var content: String
    let timestamp: Date
    var attachments: [ChatAttachment]
    var citations: [KagiCitation]
    var isStreaming: Bool

    enum Role {
        case user
        case assistant
    }

    init(role: Role, content: String, timestamp: Date = .now, kagiMessageId: String? = nil, attachments: [ChatAttachment] = [], citations: [KagiCitation] = [], isStreaming: Bool = false) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.kagiMessageId = kagiMessageId
        self.attachments = attachments
        self.citations = citations
        self.isStreaming = isStreaming
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.attachments == rhs.attachments && lhs.isStreaming == rhs.isStreaming
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
