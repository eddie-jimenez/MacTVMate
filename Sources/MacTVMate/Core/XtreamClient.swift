import Foundation

/// Xtream Codes `player_api.php` client.
struct XtreamClient {
    let server: URL
    let username: String
    let password: String
    let userAgent: String

    init?(server: String, username: String, password: String, userAgent: String) {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s) else { return nil }
        self.server = url
        self.username = username
        self.password = password
        self.userAgent = userAgent
    }

    struct ServerInfo {
        var timezone: TimeZone?
        var expiry: Date?
        var maxConnections: Int?
        var status: String?
    }

    struct Category: Decodable {
        let category_id: FlexString
        let category_name: String
    }

    struct LiveStream: Decodable {
        let num: FlexInt?
        let name: String
        let stream_id: FlexInt
        let stream_icon: String?
        let epg_channel_id: String?
        let category_id: FlexString?
        let tv_archive: FlexInt?
        let tv_archive_duration: FlexInt?
    }

    func apiURL(action: String? = nil) -> URL {
        var c = URLComponents(url: server.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "username", value: username), URLQueryItem(name: "password", value: password)]
        if let action { c.queryItems!.append(URLQueryItem(name: "action", value: action)) }
        return c.url!
    }

    var xmltvURL: URL {
        var c = URLComponents(url: server.appendingPathComponent("xmltv.php"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "username", value: username), URLQueryItem(name: "password", value: password)]
        return c.url!
    }

    func liveURL(streamID: Int, hls: Bool) -> URL {
        server.appendingPathComponent("live/\(username)/\(password)/\(streamID).\(hls ? "m3u8" : "ts")")
    }

    /// `/timeshift/{user}/{pass}/{minutes}/{yyyy-MM-dd:HH-mm}/{id}.ts`, start expressed in the server's timezone.
    func timeshiftURL(streamID: Int, start: Date, minutes: Int, serverTimeZone: TimeZone?) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = serverTimeZone ?? .current
        f.dateFormat = "yyyy-MM-dd:HH-mm"
        return server.appendingPathComponent("timeshift/\(username)/\(password)/\(minutes)/\(f.string(from: start))/\(streamID).ts")
    }

    func getData(_ url: URL) async throws -> Data { try await get(url) }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 30)
        if !userAgent.isEmpty { req.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        var (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
            req.setValue(Defaults.browserUserAgent, forHTTPHeaderField: "User-Agent")
            (data, resp) = try await URLSession.shared.data(for: req)
        }
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from \(url.host ?? "server")"])
        }
        return data
    }

    func serverInfo() async throws -> ServerInfo {
        try Self.parseServerInfo(try await get(apiURL()))
    }

    static func parseServerInfo(_ data: Data) throws -> ServerInfo {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        let user = obj["user_info"] as? [String: Any] ?? [:]
        let srv = obj["server_info"] as? [String: Any] ?? [:]
        if let auth = user["auth"], "\(auth)" == "0" {
            throw URLError(.userAuthenticationRequired, userInfo: [NSLocalizedDescriptionKey: "Xtream login rejected"])
        }
        var info = ServerInfo()
        info.timezone = (srv["timezone"] as? String).flatMap(TimeZone.init(identifier:))
        info.status = user["status"] as? String
        if let exp = user["exp_date"].map({ "\($0)" }), let t = TimeInterval(exp) { info.expiry = Date(timeIntervalSince1970: t) }
        if let m = user["max_connections"].map({ "\($0)" }) { info.maxConnections = Int(m) }
        return info
    }

    func categories() async throws -> [Category] {
        try JSONDecoder().decode([Category].self, from: try await get(apiURL(action: "get_live_categories")))
    }

    func liveStreams() async throws -> [LiveStream] {
        try JSONDecoder().decode([LiveStream].self, from: try await get(apiURL(action: "get_live_streams")))
    }

    func xmltv() async throws -> Data {
        try await get(xmltvURL)
    }

    /// `get_short_epg`: the next few programmes for one stream. Titles/descriptions are base64 on most panels.
    func shortEPG(streamID: Int, limit: Int = 12) async throws -> [Programme] {
        var c = URLComponents(url: apiURL(action: "get_short_epg"), resolvingAgainstBaseURL: false)!
        c.queryItems! += [URLQueryItem(name: "stream_id", value: String(streamID)), URLQueryItem(name: "limit", value: String(limit))]
        let data = try await get(c.url!)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let listings = obj["epg_listings"] as? [[String: Any]] else { return [] }
        func text(_ v: Any?) -> String? {
            guard let s = v as? String, !s.isEmpty else { return nil }
            if let d = Data(base64Encoded: s), let decoded = String(data: d, encoding: .utf8) { return decoded }
            return s
        }
        func epoch(_ v: Any?) -> Date? {
            guard let v, let t = TimeInterval("\(v)") else { return nil }
            return Date(timeIntervalSince1970: t)
        }
        let key = "xc:\(streamID)"
        return listings.compactMap { l in
            guard let start = epoch(l["start_timestamp"]), let stop = epoch(l["stop_timestamp"] ?? l["end_timestamp"]), stop > start,
                  let title = text(l["title"]) else { return nil }
            return Programme(channelKey: key, start: start, stop: stop, title: title, desc: text(l["description"]))
        }.sorted { $0.start < $1.start }
    }
}

/// Xtream panels return numbers as strings or ints interchangeably.
struct FlexInt: Decodable {
    let value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let s = try? c.decode(String.self) { value = Int(s) ?? 0 }
        else if let d = try? c.decode(Double.self) { value = Int(d) }
        else { value = 0 }
    }
}

struct FlexString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else { value = "" }
    }
}
