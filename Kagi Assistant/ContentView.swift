//
//  ContentView.swift
//  Kagi Assistant
//
//  Created by James on 2026-03-22.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = ChatViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            ChatView(viewModel: viewModel)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
