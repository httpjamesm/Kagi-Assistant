//
//  SourcesButton.swift
//  Kagi Assistant
//

import SwiftUI

struct SourcesButton: View {
    let citations: [KagiCitation]

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                StackedFavicons(citations: citations)
                Text("Sources")
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SourcesPopover(citations: citations)
        }
    }
}

private struct StackedFavicons: View {
    let citations: [KagiCitation]

    private let size: CGFloat = 16
    private let overlap: CGFloat = 8

    private var uniqueHosts: [String] {
        var seen = Set<String>()
        var hosts: [String] = []
        for citation in citations {
            if let host = URL(string: citation.url)?.host, seen.insert(host).inserted {
                hosts.append(host)
            }
            if hosts.count == 3 { break }
        }
        return hosts
    }

    var body: some View {
        let hosts = uniqueHosts
        let totalWidth = size + CGFloat(hosts.count - 1) * overlap

        ZStack(alignment: .leading) {
            ForEach(Array(hosts.enumerated()), id: \.element) { idx, host in
                AsyncImage(url: URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")) { image in
                    image
                        .resizable()
                        .frame(width: size, height: size)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                } placeholder: {
                    Image(systemName: "globe")
                        .font(.system(size: 9))
                        .frame(width: size, height: size)
                        .background(Color.white)
                        .foregroundStyle(.secondary)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                }
                .offset(x: CGFloat(idx) * overlap)
                .zIndex(Double(hosts.count - idx))
            }
        }
        .frame(width: totalWidth, alignment: .leading)
        .fixedSize()
    }
}

private struct SourcesPopover: View {
    let citations: [KagiCitation]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(citations.enumerated()), id: \.offset) { idx, citation in
                    if idx > 0 {
                        Divider()
                            .padding(.horizontal, 12)
                    }

                    SourceRow(index: idx + 1, citation: citation)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 320)
        .frame(maxHeight: 400)
    }
}

private struct SourceRow: View {
    let index: Int
    let citation: KagiCitation

    private var host: String {
        URL(string: citation.url)?.host ?? citation.url
    }

    private var faviconURL: URL? {
        guard let host = URL(string: citation.url)?.host else { return nil }
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }

    var body: some View {
        Link(destination: URL(string: citation.url) ?? URL(string: "about:blank")!) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(index)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)

                AsyncImage(url: faviconURL) { image in
                    image
                        .resizable()
                        .frame(width: 16, height: 16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } placeholder: {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.title)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(host)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
