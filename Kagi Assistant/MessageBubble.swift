//
//  MessageBubble.swift
//  Kagi Assistant
//

import SwiftUI

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var webViewHeight: CGFloat = 1

    private var isUser: Bool { message.role == .user }

    private var segments: [ContentSegment] {
        ContentParser.parseContent(message.content, isStreaming: message.isStreaming)
    }

    var body: some View {
        if isUser {
            userBubble
        } else {
            assistantView
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                Text("You")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !message.content.isEmpty {
                    UserMessageContent(content: message.content)
                }
                if !message.attachments.isEmpty {
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(message.attachments) { attachment in
                            AttachmentChip(attachment: attachment, style: .message)
                        }
                    }
                }
            }
        }
    }

    private var assistantView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(segments) { segment in
                switch segment {
                case .htmlContent(_, let html):
                    SegmentHTMLView(html: html)
                        .padding(.top, 4)
                case .event(_, let title, let content, let isCompleted):
                    EventView(title: title, content: content, isCompleted: isCompleted)
                        .padding(.top, 4)
                }
            }

            if message.isStreaming && segments.isEmpty {
                ProgressView()
                    .controlSize(.small)
            }

            if !message.citations.isEmpty {
                SourcesButton(citations: message.citations)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - User Message Content

struct UserMessageContent: View {
    let content: String
    @State private var isExpanded = false

    private let characterLimit = 500

    private var isTruncated: Bool { content.count > characterLimit }

    private var displayedText: String {
        if isTruncated && !isExpanded {
            return String(content.prefix(characterLimit)) + "..."
        }
        return content
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(displayedText)
                .textSelection(.enabled)

            if isTruncated {
                Button(isExpanded ? "Read Less" : "Read More") {
                    isExpanded.toggle()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .padding(10)
        .glassEffect(.regular.tint(.accentColor), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Attachment Chip

struct AttachmentChip: View {
    enum Style {
        case composer
        case message
    }

    let attachment: ChatAttachment
    let style: Style
    var onRemove: (() -> Void)? = nil

    private var byteCountText: String? {
        guard let byteCount = attachment.byteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private var thumbnailImage: NSImage? {
        guard let data = attachment.thumbnailData else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        if let image = thumbnailImage {
            thumbnailView(image: image)
        } else {
            chipView
        }
    }

    private func thumbnailView(image: NSImage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 128, maxHeight: 128)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if style == .composer, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chipView: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .lineLimit(1)
                if let byteCountText {
                    Text(byteCountText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(style == .composer ? .caption : .callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(style == .composer ? Color.secondary.opacity(0.12) : Color.primary.opacity(0.08))
        )
    }
}

// MARK: - Segment HTML View

/// Wrapper that gives each HTML segment its own height state.
struct SegmentHTMLView: View {
    let html: String
    @State private var height: CGFloat = 1

    var body: some View {
        HTMLMessageView(html: html, dynamicHeight: $height)
            .frame(height: height)
    }
}
