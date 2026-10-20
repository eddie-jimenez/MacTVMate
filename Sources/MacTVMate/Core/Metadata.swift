import Foundation

/// TV show info and art from TVmaze (free, no key): poster, rating, genres, IMDb id.
struct TVShow: Codable, Hashable {
    let id: Int
    let name: String
    let image: URL?
    let rating: Double?
    let imdb: String?
    let genres: [String]
    let premiered: String?
}

/// Enrichment for movies and shows (sports go through SportsData instead):
/// IMDb ratings from the local dataset index, art and show info from TVmaze.
@MainActor
final class MetaStore: ObservableObject {
    @Published private(set) var imdbState: IMDbIndex.State = .missing
    @Published private(set) var revision = 0

    private var imdbCache: [String: IMDbTitle?] = [:]
    private var imdbPending = Set<String>()
    private var shows: [String: TVShow?] = [:]
    private var showQueue: [String] = []
    private var showTask: Task<Void, Never>?
    private let showsFile = Persistence().dir.appendingPathComponent("tvmaze.json")

    init() {
        if let data = try? Data(contentsOf: showsFile),
           let saved = try? JSONDecoder().decode([String: TVShow].self, from: data) {
            for (k, v) in saved { shows[k] = v }
        }
        Task {
            await IMDbIndex.shared.prepare { state in
                Task { @MainActor [weak self] in
                    self?.imdbState = state
                    if case .ready = state { self?.imdbCache = [:]; self?.imdbPending = []; self?.revision += 1 }
                }
            }
        }
    }

    var imdbReady: Bool { if case .ready = imdbState { return true } else { return false } }

    // MARK: IMDb

    /// IMDb match for a guide programme (movies and episodes only). Returns the cached value; looks it up if needed.
    func imdb(for p: Programme) -> IMDbTitle? {
        switch p.kind {
        case .movie: return imdb(title: p.displayTitle, year: p.year, series: false)
        case .episode: return imdb(title: p.displayTitle, year: nil, series: true)
        default: return nil
        }
    }

    func imdb(title: String, year: Int?, series: Bool) -> IMDbTitle? {
        let key = "\(series)|\(IMDbIndex.normalise(title))|\(year ?? 0)"
        if let hit = imdbCache[key] { return hit }
        guard imdbReady, !imdbPending.contains(key) else { return nil }
        imdbPending.insert(key)
        Task {
            let t = await IMDbIndex.shared.lookup(title: title, year: year, series: series)
            imdbCache[key] = t
            imdbPending.remove(key)
            if t != nil { revision += 1 }
        }
        return nil
    }

    /// Movie titles from panels often carry the year: "Hocus Pocus (1993)" / "Hocus Pocus - 1993".
    static func splitYear(_ name: String) -> (String, Int?) {
        if let r = name.range(of: #"\s*[\(\[-]\s*((19|20)\d{2})\s*[\)\]]?\s*$"#, options: .regularExpression) {
            let y = Int(name[r].filter(\.isNumber).prefix(4))
            return (String(name[..<r.lowerBound]), y)
        }
        return (name, nil)
    }

    // MARK: TVmaze

    /// Show info/art for an episode's series. Cached on disk; looked up at most every 0.6 s (TVmaze allows 20/10 s).
    func show(for title: String) -> TVShow? {
        let key = IMDbIndex.normalise(title)
        guard !key.isEmpty else { return nil }
        if let hit = shows[key] { return hit }
        if !showQueue.contains(title) {
            showQueue.append(title)
            if showQueue.count > 30 { showQueue.removeFirst() }
        }
        startShowWorker()
        return nil
    }

    private func startShowWorker() {
        guard showTask == nil else { return }
        showTask = Task { [weak self] in
            while let self, let title = self.showQueue.popLast() {
                let key = IMDbIndex.normalise(title)
                if self.shows[key] != nil { continue }
                var comps = URLComponents(string: "https://api.tvmaze.com/singlesearch/shows")!
                comps.queryItems = [URLQueryItem(name: "q", value: title)]
                var found: TVShow?
                if let (data, resp) = try? await URLSession.shared.data(from: comps.url!),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = o["id"] as? Int, let name = o["name"] as? String,
                   IMDbIndex.normalise(name) == key {      // only exact title matches
                    let img = (o["image"] as? [String: Any])?["original"] as? String
                    found = TVShow(id: id, name: name, image: img.flatMap(URL.init(string:)),
                                   rating: (o["rating"] as? [String: Any])?["average"] as? Double,
                                   imdb: (o["externals"] as? [String: Any])?["imdb"] as? String,
                                   genres: o["genres"] as? [String] ?? [], premiered: o["premiered"] as? String)
                }
                self.shows[key] = .some(found)
                if found != nil { self.revision += 1; self.persistShows() }
                try? await Task.sleep(for: .milliseconds(600))
            }
            self?.showTask = nil
        }
    }

    private func persistShows() {
        let known = shows.compactMapValues { $0 }
        if let data = try? JSONEncoder().encode(known) { try? data.write(to: showsFile, options: .atomic) }
    }

    /// Best art for a programme: the guide's own icon, else the show's poster.
    func art(for p: Programme) -> URL? {
        if let icon = p.icon { return icon }
        if p.kind == .episode { return show(for: p.displayTitle)?.image }
        return nil
    }
}
