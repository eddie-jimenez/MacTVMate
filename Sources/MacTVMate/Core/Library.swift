import Foundation
import SwiftUI

/// Loads and holds playlists + EPG for the active source; persists sources, favourites and history.
@MainActor
final class Library: ObservableObject {
    @Published var sources: [PlaylistSource] = [] { didSet { save() } }
    @Published var activeSourceID: UUID? { didSet { save() } }
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var groups: [ChannelGroup] = []
    @Published var favourites: [String] = [] { didSet { save() } }
    @Published private(set) var recents: [String] = []
    @Published private(set) var status: String?
    @Published private(set) var error: String?
    @Published private(set) var epgLoadedAt: Date?
    /// Shown in the guide only when no guide source worked at all.
    @Published private(set) var guideWarning: String?
    /// Per-source status for Settings ▸ EPG.
    struct GuideSourceStatus: Identifiable { let id: String; let name: String; let ok: Bool; let note: String }
    @Published private(set) var guideSources: [GuideSourceStatus] = []
    /// "sourceUUID|group" keys of groups the user hid (excluded from All channels, search and zapping).
    @Published private(set) var hiddenGroups: Set<String> = [] { didSet { save() } }
    @Published var settings = AppSettings() { didSet { save(); if oldValue.hideAdultGroups != settings.hideAdultGroups { rebuildGroups() } } }
    /// Movies/series saved to "My list" ("movie|<id>" / "series|<id>").
    @Published var myList: [String] = [] { didSet { save() } }
    /// Resume positions in seconds for movies/episodes ("movie|<id>" / "episode|<id>").
    @Published var positions: [String: Double] = [:]
    @Published var recordings: [Recording] = [] { didSet { save() } }
    @Published var reminders: [Reminder] = [] { didSet { save() } }
    /// Last episode played per series ("series|<id>" -> episode id), for "next episode" and Continue watching.
    @Published var lastEpisode: [String: Int] = [:]
    var recentSeries: [String] { Array(lastEpisode.keys) }
    var epgMatchedCount: Int { epgKeyForChannel.count }
    /// Debug: which guide entry a channel was matched to.
    func epgKey(for c: Channel) -> String? { epgKeyForChannel[c.id] }

    func noteEpisode(series: String, episodeID: Int) {
        lastEpisode[series] = episodeID
        save()
    }
    /// Every group of the active source with its channel count, including hidden ones (for the manager).
    @Published private(set) var allGroups: [ChannelGroup] = []

    /// Programmes keyed by normalised EPG key.
    private(set) var programmes: [String: [Programme]] = [:]
    /// Channel.id -> EPG key, resolved after each EPG load.
    private var epgKeyForChannel: [String: String] = [:]
    private(set) var xtreamTimeZone: TimeZone?

    // Per-channel guide fallback (Xtream get_short_epg), used for channels the bulk XMLTV didn't cover.
    private var xtreamClient: XtreamClient?
    private var shortEPGQueue: [Channel] = []
    private var shortEPGRequested = Set<String>()
    private var shortEPGTask: Task<Void, Never>?
    /// Guide entries parsed from event channel names (channel id -> programmes).
    private var eventProgrammes: [String: [Programme]] = [:]

    var activeSource: PlaylistSource? { sources.first { $0.id == activeSourceID } ?? sources.first }

    private let store = Persistence()

    init() {
        let saved = store.load()
        sources = saved.sources
        activeSourceID = saved.activeSourceID
        favourites = saved.favourites
        recents = saved.recents
        hiddenGroups = Set(saved.hiddenGroups)
        settings = saved.settings
        myList = saved.myList
        positions = saved.positions
        recordings = saved.recordings
        reminders = saved.reminders
        lastEpisode = saved.lastEpisode
        // Older builds listed iptv.cat first; EPGtalk (Gracenote data) is richer, so it goes first.
        if settings.extraEPGURLs == ["https://epg.iptv.cat/epg.xml", "https://epgtalk.com/US_guide.xml.gz"] {
            settings.extraEPGURLs = AppSettings.defaultGuides
        }
    }

