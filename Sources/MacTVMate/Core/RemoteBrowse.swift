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
        let failed = recs.filter { $0.status == .failed }.sorted { $0.start > $1.start }
        let favs = library.channels(in: ChannelGroup.favourites).map { c -> [String: Any] in
            ["id": c.id, "number": c.number, "name": c.name, "logo": c.logo?.absoluteString ?? "",
             "title": library.programme(for: c, at: now)?.displayTitle ?? ""]
        }
        return ["upcoming": upcoming.map(rec), "recordings": done.map(rec), "failed": failed.map(rec),
                "myList": mine.map(remoteVODRow), "reminders": remoteReminders(), "favourites": favs]
    }

    func remotePlayRecording(id: String) {
        guard let r = library.recordings.first(where: { $0.id.uuidString == id }), r.status == .done, let f = r.file else { return }
        showSearch = false; showSettings = false
        playVOD(title: r.title, url: URL(fileURLWithPath: f), poster: nil, key: "recording|\(r.id)", group: "Recordings")
    }
}

// MARK: - Everything else the Mac can do, for the phone

extension AppModel {
    private func channel(_ id: String) -> Channel? { library.channels.first { $0.id == id } }

    /// A channel's schedule (−3 h … +24 h) with what can be done to each programme.
    func remoteChannel(id: String) -> [String: Any] {
        guard let ch = channel(id) else { return [:] }
        let progs = library.programmes(for: ch, in: now.addingTimeInterval(-3 * 3600)..<now.addingTimeInterval(24 * 3600))
        let rows = progs.map { p -> [String: Any] in
            let live = p.isLive(at: now)
            var r: [String: Any] = ["start": Int(p.start.timeIntervalSince1970), "title": p.displayTitle,
                                    "time": Theme.range(p), "day": Theme.dayLabel(p.start), "live": live,
                                    "past": p.stop <= now, "future": p.start > now, "desc": p.desc ?? "",
                                    "catchup": ch.hasCatchup && (p.stop <= now || live),
                                    "reminder": recorder.hasReminder(ch, p)]
            if let rec = recorder.recording(for: ch, p), rec.status == .scheduled || rec.status == .recording {
                r["recording"] = rec.status.rawValue
            }
            if let g = game(for: p, channel: ch), let line = g.scoreLine { r["score"] = "\(line) · \(g.detail)" }
            return r
        }
        return ["id": ch.id, "name": ch.name, "number": ch.number, "logo": ch.logo?.absoluteString ?? "",
                "group": ch.group, "favourite": library.isFavourite(ch), "playing": playing?.channel.id == ch.id,
                "streamRecording": playing?.channel.id == ch.id && player.isRecording,
                "programmes": rows]
    }

    /// watch · catchup · favourite · record · cancelRecord · remind · cancelRemind · recordStream
    func remoteChannelAction(id: String, action: String, start: Int?) {
        guard let ch = channel(id) else { return }
        let p = start.flatMap { s in library.programmes(for: ch).first { Int($0.start.timeIntervalSince1970) == s } }
        showSearch = false; showSettings = false
        switch action {
        case "watch": play(ch)
        case "catchup": if let p { playCatchup(ch, p) }
        case "favourite": library.toggleFavourite(ch)
        case "record": record(ch, p ?? library.programme(for: ch, at: now))
        case "cancelRecord":
            if let p, let r = recorder.recording(for: ch, p) { recorder.cancel(r) }
        case "remind": if let p { recorder.remind(ch, p) }
        case "cancelRemind": if let p { recorder.removeReminder(ch, p) }
        default: break
        }
    }

    // MARK: Recordings & reminders

    func remoteRecordingAction(id: String, action: String) {
        if let r = library.recordings.first(where: { $0.id.uuidString == id }) {
            switch action {
            case "cancel": recorder.cancel(r)
            case "delete": recorder.delete(r)
            case "play": remotePlayRecording(id: id)
            default: break
            }
        } else if action == "delete" {
            library.reminders.removeAll { $0.id.uuidString == id }
        }
    }

    func remoteReminders() -> [[String: Any]] {
        library.reminders.sorted { $0.start < $1.start }.map {
            ["id": $0.id.uuidString, "title": $0.title, "channel": $0.channelName,
             "time": $0.start.formatted(date: .abbreviated, time: .shortened)]
        }
    }

    // MARK: Audio & subtitles

    func remoteTracks() -> [String: Any] {
        ["audio": player.audioTracks.map { ["id": $0.id, "title": $0.title, "selected": $0.selected] },
         "subtitles": player.subtitleTracks.map { ["id": $0.id, "title": $0.title, "selected": $0.selected] }]
    }

    func remoteSelectTrack(type: String, id: Int?) {
        if type == "audio", let id { player.selectAudio(id) } else if type == "subtitles" { player.selectSubtitle(id) }
    }

    // MARK: Settings

