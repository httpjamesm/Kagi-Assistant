//
//  ChatView.swift
//  Kagi Assistant
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var showModelPicker: Bool
    @State private var messageText = ""
    @State private var textEditorHeight: CGFloat = 32
    @State private var shouldAutoScroll = true

    var body: some View {
        if let thread = viewModel.selectedThread {
            VStack(spacing: 0) {
                messageList(for: thread)
                Divider()
                inputArea
            }
            .navigationTitle(thread.name)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    ModelPicker(viewModel: viewModel, showPopover: $showModelPicker)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.createThread()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("New Chat")
                }
            }
        } else {
            ContentUnavailableView(
                "No Chat Selected",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Select a chat from the sidebar or create a new one.")
            )
        }
    }

    private func messageList(for thread: ChatThread) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(thread.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 20
            } action: { _, isAtBottom in
                shouldAutoScroll = isAtBottom
            }
            .onChange(of: thread.messages.count) {
                if shouldAutoScroll {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: thread.messages.last?.content) {
                if shouldAutoScroll {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.composerAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.composerAttachments) { attachment in
                            AttachmentChip(attachment: attachment, style: .composer) {
                                viewModel.removeComposerAttachment(attachment)
                            }
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    viewModel.internetAccess.toggle()
                } label: {
                    Image(systemName: viewModel.internetAccess ? "network" : "network.slash")
                        .font(.title2)
                        .foregroundStyle(viewModel.internetAccess ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help(viewModel.internetAccess ? "Internet access enabled" : "Internet access disabled")
                Button {
                    openAttachmentPicker()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Attach files")
                .disabled(viewModel.isStreaming)

                AutoResizingTextView(
                    text: $messageText,
                    desiredHeight: $textEditorHeight,
                    maxLines: 10,
                    placeholder: viewModel.isAuthenticated ? "Type a message..." : "Log in to start chatting...",
                    onSend: { send() }
                )
                .frame(height: textEditorHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if viewModel.isStreaming {
                    Button {
                        viewModel.stopGeneration()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop generation")
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.composerAttachments.isEmpty)
                }
            }
        }
        .padding(12)
    }

    private func send() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = viewModel.composerAttachments
        guard !viewModel.isStreaming,
              !trimmedText.isEmpty || !attachments.isEmpty else { return }
        let text = messageText
        messageText = ""
        viewModel.clearComposerAttachments()
        viewModel.sendMessage(text, attachments: attachments)
    }

    private func openAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.item]

        if panel.runModal() == .OK {
            viewModel.addAttachments(from: panel.urls)
        }
    }
}

// MARK: - Auto-resizing NSTextView wrapper

private class InputTextView: NSTextView {
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            if event.modifierFlags.contains(.shift) {
                super.keyDown(with: event)
            } else {
                onSend?()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a" {
            selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct AutoResizingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var desiredHeight: CGFloat
    var maxLines: Int
    var placeholder: String
    var onSend: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = InputTextView()
        textView.onSend = onSend
        textView.delegate = context.coordinator
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 4
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Set initial single-line height
        let lineHeight = textView.font!.boundingRectForFont.height
        let inset = textView.textContainerInset
        DispatchQueue.main.async {
            self.desiredHeight = lineHeight + inset.height * 2
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? InputTextView else { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.recalcHeight()
        }

        textView.onSend = onSend
        context.coordinator.parent = self
        context.coordinator.updatePlaceholder()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoResizingTextView
        weak var textView: NSTextView?
        private var placeholderView: NSTextField?

        init(_ parent: AutoResizingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            recalcHeight()
            updatePlaceholder()
        }

        func recalcHeight() {
            guard let textView else { return }

            let font = textView.font ?? NSFont.preferredFont(forTextStyle: .body)
            let lineHeight = font.boundingRectForFont.height
            let inset = textView.textContainerInset
            let singleLineHeight = lineHeight + inset.height * 2
            let maxHeight = lineHeight * CGFloat(parent.maxLines) + inset.height * 2

            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? lineHeight
            let naturalHeight = usedHeight + inset.height * 2

            let targetHeight = max(singleLineHeight, min(naturalHeight, maxHeight))

            DispatchQueue.main.async {
                self.parent.desiredHeight = targetHeight
            }
        }

        func updatePlaceholder() {
            guard let textView else { return }

            if placeholderView == nil {
                let field = NSTextField(labelWithString: parent.placeholder)
                field.textColor = .tertiaryLabelColor
                field.font = textView.font
                field.translatesAutoresizingMaskIntoConstraints = false
                textView.addSubview(field)

                let inset = textView.textContainerInset
                let padding = textView.textContainer?.lineFragmentPadding ?? 0
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: inset.width + padding),
                    field.topAnchor.constraint(equalTo: textView.topAnchor, constant: inset.height)
                ])
                placeholderView = field
            }

