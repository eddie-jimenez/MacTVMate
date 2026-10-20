import Foundation

struct Channel: Identifiable, Hashable, Codable {
    var id: String
    var number: Int
    var name: String
    var group: String
    var logo: URL?
    var url: URL
    /// Key used to look up programmes in the EPG (tvg-id, or Xtream epg_channel_id).
    var epgID: String?
    var catchupDays: Int = 0
    /// M3U `catchup` mode (default, append, shift, flussonic, xc).
    var catchupMode: String?
    /// M3U `catchup-source` template.
    var catchupSource: String?
    var xtreamStreamID: Int?
    /// Per-channel HTTP headers (EXTINF user-agent/http-referrer, #EXTVLCOPT, or `url|User-Agent=…`).
    var userAgent: String?
    var referrer: String?
    /// tvg-shift, hours added to EPG times for this channel.
    var epgShift: Double = 0
    /// catchup-correction, hours added to the archive start time.
    var catchupCorrection: Double = 0

    var hasCatchup: Bool { catchupDays > 0 }
}

struct Programme: Identifiable, Hashable {
    var id: String { "\(channelKey)|\(start.timeIntervalSince1970)" }
    var channelKey: String
    var start: Date
    var stop: Date
    var title: String
    var subtitle: String?
    var desc: String?
    var category: String?
    /// Synthesised from an event channel's name rather than a guide source.
    var isEvent = false

    // Rich XMLTV metadata (Gracenote-based guides carry all of these).
    var icon: URL?
    var year: Int?
    var categories: [String] = []
    var season: Int?
    var episode: Int?
    /// Gracenote program id ("MV…" movie, "EP…" episode, "SH…" show, "SP…" sports).
    var progID: String?
    var actors: [String] = []
    var directors: [String] = []
    var contentRating: String?
    var starRating: String?
    var isNew = false
    var lengthMinutes: Int?

    enum Kind { case sports, movie, episode, news, other }

    /// Sports first: games are listed as "Series" too, but they need sports treatment, not IMDb.
    var kind: Kind {
        let cats = Set(categories.map { $0.lowercased() } + [category?.lowercased()].compactMap { $0 })
        if isEvent || progID?.hasPrefix("SP") == true || cats.contains("sports") || cats.contains("sports event")
            || cats.contains("sports non-event") && Self.looksLikeGame(self) { return .sports }
        if progID?.hasPrefix("MV") == true || cats.contains("movie") || cats.contains("film") { return .movie }
        if cats.contains("news") { return .news }
        if season != nil || episode != nil || progID?.hasPrefix("EP") == true || progID?.hasPrefix("SH") == true
            || cats.contains("series") { return .episode }
        if Self.looksLikeGame(self) { return .sports }
        return .other
    }

    /// "NFL Football", "Nebraska at Oregon", "Lakers vs. Celtics"…
    static func looksLikeGame(_ p: Programme) -> Bool {
        if p.title.range(of: #"(?i)^\s*(live:\s*)?(nfl|ncaa|college|nba|wnba|nhl|mlb|mls|cfl|xfl|ufl|premier league)\b.*\b(football|basketball|hockey|baseball|soccer)\b"#,
                         options: .regularExpression) != nil { return true }
        let t = p.title + " " + (p.subtitle ?? "")
        return t.range(of: #"(?i)\b(nfl|ncaaf|ncaab|nba|wnba|nhl|mlb|mls|ufc|premier league|football|basketball|hockey|baseball|soccer)\b"#,
                       options: .regularExpression) != nil
            && t.range(of: #"(?i)\s(@|at|vs\.?|v\.?)\s"#, options: .regularExpression) != nil
    }

    /// Title without guide decorations ("🏈🎓 [NCAAF] College Football [NEW]" → "College Football").
    var displayTitle: String {
        var t = title.replacingOccurrences(of: #"\[(NEW|LIVE|HD|CC)\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"^\s*\[[A-Z0-9 ]{2,10}\]\s*"#, with: "", options: .regularExpression)
        t = String(t.unicodeScalars.drop { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x2000 || $0 == " " })
        return t.trimmingCharacters(in: .whitespaces).isEmpty ? title : t.trimmingCharacters(in: .whitespaces)
    }

    /// League tag from "[NCAAF] College Football" style titles.
    var leagueTag: String? {
        guard let r = title.range(of: #"\[([A-Z0-9]{2,8})\]"#, options: .regularExpression) else { return nil }
        let tag = title[r].dropFirst().dropLast()
        return ["NEW", "LIVE", "HD", "CC"].contains(String(tag)) ? nil : String(tag)
    }

    var episodeLabel: String? {
        switch (season, episode) {
        case let (s?, e?): return "S\(s) E\(e)"
        case let (nil, e?): return "E\(e)"
        default: return nil
        }
    }

    var duration: TimeInterval { stop.timeIntervalSince(start) }
    func isLive(at now: Date = .now) -> Bool { start <= now && now < stop }
    func progress(at now: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / duration))
    }
}

enum SourceKind: Codable, Hashable {
    case m3u(playlistURL: String, epgURL: String)
    case xtream(server: String, username: String, password: String)
}

struct PlaylistSource: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: SourceKind
    var userAgent: String = ""
    /// Xtream only: prefer HLS (.m3u8) over MPEG-TS (.ts) for live streams.
    var preferHLS: Bool = false
    /// Hours after which cached playlist/EPG data is refetched.
    var refreshHours: Int = 12
}

struct ChannelGroup: Identifiable, Hashable {
    static let all = "All channels"
    static let favourites = "Favourites"
    static let recent = "Recently watched"
    var id: String { name }
    var name: String
    var count: Int
}

/// What the player is currently showing.
enum PlaybackTarget: Equatable {
    case live(Channel)
    case catchup(Channel, Programme)
    /// A movie or episode. `key` identifies its resume position ("movie|<id>" / "episode|<id>").
    case vod(Channel, key: String)

    var channel: Channel {
        switch self {
        case .live(let c), .catchup(let c, _), .vod(let c, _): return c
        }
    }

    var isLive: Bool { if case .live = self { return true } else { return false } }
    var isSeekable: Bool { !isLive }
}

struct Recording: Identifiable, Codable, Hashable {
    enum Status: String, Codable { case scheduled, recording, done, failed, cancelled }
    var id = UUID()
    var channelID: String
    var channelName: String
    var title: String
    var start: Date
    var stop: Date
    var url: URL
    var userAgent: String
    var file: String?
    var status: Status = .scheduled
    var error: String?
}

struct Reminder: Identifiable, Codable, Hashable {
    var id = UUID()
    var channelID: String
    var channelName: String
    var title: String
    var start: Date
}
