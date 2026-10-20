import Foundation

/// Builds archive (catch-up) URLs for a programme.
enum Catchup {
    static func url(for channel: Channel, programme original: Programme, xtream: XtreamClient?, serverTimeZone: TimeZone?, now: Date = .now) -> URL? {
        guard channel.hasCatchup else { return nil }
        let minutes = Int((original.duration / 60).rounded(.up))
        // catchup-correction (hours) shifts the archive request.
        var p = original
        if channel.catchupCorrection != 0 {
            p.start += channel.catchupCorrection * 3600
            p.stop += channel.catchupCorrection * 3600
        }

        if let id = channel.xtreamStreamID, let xtream {
            return xtream.timeshiftURL(streamID: id, start: p.start, minutes: minutes, serverTimeZone: serverTimeZone)
        }

        let mode = (channel.catchupMode ?? "default").lowercased()
        let base = channel.url.absoluteString

        if let template = channel.catchupSource, !template.isEmpty {
            let filled = fill(template, start: p.start, end: p.stop, now: now)
            if mode == "append" {
                let joined = base.contains("?") && filled.hasPrefix("?") ? "&" + filled.dropFirst() : filled
                return URL(string: base + joined)
            }
            return URL(string: filled)
        }

        switch mode {
        case "shift", "timeshift":
            let sep = base.contains("?") ? "&" : "?"
            return URL(string: base + sep + "utc=\(Int(p.start.timeIntervalSince1970))&lutc=\(Int(now.timeIntervalSince1970))")
        case "flussonic", "flussonic-ts", "fs":
            // .../channel/index.m3u8 -> .../channel/index-{start}-{duration}.m3u8 ; .../channel/mpegts -> .../channel/timeshift_abs-{start}.ts
            let start = Int(p.start.timeIntervalSince1970)
            let dur = Int(p.duration)
            if base.contains("/mpegts") {
                return URL(string: base.replacingOccurrences(of: "/mpegts", with: "/timeshift_abs-\(start).ts"))
            }
            if let r = base.range(of: #"/[^/]*\.m3u8"#, options: .regularExpression) {
                let name = base[r].dropFirst().replacingOccurrences(of: ".m3u8", with: "")
                let prefix = name == "index" || name == "video" ? name : "index"
                return URL(string: base.replacingCharacters(in: r, with: "/\(prefix)-\(start)-\(dur).m3u8"))
            }
            return nil
        case "xc":
            // Xtream-style URL in an M3U: http://host/user/pass/id(.ts) -> /timeshift/user/pass/min/start/id.ts
            let comps = channel.url.pathComponents.filter { $0 != "/" }
            guard comps.count >= 3, let host = channel.url.host else { return nil }
            let tail = comps.suffix(3)
            let user = tail[tail.startIndex], pass = tail[tail.startIndex + 1]
            let id = tail.last!.split(separator: ".").first.map(String.init) ?? tail.last!
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = serverTimeZone ?? .current
            f.dateFormat = "yyyy-MM-dd:HH-mm"
            let port = channel.url.port.map { ":\($0)" } ?? ""
            return URL(string: "\(channel.url.scheme ?? "http")://\(host)\(port)/timeshift/\(user)/\(pass)/\(minutes)/\(f.string(from: p.start))/\(id).ts")
        default:
            // "default"/"append" without a template: common query-string form.
            let sep = base.contains("?") ? "&" : "?"
            return URL(string: base + sep + "utc=\(Int(p.start.timeIntervalSince1970))&lutc=\(Int(now.timeIntervalSince1970))")
        }
    }

    /// Replaces catchup-source placeholders. Supports {utc} {start} {utcend} {end} {lutc} {now} {timestamp}
    /// {duration} {duration:N} {offset:N} {Y} {m} {d} {H} {M} {S} and the ${…} variants, plus {utc:FORMAT}/{start:FORMAT}.
    static func fill(_ template: String, start: Date, end: Date, now: Date) -> String {
        let s = Int(start.timeIntervalSince1970)
        let e = Int(end.timeIntervalSince1970)
        let n = Int(now.timeIntervalSince1970)
        let dur = e - s
        var out = template.replacingOccurrences(of: "${", with: "{")

        // Placeholders with arguments: {duration:60}, {offset:1}, {utc:Y-m-d}, {utcend:...}
        let pattern = #"\{(\w+):([^}]+)\}"#
        if let re = try? NSRegularExpression(pattern: pattern) {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let name = ns.substring(with: m.range(at: 1)).lowercased()
                let arg = ns.substring(with: m.range(at: 2))
                switch name {
                case "duration": result += String(dur / max(1, Int(arg) ?? 1))
                case "offset": result += String((n - s) / max(1, Int(arg) ?? 1))
                case "utc", "start": result += strftime(arg, start)
                case "utcend", "end": result += strftime(arg, end)
                case "lutc", "now", "timestamp": result += strftime(arg, now)
                default: result += ns.substring(with: m.range)
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }

        let cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents(in: utc, from: start)
        let ce = cal.dateComponents(in: utc, from: end)
        func two(_ v: Int?) -> String { String(format: "%02d", v ?? 0) }
        let simple: [String: String] = [
            "{utc}": "\(s)", "{start}": "\(s)", "{utcend}": "\(e)", "{end}": "\(e)",
            "{lutc}": "\(n)", "{now}": "\(n)", "{timestamp}": "\(n)",
            "{duration}": "\(dur)", "{offset}": "\(n - s)",
            "{Y}": "\(c.year ?? 0)", "{m}": two(c.month), "{d}": two(c.day),
            "{H}": two(c.hour), "{M}": two(c.minute), "{S}": two(c.second),
            "{Ye}": "\(ce.year ?? 0)", "{me}": two(ce.month), "{de}": two(ce.day),
            "{He}": two(ce.hour), "{Me}": two(ce.minute), "{Se}": two(ce.second),
        ]
        for (k, v) in simple { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }

    /// `{utc:Y-m-d H:M:S}` style formats use the single-letter tokens above.
    private static func strftime(_ fmt: String, _ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        var out = ""
        for ch in fmt {
            switch ch {
            case "Y": out += "\(c.year ?? 0)"
            case "m": out += String(format: "%02d", c.month ?? 0)
            case "d": out += String(format: "%02d", c.day ?? 0)
            case "H": out += String(format: "%02d", c.hour ?? 0)
            case "M": out += String(format: "%02d", c.minute ?? 0)
            case "S": out += String(format: "%02d", c.second ?? 0)
            default: out.append(ch)
            }
        }
        return out
    }
}