    private struct BoolSetting { let key: String, section: String, title: String; let path: WritableKeyPath<AppSettings, Bool> }
    private struct IntSetting { let key: String, section: String, title: String; let path: WritableKeyPath<AppSettings, Int>; let options: [(Int, String)] }

    private static let boolSettings: [BoolSetting] = [
        .init(key: "startOnLastChannel", section: "General", title: "Play the last channel on start", path: \.startOnLastChannel),
        .init(key: "previewOnFocus", section: "General", title: "Preview the focused channel", path: \.previewOnFocus),
        .init(key: "hideAdultGroups", section: "General", title: "Hide adult groups (XXX, Adult, 18+)", path: \.hideAdultGroups),
        .init(key: "showGroupColumn", section: "TV guide", title: "Show group column", path: \.showGroupColumn),
        .init(key: "showChannelNumbers", section: "TV guide", title: "Show channel numbers", path: \.showChannelNumbers),
        .init(key: "dimPastProgrammes", section: "TV guide", title: "Dim past programmes", path: \.dimPastProgrammes),
        .init(key: "guideArrowsChangeChannelNumber", section: "TV guide", title: "↑ / ↓ change channel number (↓ = 44 → 43)", path: \.guideArrowsChangeChannelNumber),
        .init(key: "eventsFromChannelNames", section: "TV guide", title: "Show events from channel names", path: \.eventsFromChannelNames),
        .init(key: "hardwareDecoding", section: "Playback", title: "Hardware decoding (VideoToolbox)", path: \.hardwareDecoding),
    ]

    private static var intSettings: [IntSetting] {
        [.init(key: "interfaceSize", section: "Appearance", title: "Interface size", path: \.interfaceSize,
               options: [(0, "Auto")] + [100, 125, 150, 175, 200, 250].map { ($0, "\($0)%") }),
         .init(key: "guideSize", section: "TV guide", title: "Guide size", path: \.guideSize,
               options: AppSettings.sizeNames.enumerated().map { ($0.offset, $0.element) }),
         .init(key: "bufferSize", section: "Playback", title: "Buffer size", path: \.bufferSize,
               options: AppSettings.bufferNames.enumerated().map { ($0.offset, $0.element) }),
         .init(key: "pastEPGDays", section: "TV guide", title: "Past days kept", path: \.pastEPGDays,
               options: [1, 2, 3, 5, 7, 14, 30].map { ($0, "\($0)") }),
         .init(key: "epgOffsetMinutes", section: "TV guide", title: "Guide time offset", path: \.epgOffsetMinutes,
               options: stride(from: -180, through: 180, by: 30).map { ($0, "\($0 >= 0 ? "+" : "")\($0) min") })]
    }

    func remoteSettings() -> [String: Any] {
        let s = library.settings
        var items: [[String: Any]] = Self.boolSettings.map {
            ["key": $0.key, "section": $0.section, "title": $0.title, "type": "bool", "value": s[keyPath: $0.path]]
        }
        items += Self.intSettings.map {
            ["key": $0.key, "section": $0.section, "title": $0.title, "type": "choice", "value": s[keyPath: $0.path],
             "options": $0.options.map { ["value": $0.0, "label": $0.1] }]
        }
        items.append(["key": "accent", "section": "Appearance", "title": "Accent colour", "type": "choice", "value": s.accent,
                      "options": AppSettings.accents.map { ["value": $0.0, "label": $0.0, "hex": String(format: "#%06X", $0.1)] }])
        let order = ["General", "Appearance", "TV guide", "Playback"]
        items = items.enumerated().sorted {
            let a = order.firstIndex(of: $0.element["section"] as? String ?? "") ?? 9, b = order.firstIndex(of: $1.element["section"] as? String ?? "") ?? 9
            return a != b ? a < b : $0.offset < $1.offset
        }.map(\.element)
        let groups = library.allGroups.map { g -> [String: Any] in
            ["name": g.name, "count": g.count, "hidden": library.isHidden(g.name), "locked": library.isHiddenByAdultFilter(g.name)]
        }
        return ["items": items, "groups": groups, "display": displayInfo,
                "status": library.status ?? library.error ?? "\(library.channels.count) channels",
                "guide": library.guideSources.map { ["name": $0.name, "ok": $0.ok, "note": $0.note] }]
    }

    func remoteSetSetting(key: String, value: Any?) {
        if key == "accent", let v = value as? String { library.settings.accent = v; return }
        if let b = Self.boolSettings.first(where: { $0.key == key }), let v = value as? Bool {
            library.settings[keyPath: b.path] = v
        } else if let i = Self.intSettings.first(where: { $0.key == key }), let v = (value as? Int) ?? (value as? NSNumber)?.intValue {
            library.settings[keyPath: i.path] = v
        }
    }

    func remoteSetGroupHidden(_ name: String, _ hidden: Bool) { library.setHidden(name, hidden) }
}
