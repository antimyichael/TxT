import SwiftUI

struct StatusBarView: View {
    let line: Int
    let column: Int
    let characterCount: Int
    let encodingName: String
    let lineEndingLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Text("Ln \(line), Col \(column)")
            Text("|")
                .foregroundStyle(.secondary)
            Text("\(characterCount) characters")
            Text("|")
                .foregroundStyle(.secondary)
            Text(encodingName)
            Text("|")
                .foregroundStyle(.secondary)
            Text(lineEndingLabel)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

enum StatusBarMetrics {
    static func lineColumn(string: String, utf16Location: Int) -> (line: Int, column: Int) {
        let s = string as NSString
        let n = s.length
        let loc = max(0, min(utf16Location, n))

        var line = 1
        var lineStart = 0
        var i = 0
        while i < loc {
            if i < n - 1, s.character(at: i) == 13, s.character(at: i + 1) == 10 {
                line += 1
                lineStart = i + 2
                i += 2
                continue
            }

            let c = s.character(at: i)
            if c == 10 || c == 13 {
                line += 1
                lineStart = i + 1
            }
            i += 1
        }

        let column = max(1, loc - lineStart + 1)
        return (line, column)
    }
}
