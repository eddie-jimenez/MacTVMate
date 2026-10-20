import Foundation

/// Channel-name normalisation shared by guide matching (runs off the main actor while parsing).
enum ChannelMatch {
    /// "US HGTV (East) (A)", "HGTV East" and "USA: HGTV HD" all become "hgtv".
    static func normalise(_ s: String) -> String {
        var t = s.lowercased().replacingOccurrences(of: "&", with: " and ")
        // Country prefixes: "US:", "USA:", "US -", "(US)", "US " (as in "US Investigation Discovery").
        t = t.replacingOccurrences(of: #"^\s*(\(?\s*(us|usa|uk|ca)\s*\)?\s*[:|\-]?\s+|[a-z]{2,3}\s*[:|]\s*)"#, with: "", options: .regularExpression)
        // Feed tags only inside brackets, so "A&E" survives: any single letter (A) (S) (X)…, (Backup) (East)…
        t = t.replacingOccurrences(of: #"[\(\[]\s*([a-z]|backup|vip|east|west|hd|fhd|uhd|sd|4k|alt|feed)\s*[\)\]]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\b(fhd|uhd|hd|sd|4k|hevc|h265|1080p|720p|east|west|vip)\b"#, with: "", options: .regularExpression)
        return t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    /// Which feed a name refers to: "w" for West / Pacific ("HBO Zone West", "HBO (W)"), else "e".
    /// Whole words only, so "Westerns" or "Bally Sports Southwest" stay East.
    /// US premium channels run their West feed 3 hours behind, so the two must never share listings.
    static func feed(_ s: String) -> String {
        let t = s.lowercased()
        if t.range(of: #"(\bwest\b|\bpacific\b|[\(\[]\s*w\s*[\)\]]|\bpst\b)"#, options: .regularExpression) != nil { return "w" }
        return "e"
    }

    /// Lookup key: normalised name plus feed.
    static func key(_ normalised: String, feed: String) -> String { normalised + "|" + feed }

    /// Forms of a playlist name worth trying, best first:
    /// "US The Movie Channel (TMC) (East) (X)" → "themoviechanneltmc", "themoviechannel", "moviechannel", "tmc".
    private static let abbreviationRE = try! NSRegularExpression(pattern: #"[\(\[]\s*([A-Z0-9&+]{2,6})\s*[\)\]]"#)

    static func candidates(_ s: String) -> [String] {
        var out: [String] = []
        func add(_ x: String) { let n = normalise(x); if n.count >= 2, !out.contains(n) { out.append(n) } }
        add(s)
        let noBrackets = s.replacingOccurrences(of: #"[\(\[][^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)
        add(noBrackets)
        let noThe = noBrackets.replacingOccurrences(of: #"(?i)^\s*(\(?\s*(us|usa|uk|ca)\s*\)?\s*[:|\-]?\s+)?the\s+"#, with: "", options: .regularExpression)
        add(noThe)
        // A bracketed abbreviation on its own: "(TMC)", "(AHC)".
        let ns = s as NSString
        for m in abbreviationRE.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let abbr = ns.substring(with: m.range(at: 1))
            if !["HD", "FHD", "UHD", "SD", "4K", "VIP"].contains(abbr) { add(abbr) }
        }
        return out
    }

    /// What the playlist needs, so huge guides only keep listings for matching channels.
    struct Wanted: Sendable {
        var ids: Set<String>          // lowercased tvg-ids
        var names: Set<String>        // normalised channel names and tvg-ids
    }
}
