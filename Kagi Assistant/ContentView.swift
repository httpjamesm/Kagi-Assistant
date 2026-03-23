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

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            ChatView(viewModel: viewModel)
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if viewModel.isAuthenticated {
                    Menu {
                        if let email = viewModel.userEmail {
                            Text(email)
                        }

                        Divider()
                        Button("Sign Out") {
                            Task { await viewModel.logout() }
                        }
                    } label: {
                        Image(systemName: "person.circle.fill")
                    }
                } else {
                    Button("Sign In") {
                        showingLogin = true
                    }
                }
            }
        }
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
