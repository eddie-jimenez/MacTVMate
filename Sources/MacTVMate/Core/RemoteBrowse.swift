import Foundation

/// iPhone remote: browse Movies, Shows, Recordings and My list on the phone, play on the Mac,
/// and jump the Mac between sections. Stream URLs (which carry the provider login) never leave the Mac;
/// the phone only sees ids.
extension AppModel {
    /// Shows a section on the Mac ("guide", "movies", "shows", "recordings", "mylist", "settings", "search").
    func remoteGo(_ section: String) {
        showChannelList = false
        switch section {
        case "settings": showSearch = false; showSettings = true; return
        case "search": showSettings = false; openSearch(); return
        default: break
        }
        showSearch = false; showSettings = false
        switch section {
        case "movies": screen = .movies
        case "shows": screen = .shows
        case "recordings": screen = .recordings
        case "mylist": screen = .myList
        default: showGuide()
        }
    }

    /// Picks a channel group for the guide, so the Mac follows what the phone is browsing.
    func remoteSelectGroup(_ name: String) {
        guard library.groups.contains(where: { $0.name == name }), selectedGroup != name else { return }
        selectedGroup = name
        guideRow = 0
    }

    // MARK: Movies & shows

    func remoteVOD(kind: VODKind, category: String, query: String, offset: Int) async -> [String: Any] {
        await vod.ensureLoaded(kind)
        var items = vod.items(kind)
        switch category {
        case "": break
        case "__continue":
            items = items.filter { kind == .movies ? library.positions[$0.id] != nil : library.recentSeries.contains($0.id) }
        case "__mylist": items = items.filter { library.isInMyList($0.id) }
        default: items = items.filter { $0.categoryIDs.contains(category) }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { items = items.filter { $0.name.localizedCaseInsensitiveContains(q) } }
        else { items.sort { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) } }
        let page = items.dropFirst(offset).prefix(60)
        var cats: [[String: Any]] = [["id": "", "name": "All"], ["id": "__continue", "name": "Continue watching"],
                                     ["id": "__mylist", "name": "My list"]]
        cats += vod.categories(kind).map { ["id": $0.id, "name": $0.name] }
        return ["categories": cats, "total": items.count, "offset": offset, "items": page.map(remoteVODRow)]
    }

    func remoteVODRow(_ item: VODItem) -> [String: Any] {
        var row: [String: Any] = ["id": item.id, "kind": item.kind.rawValue, "name": item.name,
                                  "poster": item.poster?.absoluteString ?? "", "year": item.year ?? "",
                                  "inList": library.isInMyList(item.id)]
        let (title, y) = MetaStore.splitYear(item.name)
        if let t = meta.imdb(title: title, year: y ?? item.year.flatMap { Int($0.prefix(4)) }, series: item.kind == .series) {
            row["rating"] = "IMDb \(t.ratingText)"
        } else if let r = item.rating, r > 0 {
            row["rating"] = String(format: "★ %.1f", r)
        }
        if item.kind == .movies, library.positions[item.id] != nil { row["resume"] = true }
        return row
    }

    private func vodItem(_ id: String) -> VODItem? {
        (vod.movies.first { $0.id == id }) ?? (vod.series.first { $0.id == id })
    }

    func remotePlayMovie(id: String) {
        guard let item = vodItem(id), item.kind == .movies, let url = vod.movieURL(item, ext: nil) else { return }
        showSearch = false; showSettings = false
        playVOD(title: item.name, url: url, poster: item.poster, key: item.id, group: "Movies")
    }

    func remoteSeries(id: String) async -> [String: Any] {
        guard let item = vodItem(id), item.kind == .series else { return [:] }
        let d = await vod.details(series: item)
        let seasons = d?.seasons ?? [:]
        let all = seasons.keys.sorted().flatMap { seasons[$0] ?? [] }
        let next = all.first { library.positions[$0.key] != nil }
            ?? library.lastEpisode[item.id].flatMap { last in all.firstIndex { $0.id == last }.flatMap { $0 + 1 < all.count ? all[$0 + 1] : nil } }
            ?? all.first
        var out: [String: Any] = ["id": item.id, "name": item.name, "poster": item.poster?.absoluteString ?? "",
                                  "plot": d?.plot ?? item.plot ?? "", "inList": library.isInMyList(item.id)]
        if let next {
            out["next"] = ["episode": next.id, "label": "\(library.positions[next.key] != nil ? "Resume" : "Play") S\(next.season) E\(next.number)"]
        }
        out["seasons"] = seasons.keys.sorted().map { s -> [String: Any] in
            ["season": s, "episodes": (seasons[s] ?? []).map { ep -> [String: Any] in
                ["id": ep.id, "number": ep.number, "title": ep.title, "duration": ep.duration ?? "",
                 "watched": library.lastEpisode[item.id] == ep.id, "resume": library.positions[ep.key] != nil]
            }]
        }
        return out
    }

    func remotePlayEpisode(series id: String, episode: Int) async {
        guard let item = vodItem(id), let d = await vod.details(series: item),
              let ep = d.seasons.values.flatMap({ $0 }).first(where: { $0.id == episode }),
              let url = vod.episodeURL(ep) else { return }
        library.noteEpisode(series: item.id, episodeID: ep.id)
        showSearch = false; showSettings = false
        playVOD(title: "\(item.name) · S\(ep.season)E\(ep.number) \(ep.title)", url: url, poster: item.poster, key: ep.key, group: "Shows")
    }

    func remoteToggleMyList(id: String) -> [String: Any] {
        library.toggleMyList(id)
        return ["inList": library.isInMyList(id)]
    }

    // MARK: Recordings & My list

    func remoteLibrary() async -> [String: Any] {
        await vod.ensureLoaded(.movies)
        await vod.ensureLoaded(.series)
        let recs = library.recordings
        func rec(_ r: Recording) -> [String: Any] {
            ["id": r.id.uuidString, "title": r.title, "channel": r.channelName,
             "time": "\(r.start.formatted(date: .abbreviated, time: .shortened)) – \(r.stop.formatted(date: .omitted, time: .shortened))",
             "status": r.status.rawValue, "playable": r.status == .done && r.file != nil]
        }
        let upcoming = recs.filter { $0.status == .scheduled || $0.status == .recording }.sorted { $0.start < $1.start }
        let done = recs.filter { $0.status == .done }.sorted { $0.start > $1.start }
        let mine = library.myList.compactMap { vodItem($0) }
        return ["upcoming": upcoming.map(rec), "recordings": done.map(rec), "myList": mine.map(remoteVODRow)]
    }

    func remotePlayRecording(id: String) {
        guard let r = library.recordings.first(where: { $0.id.uuidString == id }), r.status == .done, let f = r.file else { return }
        showSearch = false; showSettings = false
        playVOD(title: r.title, url: URL(fileURLWithPath: f), poster: nil, key: "recording|\(r.id)", group: "Recordings")
    }
}
