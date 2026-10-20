import AppKit
import SwiftUI

/// Movies / Shows browser: categories on the left, poster grid, details sheet.
struct VODBrowser: View {
    @EnvironmentObject var model: AppModel
    let kind: VODKind
    @State private var category: String = "__all"
    @State private var query = ""
    @State private var sort = 0          // 0 recently added, 1 A–Z, 2 rating
    @State private var selected: VODItem?

    var body: some View {
        let store = model.vod
        HStack(spacing: 0) {
            // Categories
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    categoryRow("__all", "All \(kind == .movies ? "movies" : "shows")", store.items(kind).count)
                    categoryRow("__mylist", "My list", store.items(kind).filter { model.library.isInMyList($0.id) }.count)
                    if kind == .movies || kind == .series {
                        categoryRow("__continue", "Continue watching", continueItems.count)
                    }
                    Divider().padding(.vertical, 6)
                    let counts = categoryCounts
                    ForEach(store.categories(kind).filter { (counts[$0.id] ?? 0) > 0 }) { c in
                        categoryRow(c.id, c.name, counts[c.id])
                    }
                }
                .padding(10)
            }
            .frame(width: 240)
            .background(Theme.panel)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(kind == .movies ? "Movies" : "Shows").font(.largeTitle.weight(.semibold))
                    Spacer()
                    Picker("", selection: $sort) {
                        Text("Recently added").tag(0); Text("A–Z").tag(1); Text("IMDb rating").tag(2); Text("Popular").tag(3)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 400)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                        TextField("Search \(kind == .movies ? "movies" : "shows")", text: $query).textFieldStyle(.plain)
                    }
                    .padding(8).frame(width: 240)
                    .background(Theme.cell, in: RoundedRectangle(cornerRadius: 8))
                }

                if !store.isAvailable {
                    placeholder("Movies and shows need an Xtream Codes playlist.", "film")
                } else if store.loading == kind && store.items(kind).isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Loading \(kind == .movies ? "movies" : "shows")…").foregroundStyle(Theme.dim) }
                    Spacer()
                } else if let err = store.error, store.items(kind).isEmpty {
                    placeholder(err, "exclamationmark.triangle")
                } else {
                    let items = filtered
                    Text("\(items.count) titles").font(.callout).foregroundStyle(Theme.dim)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18, alignment: .top)], alignment: .leading, spacing: 22) {
                            ForEach(items) { item in
                                PosterCard(item: item, progress: progress(item), imdb: store.imdb[item.id])
                                    .onTapGesture { selected = item }
                            }
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.bg)
        .task(id: kind) { await model.vod.ensureLoaded(kind) }
        .task(id: model.meta.imdbReady) { if model.meta.imdbReady { await model.vod.matchIMDb(kind) } }
        .sheet(item: $selected) { item in
            if item.kind == .movies { MovieDetailView(item: item) } else { SeriesDetailView(item: item) }
        }
    }

    private var categoryCounts: [String: Int] {
        var c: [String: Int] = [:]
        for item in model.vod.items(kind) { for id in item.categoryIDs { c[id, default: 0] += 1 } }
        return c
    }

    private var continueItems: [VODItem] {
        model.vod.items(kind).filter { kind == .movies ? model.library.positions[$0.id] != nil : model.library.recentSeries.contains($0.id) }
    }

    private var filtered: [VODItem] {
        var items: [VODItem]
        switch category {
        case "__all": items = model.vod.items(kind)
        case "__mylist": items = model.vod.items(kind).filter { model.library.isInMyList($0.id) }
        case "__continue": items = continueItems
        default: items = model.vod.items(kind).filter { $0.categoryIDs.contains(category) }
        }
        if !query.isEmpty {
            let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            items = items.filter { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) }
        }
        switch sort {
        case 1: items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case 2:
            // IMDb rating, ignoring titles with too few votes to mean much; provider rating as a fallback.
            let imdb = model.vod.imdb
            func score(_ i: VODItem) -> Double {
                if let t = imdb[i.id], t.votes >= 1000 { return t.rating }
                return (i.rating ?? 0) - 10
            }
            items.sort { score($0) > score($1) }
        case 3:
            let imdb = model.vod.imdb
            items.sort { (imdb[$0.id]?.votes ?? 0) > (imdb[$1.id]?.votes ?? 0) }
        default: items.sort { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
        }
        return items
    }

    private func progress(_ item: VODItem) -> Double? {
        guard item.kind == .movies, model.library.positions[item.id] != nil else { return nil }
        return 0.5   // exact fraction needs the duration; show a "started" bar
    }

    private func categoryRow(_ id: String, _ name: String, _ count: Int?) -> some View {
        let sel = category == id
        return HStack {
            Text(name).lineLimit(1)
            Spacer()
            if let count { Text("\(count)").font(.caption).foregroundStyle(sel ? Theme.focusText.opacity(0.6) : Theme.faint) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(sel ? Theme.focus : .clear, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(sel ? Theme.focusText : Theme.text)
        .contentShape(Rectangle())
        .onTapGesture { category = id }
    }

    private func placeholder(_ text: String, _ icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Theme.faint)
            Text(text).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PosterCard: View {
    @EnvironmentObject var model: AppModel
    let item: VODItem
    let progress: Double?
    var imdb: IMDbTitle? = nil
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A fixed 2:3 frame, filled and cropped, so every card in a row lines up. Badges are overlays,
            // so they can never change the poster's size.
            Color.clear
                .aspectRatio(2/3, contentMode: .fit)
                .overlay {
                    AsyncImage(url: item.poster) { phase in
                        if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                        else {
                            ZStack {
                                Theme.cell
                                Text(item.name).font(.caption).multilineTextAlignment(.center).foregroundStyle(Theme.dim).padding(8)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(hover ? Theme.accent : .clear, lineWidth: 3))
                .overlay(alignment: .topTrailing) {
                    if model.library.isInMyList(item.id) {
                        Image(systemName: "bookmark.fill").foregroundStyle(Theme.accent).padding(6)
                    }
                }
                .overlay(alignment: .bottomLeading) { ratingBadge.padding(6) }
            if let progress { ProgressLine(value: progress) }
            Text(item.name).font(.callout.weight(.medium)).lineLimit(2)
            let year = item.year ?? imdb?.year.map(String.init)
            let genres = imdb?.genres.prefix(2).joined(separator: ", ")
            if year != nil || genres != nil {
                Text([year, genres].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
        }
        .scaleEffect(hover ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var ratingBadge: some View {
        if let t = imdb {
            HStack(spacing: 3) {
                Text("IMDb").font(.system(size: 8, weight: .heavy)).foregroundStyle(.black)
                    .padding(.horizontal, 2).background(Color(hex: 0xF5C518), in: RoundedRectangle(cornerRadius: 2))
                Text(t.ratingText).font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(.black.opacity(0.75), in: Capsule())
        } else if let r = item.rating, r > 0 {
            Text(String(format: "★ %.1f", r)).font(.caption2.weight(.bold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.7), in: Capsule())
        }
    }
}

struct MovieDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: VODItem
    @State private var details: MovieDetails?

    var body: some View {
        let resume = model.library.positions[item.id]
        DetailLayout(item: item, backdrop: details?.backdrop, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.name).font(.largeTitle.weight(.bold))
                HStack(spacing: 10) {
                    if let y = details?.releaseDate ?? item.year { Text(String(y.prefix(10))) }
                    if let d = details?.duration { Text(d) }
                    if let r = details?.rating ?? item.rating, r > 0 { Text(String(format: "★ %.1f", r)) }
                    if let g = details?.genre { Text(g).lineLimit(1) }
                }
                .foregroundStyle(Theme.dim)
                if let imdb = movieIMDb { IMDbBadge(title: imdb) }
                HStack(spacing: 12) {
                    Button {
                        play()
                    } label: { Label(resume != nil ? "Resume \(fmt(resume!))" : "Play", systemImage: "play.fill").padding(.horizontal, 6) }
                    .controlSize(.large).buttonStyle(.borderedProminent).tint(Theme.accent)
                    if resume != nil {
                        Button("Play from start") { model.library.positions[item.id] = nil; play() }.controlSize(.large)
                    }
                    MyListButton(key: item.id)
                    if let t = details?.trailer, !t.isEmpty, let url = URL(string: t.hasPrefix("http") ? t : "https://www.youtube.com/watch?v=\(t)") {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Trailer", systemImage: "play.rectangle") }.controlSize(.large)
                    }
                }
                .padding(.vertical, 6)
                if let p = details?.plot ?? item.plot { Text(p).foregroundStyle(Theme.text.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
                if let c = details?.cast { Text("Cast: \(c)").font(.callout).foregroundStyle(Theme.dim).lineLimit(3) }
                if let d = details?.director { Text("Director: \(d)").font(.callout).foregroundStyle(Theme.dim) }
                if details == nil { ProgressView().controlSize(.small) }
            }
        }
        .task { details = await model.vod.details(movie: item) }
    }

    private var movieIMDb: IMDbTitle? {
        let (t, y) = MetaStore.splitYear(item.name)
        let year = y ?? (details?.releaseDate ?? item.year).flatMap { Int($0.prefix(4)) }
        return model.meta.imdb(title: t, year: year, series: false)
    }

    private func play() {
        guard let url = model.vod.movieURL(item, ext: details?.containerExtension) else { return }
        dismiss()
        model.playVOD(title: item.name, url: url, poster: item.poster, key: item.id, group: "Movies")
    }
}

struct SeriesDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: VODItem
    @State private var details: SeriesDetails?
    @State private var season = 1

    var body: some View {
        DetailLayout(item: item, backdrop: details?.backdrop, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.name).font(.largeTitle.weight(.bold))
                HStack(spacing: 10) {
                    if let y = details?.releaseDate ?? item.year { Text(String(y.prefix(10))) }
                    if let r = details?.rating ?? item.rating, r > 0 { Text(String(format: "★ %.1f", r)) }
                    if let g = details?.genre { Text(g).lineLimit(1) }
                }
                .foregroundStyle(Theme.dim)
                if let imdb = model.meta.imdb(title: MetaStore.splitYear(item.name).0, year: nil, series: true) { IMDbBadge(title: imdb) }
                HStack(spacing: 12) {
                    if let next = nextEpisode {
                        Button { play(next) } label: {
                            Label("\(model.library.positions[next.key] != nil ? "Resume" : "Play") S\(next.season) E\(next.number)", systemImage: "play.fill")
                                .padding(.horizontal, 6)
                        }
                        .controlSize(.large).buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                    MyListButton(key: item.id)
                }
                .padding(.vertical, 6)
                if let p = details?.plot ?? item.plot { Text(p).foregroundStyle(Theme.text.opacity(0.85)).lineLimit(5) }

                if let seasons = details?.seasons, !seasons.isEmpty {
                    Picker("Season", selection: $season) {
                        ForEach(seasons.keys.sorted(), id: \.self) { Text("Season \($0)").tag($0) }
                    }
                    .frame(maxWidth: 220)
                    VStack(spacing: 2) {
                        ForEach(seasons[season] ?? []) { ep in episodeRow(ep) }
                    }
                } else if details == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Text("No episodes listed.").foregroundStyle(Theme.dim)
                }
            }
        }
        .task {
            details = await model.vod.details(series: item)
            if let first = nextEpisode?.season ?? details?.seasons.keys.sorted().first { season = first }
        }
    }

    /// First episode with a saved position, else the episode after the last one watched, else S1E1.
    private var nextEpisode: Episode? {
        guard let seasons = details?.seasons else { return nil }
        let all = seasons.keys.sorted().flatMap { seasons[$0] ?? [] }
        if let inProgress = all.first(where: { model.library.positions[$0.key] != nil }) { return inProgress }
        if let lastID = model.library.lastEpisode[item.id], let i = all.firstIndex(where: { $0.id == lastID }), i + 1 < all.count { return all[i + 1] }
        return all.first
    }

    private func episodeRow(_ ep: Episode) -> some View {
        let watched = model.library.lastEpisode[item.id] == ep.id
        return HStack(spacing: 12) {
            AsyncImage(url: ep.image) { p in
                if let i = p.image { i.resizable().aspectRatio(contentMode: .fill) } else { Theme.cell }
            }
            .frame(width: 120, height: 68).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("\(ep.number). \(ep.title)").font(.callout.weight(.semibold)).lineLimit(1)
                    if watched { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.caption) }
                }
                if let p = ep.plot { Text(p).font(.caption).foregroundStyle(Theme.dim).lineLimit(2) }
                if model.library.positions[ep.key] != nil { ProgressLine(value: 0.5).frame(width: 120) }
            }
            Spacer()
            if let d = ep.duration { Text(d).font(.caption).foregroundStyle(Theme.dim) }
        }
        .padding(6)
        .background(Theme.cell.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { play(ep) }
    }

    private func play(_ ep: Episode) {
        guard let url = model.vod.episodeURL(ep) else { return }
        model.library.noteEpisode(series: item.id, episodeID: ep.id)
        dismiss()
        model.playVOD(title: "\(item.name) · S\(ep.season)E\(ep.number) \(ep.title)", url: url, poster: item.poster, key: ep.key, group: "Shows")
    }
}

/// Backdrop + poster + content, used by both detail sheets.
struct DetailLayout<Content: View>: View {
    let item: VODItem
    let backdrop: URL?
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: backdrop ?? item.poster) { p in
                if let i = p.image { i.resizable().aspectRatio(contentMode: .fill).blur(radius: backdrop == nil ? 30 : 0) } else { Theme.bg }
            }
            .frame(width: 900, height: 600).clipped()
            .overlay(LinearGradient(colors: [Theme.bg.opacity(0.55), Theme.bg.opacity(0.97)], startPoint: .top, endPoint: .bottom))

            HStack(alignment: .top, spacing: 26) {
                AsyncImage(url: item.poster) { p in
                    if let i = p.image { i.resizable().aspectRatio(contentMode: .fit) } else { Theme.cell }
                }
                .frame(width: 210).clipShape(RoundedRectangle(cornerRadius: 10)).shadow(radius: 20)
                ScrollView { content.frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(30)

            Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.title) }
                .buttonStyle(.borderless).foregroundStyle(Theme.dim).padding(16)
                .keyboardShortcut(.cancelAction)
        }
        .frame(width: 900, height: 600)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }
}