    func save() {
        store.save(.init(sources: sources, activeSourceID: activeSourceID, favourites: favourites, recents: recents,
                         hiddenGroups: hiddenGroups.sorted(), settings: settings, myList: myList, positions: positions,
                         recordings: recordings, reminders: reminders, lastEpisode: lastEpisode))
    }

    func savePosition(_ key: String, _ seconds: Double, duration: Double) {
        // Forget positions near the start or end (finished), like TiViMate's resume.
        if seconds < 30 || (duration > 0 && seconds > duration - 60) { positions[key] = nil } else { positions[key] = seconds }
        save()
    }

    func isInMyList(_ key: String) -> Bool { myList.contains(key) }
    func toggleMyList(_ key: String) {
        if let i = myList.firstIndex(of: key) { myList.remove(at: i) } else { myList.insert(key, at: 0) }
    }

    static func isAdult(_ group: String) -> Bool {
        group.range(of: AppSettings.adultGroupPattern, options: .regularExpression) != nil
    }

    /// Hidden by the "Hide adult groups" setting (separate from manual hiding, so reloads never undo a choice).
    func isHiddenByAdultFilter(_ group: String) -> Bool { settings.hideAdultGroups && Self.isAdult(group) }

    // MARK: Groups

    private func groupKey(_ group: String) -> String { "\(activeSource?.id.uuidString ?? "")|\(group)" }

    func isHidden(_ group: String) -> Bool { isHiddenByAdultFilter(group) || hiddenGroups.contains(groupKey(group)) }

    func setHidden(_ group: String, _ hidden: Bool) {
        if hidden { hiddenGroups.insert(groupKey(group)) } else { hiddenGroups.remove(groupKey(group)) }
        rebuildGroups()
    }

    /// Channels in groups the user hasn't hidden.
    var visibleChannels: [Channel] { channels.filter { !isHidden($0.group) } }

    // MARK: Queries

    func channels(in group: String) -> [Channel] {
        switch group {
        case ChannelGroup.all: return visibleChannels
        case ChannelGroup.favourites:
            let byID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return favourites.compactMap { byID[$0] }
        case ChannelGroup.recent:
            let byID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return recents.compactMap { byID[$0] }
        default: return channels.filter { $0.group == group }
        }
    }

    func programmes(for channel: Channel) -> [Programme] {
        let list = epgKeyForChannel[channel.id].flatMap { programmes[$0] } ?? []
        if list.isEmpty {
            return settings.eventsFromChannelNames ? (eventProgrammes[channel.id] ?? []) : []
        }
        let shift = channel.epgShift * 3600 + Double(settings.epgOffsetMinutes * 60)
        guard shift != 0 else { return list }
        return list.map { var p = $0; p.start += shift; p.stop += shift; return p }
    }

