import Foundation

/// The live filter typed into the search field at the top of the window.
/// Matching ignores case and accents ("cafe" finds "Café", "isik" finds "Işık"); every word must appear.
enum Search {
    private(set) static var terms: [String] = []

    static var isActive: Bool { !terms.isEmpty }

    static func set(_ query: String) {
        terms = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func fold(_ s: String) -> String {
        // Folding leaves the dotless "ı" alone, so map it by hand.
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).replacingOccurrences(of: "ı", with: "i")
    }

    /// `folded` must already have gone through `fold`.
    static func matches(folded: String) -> Bool {
        terms.allSatisfy { folded.contains($0) }
    }

    static func matches(_ parts: String...) -> Bool {
        matches(folded: fold(parts.joined(separator: "\n")))
    }
}
