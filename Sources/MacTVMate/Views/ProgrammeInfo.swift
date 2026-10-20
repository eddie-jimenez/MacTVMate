import SwiftUI

/// Matchup header for a sports programme: logos, records, score, clock, situation, venue, network.
struct GameHeader: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s(8)) {
            HStack(spacing: Theme.s(18)) {
                team(game.away)
                VStack(spacing: Theme.s(2)) {
                    if let a = game.away.score, let h = game.home.score, game.state != .pre {
                        Text("\(a) – \(h)").font(.system(size: Theme.uiScale * 30, weight: .bold).monospacedDigit())
                    } else {
                        Text("@").font(Theme.f(.title2)).foregroundStyle(Theme.dim)
                    }
                    status
                }
                .frame(minWidth: Theme.s(110))
                team(game.home)
            }
            HStack(spacing: Theme.s(10)) {
                Badge(text: game.league, color: .purple)
                if let s = game.situation, game.state == .live { Text(s).foregroundStyle(Theme.text) }
                if let v = game.venue { Label(v, systemImage: "mappin.and.ellipse").foregroundStyle(Theme.dim) }
                if !game.networks.isEmpty { Label(game.networks.joined(separator: ", "), systemImage: "tv").foregroundStyle(Theme.dim) }
            }
            .font(Theme.f(.callout))
            .lineLimit(1)
            if let h = game.headline { Text(h).font(Theme.f(.callout)).foregroundStyle(Theme.dim).lineLimit(2) }
        }
    }

    @ViewBuilder private var status: some View {
        switch game.state {
        case .live:
            HStack(spacing: Theme.s(4)) { Circle().fill(Theme.live).frame(width: Theme.s(7), height: Theme.s(7)); Text(game.detail) }
                .font(Theme.f(.caption).weight(.semibold)).foregroundStyle(Theme.live)
        case .post:
            Text(game.detail).font(Theme.f(.caption).weight(.semibold)).foregroundStyle(Theme.dim)
        case .pre:
            Text(Theme.dayLabel(game.start, withTime: true)).font(Theme.f(.caption)).foregroundStyle(Theme.dim)
        }
    }

    private func team(_ s: Game.Side) -> some View {
        HStack(spacing: Theme.s(10)) {
            AsyncImage(url: s.logo) { p in
                if let i = p.image { i.resizable().aspectRatio(contentMode: .fit) } else { Color.clear }
            }
            .frame(width: Theme.s(46), height: Theme.s(46))
            VStack(alignment: .leading, spacing: Theme.s(1)) {
                Text(s.short.isEmpty ? s.name : s.short).font(Theme.f(.headline)).lineLimit(1)
                Text([s.location, s.record].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                    .font(Theme.f(.caption)).foregroundStyle(Theme.dim).lineLimit(1)
            }
        }
    }
}

/// Movie / episode details from the guide data (Gracenote fields): poster, year, S/E, genres, cast.
struct ProgrammeMeta: View {
    let p: Programme

    var body: some View {
        let genres = p.categories.filter { !["Series", "Movie", "Sports", "Sports event", "Sports non-event"].contains($0) }
        HStack(spacing: Theme.s(8)) {
            switch p.kind {
            case .movie: Badge(text: "MOVIE", color: .orange)
            case .episode: Badge(text: "SERIES", color: .teal)
            case .news: Badge(text: "NEWS", color: .gray)
            default: EmptyView()
            }
            if p.isNew { Badge(text: "NEW", color: .green) }
            if let y = p.year, p.kind == .movie { Text(String(y)) }
            if let e = p.episodeLabel { Text(e) }
            if let r = p.contentRating { Text(r).padding(.horizontal, Theme.s(4)).overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.dim)) }
            if let s = p.starRating { Text("★ \(s)") }
            if !genres.isEmpty { Text(genres.prefix(3).joined(separator: ", ")).foregroundStyle(Theme.faint) }
        }
        .font(Theme.f(.callout)).foregroundStyle(Theme.dim).lineLimit(1)
    }
}

/// "IMDb ★ 7.7 (82K)" — opens the title on imdb.com.
struct IMDbBadge: View {
    let title: IMDbTitle

    var body: some View {
        Link(destination: title.url) {
            HStack(spacing: Theme.s(6)) {
                Text("IMDb").font(.system(size: Theme.uiScale * 11, weight: .heavy)).foregroundStyle(.black)
                    .padding(.horizontal, Theme.s(4)).padding(.vertical, Theme.s(1))
                    .background(Color(hex: 0xF5C518), in: RoundedRectangle(cornerRadius: 3))
                Text("★ \(title.ratingText)").fontWeight(.semibold)
                Text("(\(title.votesText))").foregroundStyle(Theme.dim)
            }
        }
        .buttonStyle(.plain)
        .help("Open on IMDb")
    }
}

/// IMDb rating, runtime and genres for a movie/episode, plus the show's TVmaze info.
struct EnrichmentLine: View {
    @EnvironmentObject var model: AppModel
    let p: Programme

    var body: some View {
        let imdb = model.meta.imdb(for: p)
        let show = p.kind == .episode ? model.meta.show(for: p.displayTitle) : nil
        if imdb != nil || show != nil {
            HStack(spacing: Theme.s(10)) {
                if let imdb { IMDbBadge(title: imdb) }
                else if let r = show?.rating { Text("★ \(String(format: "%.1f", r)) TVmaze") }
                if let imdb, let y = imdb.year {
                    Text(imdb.isSeries ? "\(y)–\(imdb.endYear.map(String.init) ?? "")" : String(y))
                }
                if let m = imdb?.runtime, p.kind == .movie { Text("\(m / 60)h \(m % 60)m") }
                let genres = imdb?.genres ?? show?.genres ?? []
                if !genres.isEmpty { Text(genres.prefix(3).joined(separator: ", ")).foregroundStyle(Theme.faint) }
            }
            .font(Theme.f(.callout)).foregroundStyle(Theme.dim).lineLimit(1)
        }
    }
}
