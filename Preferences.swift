import AppKit
import Foundation

enum Preferences {
    private enum Keys {
        static let windowFrame = "txt.window.frame"
        static let fontName = "txt.font.name"
        static let fontSize = "txt.font.size"
        static let wordWrap = "txt.wordWrap"
        static let statusBarVisible = "txt.statusBar.visible"
        static let lastEncoding = "txt.encoding.last"
    }

    static var wordWrap: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.wordWrap) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.wordWrap)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.wordWrap) }
    }

    static var statusBarVisible: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.statusBarVisible) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.statusBarVisible)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.statusBarVisible) }
    }

    static var fontName: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Keys.fontName)
            if let stored, NSFont(name: stored, size: 12) != nil {
                return stored
            }
            if NSFont(name: "SF Mono", size: 12) != nil {
                return "SF Mono"
            }
            return "Menlo"
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.fontName) }
    }

    static var fontSize: CGFloat {
        get {
            let v = UserDefaults.standard.double(forKey: Keys.fontSize)
            if v < 1 {
                return 11
            }
            return CGFloat(v)
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: Keys.fontSize) }
    }

    static var lastEncodingRaw: String {
        get {
            UserDefaults.standard.string(forKey: Keys.lastEncoding) ?? "utf8"
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastEncoding) }
    }

    static func resolvedEditorFont() -> NSFont {
        let name = fontName
        let size = max(6, min(72, fontSize))
        if let f = NSFont(name: name, size: size) {
            return f
        }
        if let mono = NSFont(name: "Menlo", size: size) {
            return mono
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func windowFrameString() -> String? {
        UserDefaults.standard.string(forKey: Keys.windowFrame)
    }

    static func setWindowFrameString(_ string: String?) {
        UserDefaults.standard.set(string, forKey: Keys.windowFrame)
    }
}
