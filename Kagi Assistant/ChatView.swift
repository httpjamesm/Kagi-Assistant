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
    @Binding var showingLogin: Bool
    @State private var messageText = ""
    @State private var textEditorHeight: CGFloat = 32
    @State private var shouldAutoScroll = true
    @State private var showAccountPopover = false
    @State private var focusTrigger = false
    @State private var keyMonitor: Any?
    private let chatContentMaxWidth: CGFloat = 750

    var body: some View {
        if let thread = viewModel.selectedThread {
            messageList(for: thread)
                .safeAreaInset(edge: .top, spacing: 0) {
                    threadHeader(for: thread)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    inputArea
                }
                .ignoresSafeArea(edges: .top)
                .onChange(of: viewModel.selectedThread) {
                    focusTrigger.toggle()
                }
                .onAppear {
                    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        if event.charactersIgnoringModifiers == "/",
                           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                           !(event.window?.firstResponder is NSTextView) {
                            focusTrigger.toggle()
                            return nil
                        }
                        return event
                    }
                }
                .onDisappear {
                    if let keyMonitor {
                        NSEvent.removeMonitor(keyMonitor)
                    }
                    keyMonitor = nil
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
                .frame(maxWidth: chatContentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
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

    private func threadHeader(for thread: ChatThread) -> some View {
        ZStack {
            Text(thread.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)

            HStack {
                Spacer()
                headerControls
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.6),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            accountControl
            ModelPicker(viewModel: viewModel, showPopover: $showModelPicker)

            Button {
                viewModel.createThread()
            } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .padding(6)
            .glassEffect(.regular.interactive(), in: .circle)
            .help("New Chat")
        }
    }

    @ViewBuilder
    private var accountControl: some View {
        if viewModel.isAuthenticated {
            Button {
                showAccountPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .frame(width: 18, height: 18)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .help("Account")
            .popover(isPresented: $showAccountPopover, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    if let email = viewModel.userEmail {
                        Text(email)
                            .font(.callout)
                    }

                    Button("Sign Out") {
                        showAccountPopover = false
                        Task { await viewModel.logout() }
                    }
                }
                .padding()
                .frame(minWidth: 220, alignment: .leading)
            }
        } else {
            Button {
                showingLogin = true
            } label: {
                Image(systemName: "person.crop.circle.badge.plus")
                    .frame(width: 18, height: 18)
                    .padding(6)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .help("Sign In")
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
                        .frame(width: 18, height: 18)
                        .foregroundStyle(viewModel.internetAccess ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .padding(6)
                .glassEffect(.regular.interactive(), in: .circle)
                .help(viewModel.internetAccess ? "Internet access enabled" : "Internet access disabled")
                if viewModel.selectedModelHasThinkingVariant {
                    Button {
                        viewModel.thinkingEnabled.toggle()
                    } label: {
                        Image(systemName: viewModel.thinkingEnabled ? "lightbulb.fill" : "lightbulb")
                            .frame(width: 18, height: 18)
                            .foregroundStyle(viewModel.thinkingEnabled ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .help(viewModel.thinkingEnabled ? "Thinking enabled" : "Enable thinking")
                }
                Button {
                    openAttachmentPicker()
                } label: {
                    Image(systemName: "plus.circle")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .padding(6)
                .glassEffect(.regular.interactive(), in: .circle)
                .help("Attach files")
                .disabled(viewModel.isStreaming)

                AutoResizingTextView(
                    text: $messageText,
                    desiredHeight: $textEditorHeight,
                    maxLines: 10,
                    placeholder: viewModel.isAuthenticated ? "Type a message..." : "Log in to start chatting...",
                    requestFocus: focusTrigger,
                    onSend: { send() }
                )
                .frame(height: textEditorHeight)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))

                if viewModel.isStreaming {
                    Button {
                        viewModel.stopGeneration()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 18, height: 18)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .help("Stop generation")
                } else {
                    sendButton
                }
            }
        }
        .padding(12)
        .padding(.top, 12)
        .frame(maxWidth: chatContentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(.ultraThinMaterial)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.4),
                    .init(color: .white, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.composerAttachments.isEmpty
    }

    @ViewBuilder
    private var sendButton: some View {
        let button = Button {
            send()
        } label: {
            Image(systemName: "arrow.up")
                .fontWeight(.semibold)
                .frame(width: 18, height: 18)
                .foregroundStyle(canSend ? .white : .primary)
        }
        .buttonStyle(.plain)
        .padding(6)
        .disabled(!canSend)

        if canSend {
            button
                .glassEffect(.regular.interactive().tint(.accentColor), in: .circle)
        } else {
            button
                .glassEffect(.regular.interactive(), in: .circle)
        }
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
