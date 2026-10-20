import Foundation
import SQLite3

/// Local index of IMDb's official datasets (datasets.imdbws.com — free for personal, non-commercial use).
/// Built from title.basics + title.ratings into SQLite; only movies/series with ratings are kept.
struct IMDbTitle: Sendable, Hashable {
    let tconst: String        // "tt8550800"
    let type: String          // movie, tvMovie, tvSeries, tvMiniSeries, tvSpecial
    let title: String
    let year: Int?
    let endYear: Int?
    let runtime: Int?
    let genres: [String]
    let rating: Double
    let votes: Int

    var url: URL { URL(string: "https://www.imdb.com/title/\(tconst)/")! }
    var isSeries: Bool { type == "tvSeries" || type == "tvMiniSeries" }
    var ratingText: String { String(format: "%.1f", rating) }
    var votesText: String {
        votes >= 1_000_000 ? String(format: "%.1fM", Double(votes) / 1e6)
            : votes >= 1000 ? "\(votes / 1000)K" : "\(votes)"
    }
}

actor IMDbIndex {
    enum State: Equatable { case missing, building(String), ready(Date), failed(String) }

    static let shared = IMDbIndex()
    private(set) var state: State = .missing
    private var db: OpaquePointer?
    private var lookupStmt: OpaquePointer?
    private var cache: [String: IMDbTitle?] = [:]

    private let dir = Persistence().dir
    private var dbURL: URL { dir.appendingPathComponent("imdb.sqlite") }

    init() {}

    /// Opens the index if present; (re)builds it in the background when missing or older than a week.
    func prepare(onChange: @escaping @Sendable (State) -> Void) async {
        if db == nil { open() }
        let built = (try? FileManager.default.attributesOfItem(atPath: dbURL.path)[.modificationDate] as? Date) ?? nil
        if let built, db != nil {
            state = .ready(built)
            onChange(state)
            if Date().timeIntervalSince(built) < 7 * 86400 { return }
        }
        await build(onChange: onChange)
    }

    // MARK: Lookup

    /// Best IMDb match for a title (and year when known). Movies prefer ±1 year; series prefer the most-voted.
    func lookup(title: String, year: Int?, series: Bool) -> IMDbTitle? {
        let norm = Self.normalise(title)
        guard !norm.isEmpty, let db else { return nil }
        let key = "\(norm)|\(year ?? 0)|\(series)"
        if let hit = cache[key] { return hit }
        if lookupStmt == nil {
            sqlite3_prepare_v2(db, "SELECT tconst,type,title,year,end_year,runtime,genres,rating,votes FROM titles WHERE norm=?1 ORDER BY votes DESC LIMIT 25", -1, &lookupStmt, nil)
        }
        guard let st = lookupStmt else { return nil }
        sqlite3_reset(st)
        sqlite3_bind_text(st, 1, norm, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var rows: [IMDbTitle] = []
        while sqlite3_step(st) == SQLITE_ROW {
            func str(_ i: Int32) -> String { sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" }
            func int(_ i: Int32) -> Int? { sqlite3_column_type(st, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(st, i)) }
            rows.append(IMDbTitle(tconst: str(0), type: str(1), title: str(2), year: int(3), endYear: int(4), runtime: int(5),
                                  genres: str(6).split(separator: ",").map(String.init),
                                  rating: sqlite3_column_double(st, 7), votes: int(8) ?? 0))
        }
        let candidates = rows.filter { series ? $0.isSeries : !$0.isSeries }
        var best: IMDbTitle?
        if let year, !series {
            best = candidates.filter { $0.year.map { abs($0 - year) <= 1 } ?? false }.max { $0.votes < $1.votes }
        }
        // Without a year, only trust a clear favourite (avoids matching an obscure namesake).
        if best == nil, year == nil || series {
            let sorted = candidates.sorted { $0.votes > $1.votes }
            if let first = sorted.first, sorted.count == 1 || first.votes >= 5 * sorted[1].votes || first.votes > 20_000 { best = first }
        }
        cache[key] = best
        return best
    }

    static func normalise(_ s: String) -> String {
        var t = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        t = t.replacingOccurrences(of: "&", with: " and ")
        t = t.replacingOccurrences(of: #"\s*\((19|20)\d{2}\)\s*$"#, with: "", options: .regularExpression)   // "Title (1993)"
        t = t.replacingOccurrences(of: #"^(the|a|an)\s+"#, with: "", options: .regularExpression)
        return t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    // MARK: Build

    private func open() {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return }
        var h: OpaquePointer?
        if sqlite3_open_v2(dbURL.path, &h, SQLITE_OPEN_READONLY, nil) == SQLITE_OK { db = h } else { sqlite3_close(h) }
    }

    private func close() {
        if let s = lookupStmt { sqlite3_finalize(s); lookupStmt = nil }
        if let d = db { sqlite3_close(d); db = nil }
    }

    private func build(onChange: @escaping @Sendable (State) -> Void) async {
        func report(_ s: State) { state = s; onChange(s) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mactvmate-imdb-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            report(.building("Downloading IMDb ratings…"))
            let ratingsGz = try await download("title.ratings", to: tmp)
            report(.building("Downloading IMDb titles (230 MB)…"))
            let basicsGz = try await download("title.basics", to: tmp)

            report(.building("Indexing IMDb ratings…"))
            var ratings: [Int32: (Float, Int32)] = [:]
            ratings.reserveCapacity(1_700_000)
            try await Self.eachLine(gz: ratingsGz) { line in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard f.count >= 3, f[0].hasPrefix("tt"), let id = Int32(f[0].dropFirst(2)),
                      let r = Float(f[1]), let v = Int32(f[2]), v >= 20 else { return }
                ratings[id] = (r, v)
            }

            report(.building("Indexing IMDb titles…"))
            let out = dir.appendingPathComponent("imdb.sqlite.new")
            try? FileManager.default.removeItem(at: out)
            var w: OpaquePointer?
            guard sqlite3_open(out.path, &w) == SQLITE_OK, let w else { throw URLError(.cannotCreateFile) }
            defer { sqlite3_close(w) }
            sqlite3_exec(w, "PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; CREATE TABLE titles(tconst TEXT, type TEXT, norm TEXT, title TEXT, year INT, end_year INT, runtime INT, genres TEXT, rating REAL, votes INT); BEGIN;", nil, nil, nil)
            var ins: OpaquePointer?
            sqlite3_prepare_v2(w, "INSERT INTO titles VALUES (?,?,?,?,?,?,?,?,?,?)", -1, &ins, nil)
            let keep: Set<Substring> = ["movie", "tvMovie", "tvSeries", "tvMiniSeries", "tvSpecial"]
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            var count = 0
            try await Self.eachLine(gz: basicsGz) { line in
                // tconst titleType primaryTitle originalTitle isAdult startYear endYear runtimeMinutes genres
                let f = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard f.count >= 9, keep.contains(f[1]), f[4] == "0", f[0].hasPrefix("tt"),
                      let id = Int32(f[0].dropFirst(2)), let (r, v) = ratings[id] else { return }
                func bindText(_ i: Int32, _ s: Substring) { sqlite3_bind_text(ins, i, String(s), -1, transient) }
                func bindInt(_ i: Int32, _ s: Substring) { if let n = Int64(s) { sqlite3_bind_int64(ins, i, n) } else { sqlite3_bind_null(ins, i) } }
                let names = f[2] == f[3] ? [f[2]] : [f[2], f[3]]
                for name in names {
                    sqlite3_reset(ins)
                    bindText(1, f[0]); bindText(2, f[1]); bindText(3, Substring(Self.normalise(String(name)))); bindText(4, f[2])
                    bindInt(5, f[5]); bindInt(6, f[6]); bindInt(7, f[7])
                    bindText(8, f[8] == "\\N" ? "" : f[8])
                    sqlite3_bind_double(ins, 9, Double(r)); sqlite3_bind_int64(ins, 10, Int64(v))
                    sqlite3_step(ins)
                }
                count += 1
            }
            sqlite3_finalize(ins)
            sqlite3_exec(w, "COMMIT; CREATE INDEX idx_norm ON titles(norm);", nil, nil, nil)
            sqlite3_close(w)

            close()
            cache = [:]
            _ = try FileManager.default.replaceItemAt(dbURL, withItemAt: out)
            open()
            report(.ready(Date()))
            Persistence().log("IMDb index built: \(count) titles")
        } catch {
            report(db == nil ? .failed(error.localizedDescription) : .ready(Date()))
            Persistence().log("IMDb index build failed: \(error.localizedDescription)")
        }
    }

    private func download(_ name: String, to dir: URL) async throws -> URL {
        let url = URL(string: "https://datasets.imdbws.com/\(name).tsv.gz")!
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let dest = dir.appendingPathComponent("\(name).tsv.gz")
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Streams a .gz through /usr/bin/gunzip, calling `body` for each line after the header.
    private static func eachLine(gz: URL, _ body: (Substring) -> Void) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        p.arguments = ["-c", gz.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let handle = pipe.fileHandleForReading
        var buffer = Data()
        var first = true
        while true {
            let chunk = handle.readData(ofLength: 4 << 20)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            guard let lastNL = buffer.lastIndex(of: 0x0A) else { continue }
            let complete = buffer[buffer.startIndex...lastNL]
            let text = String(decoding: complete, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if first { first = false; continue }
                body(line)
            }
            buffer = Data(buffer[(lastNL + 1)...])
            await Task.yield()
        }
        p.waitUntilExit()
    }
}
