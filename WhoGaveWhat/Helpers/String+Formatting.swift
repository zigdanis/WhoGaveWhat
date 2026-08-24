import Foundation

extension String {
    var initials: String {
        let letters = split(separator: " ").compactMap(\.first)
        return String(letters.prefix(2)).uppercased()
    }

    var lastWord: String {
        String(split(separator: " ").last ?? "")
    }

    var firstGrapheme: String {
        trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? ""
    }
}

enum LocalizedCount {
    static func gifts(_ count: Int) -> String { String(localized: "\(count) gifts") }
    static func people(_ count: Int) -> String { String(localized: "\(count) people") }
}
