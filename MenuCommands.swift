import AppKit
import SwiftUI

enum TxTMenuActions {
    static func frontDocument() -> TxTDocument? {
        NSApp.keyWindow?.windowController?.document as? TxTDocument
    }

    static func save(_ sender: Any?) {
        guard let doc = frontDocument() else { return }
        doc.save(sender)
    }

    static func saveAs(_ sender: Any?) {
        guard let doc = frontDocument() else { return }
        doc.saveAs(sender)
    }

    static func pageSetup(_ sender: Any?) {
        guard let doc = frontDocument() else { return }
        let printInfo = doc.printInfo
        let layout = NSPageLayout()

        if let window = doc.windowControllers.first?.window {
            if #available(macOS 14.0, *) {
                layout.beginSheet(using: printInfo, on: window) { result in
                    DispatchQueue.main.async {
                        guard result == .changed else { return }
                        doc.printInfo = printInfo
                    }
                }
            } else {
                // Fallback for older macOS where completion-handler sheet API is unavailable.
                let response = layout.runModal(with: printInfo)
                if response == NSApplication.ModalResponse.OK.rawValue {
                    doc.printInfo = printInfo
                }
            }
        } else {
            let response = layout.runModal(with: printInfo)
            if response == NSApplication.ModalResponse.OK.rawValue {
                doc.printInfo = printInfo
            }
        }
    }

    static func printDocument(_ sender: Any?) {
        guard let doc = frontDocument() else { return }
        doc.printDocument(sender)
    }

    static func insertTimeDateInFrontDocument() {
        guard let doc = frontDocument() else { return }
        insertTimeDate(in: doc)
    }

    static func insertTimeDate(in document: TxTDocument) {
        guard let tv = document.textView else { return }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "h:mm a M/d/yyyy"
        let text = formatter.string(from: Date())
        tv.insertText(text, replacementRange: tv.selectedRange)
        tv.didChangeText()
    }

    static func setLineEnding(_ style: LineEndingStyle) {
        guard let doc = frontDocument() else { return }
        doc.setLineEnding(style)
    }

    static func orderFrontFontPanel() {
        guard let doc = frontDocument(), let tv = doc.textView else { return }
        tv.window?.makeFirstResponder(tv)
        NSFontManager.shared.target = tv
        NSFontPanel.shared.orderFront(tv)
    }

    static func zoomIn() {
        adjustZoom(by: 2)
    }

    static func zoomOut() {
        adjustZoom(by: -2)
    }

    static func zoomReset() {
        Preferences.fontSize = 11
        Preferences.fontName = NSFont(name: "SF Mono", size: 11)?.fontName ?? "Menlo"
        reapplyFontToAllDocuments()
    }

    private static func adjustZoom(by delta: CGFloat) {
        let next = max(6, min(72, Preferences.fontSize + delta))
        Preferences.fontSize = next
        reapplyFontToAllDocuments()
    }

    private static func reapplyFontToAllDocuments() {
        for case let doc as TxTDocument in NSDocumentController.shared.documents {
            if let tv = doc.textView {
                doc.applyEditorPreferences(to: tv)
            }
        }
    }

    static func toggleStatusBar() {
        let next = !Preferences.statusBarVisible
        Preferences.statusBarVisible = next
        for case let doc as TxTDocument in NSDocumentController.shared.documents {
            doc.setStatusBarVisible(next)
        }
    }

    static func showHelp() {
        let alert = NSAlert()
        alert.messageText = "TxT Help"
        alert.informativeText = "TxT is a plain-text editor for macOS.\n\nUse the menus to open, edit, save, and print text files."
        alert.runModal()
    }
}

struct TxTCommands: Commands {
    @ObservedObject var recentModel: RecentDocumentsModel