            placeholderView?.stringValue = parent.placeholder
            placeholderView?.isHidden = !textView.string.isEmpty
        }
    }
}

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

private struct UserMessageContent: View {
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.15))
        )
    }
}

private struct AttachmentChip: View {
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

    var body: some View {
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

/// Wrapper that gives each HTML segment its own height state.
private struct SegmentHTMLView: View {
    let html: String
    @State private var height: CGFloat = 1

    var body: some View {
        HTMLMessageView(html: html, dynamicHeight: $height)
            .frame(height: height)
    }
}

// MARK: - Model Picker

struct ModelPicker: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var showPopover: Bool

    private var selectedProfileName: String {
        if let profile = viewModel.selectedProfile {
            return profile.name ?? profile.model ?? "Unknown"
        }
        return "Select Model"
    }

    var body: some View {
        Menu {
            ForEach(groupedProviders, id: \.provider) { group in
                Section(group.provider) {
                    ForEach(group.profiles, id: \.stableId) { profile in
                        Toggle(isOn: Binding(
                            get: { viewModel.selectedProfile == profile },
                            set: { if $0 { viewModel.selectedProfile = profile } }
                        )) {
                            Text(profile.name ?? profile.model ?? "Unknown")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text(selectedProfileName)
                    .lineLimit(1)
            }
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Select model")
        .disabled(viewModel.profiles.isEmpty)
        .popover(isPresented: $showPopover) {
            ModelPopoverContent(viewModel: viewModel, showPopover: $showPopover, groups: groupedProviders)
        }
    }

    struct ProviderGroup: Identifiable {
        let provider: String
        let profiles: [KagiProfile]
        var id: String { provider }
    }

    private var groupedProviders: [ProviderGroup] {
        let grouped = Dictionary(grouping: viewModel.profiles) { profile in
            profile.model_provider ?? "Other"
        }
        return grouped.map { ProviderGroup(provider: $0.key, profiles: $0.value) }
            .sorted { a, b in
                if a.provider == "kagi" { return true }
                if b.provider == "kagi" { return false }
                return a.provider < b.provider
            }
    }
}

private struct ModelPopoverContent: View {
    var viewModel: ChatViewModel
    @Binding var showPopover: Bool
    let groups: [ModelPicker.ProviderGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groups, id: \.provider) { (group: ModelPicker.ProviderGroup) in
                ModelPopoverGroupView(group: group, groups: groups, viewModel: viewModel, showPopover: $showPopover)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}

private struct ModelPopoverGroupView: View {
    let group: ModelPicker.ProviderGroup
    let groups: [ModelPicker.ProviderGroup]
    var viewModel: ChatViewModel
    @Binding var showPopover: Bool

    var body: some View {
        Text(group.provider.uppercased())
            .font(.caption2)
            .foregroundStyle(.secondary)
        ForEach(group.profiles, id: \.stableId) { profile in
            Button {
                viewModel.selectedProfile = profile
                showPopover = false
            } label: {
                HStack {
                    Text(profile.name ?? profile.model ?? "Unknown")
                    Spacer()
                    if viewModel.selectedProfile == profile {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        if group.provider != groups.last?.provider {
            Divider()
        }
    }
}
