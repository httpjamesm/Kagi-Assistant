//
//  ContentView.swift
//  Kagi Assistant
//
//  Created by James on 2026-03-22.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = ChatViewModel()
    @State private var showingLogin = false
    @State private var searchFocusTrigger = false
    @State private var showModelPicker = false

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, focusSearch: $searchFocusTrigger)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            ChatView(viewModel: viewModel, showModelPicker: $showModelPicker, showingLogin: $showingLogin)
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .sheet(isPresented: $showingLogin) {
            LoginSheet(viewModel: viewModel, isPresented: $showingLogin)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .background {
            Group {
                Button(action: { viewModel.createThread() }) { EmptyView() }
                    .keyboardShortcut("k", modifiers: .command)
                Button(action: { searchFocusTrigger.toggle() }) { EmptyView() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button(action: { viewModel.internetAccess.toggle() }) { EmptyView() }
                    .keyboardShortcut("i", modifiers: .command)
                Button(action: { showModelPicker.toggle() }) { EmptyView() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Login Sheet

struct LoginSheet: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    @State private var tokenInput = ""
    @State private var isLoggingIn = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Sign in to Kagi")
                .font(.headline)

            Text("Enter your Kagi session token. You can find this in your browser cookies for kagi.com (cookie name: `kagi_session`).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("Session Token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Sign In") {
                    isLoggingIn = true
                    Task {
                        await viewModel.login(token: tokenInput)
                        isLoggingIn = false
                        if viewModel.isAuthenticated {
                            isPresented = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tokenInput.isEmpty || isLoggingIn)
            }

            if isLoggingIn {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

#Preview {
    ContentView()
}
