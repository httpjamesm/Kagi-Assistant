//
//  ContentParser.swift
//  Kagi Assistant
//

import Foundation

enum ContentSegment: Identifiable, Equatable {
    case htmlContent(id: UUID = UUID(), html: String)
    case event(id: UUID = UUID(), title: String, content: String, isCompleted: Bool)

    var id: UUID {
        switch self {
        case .htmlContent(let id, _): return id
        case .event(let id, _, _, _): return id
        }
    }
}

enum ContentParser {
    private static let detailsPattern = try! NSRegularExpression(
        pattern: #"<details[^>]*>(.*?)</details>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let summaryPattern = try! NSRegularExpression(
        pattern: #"<summary[^>]*>(.*?)</summary>"#,
        options: [.dotMatchesLineSeparators]
    )

    static func parseContent(_ html: String, isStreaming: Bool) -> [ContentSegment] {
        let nsHTML = html as NSString
        let matches = detailsPattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        guard !matches.isEmpty else {
            let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return [] }
            return [.htmlContent(html: html)]
        }

        var segments: [ContentSegment] = []
        var cursor = 0

        for (i, match) in matches.enumerated() {
            // Content before this <details> block
            if match.range.location > cursor {
                let preceding = nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let trimmed = preceding.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(.htmlContent(html: preceding))
                }
            }

            // Parse the <details> block
            let detailsInner = nsHTML.substring(with: match.range(at: 1))
            let (title, content) = extractEvent(from: detailsInner)

            // An event is completed if another segment follows it, or if streaming is done
            let isLast = i == matches.count - 1
            let hasContentAfter: Bool = {
                let afterEnd = match.range.location + match.range.length
                if afterEnd < nsHTML.length {
                    let remaining = nsHTML.substring(from: afterEnd).trimmingCharacters(in: .whitespacesAndNewlines)
                    return !remaining.isEmpty
                }
                return false
            }()

            let completed = !isLast || hasContentAfter || !isStreaming

            segments.append(.event(title: title, content: content, isCompleted: completed))
            cursor = match.range.location + match.range.length
        }

        // Remaining content after last <details>
        if cursor < nsHTML.length {
            let remaining = nsHTML.substring(from: cursor)
            let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(.htmlContent(html: remaining))
            }
        }

        return segments
    }

    private static func extractEvent(from detailsInner: String) -> (title: String, content: String) {
        let ns = detailsInner as NSString
        guard let summaryMatch = summaryPattern.firstMatch(in: detailsInner, range: NSRange(location: 0, length: ns.length)) else {
            return ("Event", detailsInner)
        }

        var title = ns.substring(with: summaryMatch.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Clean up title: remove trailing colon, "from", and anything after <
        if let angleBracketRange = title.range(of: "<") {
            title = String(title[title.startIndex..<angleBracketRange.lowerBound])
        }
        title = title
            .replacingOccurrences(of: #":?\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+from\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if title.isEmpty { title = "Event" }

        // Content is everything after </summary>
        let summaryEnd = summaryMatch.range.location + summaryMatch.range.length
        let content = ns.substring(from: summaryEnd).trimmingCharacters(in: .whitespacesAndNewlines)

        return (title, content)
    }
}
