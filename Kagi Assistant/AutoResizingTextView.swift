//
//  AutoResizingTextView.swift
//  Kagi Assistant
//

import SwiftUI
import AppKit

// MARK: - Auto-resizing NSTextView wrapper

private class InputTextView: NSTextView {
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            if event.modifierFlags.contains(.shift) {
                super.keyDown(with: event)
            } else {
                onSend?()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a",
           window?.firstResponder == self {
            selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct AutoResizingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var desiredHeight: CGFloat
    var maxLines: Int
    var placeholder: String
    var requestFocus: Bool = false
    var onSend: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = InputTextView()
        textView.onSend = onSend
        textView.delegate = context.coordinator
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 4
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Set initial single-line height
        let lineHeight = textView.font!.boundingRectForFont.height
        let inset = textView.textContainerInset
        DispatchQueue.main.async {
            self.desiredHeight = lineHeight + inset.height * 2
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? InputTextView else { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.recalcHeight()
        }

        if requestFocus != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = requestFocus
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        textView.onSend = onSend
        context.coordinator.parent = self
        context.coordinator.updatePlaceholder()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoResizingTextView
        weak var textView: NSTextView?
        var lastFocusTrigger = false
        private var placeholderView: NSTextField?

        init(_ parent: AutoResizingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            recalcHeight()
            updatePlaceholder()
        }

        func recalcHeight() {
            guard let textView else { return }

            let font = textView.font ?? NSFont.preferredFont(forTextStyle: .body)
            let lineHeight = font.boundingRectForFont.height
            let inset = textView.textContainerInset
            let singleLineHeight = lineHeight + inset.height * 2
            let maxHeight = lineHeight * CGFloat(parent.maxLines) + inset.height * 2

            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? lineHeight
            let naturalHeight = usedHeight + inset.height * 2

            let targetHeight = max(singleLineHeight, min(naturalHeight, maxHeight))

            DispatchQueue.main.async {
                self.parent.desiredHeight = targetHeight
            }
        }

        func updatePlaceholder() {
            guard let textView else { return }

            if placeholderView == nil {
                let field = NSTextField(labelWithString: parent.placeholder)
                field.textColor = .tertiaryLabelColor
                field.font = textView.font
                field.translatesAutoresizingMaskIntoConstraints = false
                textView.addSubview(field)

                let inset = textView.textContainerInset
                let padding = textView.textContainer?.lineFragmentPadding ?? 0
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: inset.width + padding),
                    field.topAnchor.constraint(equalTo: textView.topAnchor, constant: inset.height)
                ])
                placeholderView = field
            }

            placeholderView?.stringValue = parent.placeholder
            placeholderView?.isHidden = !textView.string.isEmpty
        }
    }
}
