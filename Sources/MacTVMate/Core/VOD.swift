import Foundation

/// Movies and series from an Xtream panel (TiViMate's Movies / Shows sections).
enum VODKind: String { case movies, series }

struct VODItem: Identifiable, Hashable {
    let kind: VODKind
    let streamID: Int            // stream_id for movies, series_id for series
    let name: String
    let poster: URL?
    /// Panels list one title under several categories; duplicates are merged and keep all of them.
    var categoryIDs: [String]
    let rating: Double?
    let added: Date?
    let containerExtension: String?
    let year: String?
    let plot: String?

    var id: String { "\(kind == .movies ? "movie" : "series")|\(streamID)" }
}

struct VODCategory: Identifiable, Hashable {
    let id: String
    let name: String
}

struct MovieDetails {
    var plot, cast, director, genre, releaseDate, duration, trailer: String?
    var backdrop: URL?
    var rating: Double?
    var containerExtension: String?
}

struct Episode: Identifiable, Hashable {
    let id: Int
    let season: Int
    let number: Int
    let title: String
    let plot: String?
    let duration: String?
    let image: URL?
    let containerExtension: String
    var key: String { "episode|\(id)" }
}

struct SeriesDetails {
    var plot, cast, genre, releaseDate: String?
    var backdrop: URL?
    var rating: Double?
    var seasons: [Int: [Episode]] = [:]
}

@MainActor
final class VODStore: ObservableObject {
    @Published private(set) var movies: [VODItem] = []
    @Published private(set) var series: [VODItem] = []
    @Published private(set) var movieCategories: [VODCategory] = []
    @Published private(set) var seriesCategories: [VODCategory] = []
    @Published private(set) var loading: VODKind?
    @Published private(set) var error: String?
    /// IMDb matches for the loaded movies/series (filled in the background once the index is ready).
    @Published private(set) var imdb: [String: IMDbTitle] = [:]
    private var imdbDoneFor = Set<VODKind>()

    private var movieDetails: [Int: MovieDetails] = [:]
    private var seriesDetails: [Int: SeriesDetails] = [:]
    private var loadedFor: UUID?
    private unowned let library: Library

    init(library: Library) { self.library = library }

    var client: XtreamClient? { library.xtreamClientForVOD }
    var isAvailable: Bool { client != nil }

    func items(_ kind: VODKind) -> [VODItem] { kind == .movies ? movies : series }
    func categories(_ kind: VODKind) -> [VODCategory] { kind == .movies ? movieCategories : seriesCategories }

    /// Loads (cached) lists the first time a section opens, or when the playlist changes.
    func ensureLoaded(_ kind: VODKind, force: Bool = false) async {
        guard let client, let source = library.activeSource else { return }
        if loadedFor != source.id { movies = []; series = []; movieCategories = []; seriesCategories = []; loadedFor = source.id }
        if !force, !items(kind).isEmpty { return }
        loading = kind
        error = nil
        defer { loading = nil }
        do {
            let (catAction, listAction) = kind == .movies ? ("get_vod_categories", "get_vod_streams") : ("get_series_categories", "get_series")
            let catData = try await library.fetch(client.apiURL(action: catAction).absoluteString, source: source,
                                                  cacheName: "xc-\(kind.rawValue)-categories", force: force)
            try? await Task.sleep(for: .seconds(1))
            let listData = try await library.fetch(client.apiURL(action: listAction).absoluteString, source: source,
                                                   cacheName: "xc-\(kind.rawValue)", force: force)
            let (cats, list) = try await Task.detached(priority: .userInitiated) {
                (try Self.parseCategories(catData), try Self.parseItems(listData, kind: kind))
            }.value
            if kind == .movies { movieCategories = cats; movies = list } else { seriesCategories = cats; series = list }
            imdbDoneFor.remove(kind)
            await matchIMDb(kind)
        } catch {
            self.error = "Couldn't load \(kind == .movies ? "movies" : "shows"): \(error.localizedDescription)"
        }
    }

    /// Looks every title up in the local IMDb index (fast: one indexed query each, off the main thread).
    func matchIMDb(_ kind: VODKind) async {
        guard !imdbDoneFor.contains(kind) else { return }
        let items = self.items(kind)
        guard !items.isEmpty else { return }
        var found: [String: IMDbTitle] = [:]
        for item in items {
            let (title, y) = MetaStore.splitYear(item.name)
            let year = y ?? item.year.flatMap { Int($0.prefix(4)) }
            if let t = await IMDbIndex.shared.lookup(title: title, year: year, series: kind == .series) { found[item.id] = t }
        }
        guard !found.isEmpty else { return }      // index not ready yet; retried when it is
        imdbDoneFor.insert(kind)
        imdb.merge(found) { _, new in new }
    }

    func movieURL(_ item: VODItem, ext: String?) -> URL? {
        guard let client else { return nil }
        let e = (ext ?? item.containerExtension ?? "mp4")
        return client.server.appendingPathComponent("movie/\(client.username)/\(client.password)/\(item.streamID).\(e)")
    }

    func episodeURL(_ ep: Episode) -> URL? {
        guard let client else { return nil }
        return client.server.appendingPathComponent("series/\(client.username)/\(client.password)/\(ep.id).\(ep.containerExtension)")
    }

