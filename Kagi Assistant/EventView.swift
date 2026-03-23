//
//  EventView.swift
//  Kagi Assistant
//

import SwiftUI
import WebKit

struct EventView: View {
    let title: String
    let content: String
    let isCompleted: Bool

    @State private var isExpanded = false
    @State private var webViewHeight: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    if isCompleted {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        ShimmerText(text: title)
                    }

                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded && !content.isEmpty {
                Divider()
                    .padding(.horizontal, 8)

                HTMLMessageView(html: content, dynamicHeight: $webViewHeight)
                    .frame(height: webViewHeight)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Shimmer Text

struct ShimmerText: View {
    let text: String

    @State private var phase: CGFloat = 0

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.4), location: max(0, phase - 0.15)),
                                .init(color: .white, location: phase),
                                .init(color: .white.opacity(0.4), location: min(1, phase + 0.15)),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}