    func programme(for channel: Channel, at date: Date = .now) -> Programme? {
        let list = programmes(for: channel)
        // Binary search on start time.
        var lo = 0, hi = list.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if list[mid].stop <= date { lo = mid + 1 }
            else if list[mid].start > date { hi = mid - 1 }
            else { return list[mid] }
        }
        return nil
    }

    func programmes(for channel: Channel, in range: Range<Date>) -> [Programme] {
        programmes(for: channel).filter { $0.stop > range.lowerBound && $0.start < range.upperBound }
    }

    func isFavourite(_ c: Channel) -> Bool { favourites.contains(c.id) }

    func toggleFavourite(_ c: Channel) {
        if let i = favourites.firstIndex(of: c.id) { favourites.remove(at: i) } else { favourites.append(c.id) }
        rebuildGroups()
    }

    func noteWatched(_ c: Channel) {
        recents.removeAll { $0 == c.id }
        recents.insert(c.id, at: 0)
        if recents.count > 30 { recents.removeLast(recents.count - 30) }
        save()
    }

    // MARK: Loading

    func reload(force: Bool = false) async {
        guard let source = activeSource else {
            channels = []; groups = []; allGroups = []; programmes = [:]
            return
        }
        error = nil
        xtreamClient = nil
        shortEPGTask?.cancel(); shortEPGTask = nil
        shortEPGQueue = []; shortEPGRequested = []
        do {
            switch source.kind {
            case let .m3u(playlistURL, epgURL):
                // TiViMate loads get.php?username&password&type&output URLs through player_api, falling back to the M3U.
                if let x = M3UParser.xtreamCredentials(fromGetPHP: playlistURL),
                   let client = XtreamClient(server: x.server, username: x.username, password: x.password, userAgent: source.userAgent) {
                    do {
                        try await loadXtream(client, source: source, hls: x.hls, epgOverride: epgURL, force: force)
                        break
                    } catch {
                        store.log("Xtream login via get.php failed (\(error.localizedDescription)); loading as M3U")
                    }
                }
                status = "Loading playlist…"
                let data = try await fetch(playlistURL, source: source, cacheName: "playlist", force: force)
                let text = String(decoding: data, as: UTF8.self)
                let result = M3UParser.parse(text, sourceID: source.id)
                setChannels(result.channels)
                store.log("M3U: \(result.channels.count) channels, \(groups.count) groups")
                let epg = epgURL.isEmpty ? (result.headerEPGURL ?? "") : epgURL
                await loadGuide(epg, source: source, force: force)
            case let .xtream(server, username, password):
                guard let client = XtreamClient(server: server, username: username, password: password, userAgent: source.userAgent) else {
                    throw URLError(.badURL)
                }
                try await loadXtream(client, source: source, hls: source.preferHLS, epgOverride: "", force: force)
            }
            status = nil
        } catch {
            status = nil
            self.error = error.localizedDescription
            store.log("Load failed: \(error.localizedDescription)")
        }
    }

    /// Mirrors TiViMate's call order: player_api, then categories, then streams, one at a time with 1 s gaps
    /// (panels rate-limit or ban parallel bursts).
    private func loadXtream(_ client: XtreamClient, source: PlaylistSource, hls: Bool, epgOverride: String, force: Bool) async throws {
        // Responses are cached for the source's refresh interval, so startup is instant and the panel isn't hit every launch.
        let cached = !force && ["xc-info", "xc-categories", "xc-streams"].allSatisfy { isCacheFresh($0, source: source) }
        status = cached ? "Loading channels…" : "Signing in…"
        let info = try XtreamClient.parseServerInfo(try await fetch(client.apiURL().absoluteString, source: source, cacheName: "xc-info", force: force))
        xtreamTimeZone = info.timezone
        status = "Loading channels…"
        if !cached { try await Task.sleep(for: .seconds(1)) }
        let cats = try JSONDecoder().decode([XtreamClient.Category].self,
            from: try await fetch(client.apiURL(action: "get_live_categories").absoluteString, source: source, cacheName: "xc-categories", force: force))
        if !cached { try await Task.sleep(for: .seconds(1)) }
        let list = try JSONDecoder().decode([XtreamClient.LiveStream].self,
            from: try await fetch(client.apiURL(action: "get_live_streams").absoluteString, source: source, cacheName: "xc-streams", force: force))
        xtreamClient = client
        let catNames = Dictionary(cats.map { ($0.category_id.value, $0.category_name) }, uniquingKeysWith: { a, _ in a })
        let chans: [Channel] = list.enumerated().map { idx, s in
            var c = Channel(
                id: "\(source.id.uuidString)|\(s.stream_id.value)",
                number: s.num?.value ?? idx + 1,
                name: s.name,
                group: s.category_id.flatMap { catNames[$0.value] } ?? "Uncategorised",
                logo: s.stream_icon.flatMap { URL(string: $0) },
                url: client.liveURL(streamID: s.stream_id.value, hls: hls),
                epgID: s.epg_channel_id.flatMap { $0.isEmpty ? nil : $0 }
            )
            c.xtreamStreamID = s.stream_id.value
            // TiViMate only checks tv_archive_duration > 0 (not the tv_archive flag).
            if let days = s.tv_archive_duration?.value, days > 0 {
                c.catchupDays = days
                c.catchupMode = "xc"
            }
            return c
        }
        setChannels(chans)
        store.log("Xtream\(cached ? " (cached)" : ""): \(chans.count) live channels in \(catNames.count) categories, \(chans.filter(\.hasCatchup).count) with catch-up, server tz \(info.timezone?.identifier ?? "unknown"), status \(info.status ?? "?"), output \(hls ? "m3u8" : "ts")")
        let epgURL = epgOverride.isEmpty ? client.xmltvURL.absoluteString : epgOverride
        await loadGuide(epgURL, source: source, force: force)
    }

    /// Loads the playlist's guide plus any extra XMLTV sources (Settings ▸ EPG), then matches channels
    /// source by source. Every source is optional: channels stay usable if one fails (some panels 502 on xmltv.php).
    private func loadGuide(_ url: String, source: PlaylistSource, force: Bool) async {
        status = "Loading TV guide…"
        guideWarning = nil
        var datas: [Data] = []
        var statuses: [GuideSourceStatus] = []
        var sources: [(name: String, url: String, cache: String)] = []
        if !url.isEmpty { sources.append(("Provider guide", url, "epg")) }
        for extra in settings.extraEPGURLs {
            sources.append((URL(string: extra)?.host ?? extra, extra, "epg-extra-\(Self.stableHash(extra))"))
        }
        for s in sources {
            let (data, note) = await fetchGuide(s.url, source: source, cacheName: s.cache, force: force)
            if let data { datas.append(data) }
            statuses.append(GuideSourceStatus(id: s.cache, name: s.name, ok: data != nil, note: note))
        }
        guideSources = statuses
        if datas.isEmpty, !sources.isEmpty {
            guideWarning = "TV guide unavailable right now. Channels still work."
        }
        await applyEPG(datas)
    }

    /// A failing source is retried at most every 6 h (or on "Update guide now"); its last good copy is used meanwhile.
    private func fetchGuide(_ url: String, source: PlaylistSource, cacheName: String, force: Bool) async -> (Data?, String) {
        let marker = store.cacheURL(source: source.id, name: cacheName + ".failed")
        let lastGood = store.cacheURL(source: source.id, name: cacheName)
        func fallback(_ why: String) -> (Data?, String) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: lastGood.path),
               let modified = attrs[.modificationDate] as? Date, Date().timeIntervalSince(modified) < 3 * 86400,
               let d = try? Data(contentsOf: lastGood) {
                return (d, "\(why); using copy from \(modified.formatted(date: .abbreviated, time: .shortened))")
            }
            return (nil, why)
        }
        if !force, let attrs = try? FileManager.default.attributesOfItem(atPath: marker.path),
           let failedAt = attrs[.modificationDate] as? Date, Date().timeIntervalSince(failedAt) < 6 * 3600,
           let why = try? String(contentsOf: marker, encoding: .utf8) {
            return fallback("\(why) (retrying after \(failedAt.addingTimeInterval(6 * 3600).formatted(date: .omitted, time: .shortened)))")
        }
        do {
            let d = try await fetch(url, source: source, cacheName: cacheName, force: force)
            try? FileManager.default.removeItem(at: marker)
            return (d, "OK")
        } catch {
            store.log("Guide \(URL(string: url)?.host ?? "?") failed: \(error.localizedDescription)")
            try? error.localizedDescription.write(to: marker, atomically: true, encoding: .utf8)
            return fallback(error.localizedDescription)
        }
    }

    static func stableHash(_ s: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 36)
    }

    private func setChannels(_ list: [Channel]) {
        channels = list.sorted { $0.number < $1.number }
        var events: [String: [Programme]] = [:]
        for c in channels { if let e = EventParser.programmes(for: c) { events[c.id] = e } }
        eventProgrammes = events
        rebuildGroups()
    }

    private func rebuildGroups() {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for c in channels {
            if counts[c.group] == nil { order.append(c.group) }
            counts[c.group, default: 0] += 1
        }
        allGroups = order.map { ChannelGroup(name: $0, count: counts[$0]!) }
        var result = [ChannelGroup(name: ChannelGroup.all, count: visibleChannels.count)]
        let favCount = channels(in: ChannelGroup.favourites).count
        if favCount > 0 { result.insert(ChannelGroup(name: ChannelGroup.favourites, count: favCount), at: 0) }
        let recentCount = channels(in: ChannelGroup.recent).count
        if recentCount > 0 { result.append(ChannelGroup(name: ChannelGroup.recent, count: recentCount)) }
        result += order.filter { !isHidden($0) }.map { ChannelGroup(name: $0, count: counts[$0]!) }
        groups = result
    }

    private func applyEPG(_ datas: [Data]) async {
        let maxCatchup = channels.map(\.catchupDays).max() ?? 0
        let now = Date()
        let past = Double(max(settings.pastEPGDays, maxCatchup, 1)) * 86400
        let window = now.addingTimeInterval(-past)...now.addingTimeInterval(10 * 86400)
        let wanted = ChannelMatch.Wanted(
            ids: Set(channels.compactMap { $0.epgID.map(XMLTVParser.key) }),
            names: Set(channels.flatMap { ChannelMatch.candidates($0.name) } + channels.compactMap { $0.epgID.map(ChannelMatch.normalise) }))
        var results: [XMLTVParser.Result] = []
        for (i, d) in datas.enumerated() {
            status = datas.count > 1 ? "Loading TV guide (\(i + 1)/\(datas.count))…" : "Loading TV guide…"
            results.append(await Task.detached(priority: .userInitiated) { XMLTVParser.parse(data: d, window: window, wanted: wanted) }.value)
        }

        // Keys are prefixed per source ("s0|id") so sources never collide; earlier sources win.
        var merged: [String: [Programme]] = [:]
        var map: [String: String] = [:]
        var perSource: [Int] = []
        for (i, r) in results.enumerated() {
            for (id, list) in r.programmes { merged["s\(i)|\(id)"] = list }
            // Several feeds can share a name ("Cinemax" US and LatAm): prefer English listings.
            func better(_ a: String?, _ b: String) -> String {
                guard let a else { return b }
                let la = r.languages[a] ?? "en", lb = r.languages[b] ?? "en"
                return la != "en" && lb == "en" ? b : a
            }
            var byName: [String: String] = [:]
            var byStation: [String: String] = [:]
            for (id, names) in r.displayNames where r.programmes[id] != nil {
                for n in names { let k = Self.normalise(n); byName[k] = better(byName[k], id) }
                let k = Self.normalise(id); byName[k] = better(byName[k], id)
                // Gracenote ids ("I2.1.19600.gracenote.com") carry the TMS station number some panels use as tvg-id.
                if let station = id.split(separator: ".").dropLast(2).last, id.hasSuffix("gracenote.com") { byStation[String(station)] = id }
            }
            var n = 0
            for c in channels where map[c.id] == nil {
                let epg = c.epgID.map(XMLTVParser.key)
                let hit: String? = {
                    if let e = epg, r.programmes[e] != nil { return e }
                    if let e = c.epgID, let id = byStation[e], r.programmes[id] != nil { return id }
                    if let e = c.epgID, let id = byName[Self.normalise(e)], r.programmes[id] != nil { return id }
                    for k in ChannelMatch.candidates(c.name) {
                        if let id = byName[k], r.programmes[id] != nil { return id }
                    }
                    return nil
                }()
                if let hit { map[c.id] = "s\(i)|\(hit)"; n += 1 }
            }
            perSource.append(n)
        }
        // Keep per-channel fallback listings fetched earlier.
        for (k, v) in programmes where k.hasPrefix("xc:") { merged[k] = v }
        for (cid, k) in epgKeyForChannel where k.hasPrefix("xc:") && map[cid] == nil { map[cid] = k }
        programmes = merged
        epgKeyForChannel = map
        epgLoadedAt = now
        store.log("EPG: \(results.count) source(s), matched \(map.count) of \(channels.count) channels \(perSource); \(eventProgrammes.count) event channels from names")
    }

    static func normalise(_ s: String) -> String { ChannelMatch.normalise(s) }

    /// Superseded by ChannelMatch.normalise.
    private static func legacyNormalise(_ s: String) -> String {
        var t = s.lowercased().replacingOccurrences(of: "&", with: " and ")
        // Country prefixes: "US:", "USA:", "US -", "(US)", "US " (as in "US Investigation Discovery").
        t = t.replacingOccurrences(of: #"^\s*(\(?\s*(us|usa|uk|ca)\s*\)?\s*[:|\-]?\s+|[a-z]{2,3}\s*[:|]\s*)"#, with: "", options: .regularExpression)
        // Quality / feed tags: HD, FHD, 4K, (H), (P), East, West…
        t = t.replacingOccurrences(of: #"[\(\[]?\b(fhd|uhd|hd|sd|4k|hevc|h265|1080p|720p|east|west|e|w|h|p|vip)\b[\)\]]?"#, with: "", options: .regularExpression)
        return t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    // MARK: Per-channel guide fallback

    /// Ask for listings of a channel the bulk guide doesn't cover. Newest requests are served first,
    /// one request per second at most (TiViMate spaces Xtream detail calls ≥ 1 s apart).
    func wantEPG(_ c: Channel) {
        guard xtreamClient != nil, c.xtreamStreamID != nil, epgKeyForChannel[c.id] == nil,
              !shortEPGRequested.contains(c.id) else { return }
        shortEPGRequested.insert(c.id)
        shortEPGQueue.append(c)
        if shortEPGQueue.count > 40 { shortEPGRequested.remove(shortEPGQueue.removeFirst().id) }
        guard shortEPGTask == nil else { return }
        shortEPGTask = Task { [weak self] in
            while !Task.isCancelled, let self, let c = self.shortEPGQueue.popLast() {
                guard let client = self.xtreamClient, let id = c.xtreamStreamID else { break }
                if let progs = try? await client.shortEPG(streamID: id), !progs.isEmpty, !Task.isCancelled {
                    let key = "xc:\(id)"
                    self.programmes[key] = progs
                    self.epgKeyForChannel[c.id] = key
                    self.objectWillChange.send()
                }
                try? await Task.sleep(for: .seconds(1))
            }
            self?.shortEPGTask = nil
        }
    }

    // MARK: Network + cache

    private func isCacheFresh(_ name: String, source: PlaylistSource) -> Bool {
        let url = store.cacheURL(source: source.id, name: name)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < Double(source.refreshHours) * 3600
    }

    /// The Xtream login of the active playlist (VOD needs it even when the guide fell back).
    var xtreamClientForVOD: XtreamClient? { xtreamClient }

    func fetch(_ urlString: String, source: PlaylistSource, cacheName: String, force: Bool) async throws -> Data {
        let cacheURL = store.cacheURL(source: source.id, name: cacheName)
        if !force,
           let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Double(source.refreshHours) * 3600,
           let data = try? Data(contentsOf: cacheURL) {
            return data
        }
        let data: Data
        if urlString.hasPrefix("/") || urlString.hasPrefix("file://") {
            let url = urlString.hasPrefix("/") ? URL(fileURLWithPath: urlString) : URL(string: urlString)!
            data = try Data(contentsOf: url)
        } else {
            guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw URLError(.badURL) }
            var req = URLRequest(url: url, timeoutInterval: 120)
            req.setValue(source.userAgent.isEmpty ? Defaults.userAgent : source.userAgent, forHTTPHeaderField: "User-Agent")
            var (d, resp) = try await URLSession.shared.data(for: req)
            // TiViMate retries playlist downloads once with a desktop browser UA on 401/403; we also retry 5xx.
            if let http = resp as? HTTPURLResponse, [401, 403].contains(http.statusCode) || (500...599).contains(http.statusCode) {
                if http.statusCode >= 500 { try? await Task.sleep(for: .seconds(2)) }
                req.setValue(Defaults.browserUserAgent, forHTTPHeaderField: "User-Agent")
                (d, resp) = try await URLSession.shared.data(for: req)
            }
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) loading \(url.host ?? urlString)"])
            }
            data = d
        }
        try? data.write(to: cacheURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        return data
    }

    func remove(_ source: PlaylistSource) {
        sources.removeAll { $0.id == source.id }
        store.clearCache(source: source.id)
        if activeSourceID == source.id { activeSourceID = sources.first?.id }
    }
}

