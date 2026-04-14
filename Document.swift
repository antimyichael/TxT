import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let txtTextViewAttached = Notification.Name("txtTextViewAttached")
}

enum LineEndingStyle: String, CaseIterable, Identifiable {
    case crlf
    case lf
    case cr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crlf: return "Windows (CRLF)"
        case .lf: return "Unix (LF)"
        case .cr: return "Old Mac (CR)"
        }
    }

    var separator: String {
        switch self {
        case .crlf: return "\r\n"
        case .lf: return "\n"
        case .cr: return "\r"
        }
    }

    static func detect(in string: String) -> LineEndingStyle {
        let crlf = string.components(separatedBy: "\r\n").count - 1
        let lfOnly = {
            var n = 0
            var i = string.startIndex
            while i < string.endIndex {
                if string[i] == "\n" {
                    let prev = string.index(before: i)
                    if string[prev] != "\r" {
                        n += 1
                    }
                }
                i = string.index(after: i)
            }
            return n
        }()
        let crOnly = {
            var n = 0
            var i = string.startIndex
            while i < string.endIndex {
                if string[i] == "\r" {
                    let next = string.index(after: i)
                    if next == string.endIndex || string[next] != "\n" {
                        n += 1
                    }
                }
                i = string.index(after: i)
            }
            return n
        }()

        if crlf >= lfOnly, crlf >= crOnly, crlf > 0 {
            return .crlf
        }
        if crOnly > lfOnly, crOnly > 0 {
            return .cr
        }
        return .lf
    }

    func apply(to string: String) -> String {
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let parts = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        return parts.map(String.init).joined(separator: separator)
    }
}

enum EncodingChoice: String, CaseIterable, Identifiable {
    case utf8
    case windows1252

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .windows1252: return "ANSI (Windows-1252)"
        }
    }

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .windows1252: return .windowsCP1252
        }
    }

    static func fromStored(_ raw: String) -> EncodingChoice {
        EncodingChoice(rawValue: raw) ?? .utf8
    }

    static func detect(for data: Data) -> EncodingChoice {
        if data.isEmpty {
            return .utf8
        }
        if data.isValidUTF8 {
            return .utf8
        }
        return .windows1252
    }
}

private extension Data {
    var isValidUTF8: Bool {
        withUnsafeBytes { raw -> Bool in
            let ptr = raw.bindMemory(to: UInt8.self).baseAddress
            guard let ptr else { return true }
            var idx = 0
            let len = count
            while idx < len {
                let b0 = ptr[idx]
                if b0 & 0x80 == 0 {
                    idx += 1
                    continue
                }
                var need = 0
                if (b0 & 0xE0) == 0xC0 { need = 1 }
                else if (b0 & 0xF0) == 0xE0 { need = 2 }
                else if (b0 & 0xF8) == 0xF0 { need = 3 }
                else { return false }
                for j in 1 ... need {
                    let k = idx + j
                    if k >= len { return false }
                    let bn = ptr[k]
                    if (bn & 0xC0) != 0x80 { return false }
                }
                idx += need + 1
            }
            return true
        }
    }
}

final class TxTDocument: NSDocument, ObservableObject {
    override class var autosavesInPlace: Bool { false }

    @Published var lineEnding: LineEndingStyle = .lf
    @Published var encodingChoice: EncodingChoice = .utf8
    @Published var wordWrap: Bool = Preferences.wordWrap
    @Published var showStatusBar: Bool = Preferences.statusBarVisible

    weak var textView: NSTextView?

    override init() {
        super.init()
        encodingChoice = EncodingChoice.fromStored(Preferences.lastEncodingRaw)
        wordWrap = Preferences.wordWrap
        showStatusBar = Preferences.statusBarVisible
    }

    required init?(coder: NSCoder) {
        super.init()
        encodingChoice = EncodingChoice.fromStored(Preferences.lastEncodingRaw)
        wordWrap = Preferences.wordWrap
        showStatusBar = Preferences.statusBarVisible
    }

