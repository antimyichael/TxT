import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let txtShowFindReplace = Notification.Name("txtShowFindReplace")
    static let txtToggleFindReplace = Notification.Name("txtToggleFindReplace")
    static let txtFindNext = Notification.Name("txtFindNext")
    static let txtFindPrevious = Notification.Name("txtFindPrevious")
    static let txtShowGoToLine = Notification.Name("txtShowGoToLine")
}

struct ContentView: View {
    @ObservedObject var document: TxTDocument

    @StateObject private var findController = FindReplaceController()

    @State private var showFindReplace = false
    @State private var showGoToLine = false
    @State private var statusTick: Int = 0

    private var editorString: String {
        _ = statusTick
        return document.currentEditorString()
    }

    private var caretUTF16: Int {
        _ = statusTick
        return document.textView?.selectedRange.location ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if showFindReplace {
                FindReplaceBar(controller: findController, isPresented: $showFindReplace)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            EditorView(
                document: document,
                onSelectionChange: { statusTick &+= 1 },
                onTextChange: { statusTick &+= 1 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if document.showStatusBar {
                let (line, col) = StatusBarMetrics.lineColumn(string: editorString, utf16Location: caretUTF16)
                StatusBarView(
                    line: line,
                    column: col,
                    characterCount: (editorString as NSString).length,
                    encodingName: document.encodingChoice.displayName,
                    lineEndingLabel: document.lineEnding.displayName
                )
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(nsColor: .textBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    guard let url else { return }
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                }
            }
            return true
        }
        .onAppear {
            document.updateWindowTitle()
            if let tv = document.textView {
                findController.bind(textView: tv)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .txtTextViewAttached)) { output in
            guard let doc = output.object as? TxTDocument, doc === document else { return }
            if let tv = document.textView {
                findController.bind(textView: tv)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .txtShowFindReplace)) { _ in
            guard TxTMenuActions.frontDocument() === document else { return }
            showFindReplace = true
            syncFindAfterToggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .txtToggleFindReplace)) { _ in
            guard TxTMenuActions.frontDocument() === document else { return }
            showFindReplace.toggle()
            syncFindAfterToggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .txtFindNext)) { _ in
            guard TxTMenuActions.frontDocument() === document else { return }
            showFindReplace = true
            syncFindAfterToggle()
            DispatchQueue.main.async {
                findController.findNext(wrap: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .txtFindPrevious)) { _ in
            guard TxTMenuActions.frontDocument() === document else { return }
            showFindReplace = true
            syncFindAfterToggle()
            DispatchQueue.main.async {
                findController.findPrevious(wrap: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .txtShowGoToLine)) { _ in
            guard TxTMenuActions.frontDocument() === document else { return }
            showGoToLine = true
        }
        .onChange(of: showFindReplace) { newValue in
            if newValue, let tv = document.textView {
                findController.bind(textView: tv)
                findController.refreshHighlightsAndCounts()
            } else {
                findController.clearHighlights()
            }
        }
        .background(LocalKeyMonitor(document: document, findController: findController, showFindReplace: $showFindReplace))
        .sheet(isPresented: $showGoToLine) {
            GoToLineSheet(
                isPresented: $showGoToLine,
                text: editorString,
                onGo: { line in
                    guard let loc = GoToLineLogic.utf16LocationForLineStart(line: line, in: editorString),
                          let tv = document.textView else { return }
                    tv.selectedRange = NSRange(location: loc, length: 0)
                    tv.scrollRangeToVisible(tv.selectedRange)
                    statusTick &+= 1
                }
            )
        }
    }

    private func syncFindAfterToggle() {
        if showFindReplace, let tv = document.textView {
            findController.bind(textView: tv)
            findController.refreshHighlightsAndCounts()
        } else {
            findController.clearHighlights()
        }
    }
}

private struct LocalKeyMonitor: NSViewRepresentable {
    let document: TxTDocument
    let findController: FindReplaceController
    @Binding var showFindReplace: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, findController: findController, showFindReplace: $showFindReplace)
    }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.isHidden = true
        context.coordinator.start()
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.document = document
        context.coordinator.findController = findController
        context.coordinator.showFindReplace = $showFindReplace
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var document: TxTDocument
        var findController: FindReplaceController
        var showFindReplace: Binding<Bool>
        private var monitor: Any?

        init(document: TxTDocument, findController: FindReplaceController, showFindReplace: Binding<Bool>) {
            self.document = document
            self.findController = findController
            self.showFindReplace = showFindReplace
        }

        func start() {
            stop()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard let win = NSApp.keyWindow,
                      win.windowController?.document as? TxTDocument === self.document else {
                    return event
                }

                let code = event.keyCode

                if code == 96 {
                    TxTMenuActions.insertTimeDate(in: self.document)
                    return nil
                }

                if code == 99 {
                    if event.modifierFlags.contains(.shift) {
                        NotificationCenter.default.post(name: .txtFindPrevious, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .txtFindNext, object: nil)
                    }
                    return nil
                }

                let key = event.charactersIgnoringModifiers ?? ""
                if key == "h", event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.option) {
                    if NSApp.keyWindow?.firstResponder is NSTextView {
                        NotificationCenter.default.post(name: .txtToggleFindReplace, object: nil)
                        return nil
                    }
                }

                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}
