import Foundation

/// Builds guide entries for event channels whose name carries the matchup and start time, e.g.
///   "NFL 01: Washington Commanders @ San Francisco 49ers | Home Stream | 8:15 PM"
///   "NFL 14: 49ers vs Commanders (10.19 8:15PM ET)"
///   "NCAAF 12 Alabama @ Tennessee 330PM"
/// Providers leave these channels without EPG, so TiViMate shows "No information" for them.
enum EventParser {
    private static let timeRE = try! NSRegularExpression(
        pattern: #"(?<![\d.:])(\d{1,2})(?::(\d{2})|(\d{2}))?\s*([ap])\.?m\.?(?:\s*(ET|EST|EDT|CT|CST|CDT|MT|MST|MDT|PT|PST|PDT|UK|GMT|BST|CET))?"#,
        options: [.caseInsensitive])
    private static let dateRE = try! NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})[./](\d{1,2})(?![\d.:/])"#)
    private static let matchupRE = try! NSRegularExpression(
        pattern: #"\S.*?\s(?:@|vs\.?|v\.?|at)\s.*\S"#, options: [.caseInsensitive])

    /// "(2026 11 01 12:50:00)" — full timestamp in US Eastern time (Paramount+ event channels).
    private static let stampRE = try! NSRegularExpression(pattern: #"\(\s*(\d{4})\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2}):(\d{2})(?::\d{2})?\s*\)"#)

    static func programmes(for c: Channel, now: Date = .now) -> [Programme]? {
        let name = c.name
        let ns = name as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard matchupRE.firstMatch(in: name, range: full) != nil else { return nil }
        if let m = stampRE.firstMatch(in: name, range: full) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "America/New_York")!
            let n = (1...5).map { Int(ns.substring(with: m.range(at: $0)))! }
            guard let start = cal.date(from: DateComponents(year: n[0], month: n[1], day: n[2], hour: n[3], minute: n[4])) else { return nil }
            return build(c, title: cleanTitle(name, timeRange: m.range), start: start, now: now)
        }
        guard let t = timeRE.firstMatch(in: name, range: full) else { return nil }

        // Time (handles "8:15 PM", "8:15pm", "12PM" and "330PM").
        var hour = Int(ns.substring(with: t.range(at: 1)))!
        var minute = 0
        if t.range(at: 2).location != NSNotFound { minute = Int(ns.substring(with: t.range(at: 2)))! }
        else if t.range(at: 3).location != NSNotFound { minute = Int(ns.substring(with: t.range(at: 3)))! }
        if hour > 12 || minute > 59 { return nil }
        let pm = ns.substring(with: t.range(at: 4)).lowercased() == "p"
        if pm, hour < 12 { hour += 12 }
        if !pm, hour == 12 { hour = 0 }
        let zone = t.range(at: 5).location != NSNotFound ? timeZone(ns.substring(with: t.range(at: 5))) : TimeZone(identifier: "America/New_York")!

        // Date: "(10.19 …" / "10/19", else the next occurrence of that time (within the last 6 h counts as today).
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        if let d = dateRE.firstMatch(in: name, range: full),
           let m = Int(ns.substring(with: d.range(at: 1))), let day = Int(ns.substring(with: d.range(at: 2))),
           (1...12).contains(m), (1...31).contains(day) {
            comps.month = m; comps.day = day
        }
        comps.hour = hour; comps.minute = minute
        // Without a date, the time refers to today's slate (event channels are refreshed daily).
        guard let start = cal.date(from: comps) else { return nil }

        return build(c, title: cleanTitle(name, timeRange: t.range), start: start, now: now)
    }

    private static func build(_ c: Channel, title tn: (String, String?), start: Date, now: Date) -> [Programme] {
        let name = c.name
        let league = leagueName(name) ?? (c.group.localizedCaseInsensitiveContains("paramount") ? "Soccer" : nil)
        let stop = start.addingTimeInterval(duration(league))
        let (title, note) = tn
        let key = "event:\(c.id)"
        var event = Programme(channelKey: key, start: start, stop: stop, title: title,
                              subtitle: note, desc: "\(league.map { "\($0) · " } ?? "")From the channel name.", category: league)
        event.isEvent = true
        var list = [event]
        // Fill the row before kick-off so the guide reads "Upcoming …" instead of "No information".
        let windowStart = now.addingTimeInterval(-24 * 3600)
        if start > windowStart {
            var pre = Programme(channelKey: key, start: windowStart, stop: start, title: "Upcoming: \(title)",
                                desc: "Starts \(Theme.dayLabel(start, withTime: true)).", category: league)
            pre.isEvent = true
            list.insert(pre, at: 0)
        }
        return list
    }

    private static func timeZone(_ s: String) -> TimeZone {
        switch s.uppercased() {
        case "ET", "EST", "EDT": return TimeZone(identifier: "America/New_York")!
        case "CT", "CST", "CDT": return TimeZone(identifier: "America/Chicago")!
        case "MT", "MST", "MDT": return TimeZone(identifier: "America/Denver")!
        case "PT", "PST", "PDT": return TimeZone(identifier: "America/Los_Angeles")!
        case "UK", "BST": return TimeZone(identifier: "Europe/London")!
        case "CET": return TimeZone(identifier: "Europe/Paris")!
        default: return TimeZone(identifier: "GMT")!
        }
    }

    private static let leagues = ["NFL", "NCAAF", "NCAAB", "NBA", "WNBA", "NHL", "MLB", "MLS", "EPL", "UCL", "UFC", "PPV",
                                  "NASCAR", "F1", "PGA", "WWE", "Boxing", "Soccer", "Football", "Hockey", "Baseball", "Basketball"]

    private static func leagueName(_ name: String) -> String? {
        let upper = name.uppercased()
        return leagues.first { l in
            upper.range(of: #"(^|[^A-Z])"# + NSRegularExpression.escapedPattern(for: l.uppercased()) + #"([^A-Z]|$)"#,
                        options: .regularExpression) != nil
        }
    }

    private static func duration(_ league: String?) -> TimeInterval {
        switch league?.uppercased() {
        case "NFL", "NCAAF", "FOOTBALL": return 3.5 * 3600
        case "MLB", "BASEBALL": return 3 * 3600
        case "NBA", "WNBA", "NCAAB", "NHL", "BASKETBALL", "HOCKEY": return 2.5 * 3600
        case "MLS", "EPL", "UCL", "SOCCER": return 2 * 3600
        case "UFC", "PPV", "BOXING", "WWE": return 4 * 3600
        case "NASCAR", "F1", "PGA": return 3.5 * 3600
        default: return 3 * 3600
        }
    }

    /// "NFL 01: Washington Commanders @ San Francisco 49ers | Home Stream | 8:15 PM" →
    /// ("Washington Commanders @ San Francisco 49ers", "Home Stream").
    private static func cleanTitle(_ name: String, timeRange: NSRange) -> (String, String?) {
        var s = (name as NSString).replacingCharacters(in: timeRange, with: " ")
        s = s.replacingOccurrences(of: #"\(\s*\d{1,2}[./]\d{1,2}[^)]*\)"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\s*US\s*\([^)]*\)\s*\|?"#, with: "", options: .regularExpression)
        // Leading "NFL 01:", "NFL | 14", "NCAAF 11", "(NFL)", "MNF" prefixes.
        // Only an uppercase league tag followed by a number and/or separator ("NFL 01:", "NFL | 14", "(NFL)") — not "Lecce".
        s = s.replacingOccurrences(of: #"^\s*(\([A-Z]{2,6}\)|[A-Z]{2,6}(\s*\|)?\s*(4k|uhd|hd|\d{1,3})\s*[:|\-]?|[A-Z]{2,6}\s*[:|])\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"^\s*(MNF|SNF|TNF)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        let parts = s.split(separator: "|")
            .map { $0.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                     .replacingOccurrences(of: #"\s+\d{1,2}\s*$"#, with: "", options: .regularExpression)   // truncated "3…" leftovers
                     .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let title = (parts.first { $0.range(of: #"\s(@|vs\.?|v\.?|at)\s"#, options: [.regularExpression, .caseInsensitive]) != nil } ?? parts.first ?? name)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -:|"))
        let note = parts.filter { $0 != title && !$0.isEmpty }.joined(separator: " · ")
        return (title, note.isEmpty ? nil : note)
    }
}