    override func makeWindowControllers() {
        let content = ContentView(document: self)
        let hosting = NSHostingController(rootView: content)
        hosting.identifier = NSUserInterfaceItemIdentifier("TxTContent")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 400, height: 300)
        window.setFrameAutosaveName("TxTMainWindow")
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]

        if let saved = Preferences.windowFrameString() {
            let rect = NSRectFromString(saved)
            if rect.width >= window.minSize.width, rect.height >= window.minSize.height {
                window.setFrame(rect, display: false)
            }
        }

        window.delegate = self

        let wc = NSWindowController(window: window)
        addWindowController(wc)
        wc.shouldCascadeWindows = true
        wc.showWindow(nil)

        updateWindowTitle()
    }

    func attachTextView(_ tv: NSTextView) {
        textView = tv
        if let pending = pendingInitialText {
            tv.string = pending
            pendingInitialText = nil
            tv.selectedRange = NSRange(location: 0, length: 0)
            tv.scrollToBeginningOfDocument(nil)
            tv.undoManager?.removeAllActions()
            updateChangeCount(.changeCleared)
        }
        applyEditorPreferences(to: tv)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: tv
        )

        NotificationCenter.default.post(name: .txtTextViewAttached, object: self)
    }

    func detachTextView(_ tv: NSTextView) {
        if textView === tv {
            NotificationCenter.default.removeObserver(self, name: NSText.didChangeNotification, object: tv)
            textView = nil
        }
    }

    @objc private func textDidChange(_ note: Notification) {
        objectWillChange.send()
        updateChangeCount(.changeDone)
        updateWindowTitle()
    }

    private var pendingInitialText: String?

    override func read(from data: Data, ofType typeName: String) throws {
        let enc = EncodingChoice.detect(for: data)
        encodingChoice = enc
        let decoded: String
        if enc == .utf8 {
            decoded = String(decoding: data, as: UTF8.self)
        } else {
            decoded = String(data: data, encoding: enc.stringEncoding) ?? ""
        }
        lineEnding = LineEndingStyle.detect(in: decoded)
        pendingInitialText = decoded
        objectWillChange.send()
    }

    override func data(ofType typeName: String) throws -> Data {
        let raw = textView?.string ?? pendingInitialText ?? ""
        let withLE = lineEnding.apply(to: raw)
        let enc = encodingChoice.stringEncoding
        guard let data = withLE.data(using: enc, allowLossyConversion: true) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        let data = try data(ofType: typeName)
        return FileWrapper(regularFileWithContents: data)
    }

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        guard let data = fileWrapper.regularFileContents else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: nil)
        }
        try read(from: data, ofType: typeName)
    }

    override func write(to url: URL, ofType typeName: String) throws {
        let data = try data(ofType: typeName)
        try data.write(to: url, options: .atomic)
    }

    override var autosavingFileType: String? { nil }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        Preferences.lastEncodingRaw = encodingChoice.rawValue
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    func currentEditorString() -> String {
        textView?.string ?? pendingInitialText ?? ""
    }

    func updateWindowTitle() {
        guard let wc = windowControllers.first, let window = wc.window else { return }
        let name: String
        if let url = fileURL {
            name = url.lastPathComponent
        } else {
            name = displayName
        }
        window.title = "\(name) — TxT"
    }

    override var fileURL: URL? {
        get { super.fileURL }
        set {
            super.fileURL = newValue
            updateWindowTitle()
        }
    }

    func applyEditorPreferences(to textView: NSTextView) {
        let font = Preferences.resolvedEditorFont()
        textView.font = font
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFontPanel = true
        textView.allowsUndo = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)

        guard let scroll = textView.enclosingScrollView,
              let container = textView.textContainer else { return }

        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.borderType = .noBorder

        if wordWrap {
            scroll.hasHorizontalScroller = false
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
        } else {
            scroll.hasHorizontalScroller = true
            container.widthTracksTextView = false
            let width = max(scroll.contentSize.width, textView.bounds.width)
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            textView.sizeToFit()
        }

        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func setWordWrap(_ on: Bool) {
        wordWrap = on
        Preferences.wordWrap = on
        if let tv = textView {
            applyEditorPreferences(to: tv)
        }
        objectWillChange.send()
    }

    func setStatusBarVisible(_ on: Bool) {
        showStatusBar = on
        Preferences.statusBarVisible = on
        objectWillChange.send()
    }

    func setLineEnding(_ style: LineEndingStyle) {
        lineEnding = style
        objectWillChange.send()
    }

    func setEncodingChoice(_ enc: EncodingChoice) {
        encodingChoice = enc
        Preferences.lastEncodingRaw = enc.rawValue
        objectWillChange.send()
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let textView else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [NSLocalizedDescriptionKey: "No editor"])
        }
        let info = printInfo
        let op = NSPrintOperation(view: textView, printInfo: info)
        op.printPanel.options = [.showsPaperSize, .showsOrientation, .showsScaling, .showsPreview]
        return op
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        let acc = SaveEncodingAccessoryView(document: self)
        savePanel.accessoryView = acc
        savePanel.allowedContentTypes = [.plainText]
        savePanel.allowsOtherFileTypes = true
        if savePanel.nameFieldStringValue.isEmpty {
            let base: String
            if let url = fileURL {
                base = url.deletingPathExtension().lastPathComponent
            } else {
                base = displayName
            }
            savePanel.nameFieldStringValue = base.hasSuffix(".txt") ? base : "\(base).txt"
        }
        return true
    }
}

final class SaveEncodingAccessoryView: NSView {
    private weak var document: TxTDocument?
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(document: TxTDocument) {
        self.document = document
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Encoding:")
        label.translatesAutoresizingMaskIntoConstraints = false

        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.addItems(withTitles: [EncodingChoice.utf8.displayName, EncodingChoice.windows1252.displayName])
        popup.selectItem(at: document.encodingChoice == .utf8 ? 0 : 1)
        popup.target = self
        popup.action = #selector(changed(_:))

        addSubview(label)
        addSubview(popup)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            popup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            popup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            popup.centerYAnchor.constraint(equalTo: centerYAnchor),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func changed(_ sender: NSPopUpButton) {
        let choice: EncodingChoice = sender.indexOfSelectedItem == 0 ? .utf8 : .windows1252
        document?.setEncodingChoice(choice)
    }
}

extension TxTDocument: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Preferences.setWindowFrameString(NSStringFromRect(window.frame))
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Preferences.setWindowFrameString(NSStringFromRect(window.frame))
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Preferences.setWindowFrameString(NSStringFromRect(window.frame))
    }
}