/// JSON state in ~/Library/Application Support/MacTVMate.
struct Persistence {
    struct State: Codable {
        var sources: [PlaylistSource] = []
        var activeSourceID: UUID?
        var favourites: [String] = []
        var recents: [String] = []
        var hiddenGroups: [String] = []
        var settings = AppSettings()
        var myList: [String] = []
        var positions: [String: Double] = [:]
        var recordings: [Recording] = []
        var reminders: [Reminder] = []
        var lastEpisode: [String: Int] = [:]

        init(sources: [PlaylistSource] = [], activeSourceID: UUID? = nil, favourites: [String] = [], recents: [String] = [],
             hiddenGroups: [String] = [], settings: AppSettings = AppSettings(), myList: [String] = [],
             positions: [String: Double] = [:], recordings: [Recording] = [], reminders: [Reminder] = [],
             lastEpisode: [String: Int] = [:]) {
            self.sources = sources; self.activeSourceID = activeSourceID
            self.favourites = favourites; self.recents = recents; self.hiddenGroups = hiddenGroups
            self.settings = settings; self.myList = myList; self.positions = positions
            self.recordings = recordings; self.reminders = reminders; self.lastEpisode = lastEpisode
        }

        // Missing keys (older versions) fall back to defaults instead of failing the whole decode.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sources = try c.decodeIfPresent([PlaylistSource].self, forKey: .sources) ?? []
            activeSourceID = try c.decodeIfPresent(UUID.self, forKey: .activeSourceID)
            favourites = try c.decodeIfPresent([String].self, forKey: .favourites) ?? []
            recents = try c.decodeIfPresent([String].self, forKey: .recents) ?? []
            hiddenGroups = try c.decodeIfPresent([String].self, forKey: .hiddenGroups) ?? []
            settings = (try? c.decodeIfPresent(AppSettings.self, forKey: .settings)) ?? AppSettings()
            myList = (try? c.decodeIfPresent([String].self, forKey: .myList)) ?? []
            positions = (try? c.decodeIfPresent([String: Double].self, forKey: .positions)) ?? [:]
            recordings = (try? c.decodeIfPresent([Recording].self, forKey: .recordings)) ?? []
            reminders = (try? c.decodeIfPresent([Reminder].self, forKey: .reminders)) ?? []
            lastEpisode = (try? c.decodeIfPresent([String: Int].self, forKey: .lastEpisode)) ?? [:]
        }
    }

    let dir: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.appendingPathComponent("MacTVMate")
        // The app was called TiViMac during development: carry its data (playlists, favourites, caches) over once.
        let old = support.appendingPathComponent("TiViMac")
        if !FileManager.default.fileExists(atPath: base.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: base)
        }
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("cache"), withIntermediateDirectories: true)
        return base
    }()

    private var stateURL: URL { dir.appendingPathComponent("state.json") }

    func load() -> State {
        (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    func save(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
        // Holds playlist logins: readable by this user only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    func cacheURL(source: UUID, name: String) -> URL {
        dir.appendingPathComponent("cache/\(source.uuidString)-\(name)")
    }

    /// Diagnostic log (counts and errors only — never credentials).
    func log(_ line: String) {
        let url = dir.appendingPathComponent("load.log")
        let entry = "\(ISO8601DateFormatter().string(from: .now)) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(entry.utf8)); try? h.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }

    func clearCache(source: UUID) {
        for n in ["playlist", "epg", "xc-info", "xc-categories", "xc-streams",
                  "xc-movies", "xc-movies-categories", "xc-series", "xc-series-categories"] {
            try? FileManager.default.removeItem(at: cacheURL(source: source, name: n))
        }
    }
}
