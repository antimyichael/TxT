import SwiftUI

enum GoToLineLogic {
    static func totalLines(in string: String) -> Int {
        if string.isEmpty {
            return 1
        }
        let ns = string as NSString
        var lines = 1
        var i = 0
        while i < ns.length {
            if i < ns.length - 1, ns.character(at: i) == 13, ns.character(at: i + 1) == 10 {
                lines += 1
                i += 2
                continue
            }
            let c = ns.character(at: i)
            if c == 10 || c == 13 {
                lines += 1
            }
            i += 1
        }
        return max(1, lines)
    }

    static func utf16LocationForLineStart(line: Int, in string: String) -> Int? {
        guard line >= 1 else { return nil }
        if line == 1 {
            return 0
        }

        let ns = string as NSString
        var currentLine = 1
        var i = 0

        while i < ns.length {
            if i < ns.length - 1, ns.character(at: i) == 13, ns.character(at: i + 1) == 10 {
                currentLine += 1
                if currentLine == line {
                    return i + 2
                }
                i += 2
                continue
            }

            let c = ns.character(at: i)
            if c == 10 || c == 13 {
                currentLine += 1
                if currentLine == line {
                    return i + 1
                }
            }
            i += 1
        }

        return nil
    }
}

struct GoToLineSheet: View {
    @Binding var isPresented: Bool
    let text: String
    let onGo: (Int) -> Void

    @State private var lineText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go To Line")
                .font(.headline)

            Text("Line number:")
            TextField("Line number", text: $lineText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Go") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        .onAppear {
            errorMessage = nil
        }
    }

    private func submit() {
        errorMessage = nil
        let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else {
            errorMessage = "Enter a valid line number."
            return
        }

        let total = GoToLineLogic.totalLines(in: text)
        if value < 1 || value > total {
            errorMessage = "Line number is out of range (1–\(total))."
            return
        }

        onGo(value)
        isPresented = false
    }
}
