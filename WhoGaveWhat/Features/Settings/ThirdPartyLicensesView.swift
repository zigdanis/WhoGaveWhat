import SwiftUI

struct ThirdPartyLicensesView: View {
    @State private var blocks: [LicenseBlock] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(blocks) { block in
                    LicenseBlockView(block: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(16)
        }
        .background(Color.bg)
        .navigationTitle("Third-party licenses")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            blocks = loadNotice()
        }
    }

    private func loadNotice() -> [LicenseBlock] {
        let resources = [
            (name: "THIRD_PARTY_NOTICES", extension: "md"),
            (name: "Archivo-OFL", extension: "txt")
        ]
        let documents = resources.compactMap { resource -> String? in
            guard
                let url = Bundle.main.url(
                    forResource: resource.name,
                    withExtension: resource.extension)
            else {
                return nil
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        guard documents.count == resources.count else {
            return [
                LicenseBlock(
                    id: 0,
                    kind: .paragraph,
                    text: String(localized: "License information is unavailable."))
            ]
        }

        let markdown = documents.joined(separator: "\n\n---\n\n# Archivo license\n\n")
        return LicenseBlock.parse(markdown)
    }
}

private struct LicenseBlock: Identifiable {
    enum Kind {
        case heading(level: Int)
        case paragraph
        case divider
    }

    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [LicenseBlock] {
        var parsed: [(Kind, String)] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            parsed.append((.paragraph, paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                flushParagraph()
                continue
            }

            if line.allSatisfy({ $0 == "-" }) && line.count >= 3 {
                flushParagraph()
                parsed.append((.divider, ""))
            } else if line.first == "#" {
                flushParagraph()
                let level = min(line.prefix(while: { $0 == "#" }).count, 3)
                let title = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                parsed.append((.heading(level: level), title))
            } else if isPlainTextHeading(line) {
                flushParagraph()
                parsed.append((.heading(level: 3), line))
            } else {
                paragraphLines.append(line)
            }
        }
        flushParagraph()

        return parsed.enumerated().map { index, value in
            LicenseBlock(id: index, kind: value.0, text: value.1)
        }
    }

    private static func isPlainTextHeading(_ line: String) -> Bool {
        line.count < 60 && line.rangeOfCharacter(from: .letters) != nil && line == line.uppercased() && !line.contains("http")
    }
}

private struct LicenseBlockView: View {
    let block: LicenseBlock

    var body: some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text)
                .font(level == 1 ? .title2.bold() : .headline)
                .foregroundColor(Color.ink)
                .padding(.top, level == 1 ? 8 : 2)
        case .paragraph:
            Text(inlineMarkdown)
                .font(.body)
                .foregroundColor(Color.ink)
        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private var inlineMarkdown: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: block.text, options: options))
            ?? AttributedString(block.text)
    }
}
