import AppKit

/// Developer aid: `MACTVMATE_SNAPSHOTS=/some/dir` makes the app walk through its screens and
/// save PNGs of the window (UI) and of the decoded video frame (via mpv), so it can be checked headlessly.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(_ model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["MACTVMATE_SNAPSHOTS"] else { return }
        let base = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            @MainActor func probe(_ name: String) {
                DispatchQueue.main.async {
                    print("[probe] \(name) …"); fflush(stdout)
                    MainActor.assumeIsolated { print("[probe] \(name) OK") }
                    fflush(stdout)
                }
            }
            probe("startup")
            @MainActor func snap(_ name: String) {
                probe(name)
                guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return }
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: base.appendingPathComponent("\(name).png"))
                model.player.screenshot(to: base.appendingPathComponent("\(name)-video.png"))
                let p = model.player
                print("[snap] \(name) screen=\(model.screen) playing=\(model.playing?.channel.name ?? "-") idle=\(p.isIdle) buffering=\(p.isBuffering) tuning=\(p.tuning) blank=\(p.blankVideo) video=\(p.videoSize) err=\(p.errorMessage ?? "-") channels=\(model.library.channels.count) status=\(model.library.status ?? "-") libErr=\(model.library.error ?? "-")")
                fflush(stdout)
            }
            if ProcessInfo.processInfo.environment["MACTVMATE_KEY_TEST"] != nil {
                for _ in 0..<60 where model.library.channels.isEmpty { await wait(1) }
                for _ in 0..<120 where model.library.epgLoadedAt == nil { await wait(1) }
                model.screen = .guide; model.selectedGroup = "US Movies"; model.guideRow = 3; model.guideTime = .now
                await wait(2)
                @MainActor func state(_ tag: String) {
                    let ch = model.guideSelectedChannel
                    print("[key] \(tag): row \(model.guideRow) \(ch.map { "\($0.number) \($0.name)" } ?? "-") | \(model.guideSelectedProgramme?.displayTitle ?? "-") | first responder \(NSApp.keyWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil") key window \(NSApp.keyWindow != nil)")
                    fflush(stdout)
                }
                // Reproduce the stuck state: a text field takes focus, then disappears (like leaving a search box).
                if let w = NSApp.keyWindow, let content = w.contentView {
                    let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
                    content.addSubview(f)
                    w.makeFirstResponder(f)
                    f.isHidden = true
                }
                state("start (stale text focus)")
                for (code, chars, name) in [(UInt16(125), "\u{F701}", "down"), (125, "\u{F701}", "down"), (124, "\u{F703}", "right"), (124, "\u{F703}", "right"), (126, "\u{F700}", "up"), (123, "\u{F702}", "left")] {
                    model.remoteAction(code == 125 ? .down : code == 126 ? .up : code == 124 ? .right : .left)
                    await wait(1.2)
                    state(name + " (\(chars.count))")
                }
                print("[snap] done"); fflush(stdout); return
            }
            if ProcessInfo.processInfo.environment["MACTVMATE_VOD_TEST"] != nil {
                for _ in 0..<60 where model.library.channels.isEmpty { await wait(1) }
                for _ in 0..<60 where !model.meta.imdbReady { await wait(1) }
                model.screen = .movies
                let t0 = Date()
                await model.vod.ensureLoaded(.movies)
                await model.vod.matchIMDb(.movies)
                let m = model.vod.movies
                print("[vod] movies \(m.count) unique, IMDb-matched \(m.filter { model.vod.imdb[$0.id] != nil }.count) in \(Int(Date().timeIntervalSince(t0)))s; multi-category \(m.filter { $0.categoryIDs.count > 1 }.count)")
                let top = m.compactMap { i in model.vod.imdb[i.id].map { (i, $0) } }.filter { $0.1.votes >= 1000 }.sorted { $0.1.rating > $1.1.rating }.prefix(8)
                for (i, t) in top { print("   \(i.name) → \(t.title) (\(t.year ?? 0)) ★\(t.ratingText) \(t.votesText)") }
                await model.vod.ensureLoaded(.series); await model.vod.matchIMDb(.series)
                print("[vod] shows \(model.vod.series.count) unique, IMDb-matched \(model.vod.series.filter { model.vod.imdb[$0.id] != nil }.count)")
                fflush(stdout)
                await wait(4); snap("V-movies")
                if ProcessInfo.processInfo.environment["MACTVMATE_SCRUB_TEST"] != nil,
                   let m = model.vod.movies.first(where: { model.vod.imdb[$0.id] != nil }), let url = model.vod.movieURL(m, ext: nil) {
                    model.playVOD(title: m.name, url: url, poster: m.poster, key: m.id, group: "Movies")
                    for _ in 0..<20 where model.player.duration <= 0 { await wait(1) }
                    model.player.seek(absolute: model.player.duration * 0.4)
                    await wait(3); model.flashInfoBar()
                    await wait(1); snap("P-scrub")
                    print("[vod] playing \(m.name): position \(Int(model.player.position))s of \(Int(model.player.duration))s, err \(model.player.errorMessage ?? "-")")
                    model.player.stop()
                }
                print("[snap] done"); fflush(stdout); return
            }
            if ProcessInfo.processInfo.environment["MACTVMATE_GROUP_TEST"] != nil {
                for _ in 0..<60 where model.library.channels.isEmpty { await wait(1) }
                for _ in 0..<120 where model.library.epgLoadedAt == nil { await wait(1) }
                model.screen = .guide
                model.selectedGroup = "NFL"; model.guideRow = 0
                await wait(3); snap("H1-nfl")
                model.selectedGroup = "US Movies"; model.guideRow = 0
                await wait(3); snap("H2-usmovies")
                print("[group] first rows of \(model.selectedGroup): \(model.groupChannels.prefix(3).map(\.name))")
                print("[snap] done"); fflush(stdout); return
            }
            if let group = ProcessInfo.processInfo.environment["MACTVMATE_DUMP_GROUP"] {
                for _ in 0..<60 where model.library.channels.isEmpty { await wait(1) }
                for _ in 0..<120 where model.library.epgLoadedAt == nil { await wait(1) }
                for c in model.library.channels(in: group) {
                    for q in model.library.programmes(for: c) where (q.title + " " + (q.subtitle ?? "")).range(of: #"(?i)\bnfl\b|football"#, options: .regularExpression) != nil {
                        print("[hit] \(c.name) | key \(model.library.epgKey(for: c) ?? "-") | \(Theme.dayLabel(q.start, withTime: true)) \(q.title) | \(q.subtitle ?? "-") [\(q.kind)]")
                    }
                    let p = model.library.programme(for: c, at: .now)
                    print("[dump] \(c.number) \(c.name) | tvg-id \(c.epgID ?? "-") | key \(model.library.epgKey(for: c) ?? "-") | now: \(p?.title ?? "-") [\(p.map { "\($0.kind)" } ?? "")]")
                }
                print("[snap] done"); fflush(stdout); return
            }
            if ProcessInfo.processInfo.environment["MACTVMATE_REC_TEST"] != nil {
                for _ in 0..<60 where model.library.channels.isEmpty { await wait(1) }
                // A guide-matched channel (likely live and stable), recorded for 20 s via the scheduler path.
                guard let ch = model.library.visibleChannels.first(where: { $0.name.contains("HBO (East)") }) ?? model.library.visibleChannels.first else { return }
                let p = Programme(channelKey: "test", start: Date(), stop: Date().addingTimeInterval(20), title: "Recording test")
                model.recorder.recordNow(ch, programme: p, userAgent: model.library.activeSource?.userAgent ?? "")
                // recordNow pads 5 min after the programme; trim this test to 20 s.
                if let i = model.library.recordings.lastIndex(where: { $0.title == "Recording test" }) {
                    model.recorder.cancel(model.library.recordings[i]); model.library.recordings.remove(at: i)
                }
                model.library.recordings.append(Recording(channelID: ch.id, channelName: ch.name, title: "Recording test",
                    start: Date(), stop: Date().addingTimeInterval(20), url: ch.url, userAgent: model.library.activeSource?.userAgent ?? ""))
                print("[rec] recording \(ch.name) for 20 s…"); fflush(stdout)
                for _ in 0..<45 {
                    await wait(1)
                    if let r = model.library.recordings.last, r.status == .done || r.status == .failed { break }
                }
                if let r = model.library.recordings.last {
                    let size = r.file.flatMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? Int } ?? 0
                    print("[rec] status \(r.status.rawValue) size \(size / 1024) KB error \(r.error ?? "-") file \(r.file.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "-")")
                }
                print("[snap] done"); fflush(stdout); return
            }
            if ProcessInfo.processInfo.environment["MACTVMATE_FULL_TEST"] != nil {
                await fullTest(model, snap: snap, wait: wait)
                print("[snap] done"); fflush(stdout); return
            }
            // Wait for the playlist, then exercise search.
            for _ in 0..<60 where model.library.channels.isEmpty { await wait(1) }
            for q in ["49ers", "niners", "NFL", "FOX", "ESPN"] {
                let r = model.search(q)
                print("[search] \(q): \(r.channels.count) channels, \(r.programmes.count) programmes — " +
                      (r.channels.prefix(8).map { "\($0.channel.number) \($0.channel.name)" } + r.programmes.prefix(5).map { "\($0.channel.name): \($0.programme!.title)" }).joined(separator: " | "))
                fflush(stdout)
            }
            print("[groups] " + model.library.allGroups.map { "\($0.name) (\($0.count))" }.joined(separator: " | ")); fflush(stdout)
            // Guide fallback: let the visible rows request listings, then report coverage.
            model.selectedGroup = model.library.groups.first(where: { $0.name.localizedCaseInsensitiveContains("nfl") })?.name ?? ChannelGroup.all
            model.screen = .guide
            await wait(14)
            let shown = model.groupChannels.prefix(12)
            print("[epg] group \(model.selectedGroup): \(shown.filter { model.library.programme(for: $0) != nil }.count)/\(shown.count) of the first rows have a current programme; e.g. " +
                  shown.compactMap { c in model.library.programme(for: c).map { "\(c.name) → \($0.title) \(Theme.range($0))" } }.prefix(4).joined(separator: " | "))
            fflush(stdout)
            snap("0-guide-nfl")
            model.searchQuery = "NFL"; model.openSearch()
            await wait(2); snap("0-search")
            model.showSearch = false
            if ProcessInfo.processInfo.environment["MACTVMATE_SEARCH_ONLY"] != nil { print("[snap] done"); fflush(stdout); return }
            await wait(8); snap("1-guide")
            model.guideMove(rows: 1); model.guideMove(programmes: 1)
            await wait(5); snap("2-guide-moved")
            model.screen = .player; model.flashInfoBar()
            await wait(3); snap("3-player-info")
            model.openChannelList()
            await wait(5); snap("4-channel-list")
            model.showChannelList = false
            model.zap(1)
            await wait(6); snap("5-zapped")
            if let ch = model.library.channels.first(where: \.hasCatchup),
               let p = model.library.programmes(for: ch).last(where: { $0.stop < .now }) {
                print("[snap] catchup URL: \(Catchup.url(for: ch, programme: p, xtream: nil, serverTimeZone: nil)?.absoluteString ?? "nil")")
            }
            model.settingsSection = .playlists; model.showSettings = true
            await wait(1); snap("6-sources")

            print("[snap] done"); fflush(stdout)
        }
    }

    /// End-to-end pass: guide sources, events, VOD, screens.
    static func fullTest(_ model: AppModel, snap: (String) -> Void, wait: (Double) async -> Void) async {
        let t0 = Date()
        for _ in 0..<60 where model.library.channels.isEmpty { await wait(1) }
        print("[test] channels \(model.library.channels.count) (\(model.library.visibleChannels.count) visible) after \(Int(Date().timeIntervalSince(t0)))s"); fflush(stdout)
        for _ in 0..<300 where model.library.epgLoadedAt == nil { await wait(1) }
        let vis = model.library.visibleChannels
        let withNow = vis.filter { model.library.programme(for: $0, at: .now) != nil }
        let events = vis.filter { model.library.programmes(for: $0).first?.isEvent == true }
        print("[test] guide ready after \(Int(Date().timeIntervalSince(t0)))s: \(model.library.epgMatchedCount) channels matched to guides, \(events.count) event channels, \(withNow.count)/\(vis.count) visible channels have a current programme; warning: \(model.library.guideWarning ?? "-")")
        for c in withNow.prefix(6) { if let p = model.library.programme(for: c, at: .now) { print("   \(c.name) → \(p.title) \(Theme.range(p)) \(p.desc.map { "| " + $0.prefix(60) } ?? "")") } }
        for c in events.prefix(5) { if let p = model.library.programmes(for: c).last { print("   EVENT \(c.name) → \(p.title) \(Theme.dayLabel(p.start, withTime: true))") } }
        fflush(stdout)
        // Classification + sports matching across everything on now.
        var kinds: [String: Int] = [:]
        var sportsNow: [(Channel, Programme)] = []
        for c in vis { if let p = model.library.programme(for: c, at: .now) {
            kinds["\(p.kind)", default: 0] += 1
            if p.kind == .sports { sportsNow.append((c, p)) }
        } }
        let withArt = vis.compactMap { model.library.programme(for: $0, at: .now) }.filter { $0.icon != nil }.count
        print("[test] on now by kind: \(kinds); with poster art: \(withArt)"); fflush(stdout)
        for (c, p) in sportsNow { _ = model.game(for: p, channel: c) }
        await wait(8)
        var matched = 0
        for (c, p) in sportsNow { if let g = model.game(for: p, channel: c) {
            matched += 1
            if matched <= 6 { print("   GAME \(c.name) | \(p.displayTitle) → \(g.name) \(g.scoreLine ?? "") \(g.detail) [\(g.networks.joined(separator: ","))]") }
        } }
        print("[test] sports on now: \(sportsNow.count), matched to live games: \(matched)")
        for (c, p) in sportsNow.prefix(12) where model.game(for: p, channel: c) == nil { print("   unmatched: \(c.name) | \(p.title) | \(p.subtitle ?? "-")") }
        for c in vis where ["Cinemax", "Discovery"].contains(where: { c.name.contains($0) }) {
            if let p = model.library.programme(for: c, at: .now) { print("   LANG \(c.name) → \(p.displayTitle)") }
        }
        fflush(stdout)
        // IMDb index (first run downloads + builds it).
        let tI = Date()
        for _ in 0..<600 where !model.meta.imdbReady {
            if case .failed = model.meta.imdbState { break }
            await wait(1)
        }
        print("[test] IMDb index: \(model.meta.imdbState) after \(Int(Date().timeIntervalSince(tI)))s"); fflush(stdout)
        let onNow = vis.compactMap { c in model.library.programme(for: c, at: .now).map { (c, $0) } }
        for (_, p) in onNow { _ = model.meta.imdb(for: p); _ = model.meta.art(for: p) }
        await wait(20)
        let movies = onNow.filter { $0.1.kind == .movie }, eps = onNow.filter { $0.1.kind == .episode }
        let mHit = movies.filter { model.meta.imdb(for: $0.1) != nil }
        let eHit = eps.filter { model.meta.imdb(for: $0.1) != nil }
        let artHit = onNow.filter { model.meta.art(for: $0.1) != nil }
        print("[test] IMDb matches on now: movies \(mHit.count)/\(movies.count), episodes(series) \(eHit.count)/\(eps.count); art \(artHit.count)/\(onNow.count)")
        for (c, p) in mHit.prefix(5) { let t = model.meta.imdb(for: p)!; print("   MOVIE \(c.name) | \(p.displayTitle) (\(p.year ?? 0)) → \(t.title) \(t.year ?? 0) ★\(t.ratingText) \(t.votesText) \(t.tconst)") }
        for (c, p) in eHit.prefix(5) { let t = model.meta.imdb(for: p)!; print("   SERIES \(c.name) | \(p.displayTitle) \(p.episodeLabel ?? "") → \(t.title) ★\(t.ratingText) \(t.genres.joined(separator: ","))") }
        for (c, p) in movies.filter({ model.meta.imdb(for: $0.1) == nil }).prefix(4) { print("   no IMDb: \(c.name) | \(p.displayTitle) (\(p.year ?? 0))") }
        fflush(stdout)
        model.selectedGroup = ChannelGroup.all; model.screen = .guide; model.resetGuideToNow()
        if let i = model.groupChannels.firstIndex(where: { model.library.programme(for: $0, at: .now)?.kind == .movie && model.meta.imdb(for: model.library.programme(for: $0, at: .now)!) != nil }) {
            model.guideRow = i; model.guideTime = .now
        }
        await wait(4); snap("F-guide-movie")
        if let i = model.groupChannels.firstIndex(where: { c in model.library.programme(for: c, at: .now).flatMap { model.game(for: $0, channel: c) } != nil }) {
            model.guideRow = i; model.guideTime = .now
        }
        await wait(4); snap("G-guide-game")
        await wait(3); snap("A-guide-all")
        if let nfl = model.library.groups.first(where: { $0.name == "NFL" }) { model.selectedGroup = nfl.name; model.guideRow = 0 }
        await wait(3); snap("B-guide-nfl")

        model.screen = .movies
        await model.vod.ensureLoaded(.movies)
        print("[test] movies \(model.vod.movies.count) in \(model.vod.movieCategories.count) categories; error: \(model.vod.error ?? "-")"); fflush(stdout)
        await wait(3); snap("C-movies")
        if let m = model.vod.movies.sorted(by: { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }).first {
            let d = await model.vod.details(movie: m)
            print("[test] movie '\(m.name)': plot \(d?.plot != nil), cast \(d?.cast != nil), backdrop \(d?.backdrop != nil), rating \(d?.rating ?? -1), trailer \(d?.trailer != nil)"); fflush(stdout)
        }
        model.screen = .shows
        await model.vod.ensureLoaded(.series)
        print("[test] shows \(model.vod.series.count) in \(model.vod.seriesCategories.count) categories; error: \(model.vod.error ?? "-")"); fflush(stdout)
        if let s = model.vod.series.first {
            let d = await model.vod.details(series: s)
            print("[test] show '\(s.name)': \(d?.seasons.count ?? 0) seasons, \(d?.seasons.values.map(\.count).reduce(0, +) ?? 0) episodes, plot \(d?.plot != nil)"); fflush(stdout)
        }
        await wait(3); snap("D-shows")
        model.screen = .guide
        model.settingsSection = .epg; model.showSettings = true
        await wait(2); snap("E-settings-epg")
        model.showSettings = false
    }
}
