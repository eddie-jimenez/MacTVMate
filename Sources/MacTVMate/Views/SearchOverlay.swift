import SwiftUI

struct SearchResult: Identifiable, Hashable {
    let channel: Channel
    let programme: Programme?
    var id: String { channel.id + "|" + (programme?.id ?? "") }
}

extension AppModel {
    /// Every word must appear in the channel name/group, or in a programme title within -3 h … +24 h.
    func search(_ query: String, limit: Int = 80) -> (channels: [SearchResult], programmes: [SearchResult]) {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return ([], []) }
        func matches(_ text: String) -> Bool {
            let t = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return words.allSatisfy { t.contains($0) }
        }
        var chans: [SearchResult] = []
        var progs: [SearchResult] = []
        let from = now.addingTimeInterval(-3 * 3600), to = now.addingTimeInterval(24 * 3600)
        for c in library.visibleChannels {
            if chans.count < limit, matches(c.name + " " + c.group) {
                chans.append(SearchResult(channel: c, programme: nil))
            }
            if progs.count < limit {
                for p in library.programmes(for: c, in: from..<to) where matches(p.title + " " + (p.subtitle ?? "")) {
                    progs.append(SearchResult(channel: c, programme: p))
                }
            }
        }
        // Live first, then soonest.
        progs.sort { a, b in
            let al = a.programme!.isLive(at: now), bl = b.programme!.isLive(at: now)
            return al != bl ? al : a.programme!.start < b.programme!.start
        }
        return (favouritesFirst(chans), Array(progs.prefix(limit)))
    }

    private func favouritesFirst(_ list: [SearchResult]) -> [SearchResult] {
        list.filter { library.isFavourite($0.channel) } + list.filter { !library.isFavourite($0.channel) }
    }

    func open(_ r: SearchResult) {
        showSearch = false
        if let p = r.programme, p.stop < now, r.channel.hasCatchup {
            playCatchup(r.channel, p)
        } else {
            play(r.channel)
        }
    }
}

struct SearchOverlay: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var focused: Bool
    @State private var selection = 0

    var body: some View {
        let results = model.search(model.searchQuery)
        let all = results.channels + results.programmes
        ZStack(alignment: .top) {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { model.showSearch = false }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                    TextField("Search channels and programmes — e.g. 49ers, NFL, ESPN", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20))
                        .focused($focused)
                        .onSubmit { if all.indices.contains(selection) { model.open(all[selection]) } }
                        .onKeyPress(.downArrow) { selection = min(all.count - 1, selection + 1); return .handled }
                        .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
                        .onExitCommand { model.showSearch = false }
                    if !model.searchQuery.isEmpty {
                        Button { model.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(Theme.dim)
                    }
                }
                .padding(16)
                .background(Theme.panel)

                if model.searchQuery.isEmpty {
                    Text("Type to search \(model.library.channels.count) channels\(model.library.epgLoadedAt == nil ? "" : " and the TV guide"). ↑/↓ to pick, Return to play, F to favourite.")
                        .font(.callout).foregroundStyle(Theme.dim).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if all.isEmpty {
                    Text("No matches for “\(model.searchQuery)”").foregroundStyle(Theme.dim).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                if !results.channels.isEmpty { header("Channels (\(results.channels.count))") }
                                ForEach(Array(results.channels.enumerated()), id: \.element.id) { i, r in
                                    row(r, index: i)
                                }
                                if !results.programmes.isEmpty { header("Programmes (\(results.programmes.count))") }
                                ForEach(Array(results.programmes.enumerated()), id: \.element.id) { i, r in
                                    row(r, index: results.channels.count + i)
                                }
                            }
                            .padding(8)
                        }
                        .onChange(of: selection) { _, i in proxy.scrollTo(i, anchor: .center) }
                    }
                }
            }
            .frame(width: 720)
            .frame(maxHeight: 560, alignment: .top)
            .fixedSize(horizontal: false, vertical: model.searchQuery.isEmpty || all.isEmpty)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
            .shadow(radius: 30)
            .padding(.top, 60)
        }
        .onAppear { focused = true; selection = 0 }
        .onChange(of: model.searchQuery) { _, _ in selection = 0 }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(Theme.faint)
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
    }

    private func row(_ r: SearchResult, index: Int) -> some View {
        let focused = index == selection
        let live = r.programme.map { $0.isLive(at: model.now) } ?? false
        return HStack(spacing: 10) {
            Text(verbatim: String(r.channel.number)).font(.callout.monospacedDigit()).frame(width: 44, alignment: .trailing).opacity(0.6)
            ChannelLogo(url: r.channel.logo, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                if let p = r.programme {
                    HStack(spacing: 6) {
                        Text(p.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if live { Badge(text: "LIVE", color: Theme.live) }
                    }
                    Text("\(r.channel.name)  ·  \(Theme.day.string(from: p.start)) \(Theme.range(p))").font(.caption).opacity(0.7).lineLimit(1)
                } else {
                    Text(r.channel.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(model.library.programme(for: r.channel, at: model.now)?.title ?? r.channel.group).font(.caption).opacity(0.7).lineLimit(1)
                }
            }
            Spacer()
            FavouriteButton(channel: r.channel, inverted: focused)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(focused ? Theme.focus : .clear, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(focused ? Theme.focusText : Theme.text)
        .contentShape(Rectangle())
        .onTapGesture { model.open(r) }
        .onHover { if $0 { selection = index } }
        .id(index)
    }
}

/// One-click star toggle used in lists, search and the info bar.
struct FavouriteButton: View {
    @EnvironmentObject var model: AppModel
    let channel: Channel
    var inverted = false

    var body: some View {
        let fav = model.library.isFavourite(channel)
        Button { model.library.toggleFavourite(channel) } label: {
            Image(systemName: fav ? "star.fill" : "star")
                .foregroundStyle(fav ? .yellow : (inverted ? Theme.focusText.opacity(0.5) : Theme.faint))
        }
        .buttonStyle(.borderless)
        .help(fav ? "Remove from Favourites" : "Add to Favourites")
    }
}
