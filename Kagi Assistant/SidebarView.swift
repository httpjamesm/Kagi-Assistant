//
//  SidebarView.swift
//  Kagi Assistant
//

import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search threads...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .onSubmit {
                    guard !searchText.isEmpty else { return }
                    Task {
                        await viewModel.searchAndSelectThread(query: searchText)
                    }
                }

            Divider()

            List(viewModel.threads, selection: $viewModel.selectedThreadID) { thread in
                Text(thread.name)
                    .tag(thread.id)
                    .lineLimit(1)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            viewModel.deleteThread(thread)
                        }
                    }
            }
            .onChange(of: viewModel.selectedThreadID) { _, newValue in
                guard let newValue,
                      let thread = viewModel.threads.first(where: { $0.id == newValue }) else { return }
                Task { await viewModel.selectThread(thread) }
            }
        }
    }
}
