//
//  SidebarView.swift
//  Kagi Assistant
//

import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        List(selection: $viewModel.selectedThreadID) {
            ForEach(viewModel.threads) { thread in
                Text(thread.name)
                    .tag(thread.id)
                    .lineLimit(1)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            viewModel.deleteThread(thread)
                        }
                    }
            }
        }

    }
}
