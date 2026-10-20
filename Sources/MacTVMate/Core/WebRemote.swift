import AppKit
import Network
import SystemConfiguration

/// iPhone/iPad remote: MacTVMate serves a remote-control page on the home network.
/// Requests must carry the private key from Settings (in the link / QR code) and come from a local address.
@MainActor
final class WebRemote: ObservableObject {
    static let port: UInt16 = 8765
    @Published private(set) var status = "Starting…"
    @Published private(set) var clients = 0

    private var listener: NWListener?
    private unowned let model: AppModel
    private var lastSeen: [String: Date] = [:]

    init(model: AppModel) {
        self.model = model
    }

    var token: String { model.settings.remoteToken }

    /// "http://Eddies-MacBook-Pro.local:8765/?k=…" (Bonjour name works from any device on the same Wi-Fi).
    var url: URL? {
        guard let host = (SCDynamicStoreCopyLocalHostName(nil) as String?) else { return nil }
        return URL(string: "http://\(host).local:\(Self.port)/?k=\(token)")
    }

    /// Same link by IP, in case .local names don't resolve.
    var ipURL: URL? {
        guard let ip = Self.lanIPv4() else { return nil }
        return URL(string: "http://\(ip):\(Self.port)/?k=\(token)")
    }

    func start() {
        guard listener == nil, model.settings.webRemoteEnabled else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.status = "On — open the link below on your iPhone (same Wi-Fi)"
                    case .failed(let e): self?.status = "Couldn't start: \(e.localizedDescription)"; self?.listener = nil
                    default: break
                    }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            status = "Couldn't start: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        status = "Off"
    }

    // MARK: HTTP

    private func accept(_ conn: NWConnection) {
        // Home network only: loopback, private IPv4 ranges, link-local / unique-local IPv6.
        guard Self.isLocal(conn.endpoint) else { conn.cancel(); return }
        conn.start(queue: .main)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self else { return }
                var buf = buffer
                if let data { buf.append(data) }
                if let req = Request(buf) {
                    self.respond(conn, req)
                } else if done || error != nil || buf.count > 1 << 20 {
                    conn.cancel()
                } else {
                    self.receive(conn, buffer: buf)
                }
            }
        }
    }

    private struct Request {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data

        init?(_ data: Data) {
            guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
                  let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
            let lines = head.components(separatedBy: "\r\n")
            let first = lines[0].split(separator: " ")
            guard first.count >= 2 else { return nil }
            var headers: [String: String] = [:]
            for l in lines.dropFirst() {
                if let i = l.firstIndex(of: ":") {
                    headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
                }
            }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            let bodyStart = headerEnd.upperBound
            guard data.count - bodyStart >= length else { return nil }
            method = String(first[0])
            let comps = URLComponents(string: "http://x" + first[1])
            path = comps?.path ?? "/"
            query = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            self.headers = headers
            body = data[bodyStart..<(bodyStart + length)]
        }

        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:] }
    }

    private func respond(_ conn: NWConnection, _ r: Request) {
        func send(_ status: String, _ type: String, _ body: Data) {
            var head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            head += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
        }
        func json(_ obj: Any) {
            send("200 OK", "application/json", (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8))
        }

        // The page itself carries the key in its URL; API calls send it as a header. Icon/manifest are public.
        let key = r.headers["x-remote-key"] ?? r.query["k"] ?? ""
        let publicPaths: Set<String> = ["/manifest.json", "/icon.png", "/favicon.ico"]
        guard key == token || publicPaths.contains(r.path) else {
            send("403 Forbidden", "text/html; charset=utf-8",
                 Data("<h2 style='font-family:-apple-system'>MacTVMate remote</h2><p style='font-family:-apple-system'>Open the link or QR code from MacTVMate ▸ Settings ▸ Remote &amp; keyboard.</p>".utf8))
            return
        }
        lastSeen[Self.describe(conn.endpoint)] = Date()
        clients = lastSeen.values.filter { Date().timeIntervalSince($0) < 30 }.count

        switch (r.method, r.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            send("200 OK", "text/html; charset=utf-8", Data(RemotePage.html.utf8))
        case ("GET", "/manifest.json"):
            send("200 OK", "application/manifest+json", Data(RemotePage.manifest.utf8))
        case ("GET", "/icon.png"):
            send("200 OK", "image/png", Self.iconPNG)
        case ("POST", "/api/key"):
            if let a = r.json["action"] as? String { model.webAction(a, value: r.json["value"]) }
            json(model.remoteState())
        case ("GET", "/api/state"):
            json(model.remoteState())
        case ("GET", "/api/groups"):
            json(["selected": model.selectedGroup, "groups": model.library.groups.map { ["name": $0.name, "count": $0.count] }])
        case ("GET", "/api/channels"):
            json(model.remoteChannels(group: r.query["group"] ?? model.selectedGroup))
        case ("GET", "/api/search"):
            json(model.remoteSearch(r.query["q"] ?? ""))
        case ("POST", "/api/play"):
            if let id = r.json["id"] as? String { model.remotePlay(id: id) }
            json(model.remoteState())
        case ("POST", "/api/go"):
            if let s = r.json["section"] as? String { model.remoteGo(s) }
            json(model.remoteState())
        case ("POST", "/api/group"):
            if let g = r.json["name"] as? String { model.remoteSelectGroup(g) }
            json(["ok": true])
        case ("GET", "/api/vod"):
            let kind: VODKind = r.query["kind"] == "series" ? .series : .movies
            Task { json(await model.remoteVOD(kind: kind, category: r.query["cat"] ?? "", query: r.query["q"] ?? "",
                                              offset: Int(r.query["offset"] ?? "") ?? 0)) }
        case ("GET", "/api/series"):
            Task { json(await model.remoteSeries(id: r.query["id"] ?? "")) }
        case ("POST", "/api/vod/play"):
            let id = r.json["id"] as? String ?? ""
            if let ep = r.json["episode"] as? Int {
                Task { await model.remotePlayEpisode(series: id, episode: ep); json(model.remoteState()) }
            } else {
                model.remotePlayMovie(id: id)
                json(model.remoteState())
            }
        case ("POST", "/api/mylist"):
            json(model.remoteToggleMyList(id: r.json["id"] as? String ?? ""))
        case ("GET", "/api/library"):
            Task { json(await model.remoteLibrary()) }
        case ("POST", "/api/recording/play"):
            model.remotePlayRecording(id: r.json["id"] as? String ?? "")
            json(model.remoteState())
        default:
            send("404 Not Found", "text/plain", Data("Not found".utf8))
        }
    }

    // MARK: Helpers

    private static func host(_ e: NWEndpoint) -> NWEndpoint.Host? {
        if case let .hostPort(host, _) = e { return host }
        return nil
    }

    private static func describe(_ e: NWEndpoint) -> String { host(e).map { "\($0)" } ?? "?" }

    static func isLocal(_ e: NWEndpoint) -> Bool {
        guard let h = host(e) else { return false }
        switch h {
        case .ipv4(let a):
            let b = [UInt8](a.rawValue)
            return b[0] == 127 || b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168)
                || (b[0] == 169 && b[1] == 254)
        case .ipv6(let a):
            if a == .loopback { return true }
            let b = [UInt8](a.rawValue)
            if let v4 = a.asIPv4 { return isLocal(.hostPort(host: .ipv4(v4), port: 0)) }
            return (b[0] & 0xFE) == 0xFC || (b[0] == 0xFE && (b[1] & 0xC0) == 0x80)
        default:
            return false
        }
    }

    static func lanIPv4() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var best: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  (Int32(ifa.ifa_flags) & IFF_UP) != 0, (Int32(ifa.ifa_flags) & IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            let name = String(cString: ifa.ifa_name)
            if name == "en0" { return ip }
            if best == nil, ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") { best = ip }
        }
        return best
    }

    private static let iconPNG: Data = {
        guard let icon = NSApp.applicationIconImage, let tiff = icon.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return Data() }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }()
}
