import Foundation

/// Live sports data for guide events (ESPN's public scoreboard JSON — unofficial, no key; fails quietly).
/// Games aren't movies: what matters is who's playing, the score, the clock and where to watch.
struct Game: Identifiable, Equatable {
    struct Side: Equatable {
        let name: String          // "San Francisco 49ers"
        let short: String         // "49ers"
        let abbreviation: String  // "SF"
        let location: String      // "San Francisco"
        let logo: URL?
        let score: String?
        let record: String?
    }
    enum State: String { case pre, live = "in", post }

    let id: String
    let league: String
    let name: String            // "Washington Commanders at San Francisco 49ers"
    let start: Date
    let state: State
    let detail: String          // "14:00 - 4th", "Final", "8:15 PM ET"
    let home: Side
    let away: Side
    let venue: String?
    let networks: [String]
    let situation: String?      // "1st & 10 at WSH 20"
    let headline: String?

    var scoreLine: String? {
        guard state != .pre, let a = away.score, let h = home.score else { return nil }
        return "\(away.abbreviation) \(a) – \(h) \(home.abbreviation)"
    }
}

@MainActor
final class SportsData: ObservableObject {
    /// League key -> ESPN path.
    static let leagues: [String: String] = [
        "NFL": "football/nfl", "NCAAF": "football/college-football", "CFL": "football/cfl",
        "NBA": "basketball/nba", "WNBA": "basketball/wnba", "NCAAB": "basketball/mens-college-basketball",
        "NHL": "hockey/nhl", "MLB": "baseball/mlb",
        "MLS": "soccer/usa.1", "EPL": "soccer/eng.1", "LALIGA": "soccer/esp.1", "SERIEA": "soccer/ita.1",
        "BUNDESLIGA": "soccer/ger.1", "LIGUE1": "soccer/fra.1", "UCL": "soccer/uefa.champions",
        "UEL": "soccer/uefa.europa", "UECL": "soccer/uefa.europa.conf", "LIGAMX": "soccer/mex.1",
        "CONCACAF": "soccer/concacaf.champions",
    ]
    static let soccerLeagues = ["EPL", "LALIGA", "SERIEA", "BUNDESLIGA", "LIGUE1", "UCL", "UEL", "UECL", "MLS", "LIGAMX", "CONCACAF"]

    @Published private(set) var revision = 0
    private var boards: [String: (fetched: Date, games: [Game])] = [:]   // "NFL|20261019"
    private var inFlight = Set<String>()
    private var refreshTimer: Timer?