struct MyListButton: View {
    @EnvironmentObject var model: AppModel
    let key: String
    var body: some View {
        let inList = model.library.isInMyList(key)
        Button { model.library.toggleMyList(key) } label: {
            Label(inList ? "In My list" : "My list", systemImage: inList ? "bookmark.fill" : "bookmark")
        }
        .controlSize(.large)
    }
}

/// TiViMate's "My list": saved movies and shows, plus favourite channels.
struct MyListScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: VODItem?

    var body: some View {
        let movies = model.vod.movies.filter { model.library.isInMyList($0.id) }
        let shows = model.vod.series.filter { model.library.isInMyList($0.id) }
        let favs = model.library.channels(in: ChannelGroup.favourites)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("My list").font(.largeTitle.weight(.semibold))
                shelf("Favourite channels", empty: "Star channels in the guide or channel list (☆ or F).") {
                    ForEach(favs) { c in
                        VStack(spacing: 6) {
                            ChannelLogo(url: c.logo, size: 50).frame(width: 140, height: 80)
                                .background(Theme.cell, in: RoundedRectangle(cornerRadius: 8))
                            Text(c.name).font(.caption).lineLimit(1).frame(width: 140)
                            Text(model.library.programme(for: c, at: model.now)?.title ?? "").font(.caption2).foregroundStyle(Theme.dim).lineLimit(1).frame(width: 140)
                        }
                        .onTapGesture { model.play(c) }
                    }
                }
                shelf("Movies", empty: "Add movies with the My list button.") {
                    ForEach(movies) { m in PosterCard(item: m, progress: nil, imdb: model.vod.imdb[m.id]).frame(width: 150).onTapGesture { selected = m } }
                }
                shelf("Shows", empty: "Add shows with the My list button.") {
                    ForEach(shows) { s in PosterCard(item: s, progress: nil, imdb: model.vod.imdb[s.id]).frame(width: 150).onTapGesture { selected = s } }
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .task { await model.vod.ensureLoaded(.movies); await model.vod.ensureLoaded(.series) }
        .sheet(item: $selected) { item in
            if item.kind == .movies { MovieDetailView(item: item) } else { SeriesDetailView(item: item) }
        }
    }

    private func shelf<Content: View>(_ title: String, empty: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) { content() }
            }
            .overlay(alignment: .leading) {
                // Shown only when the shelf has no items (HStack collapses to zero width).
                Text(empty).foregroundStyle(Theme.faint).allowsHitTesting(false).opacity(0.9)
                    .background(Theme.bg).opacity(isEmpty(title) ? 1 : 0)
            }
        }
    }

    private func isEmpty(_ title: String) -> Bool {
        switch title {
        case "Favourite channels": return model.library.channels(in: ChannelGroup.favourites).isEmpty
        case "Movies": return !model.vod.movies.contains { model.library.isInMyList($0.id) }
        default: return !model.vod.series.contains { model.library.isInMyList($0.id) }
        }
    }
}

private func fmt(_ t: Double) -> String {
    let s = Int(t)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}
