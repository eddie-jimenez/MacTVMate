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
    // Remote focus: the poster grid index, the header (0 sort, 1 search) when focused, and the grid's column count.
    @State private var gridFocus = 0
    @State private var header: Int?
    @State private var columns = 5
    @FocusState private var searchFocused: Bool

    var body: some View {
        let store = model.vod
        let cats = categoryList
        HStack(spacing: Theme.s(0)) {
            // Categories
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.s(2)) {
                        ForEach(Array(cats.enumerated()), id: \.element.id) { i, c in
                            categoryRow(c.id, c.name, c.count)
                            if i == 2 { Divider().padding(.vertical, Theme.s(6)) }
                        }
                    }
                    .padding(Theme.s(10))
                }
                .onChange(of: category) { _, c in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(c, anchor: .center) } }
            }
            .frame(width: Theme.s(240))
            .background(Theme.panel)

            VStack(alignment: .leading, spacing: Theme.s(12)) {
                HStack(spacing: Theme.s(12)) {
                    Text(kind == .movies ? "Movies" : "Shows").font(Theme.f(.largeTitle).weight(.semibold))
                    Spacer()
                    Picker("", selection: $sort) {
                        Text("Recently added").tag(0); Text("A–Z").tag(1); Text("IMDb rating").tag(2); Text("Popular").tag(3)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: Theme.s(400))
                    .focusRing(model.zone == .main && header == 0)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                        TextField("Search \(kind == .movies ? "movies" : "shows")", text: $query).textFieldStyle(.plain)
                            .focused($searchFocused)
                            .onSubmit { searchFocused = false; header = nil; gridFocus = 0 }
                    }
                    .padding(Theme.s(8)).frame(width: Theme.s(240))
                    .background(Theme.cell, in: RoundedRectangle(cornerRadius: 8))
                    .focusRing(model.zone == .main && header == 1)
                }

                if !store.isAvailable {
                    placeholder("Movies and shows need an Xtream Codes playlist.", "film")
                } else if store.loading == kind && store.items(kind).isEmpty {
                    HStack { ProgressView().controlSize(Theme.control(.small)); Text("Loading \(kind == .movies ? "movies" : "shows")…").foregroundStyle(Theme.dim) }
                    Spacer()
                } else if let err = store.error, store.items(kind).isEmpty {
                    placeholder(err, "exclamationmark.triangle")
                } else {
                    let items = filtered
                    Text("\(items.count) titles").font(Theme.f(.callout)).foregroundStyle(Theme.dim)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.s(18), alignment: .top), count: columns),
                                      alignment: .leading, spacing: Theme.s(22)) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                                    PosterCard(item: item, progress: progress(item), imdb: store.imdb[item.id],
                                               focused: model.zone == .main && header == nil && i == gridFocus && selected == nil)
                                        .onTapGesture { gridFocus = i; model.zone = .main; header = nil; selected = item }
                                }
                            }
                            .padding(.horizontal, Theme.s(4)).padding(.top, Theme.s(4))
                            .padding(.bottom, Theme.s(30))
                        }
                        .background(GeometryReader { g in
                            Color.clear
                                .onAppear { columns = Self.columns(for: g.size.width) }
                                .onChange(of: g.size.width) { _, w in columns = Self.columns(for: w) }
                        })
                        .onChange(of: gridFocus) { _, i in
                            guard items.indices.contains(i) else { return }
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(items[i].id, anchor: .center) }
                        }
                    }
                }
            }
            .padding(Theme.s(24))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.bg)
        .onAppear {
            model.browserKeys = { key in handle(key) }
            DispatchQueue.main.async { searchFocused = false; model.releaseTextFocus() }
        }
        .onDisappear { model.browserKeys = nil }
        .onChange(of: category) { _, _ in gridFocus = 0 }
        .onChange(of: sort) { _, _ in gridFocus = 0 }
        .onChange(of: query) { _, _ in gridFocus = 0 }
        .task(id: kind) { await model.vod.ensureLoaded(kind) }
        .task(id: model.meta.imdbReady) { if model.meta.imdbReady { await model.vod.matchIMDb(kind) } }
        .sheet(item: $selected) { item in
            if item.kind == .movies { MovieDetailView(item: item, close: { selected = nil }) }
            else { SeriesDetailView(item: item, close: { selected = nil }) }
        }
    }

    static func columns(for width: CGFloat) -> Int {
        max(1, Int((width + Theme.s(18)) / (Theme.s(150) + Theme.s(18))))
    }

    private struct CategoryEntry: Identifiable { let id: String; let name: String; let count: Int? }

    /// All, My list, Continue watching, then the provider's categories that have titles.
    private var categoryList: [CategoryEntry] {
        let store = model.vod
        let counts = categoryCounts
        var list = [CategoryEntry(id: "__all", name: "All \(kind == .movies ? "movies" : "shows")", count: store.items(kind).count),
                    CategoryEntry(id: "__mylist", name: "My list", count: store.items(kind).filter { model.library.isInMyList($0.id) }.count),
                    CategoryEntry(id: "__continue", name: "Continue watching", count: continueItems.count)]
        list += store.categories(kind).filter { (counts[$0.id] ?? 0) > 0 }.map { CategoryEntry(id: $0.id, name: $0.name, count: counts[$0.id]) }
        return list
    }

    /// Remote / arrow keys: categories (side) ⇄ header + poster grid (main).
    private func handle(_ k: NavKey) -> Bool {
        if model.zone == .side {
            let cats = categoryList
            let i = cats.firstIndex { $0.id == category } ?? 0
            switch k {
            case .up: category = cats[max(0, i - 1)].id
            case .down: category = cats[min(cats.count - 1, i + 1)].id
            case .right, .select: model.zone = .main; header = nil
            case .left: model.enterRail()
            default: return false
            }
            return true
        }
        if let h = header {
            switch k {
            case .left: if h == 1 { header = 0 } else { model.zone = .side; header = nil }
            case .right: header = 1
            case .down: header = nil
            case .select: if h == 0 { sort = (sort + 1) % 4 } else { searchFocused = true }
            case .up: break
            default: return false
            }
            return true
        }
        let items = filtered
        let n = items.count, cols = max(1, columns)
        guard n > 0 else {
            if k == .left { model.zone = .side; return true }
            if k == .up { header = 0; return true }
            return false
        }
        gridFocus = min(gridFocus, n - 1)
        let item = items[gridFocus]
        switch k {
        case .up: if gridFocus < cols { header = 0 } else { gridFocus -= cols }
        case .down: if gridFocus + cols < n { gridFocus += cols } else if gridFocus / cols < (n - 1) / cols { gridFocus = n - 1 }
        case .left: if gridFocus % cols == 0 { model.zone = .side } else { gridFocus -= 1 }
        case .right: if gridFocus % cols < cols - 1, gridFocus + 1 < n { gridFocus += 1 }
        case .select: selected = item
        case .favourite: model.library.toggleMyList(item.id)
        case .hold, .menu: model.showOptions(item.name, subtitle: item.year, options(item))
        default: return false
        }
        return true
    }

    private func options(_ item: VODItem) -> [MenuAction] {
        var a: [MenuAction] = []
        if item.kind == .movies {
            let resume = model.library.positions[item.id] != nil
            a.append(MenuAction(title: resume ? "Resume" : "Play", icon: "play.fill") { [model] in model.remotePlayMovie(id: item.id) })
        }
        a.append(MenuAction(title: item.kind == .movies ? "Details" : "Episodes", icon: "info.circle") { selected = item })
        let inList = model.library.isInMyList(item.id)
        a.append(MenuAction(title: inList ? "Remove from My list" : "Add to My list", icon: inList ? "bookmark.slash" : "bookmark") { [model] in
            model.library.toggleMyList(item.id)
        })
        return a
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
            if let count { Text("\(count)").font(Theme.f(.caption)).foregroundStyle(sel ? Theme.focusText.opacity(0.6) : Theme.faint) }
        }
        .padding(.horizontal, Theme.s(10)).padding(.vertical, Theme.s(7))
        .background(sel ? Theme.focus : .clear, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(sel ? Theme.focusText : Theme.text)
        .focusRing(sel && model.zone == .side, radius: 6)
        .contentShape(Rectangle())
        .id(id)
        .onTapGesture { category = id; model.zone = .side }
    }

    private func placeholder(_ text: String, _ icon: String) -> some View {
        VStack(spacing: Theme.s(10)) {
            Image(systemName: icon).font(.system(size: Theme.uiScale * 40)).foregroundStyle(Theme.faint)
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
    var focused = false
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s(6)) {
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
                                Text(item.name).font(Theme.f(.caption)).multilineTextAlignment(.center).foregroundStyle(Theme.dim).padding(Theme.s(8))
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(hover || focused ? Theme.accent : .clear, lineWidth: focused ? 4 : 3))
                .overlay(alignment: .topTrailing) {
                    if model.library.isInMyList(item.id) {
                        Image(systemName: "bookmark.fill").foregroundStyle(Theme.accent).padding(Theme.s(6))
                    }
                }
                .overlay(alignment: .bottomLeading) { ratingBadge.padding(Theme.s(6)) }
            if let progress { ProgressLine(value: progress) }
            Text(item.name).font(Theme.f(.callout).weight(.medium)).lineLimit(2)
            let year = item.year ?? imdb?.year.map(String.init)
            let genres = imdb?.genres.prefix(2).joined(separator: ", ")
            if year != nil || genres != nil {
                Text([year, genres].compactMap { $0 }.joined(separator: " · ")).font(Theme.f(.caption)).foregroundStyle(Theme.dim).lineLimit(1)
            }
        }
        .scaleEffect(focused ? 1.06 : hover ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.12), value: focused)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var ratingBadge: some View {
        if let t = imdb {
            HStack(spacing: Theme.s(3)) {
                Text("IMDb").font(.system(size: Theme.uiScale * 8, weight: .heavy)).foregroundStyle(.black)
                    .padding(.horizontal, Theme.s(2)).background(Color(hex: 0xF5C518), in: RoundedRectangle(cornerRadius: 2))
                Text(t.ratingText).font(Theme.f(.caption2).weight(.bold))
            }
            .padding(.horizontal, Theme.s(5)).padding(.vertical, Theme.s(2))
            .background(.black.opacity(0.75), in: Capsule())
        } else if let r = item.rating, r > 0 {
            Text(String(format: "★ %.1f", r)).font(Theme.f(.caption2).weight(.bold))
                .padding(.horizontal, Theme.s(5)).padding(.vertical, Theme.s(2))
                .background(.black.opacity(0.7), in: Capsule())
        }
    }
}

