import AppKit
import SwiftUI

final class TxTTextView: NSTextView {
    var onFontChange: (() -> Void)?

    override func changeFont(_ sender: Any?) {
        super.changeFont(sender)
        onFontChange?()
    }
}

struct EditorView: NSViewRepresentable {
    @ObservedObject var document: TxTDocument
    var onSelectionChange: () -> Void
    var onTextChange: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, onSelectionChange: onSelectionChange, onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]
        scroll.autohidesScrollers = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true

        let text = TxTTextView()
        text.drawsBackground = true
        text.backgroundColor = .textBackgroundColor
        text.textColor = .labelColor
        text.isRichText = false
        text.importsGraphics = false
        text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.usesFontPanel = true
        text.isVerticallyResizable = true
        text.textContainerInset = NSSize(width: 4, height: 4)
        text.delegate = context.coordinator
        text.onFontChange = { [weak text] in
            guard let text, let font = text.font else { return }
            Preferences.fontName = font.fontName
            Preferences.fontSize = font.pointSize
        }

        scroll.documentView = text
        context.coordinator.textView = text

        document.attachTextView(text)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: text
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: text
        )

        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.document = document
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onTextChange = onTextChange
        guard let text = scrollView.documentView as? TxTTextView else { return }
        document.applyEditorPreferences(to: text)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let text = nsView.documentView as? TxTTextView {
            NotificationCenter.default.removeObserver(coordinator, name: NSTextView.didChangeSelectionNotification, object: text)
            NotificationCenter.default.removeObserver(coordinator, name: NSText.didChangeNotification, object: text)
            coordinator.document.detachTextView(text)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: TxTDocument
        var onSelectionChange: () -> Void
        var onTextChange: () -> Void
        weak var textView: TxTTextView?

        init(document: TxTDocument, onSelectionChange: @escaping () -> Void, onTextChange: @escaping () -> Void) {
            self.document = document
            self.onSelectionChange = onSelectionChange
            self.onTextChange = onTextChange
        }

        @objc func selectionDidChange(_ notification: Notification) {
            onSelectionChange()
        }

        @objc func textDidChange(_ notification: Notification) {
            onTextChange()
        }
    }
}
