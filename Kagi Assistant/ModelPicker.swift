//
//  ModelPicker.swift
//  Kagi Assistant
//

import SwiftUI

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
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .frame(width: 14, height: 14)
                Text(selectedProfileName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
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
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredGroups: [ModelPicker.ProviderGroup] {
        if searchText.isEmpty { return groups }
        return groups.compactMap { group in
            let filtered = group.profiles.filter { profile in
                let name = profile.name ?? profile.model ?? ""
                return name.localizedCaseInsensitiveContains(searchText)
            }
            guard !filtered.isEmpty else { return nil }
            return ModelPicker.ProviderGroup(provider: group.provider, profiles: filtered)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search models…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .focused($isSearchFocused)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredGroups, id: \.provider) { (group: ModelPicker.ProviderGroup) in
                        ModelPopoverGroupView(group: group, groups: filteredGroups, viewModel: viewModel, showPopover: $showPopover)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding()
        .frame(minWidth: 200)
        .onAppear { isSearchFocused = true }
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