    init() {
        // Live games refresh every minute while the app is open.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLive() }
        }
    }

    /// The game a sports programme shows, if it can be identified. Triggers a (cached) fetch as needed.
    func game(for p: Programme, channel: Channel) -> Game? {
        guard p.kind == .sports else { return nil }
        let leagues = candidateLeagues(p, channel)
        let days = Set([p.start, p.start.addingTimeInterval(-6 * 3600), p.stop].map(Self.dayKey))
        var found: Game?
        for l in leagues {
            for d in days {
                let key = "\(l)|\(d)"
                guard let board = boards[key] else { load(l, day: d); continue }
                if found == nil, let g = board.games.first(where: { matches($0, p, channel) }) { found = g }
            }
        }
        return found
    }

    private func candidateLeagues(_ p: Programme, _ c: Channel) -> [String] {
        let text = [p.leagueTag ?? "", p.title, p.subtitle ?? "", p.category ?? "", c.name, c.group].joined(separator: " ").uppercased()
        var out: [String] = []
        for l in ["NFL", "NCAAF", "NBA", "WNBA", "NCAAB", "NHL", "MLB", "MLS", "CFL", "UFC"] where text.range(of: "\\b\(l)\\b", options: .regularExpression) != nil {
            out.append(l)
        }
        if text.contains("COLLEGE FOOTBALL") { out.append("NCAAF") }
        if text.contains("COLLEGE BASKETBALL") { out.append("NCAAB") }
        if out.isEmpty, text.range(of: #"\bFOOTBALL\b"#, options: .regularExpression) != nil, !text.contains("SOCCER") { out.append("NFL") }
        if out.isEmpty, text.contains("BASKETBALL") { out.append("NBA") }
        if out.isEmpty, text.contains("HOCKEY") { out.append("NHL") }
        if out.isEmpty, text.contains("BASEBALL") { out.append("MLB") }
        if out.isEmpty || text.contains("SOCCER") || text.contains("PARAMOUNT") || text.contains("PEACOCK") {
            out += Self.soccerLeagues   // "Lecce vs. Genoa" — find it in whichever league plays it
        }
        return out.filter { Self.leagues[$0] != nil }
    }

    /// Both teams named in the listing (full name, nickname, location or abbreviation) and start within ±4 h.
    private func matches(_ g: Game, _ p: Programme, _ c: Channel) -> Bool {
        guard abs(g.start.timeIntervalSince(p.start)) < 4 * 3600 || (p.isEvent && abs(g.start.timeIntervalSince(p.start)) < 6 * 3600) else { return false }
        let text = " " + Self.fold([p.title, p.subtitle ?? "", p.desc ?? "", c.name].joined(separator: " ")) + " "
        func named(_ s: Game.Side) -> Bool {
            [s.name, s.short, s.location].map(Self.fold).contains { $0.count >= 3 && text.contains(" \($0) ") || text.contains($0 + " ") && $0.count > 6 }
        }
        return named(g.home) && named(g.away)
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: d)
    }

    // MARK: Fetching

    private func load(_ league: String, day: String, force: Bool = false) {
        let key = "\(league)|\(day)"
        guard !inFlight.contains(key), let path = Self.leagues[league] else { return }
        if !force, let b = boards[key], Date().timeIntervalSince(b.fetched) < 600 { return }
        inFlight.insert(key)
        Task {
            defer { inFlight.remove(key) }
            guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(path)/scoreboard?dates=\(day)&limit=300"),
                  let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else {
                boards[key] = (Date(), [])     // don't hammer on failure; retried after the cache window
                return
            }
            let games = await Task.detached { Self.parse(data, league: league) }.value
            boards[key] = (Date(), games)
            revision += 1
        }
    }

    private func refreshLive() {
        for (key, b) in boards where b.games.contains(where: { $0.state == .live })
            || b.games.contains(where: { $0.state == .pre && $0.start < Date() }) {
            let parts = key.split(separator: "|").map(String.init)
            load(parts[0], day: parts[1], force: true)
        }
    }

    nonisolated static func parse(_ data: Data, league: String) -> [Game] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        // ESPN sends "2026-10-20T00:15Z" (no seconds) — ISO8601DateFormatter rejects that, so parse both forms.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let isoNoSec = DateFormatter()
        isoNoSec.locale = Locale(identifier: "en_US_POSIX")
        isoNoSec.timeZone = TimeZone(identifier: "UTC")
        isoNoSec.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return events.compactMap { e in
            guard let id = e["id"] as? String, let dateStr = e["date"] as? String,
                  let start = iso.date(from: dateStr) ?? isoNoSec.date(from: dateStr),
                  let comp = (e["competitions"] as? [[String: Any]])?.first,
                  let teams = comp["competitors"] as? [[String: Any]] else { return nil }
            func side(_ t: [String: Any]) -> Game.Side {
                let tm = t["team"] as? [String: Any] ?? [:]
                let records = t["records"] as? [[String: Any]]
                return Game.Side(
                    name: tm["displayName"] as? String ?? "", short: tm["shortDisplayName"] as? String ?? tm["name"] as? String ?? "",
                    abbreviation: tm["abbreviation"] as? String ?? "", location: tm["location"] as? String ?? "",
                    logo: (tm["logo"] as? String).flatMap(URL.init(string:)), score: t["score"] as? String,
                    record: records?.first?["summary"] as? String)
            }
            guard let home = teams.first(where: { $0["homeAway"] as? String == "home" }),
                  let away = teams.first(where: { $0["homeAway"] as? String == "away" }) else { return nil }
            let status = (e["status"] as? [String: Any])?["type"] as? [String: Any] ?? [:]
            let broadcasts = (comp["broadcasts"] as? [[String: Any]])?.flatMap { $0["names"] as? [String] ?? [] } ?? []
            let headline = ((comp["headlines"] as? [[String: Any]])?.first?["shortLinkText"] as? String)
            return Game(
                id: id, league: league, name: e["name"] as? String ?? "", start: start,
                state: Game.State(rawValue: status["state"] as? String ?? "pre") ?? .pre,
                detail: status["shortDetail"] as? String ?? "",
                home: side(home), away: side(away),
                venue: (comp["venue"] as? [String: Any])?["fullName"] as? String,
                networks: broadcasts,
                situation: (comp["situation"] as? [String: Any])?["downDistanceText"] as? String,
                headline: headline)
        }
    }
}
