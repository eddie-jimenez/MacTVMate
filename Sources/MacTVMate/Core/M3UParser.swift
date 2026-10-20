import Foundation

/// Parses extended M3U playlists (#EXTM3U / #EXTINF with tvg-* attributes).
enum M3UParser {
    struct Result {
        var channels: [Channel]
        /// `url-tvg` / `x-tvg-url` from the #EXTM3U header, if present.
        var headerEPGURL: String?
    }

    static func parse(_ text: String, sourceID: UUID) -> Result {
        var channels: [Channel] = []
        var headerEPG: String?
        var header: [String: String] = [:]
        var pending: (attrs: [String: String], name: String)?
        var pendingGroup: String?
        var pendingOpts: [String] = []
        var seenIDs = Set<String>()

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTM3U") {
                let attrs = parseAttributes(line)
                header = attrs
                headerEPG = attrs["url-tvg"] ?? attrs["x-tvg-url"]
                headerEPG = headerEPG?.split(separator: ",").first.map(String.init)
            } else if line.hasPrefix("#EXTINF") {
                let attrs = parseAttributes(line)
                let name = extinfTitle(line)
                pending = (attrs, name)
            } else if line.hasPrefix("#EXTGRP:") {
                pendingGroup = groupName(line.dropFirst(8))
            } else if line.hasPrefix("#EXTVLCOPT:") {
                pendingOpts.append(String(line.dropFirst(11)))
            } else if line.hasPrefix("#") {
                continue
            } else if let info = pending {
                // Header-level catchup/tvg-shift apply to every channel unless overridden.
                let a = header.filter { ["catchup", "catchup-type", "catchup-days", "catchup-source", "catchup-correction", "tvg-shift"].contains($0.key) }
                    .merging(info.attrs) { _, channel in channel }
                // Kodi-style `url|User-Agent=…&Referer=…`.
                var urlString = line
                var pipeHeaders: [String: String] = [:]
                if let bar = line.firstIndex(of: "|") {
                    urlString = String(line[..<bar])
                    for pair in line[line.index(after: bar)...].split(separator: "&") {
                        let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                        if kv.count == 2 { pipeHeaders[kv[0].lowercased()] = kv[1].removingPercentEncoding ?? kv[1] }
                    }
                }
                guard let url = URL(string: urlString) else { pending = nil; continue }
                let vlc = Dictionary(pendingOpts.compactMap { opt -> (String, String)? in
                    let kv = opt.split(separator: "=", maxSplits: 1).map(String.init)
                    return kv.count == 2 ? (kv[0].lowercased(), kv[1]) : nil
                }, uniquingKeysWith: { a, _ in a })
                let name = a["tvg-name"].flatMap { $0.isEmpty ? nil : $0 } ?? info.name
                var id = "\(sourceID.uuidString)|\(a["tvg-id"] ?? "")|\(name)"
                if seenIDs.contains(id) { id += "|\(channels.count)" }
                seenIDs.insert(id)

                let number = Int(a["tvg-chno"] ?? a["channel-number"] ?? "") ?? channels.count + 1
                var ch = Channel(
                    id: id,
                    number: number,
                    name: info.name.isEmpty ? name : info.name,
                    group: a["group-title"] ?? pendingGroup ?? "Uncategorised",
                    logo: a["tvg-logo"].flatMap { URL(string: $0) },
                    url: url,
                    epgID: a["tvg-id"].flatMap { $0.isEmpty ? nil : $0 } ?? name
                )
                ch.userAgent = a["user-agent"] ?? a["http-user-agent"] ?? vlc["http-user-agent"] ?? pipeHeaders["user-agent"]
                ch.referrer = a["http-referrer"] ?? a["referrer"] ?? vlc["http-referrer"] ?? pipeHeaders["referer"] ?? pipeHeaders["referrer"]
                ch.epgShift = Double(a["tvg-shift"] ?? "") ?? 0
                ch.catchupCorrection = Double(a["catchup-correction"] ?? "") ?? 0
                if let days = Int(a["catchup-days"] ?? a["tvg-rec"] ?? a["timeshift"] ?? ""), days > 0 {
                    ch.catchupDays = days
                    ch.catchupMode = a["catchup"] ?? a["catchup-type"] ?? "default"
                    ch.catchupSource = a["catchup-source"]
                }
                channels.append(ch)
                pending = nil
                pendingGroup = nil
                pendingOpts = []
            }
        }
        return Result(channels: channels, headerEPGURL: headerEPG)
    }

    private static let attributeRegex = try! NSRegularExpression(
        pattern: #"([a-z0-9-]+)\s*=\s*("([^"]*)"|([^\s,]*))"#, options: [.caseInsensitive])

    /// Extracts `key="value"` and unquoted `key=value` pairs (TiViMate accepts both, e.g. `tvg-shift=-2`).
    /// For #EXTINF lines only the part before the title comma is scanned.
    static func parseAttributes(_ line: String) -> [String: String] {
        let part = line.hasPrefix("#EXTINF") ? splitExtinf(line).attributes : line
        var result: [String: String] = [:]
        let ns = part as NSString
        for m in attributeRegex.matches(in: part, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            // Groups: 1 key, 2 whole value, 3 quoted value, 4 bare value.
            guard m.numberOfRanges >= 5 else { continue }
            let quoted = m.range(at: 3), bare = m.range(at: 4)
            let value = quoted.location != NSNotFound ? ns.substring(with: quoted)
                : bare.location != NSNotFound ? ns.substring(with: bare) : ""
            if result[key] == nil { result[key] = value }
        }
        return result
    }

    /// The display title is everything after the first comma outside quotes
    /// (attribute values can't contain unquoted commas, but titles can).
    static func extinfTitle(_ line: String) -> String {
        splitExtinf(line).title
    }

    static func splitExtinf(_ line: String) -> (attributes: String, title: String) {
        var inQuotes = false
        for idx in line.indices {
            let c = line[idx]
            if c == "\"" { inQuotes.toggle() } else if c == ",", !inQuotes {
                return (String(line[..<idx]), line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces))
            }
        }
        return (line, "")
    }

    /// `#EXTGRP:12. Sports` -> `Sports` (TiViMate strips a numeric prefix).
    static func groupName(_ raw: Substring) -> String {
        var g = String(raw)
        if let r = g.range(of: #"^\s*\d+\."#, options: .regularExpression) { g.removeSubrange(r) }
        return g.trimmingCharacters(in: .whitespaces)
    }

    /// Xtream `get.php?username=…&password=…&type=…&output=…` URLs are loaded through player_api instead.
    static func xtreamCredentials(fromGetPHP urlString: String) -> (server: String, username: String, password: String, hls: Bool)? {
        guard let c = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.path.hasSuffix("/get.php"),
              let items = c.queryItems,
              let user = items.first(where: { $0.name == "username" })?.value,
              let pass = items.first(where: { $0.name == "password" })?.value,
              let scheme = c.scheme, let host = c.host
        else { return nil }
        let output = items.first(where: { $0.name == "output" })?.value ?? "ts"
        let port = c.port.map { ":\($0)" } ?? ""
        let base = c.path.dropLast("/get.php".count)
        return ("\(scheme)://\(host)\(port)\(base)", user, pass, !output.contains("ts"))
    }
}