    var body: some Commands {
        CommandGroup(replacing: .appVisibility) {
            Button("Hide TxT") {
                NSApp.hide(nil)
            }
            .keyboardShortcut("h", modifiers: [.command, .option])

            Button("Hide Others") {
                NSApp.hideOtherApplications(nil)
            }
            .keyboardShortcut("h", modifiers: [.command, .option, .shift])

            Button("Show All") {
                NSApp.unhideAllApplications(nil)
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New") {
                NSDocumentController.shared.newDocument(nil)
            }
            .keyboardShortcut("n")

            Button("Open…") {
                NSDocumentController.shared.openDocument(nil)
            }
            .keyboardShortcut("o")

            Menu("Open Recent") {
                ForEach(recentModel.urls, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                    }
                }

                if !recentModel.urls.isEmpty {
                    Divider()
                }

                Button("Clear Menu") {
                    NSDocumentController.shared.clearRecentDocuments(nil)
                    recentModel.refresh()
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                TxTMenuActions.save(nil)
            }
            .keyboardShortcut("s")

            Button("Save As…") {
                TxTMenuActions.saveAs(nil)
            }
            .keyboardShortcut("s", modifiers: [.shift, .command])
        }

        CommandGroup(replacing: .printItem) {
            Button("Page Setup…") {
                TxTMenuActions.pageSetup(nil)
            }
            .keyboardShortcut("p", modifiers: [.shift, .command])

            Button("Print…") {
                TxTMenuActions.printDocument(nil)
            }
            .keyboardShortcut("p")
        }

        CommandGroup(after: .pasteboard) {
            Button("Delete") {
                NSApp.sendAction(NSSelectorFromString("delete:"), to: nil, from: nil)
            }
            .keyboardShortcut(.delete, modifiers: [])

            Divider()

            Button("Find/Replace…") {
                NotificationCenter.default.post(name: .txtShowFindReplace, object: nil)
            }
            .keyboardShortcut("h", modifiers: [.command])

            Button("Find Next") {
                NotificationCenter.default.post(name: .txtFindNext, object: nil)
            }

            Button("Find Previous") {
                NotificationCenter.default.post(name: .txtFindPrevious, object: nil)
            }

            Divider()

            Button("Go To…") {
                NotificationCenter.default.post(name: .txtShowGoToLine, object: nil)
            }
            .keyboardShortcut("g", modifiers: [.command])

            Divider()

            Button("Time/Date") {
                TxTMenuActions.insertTimeDateInFrontDocument()
            }
        }

        CommandMenu("Format") {
            Toggle("Word Wrap", isOn: Binding(
                get: { Preferences.wordWrap },
                set: { newValue in
                    Preferences.wordWrap = newValue
                    for case let doc as TxTDocument in NSDocumentController.shared.documents {
                        doc.setWordWrap(newValue)
                    }
                }
            ))

            Button("Font…") {
                TxTMenuActions.orderFrontFontPanel()
            }

            Divider()

            Menu("Line Endings") {
                Button("Windows (CRLF)") {
                    TxTMenuActions.setLineEnding(.crlf)
                }
                Button("Unix (LF)") {
                    TxTMenuActions.setLineEnding(.lf)
                }
                Button("Old Mac (CR)") {
                    TxTMenuActions.setLineEnding(.cr)
                }
            }
        }

        CommandMenu("View") {
            Button("Zoom In") {
                TxTMenuActions.zoomIn()
            }
            .keyboardShortcut("=", modifiers: [.command])

            Button("Zoom Out") {
                TxTMenuActions.zoomOut()
            }
            .keyboardShortcut("-", modifiers: [.command])

            Button("Restore Default Zoom") {
                TxTMenuActions.zoomReset()
            }
            .keyboardShortcut("0", modifiers: [.command])

            Divider()

            Toggle("Status Bar", isOn: Binding(
                get: { Preferences.statusBarVisible },
                set: { newValue in
                    Preferences.statusBarVisible = newValue
                    for case let doc as TxTDocument in NSDocumentController.shared.documents {
                        doc.setStatusBarVisible(newValue)
                    }
                }
            ))
        }

        CommandGroup(after: .appInfo) {
            Button("TxT Help") {
                TxTMenuActions.showHelp()
            }
        }
    }
}

final class RecentDocumentsModel: ObservableObject {
    @Published var urls: [URL] = []

    func refresh() {
        urls = NSDocumentController.shared.recentDocumentURLs
    }
}
