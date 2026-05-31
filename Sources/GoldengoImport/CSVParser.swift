import Foundation

public enum CSVParser {
    /// Parses CSV text into rows of fields. Handles quoted fields containing commas,
    /// escaped quotes (`""`), and newlines; trims unquoted field whitespace; skips blank lines.
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var wasQuoted = false
        let chars = Array(text)
        var i = 0

        func endField() {
            row.append(wasQuoted ? field : field.trimmingCharacters(in: .whitespaces))
            field = ""; wasQuoted = false
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true; wasQuoted = true
                case ",": endField()
                case "\n": endRow()
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
