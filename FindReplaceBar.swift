import AppKit
import SwiftUI

@MainActor
final class FindReplaceController: ObservableObject {
    weak var textView: NSTextView?

    @Published var findText: String = ""
    @Published var replaceText: String = ""
    @Published var matchCase: Bool = false
    @Published var currentOrdinal: Int = 0
    @Published var totalMatches: Int = 0

    private(set) var cachedRanges: [NSRange] = []

    func bind(textView: NSTextView) {
        self.textView = textView
        refreshHighlightsAndCounts()
    }

    func refreshHighlightsAndCounts() {
        guard let tv = textView, let lm = tv.layoutManager else {
            cachedRanges = []
            totalMatches = 0
            currentOrdinal = 0
            return
        }

        let string = tv.string as NSString
        let length = string.length
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))

        let pattern = findText
        if pattern.isEmpty || length == 0 {
            cachedRanges = []
            totalMatches = 0
            currentOrdinal = 0
            return
        }

        let options: NSString.CompareOptions = matchCase ? [] : .caseInsensitive
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: length)

        while searchRange.length > 0 {
            let r = string.range(of: pattern, options: options, range: searchRange)
            if r.location == NSNotFound {
                break
            }
            ranges.append(r)
            let next = r.location + max(1, r.length)
            if next >= length {
                break
            }
            searchRange = NSRange(location: next, length: length - next)
        }

        cachedRanges = ranges
        totalMatches = ranges.count

        for r in ranges {
            lm.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.45),
                forCharacterRange: r
            )
        }

        if totalMatches == 0 {
            currentOrdinal = 0
            return
        }

        let caret = tv.selectedRange.location
        currentOrdinal = ordinal(forUTF16Location: caret, ranges: ranges)
    }

    private func ordinal(forUTF16Location caret: Int, ranges: [NSRange]) -> Int {
        guard !ranges.isEmpty else { return 0 }

        for (i, r) in ranges.enumerated() {
            if NSLocationInRange(caret, r) || caret == r.location {
                return i + 1
            }
        }

        for (i, r) in ranges.enumerated() where r.location > caret {
            return i + 1
        }

        return ranges.count
    }

    func clearHighlights() {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        let length = (tv.string as NSString).length
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        cachedRanges = []
        totalMatches = 0
        currentOrdinal = 0
    }

    func findNext(wrap: Bool) {
        guard let tv = textView else { return }
        refreshHighlightsAndCounts()
        guard !cachedRanges.isEmpty else { return }

        let sel = tv.selectedRange

        if let i = cachedRanges.firstIndex(where: { NSEqualRanges($0, sel) }) {
            let next = i + 1
            if next < cachedRanges.count {
                selectMatch(tv: tv, index: next)
            } else if wrap {
                selectMatch(tv: tv, index: 0)
            }
            return
        }

        let anchor = sel.length > 0 ? NSMaxRange(sel) : sel.location
        if let idx = cachedRanges.firstIndex(where: { $0.location >= anchor }) {
            selectMatch(tv: tv, index: idx)
            return
        }

        if wrap {
            selectMatch(tv: tv, index: 0)
        }
    }

    func findPrevious(wrap: Bool) {
        guard let tv = textView else { return }
        refreshHighlightsAndCounts()
        guard !cachedRanges.isEmpty else { return }

        let sel = tv.selectedRange

        if let i = cachedRanges.firstIndex(where: { NSEqualRanges($0, sel) }) {
            let prev = i - 1
            if prev >= 0 {
                selectMatch(tv: tv, index: prev)
            } else if wrap, let last = cachedRanges.indices.last {
                selectMatch(tv: tv, index: last)
            }
            return
        }

        let anchor = sel.location
        if let idx = cachedRanges.lastIndex(where: { NSMaxRange($0) <= anchor }) {
            selectMatch(tv: tv, index: idx)
            return
        }

        if wrap, let last = cachedRanges.indices.last {
            selectMatch(tv: tv, index: last)
        }
    }

    private func selectMatch(tv: NSTextView, index: Int) {
        guard cachedRanges.indices.contains(index) else { return }
        let r = cachedRanges[index]
        tv.selectedRange = r
        tv.scrollRangeToVisible(r)
        currentOrdinal = index + 1
    }

    func replaceOne() {
        guard let tv = textView else { return }
        refreshHighlightsAndCounts()
        guard !cachedRanges.isEmpty else { return }

        let sel = tv.selectedRange
        if let idx = cachedRanges.firstIndex(where: { NSEqualRanges($0, sel) }) {
            tv.insertText(replaceText, replacementRange: sel)
            tv.didChangeText()
            refreshHighlightsAndCounts()
            if !cachedRanges.isEmpty {
                let nextIndex = min(idx, cachedRanges.count - 1)
                selectMatch(tv: tv, index: nextIndex)
            }
            return
        }

        findNext(wrap: true)
        let newSel = tv.selectedRange
        if cachedRanges.contains(where: { NSEqualRanges($0, newSel) }) {
            tv.insertText(replaceText, replacementRange: newSel)
            tv.didChangeText()
            refreshHighlightsAndCounts()
            if !cachedRanges.isEmpty {
                selectMatch(tv: tv, index: 0)
            }
        }
    }

    func replaceAll() {
        guard let tv = textView else { return }
        let pattern = findText
        if pattern.isEmpty {
            return
        }

        let options: NSString.CompareOptions = matchCase ? [] : .caseInsensitive
        let ns = NSMutableString(string: tv.string)

        while true {
            let r = ns.range(of: pattern, options: options)
            if r.location == NSNotFound {
                break
            }
            ns.replaceCharacters(in: r, with: replaceText)
        }

        tv.string = String(ns)
        tv.didChangeText()
        refreshHighlightsAndCounts()
    }
}

struct FindReplaceBar: View {
    @ObservedObject var controller: FindReplaceController
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Find:")
                    .frame(width: 56, alignment: .trailing)
                TextField("", text: $controller.findText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: controller.findText) { _ in
                        controller.refreshHighlightsAndCounts()
                    }

                Text("Replace:")
                    .frame(width: 56, alignment: .trailing)
                TextField("", text: $controller.replaceText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Toggle("Match case", isOn: $controller.matchCase)
                    .toggleStyle(.checkbox)
                    .onChange(of: controller.matchCase) { _ in
                        controller.refreshHighlightsAndCounts()
                    }

                Spacer(minLength: 8)

                Button("Find Next") {
                    controller.findNext(wrap: true)
                }

                Button("Find Previous") {
                    controller.findPrevious(wrap: true)
                }

                Button("Replace") {
                    controller.replaceOne()
                }

                Button("Replace All") {
                    controller.replaceAll()
                }

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack {
                if controller.totalMatches == 0, !controller.findText.isEmpty {
                    Text("0 of 0 matches")
                        .foregroundStyle(.secondary)
                } else if controller.totalMatches == 0 {
                    Text(" ")
                } else {
                    Text("\(controller.currentOrdinal) of \(controller.totalMatches) matches")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.caption)
        }
        .padding(10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onExitCommand {
            isPresented = false
        }
    }
}
