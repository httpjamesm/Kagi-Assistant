//
//  ChatView.swift
//  Kagi Assistant
//

import SwiftUI
import AppKit

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var textEditorHeight: CGFloat = 32

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
                    ModelPicker(viewModel: viewModel)
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
                }
                .padding()
            }
            .onChange(of: thread.messages.count) {
                if let lastMessage = thread.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: thread.messages.last?.content) {
                if let lastMessage = thread.messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AutoResizingTextView(
                text: $messageText,
                desiredHeight: $textEditorHeight,
                maxLines: 10,
                placeholder: viewModel.isAuthenticated ? "Type a message..." : "Log in to start chatting..."
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
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
    }

    private func send() {
        let text = messageText
        messageText = ""
        viewModel.sendMessage(text)
    }
}

// MARK: - Auto-resizing NSTextView wrapper

private class InputTextView: NSTextView {
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
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.recalcHeight()
        }

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
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.15))
                    )
            }
        }
    }

    private var assistantView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(segments) { segment in
                switch segment {
                case .htmlContent(_, let html):
                    SegmentHTMLView(html: html)
                case .event(_, let title, let content, let isCompleted):
                    EventView(title: title, content: content, isCompleted: isCompleted)
                }
            }

            if message.isStreaming && segments.isEmpty {
                ProgressView()
                    .controlSize(.small)
            }

            if !message.citations.isEmpty {
                Divider()
                ForEach(Array(message.citations.enumerated()), id: \.offset) { idx, citation in
                    HStack(spacing: 4) {
                        Text("\(idx + 1).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Link(citation.title, destination: URL(string: citation.url) ?? URL(string: "about:blank")!)
                            .font(.caption)
                    }
                }
            }
        }
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

    private var selectedProfileName: String {
        if let profile = viewModel.profiles.first(where: { $0.model == viewModel.selectedModel }) {
            return profile.name ?? profile.model ?? "Unknown"
        }
        return viewModel.selectedModel
    }

    var body: some View {
        Menu {
            ForEach(groupedProviders, id: \.provider) { group in
                Section(group.provider) {
                    ForEach(group.profiles, id: \.stableId) { profile in
                        Toggle(isOn: Binding(
                            get: { profile.model == viewModel.selectedModel },
                            set: { if $0 { viewModel.selectedModel = profile.model ?? "" } }
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
    }

    private struct ProviderGroup: Identifiable {
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