    func details(movie item: VODItem) async -> MovieDetails? {
        if let d = movieDetails[item.streamID] { return d }
        guard let client else { return nil }
        var c = URLComponents(url: client.apiURL(action: "get_vod_info"), resolvingAgainstBaseURL: false)!
        c.queryItems! += [URLQueryItem(name: "vod_id", value: String(item.streamID))]
        guard let data = try? await client.getData(c.url!),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let info = obj["info"] as? [String: Any] ?? [:]
        let movie = obj["movie_data"] as? [String: Any] ?? [:]
        var d = MovieDetails()
        d.plot = Self.str(info["plot"] ?? info["description"])
        d.cast = Self.str(info["cast"] ?? info["actors"])
        d.director = Self.str(info["director"])
        d.genre = Self.str(info["genre"])
        d.releaseDate = Self.str(info["releasedate"] ?? info["release_date"])
        d.duration = Self.str(info["duration"])
        d.trailer = Self.str(info["youtube_trailer"])
        d.rating = Self.str(info["rating"]).flatMap(Double.init)
        d.backdrop = (info["backdrop_path"] as? [String])?.first.flatMap(URL.init(string:)) ?? Self.str(info["cover_big"]).flatMap(URL.init(string:))
        d.containerExtension = Self.str(movie["container_extension"])
        movieDetails[item.streamID] = d
        return d
    }

    func details(series item: VODItem) async -> SeriesDetails? {
        if let d = seriesDetails[item.streamID] { return d }
        guard let client else { return nil }
        var c = URLComponents(url: client.apiURL(action: "get_series_info"), resolvingAgainstBaseURL: false)!
        c.queryItems! += [URLQueryItem(name: "series_id", value: String(item.streamID))]
        guard let data = try? await client.getData(c.url!),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let info = obj["info"] as? [String: Any] ?? [:]
        var d = SeriesDetails()
        d.plot = Self.str(info["plot"])
        d.cast = Self.str(info["cast"])
        d.genre = Self.str(info["genre"])
        d.releaseDate = Self.str(info["releaseDate"] ?? info["release_date"])
        d.rating = Self.str(info["rating"]).flatMap(Double.init)
        d.backdrop = (info["backdrop_path"] as? [String])?.first.flatMap(URL.init(string:))
        // "episodes" is usually {"1": [...], "2": [...]} but some panels return an array of arrays.
        var groups: [[String: Any]] = []
        if let dict = obj["episodes"] as? [String: [[String: Any]]] { groups = dict.values.flatMap { $0 } }
        else if let arr = obj["episodes"] as? [[[String: Any]]] { groups = arr.flatMap { $0 } }
        for e in groups {
            guard let id = Self.str(e["id"]).flatMap(Int.init) else { continue }
            let einfo = e["info"] as? [String: Any] ?? [:]
            let ep = Episode(
                id: id,
                season: Self.str(e["season"]).flatMap(Int.init) ?? 1,
                number: Self.str(e["episode_num"]).flatMap(Int.init) ?? 0,
                title: Self.str(e["title"]) ?? "Episode",
                plot: Self.str(einfo["plot"]),
                duration: Self.str(einfo["duration"]),
                image: Self.str(einfo["movie_image"]).flatMap(URL.init(string:)),
                containerExtension: Self.str(e["container_extension"]) ?? "mp4")
            d.seasons[ep.season, default: []].append(ep)
        }
        for k in d.seasons.keys { d.seasons[k]?.sort { $0.number < $1.number } }
        seriesDetails[item.streamID] = d
        return d
    }

    // MARK: Parsing

    nonisolated static func str(_ v: Any?) -> String? {
        guard let v, !(v is NSNull) else { return nil }
        let s = "\(v)".trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    nonisolated static func parseCategories(_ data: Data) throws -> [VODCategory] {
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { c in
            guard let id = str(c["category_id"]), let name = str(c["category_name"]) else { return nil }
            return VODCategory(id: id, name: name)
        }
    }

    nonisolated static func parseItems(_ data: Data, kind: VODKind) throws -> [VODItem] {
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var order: [Int] = []
        var byID: [Int: VODItem] = [:]
        for o in arr {
            let idKey = kind == .movies ? "stream_id" : "series_id"
            guard let id = str(o[idKey]).flatMap(Int.init), let name = str(o["name"]) else { continue }
            let cat = str(o["category_id"]) ?? ""
            if var existing = byID[id] {
                if !cat.isEmpty, !existing.categoryIDs.contains(cat) { existing.categoryIDs.append(cat); byID[id] = existing }
                continue
            }
            let poster = str(o[kind == .movies ? "stream_icon" : "cover"]).flatMap(URL.init(string:))
            let added = str(o["added"] ?? o["last_modified"]).flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) }
            let year = str(o["year"]) ?? str(o["releaseDate"] ?? o["release_date"]).map { String($0.prefix(4)) }
            byID[id] = VODItem(kind: kind, streamID: id, name: name, poster: poster,
                               categoryIDs: cat.isEmpty ? [] : [cat], rating: str(o["rating"]).flatMap(Double.init),
                               added: added, containerExtension: str(o["container_extension"]), year: year, plot: str(o["plot"]))
            order.append(id)
        }
        return order.compactMap { byID[$0] }
    }
}