struct MovieDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: VODItem
    /// Set by the presenting screen; the remote's Back uses it (the environment's dismiss isn't reliable outside body).
    var close: (() -> Void)? = nil
    @State private var details: MovieDetails?

    var body: some View {
        let resume = model.library.positions[item.id]
        DetailLayout(item: item, backdrop: details?.backdrop, form: model.sheetForm, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: Theme.s(10)) {
                Text(item.name).font(Theme.f(.largeTitle).weight(.bold))
                HStack(spacing: Theme.s(10)) {
                    if let y = details?.releaseDate ?? item.year { Text(String(y.prefix(10))) }
                    if let d = details?.duration { Text(d) }
                    if let r = details?.rating ?? item.rating, r > 0 { Text(String(format: "★ %.1f", r)) }
                    if let g = details?.genre { Text(g).lineLimit(1) }
                }
                .foregroundStyle(Theme.dim)
                if let imdb = movieIMDb { IMDbBadge(title: imdb) }
                HStack(spacing: Theme.s(12)) {
                    let form = model.sheetForm
                    Button {
                        play()
                    } label: { Label(resume != nil ? "Resume \(fmt(resume!))" : "Play", systemImage: "play.fill").padding(.horizontal, Theme.s(6)) }
                    .controlSize(Theme.control(.large)).buttonStyle(.borderedProminent).tint(Theme.accent)
                    .focusSpot(form, row: 0, col: 0) { play() }
                    if resume != nil {
                        Button("Play from start") { model.library.positions[item.id] = nil; play() }.controlSize(Theme.control(.large))
                            .focusSpot(form, row: 0, col: 1) { model.library.positions[item.id] = nil; play() }
                    }
                    MyListButton(key: item.id)
                        .focusSpot(form, row: 0, col: 2) { model.library.toggleMyList(item.id) }
                    if let t = details?.trailer, !t.isEmpty, let url = URL(string: t.hasPrefix("http") ? t : "https://www.youtube.com/watch?v=\(t)") {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Trailer", systemImage: "play.rectangle") }.controlSize(Theme.control(.large))
                            .focusSpot(form, row: 0, col: 3) { NSWorkspace.shared.open(url) }
                    }
                }
                .padding(.vertical, Theme.s(6))
                if let p = details?.plot ?? item.plot { Text(p).foregroundStyle(Theme.text.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
                if let c = details?.cast { Text("Cast: \(c)").font(Theme.f(.callout)).foregroundStyle(Theme.dim).lineLimit(3) }
                if let d = details?.director { Text("Director: \(d)").font(Theme.f(.callout)).foregroundStyle(Theme.dim) }
                if details == nil { ProgressView().controlSize(Theme.control(.small)) }
            }
        }
        .task { details = await model.vod.details(movie: item) }
        .remoteSheet(model) { if let close { close() } else { dismiss() } }
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
    var close: (() -> Void)? = nil
    @State private var details: SeriesDetails?
    @State private var season = 1

    var body: some View {
        DetailLayout(item: item, backdrop: details?.backdrop, form: model.sheetForm, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: Theme.s(10)) {
                Text(item.name).font(Theme.f(.largeTitle).weight(.bold))
                HStack(spacing: Theme.s(10)) {
                    if let y = details?.releaseDate ?? item.year { Text(String(y.prefix(10))) }
                    if let r = details?.rating ?? item.rating, r > 0 { Text(String(format: "★ %.1f", r)) }
                    if let g = details?.genre { Text(g).lineLimit(1) }
                }
                .foregroundStyle(Theme.dim)
                if let imdb = model.meta.imdb(title: MetaStore.splitYear(item.name).0, year: nil, series: true) { IMDbBadge(title: imdb) }
                HStack(spacing: Theme.s(12)) {
                    if let next = nextEpisode {
                        Button { play(next) } label: {
                            Label("\(model.library.positions[next.key] != nil ? "Resume" : "Play") S\(next.season) E\(next.number)", systemImage: "play.fill")
                                .padding(.horizontal, Theme.s(6))
                        }
                        .controlSize(Theme.control(.large)).buttonStyle(.borderedProminent).tint(Theme.accent)
                        .focusSpot(model.sheetForm, row: 0, col: 0) { play(next) }
                    }
                    MyListButton(key: item.id)
                        .focusSpot(model.sheetForm, row: 0, col: 1) { model.library.toggleMyList(item.id) }
                }
                .padding(.vertical, Theme.s(6))
                if let p = details?.plot ?? item.plot { Text(p).foregroundStyle(Theme.text.opacity(0.85)).lineLimit(5) }

                if let seasons = details?.seasons, !seasons.isEmpty {
                    Picker("Season", selection: $season) {
                        ForEach(seasons.keys.sorted(), id: \.self) { Text("Season \($0)").tag($0) }
                    }
                    .frame(maxWidth: Theme.s(220), alignment: .leading)
                    .focusChoice(model.sheetForm, row: 1, $season, seasons.keys.sorted())
                    VStack(spacing: Theme.s(2)) {
                        ForEach(Array((seasons[season] ?? []).enumerated()), id: \.element.id) { i, ep in
                            episodeRow(ep).focusSpot(model.sheetForm, row: 2 + i, owner: "ep\(i)") { play(ep) }
                        }
                    }
                } else if details == nil {
                    ProgressView().controlSize(Theme.control(.small))
                } else {
                    Text("No episodes listed.").foregroundStyle(Theme.dim)
                }
            }
        }
        .task {
            details = await model.vod.details(series: item)
            if let first = nextEpisode?.season ?? details?.seasons.keys.sorted().first { season = first }
            DispatchQueue.main.async { model.sheetForm.engage(reset: true) }
        }
        .remoteSheet(model) { if let close { close() } else { dismiss() } }
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
        return HStack(spacing: Theme.s(12)) {
            AsyncImage(url: ep.image) { p in
                if let i = p.image { i.resizable().aspectRatio(contentMode: .fill) } else { Theme.cell }
            }
            .frame(width: Theme.s(120), height: Theme.s(68)).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: Theme.s(3)) {
                HStack {
                    Text("\(ep.number). \(ep.title)").font(Theme.f(.callout).weight(.semibold)).lineLimit(1)
                    if watched { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(Theme.f(.caption)) }
                }
                if let p = ep.plot { Text(p).font(Theme.f(.caption)).foregroundStyle(Theme.dim).lineLimit(2) }
                if model.library.positions[ep.key] != nil { ProgressLine(value: 0.5).frame(width: Theme.s(120)) }
            }
            Spacer()
            if let d = ep.duration { Text(d).font(Theme.f(.caption)).foregroundStyle(Theme.dim) }
        }
        .padding(Theme.s(6))
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
    @ObservedObject var form: FocusForm
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: backdrop ?? item.poster) { p in
                if let i = p.image { i.resizable().aspectRatio(contentMode: .fill).blur(radius: backdrop == nil ? 30 : 0) } else { Theme.bg }
            }
            .frame(width: Theme.s(900), height: Theme.s(600)).clipped()
            .overlay(LinearGradient(colors: [Theme.bg.opacity(0.55), Theme.bg.opacity(0.97)], startPoint: .top, endPoint: .bottom))

            HStack(alignment: .top, spacing: Theme.s(26)) {
                AsyncImage(url: item.poster) { p in
                    if let i = p.image { i.resizable().aspectRatio(contentMode: .fit) } else { Theme.cell }
                }
                .frame(width: Theme.s(210)).clipShape(RoundedRectangle(cornerRadius: 10)).shadow(radius: 20)
                FocusScroller(form: form) { _ in
                    ScrollView { content.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.s(4)) }
                }
            }
            .padding(Theme.s(30))

            Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(Theme.f(.title)) }
                .buttonStyle(.borderless).foregroundStyle(Theme.dim).padding(Theme.s(16))
                .keyboardShortcut(.cancelAction)
        }
        .frame(width: Theme.s(900), height: Theme.s(600))
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
        .controlSize(Theme.control(.large))
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
        let form = model.screenForm
        FocusScroller(form: form) { _ in ScrollView {
            VStack(alignment: .leading, spacing: Theme.s(24)) {
                Text("My list").font(Theme.f(.largeTitle).weight(.semibold))
                shelf("Favourite channels", empty: "Star channels in the guide or channel list (☆ or F).") {
                    ForEach(Array(favs.enumerated()), id: \.element.id) { i, c in
                        VStack(spacing: Theme.s(6)) {
                            ChannelLogo(url: c.logo, size: 50).frame(width: Theme.s(140), height: Theme.s(80))
                                .background(Theme.cell, in: RoundedRectangle(cornerRadius: 8))
                            Text(c.name).font(Theme.f(.caption)).lineLimit(1).frame(width: Theme.s(140))
                            Text(model.library.programme(for: c, at: model.now)?.title ?? "").font(Theme.f(.caption2)).foregroundStyle(Theme.dim).lineLimit(1).frame(width: Theme.s(140))
                        }
                        .padding(Theme.s(4))
                        .onTapGesture { model.play(c) }
                        .focusSpot(form, row: 0, col: i, owner: "fav" + c.id, options: {
                            let p = model.library.programme(for: c, at: model.now)
                            return model.channelOptions(c, p)
                        }) { model.play(c) }
                    }
                }
                shelf("Movies", empty: "Add movies with the My list button.") {
                    ForEach(Array(movies.enumerated()), id: \.element.id) { i, m in
                        PosterCard(item: m, progress: nil, imdb: model.vod.imdb[m.id]).frame(width: Theme.s(150)).padding(Theme.s(4))
                            .onTapGesture { selected = m }
                            .focusSpot(form, row: 1, col: i, owner: m.id, options: { listOptions(m) }) { selected = m }
                    }
                }
                shelf("Shows", empty: "Add shows with the My list button.") {
                    ForEach(Array(shows.enumerated()), id: \.element.id) { i, s in
                        PosterCard(item: s, progress: nil, imdb: model.vod.imdb[s.id]).frame(width: Theme.s(150)).padding(Theme.s(4))
                            .onTapGesture { selected = s }
                            .focusSpot(form, row: 2, col: i, owner: s.id, options: { listOptions(s) }) { selected = s }
                    }
                }
            }
            .padding(Theme.s(28))
        } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .onAppear { DispatchQueue.main.async { model.screenForm.engage(reset: true) } }
        .task { await model.vod.ensureLoaded(.movies); await model.vod.ensureLoaded(.series) }
        .sheet(item: $selected) { item in
            if item.kind == .movies { MovieDetailView(item: item, close: { selected = nil }) }
            else { SeriesDetailView(item: item, close: { selected = nil }) }
        }
    }

    private func listOptions(_ item: VODItem) -> [MenuAction] {
        var a: [MenuAction] = []
        if item.kind == .movies {
            a.append(MenuAction(title: model.library.positions[item.id] != nil ? "Resume" : "Play", icon: "play.fill") { [model] in
                model.remotePlayMovie(id: item.id)
            })
        }
        a.append(MenuAction(title: item.kind == .movies ? "Details" : "Episodes", icon: "info.circle") { selected = item })
        a.append(MenuAction(title: "Remove from My list", icon: "bookmark.slash", role: .destructive) { [model] in
            model.library.toggleMyList(item.id)
        })
        return a
    }

    private func shelf<Content: View>(_ title: String, empty: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.s(10)) {
            Text(title).font(Theme.f(.title3).weight(.semibold))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.s(16)) { content() }
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

extension View {
    /// Detail sheets: arrows move between their buttons/episodes, Back closes.
    func remoteSheet(_ model: AppModel, close: @escaping () -> Void) -> some View {
        onAppear {
            model.sheetBack = close
            DispatchQueue.main.async { model.sheetForm.engage(reset: true) }
        }
        .onDisappear {
            model.sheetForm.clear()
            model.sheetBack = nil
        }
    }
}
