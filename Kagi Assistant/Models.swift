//
//  Models.swift
//  Kagi Assistant
//

import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date

    enum Role {
        case user
        case assistant
    }

    init(role: Role, content: String, timestamp: Date = .now) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

struct ChatThread: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var messages: [ChatMessage]
    let createdAt: Date

    init(name: String, messages: [ChatMessage] = [], createdAt: Date = .now) {
        self.name = name
        self.messages = messages
        self.createdAt = createdAt
    }

    static func == (lhs: ChatThread, rhs: ChatThread) -> Bool {
        lhs.id == rhs.id
    }
}
