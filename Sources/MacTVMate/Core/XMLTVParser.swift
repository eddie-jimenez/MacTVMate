import Foundation
import NaturalLanguage

/// Streaming XMLTV parser. Keeps only programmes for wanted channels inside a time window.
final class XMLTVParser: NSObject, XMLParserDelegate {
    struct Result {
        /// Programmes keyed by normalised channel key, sorted by start.
        var programmes: [String: [Programme]]
        /// XMLTV channel id -> normalised display names (for name-based matching).
        var displayNames: [String: [String]]
        /// XMLTV channel id -> detected language of its listings ("en", "es", "fr"…).
        var languages: [String: String] = [:]
    }

    private let window: ClosedRange<Date>
    private let wanted: ChannelMatch.Wanted?
    /// Channel ids whose programmes are kept (nil = keep everything).
    private var keep: Set<String>?
    private var currentNames: [String] = []
    private var programmes: [String: [Programme]] = [:]
    private var displayNames: [String: [String]] = [:]

    private var currentChannelID: String?
    private var current: Programme?
    private var text = ""
    private var stack: [String] = []
    private var episodeSystem: String?
    /// A few titles/descriptions per channel for language detection.
    private var samples: [String: String] = [:]

    private static let placeholderTitles: Set<String> = ["no data", "no information", "no program information",
                                                         "no programme information", "no info", "n/a"]

    init(window: ClosedRange<Date>, wanted: ChannelMatch.Wanted?) {
        self.window = window
        self.wanted = wanted
        self.keep = wanted == nil ? nil : []
    }

    static func parse(data: Data, window: ClosedRange<Date>, wanted: ChannelMatch.Wanted? = nil) -> Result {
        let xml = Gzip.isGzipped(data) ? (Gzip.decompress(data) ?? data) : data
        let delegate = XMLTVParser(window: window, wanted: wanted)
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.parse()
        for key in delegate.programmes.keys {
            delegate.programmes[key]?.sort { $0.start < $1.start }
        }
        // Language per channel, so a Spanish "Cinemax" feed doesn't win over the English one.
        var languages: [String: String] = [:]
        let recognizer = NLLanguageRecognizer()
        for (id, text) in delegate.samples {
            recognizer.reset()
            recognizer.processString(text)
            if let lang = recognizer.dominantLanguage { languages[id] = lang.rawValue }
        }
        return Result(programmes: delegate.programmes, displayNames: delegate.displayNames, languages: languages)
    }

    static func key(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespaces) }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        stack.append(name)
        switch name {
        case "channel":
            currentChannelID = a["id"].map(Self.key)
            currentNames = []
        case "programme":
            guard let ch = a["channel"], let start = a["start"].flatMap(Self.date), let stop = a["stop"].flatMap(Self.date) else {
                current = nil
                return
            }
            if stop < window.lowerBound || start > window.upperBound || !(keep?.contains(Self.key(ch)) ?? true) {
                current = nil
                return
            }
            current = Programme(channelKey: Self.key(ch), start: start, stop: stop, title: "")
        case "icon":
            if current != nil, current?.icon == nil, let src = a["src"] { current?.icon = URL(string: src) }
        case "episode-num":
            episodeSystem = a["system"]
        case "new":
            current?.isNew = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stack.last == name { stack.removeLast() }
        let parent = stack.last
        switch name {
        case "display-name":
            if let id = currentChannelID, !value.isEmpty {
                displayNames[id, default: []].append(Self.key(value))
                currentNames.append(value)
            }
        case "channel":
            if let id = currentChannelID, let wanted {
                // Keep this channel's programmes if any of its ids/names could match the playlist.
                let station = id.hasSuffix("gracenote.com") ? id.split(separator: ".").dropLast(2).last.map(String.init) : nil
                if wanted.ids.contains(id) || (station.map { wanted.ids.contains($0) } ?? false)
                    || wanted.names.contains(ChannelMatch.normalise(id))
                    || currentNames.contains(where: { wanted.names.contains(ChannelMatch.normalise($0)) }) {
                    keep?.insert(id)
                } else {
                    displayNames[id] = nil
                }
            }
            currentChannelID = nil
        case "title":
            if current != nil, current!.title.isEmpty {
                current!.title = value
                if value.range(of: "[NEW]", options: .caseInsensitive) != nil { current!.isNew = true }
            }
        case "sub-title":
            current?.subtitle = value
        case "desc":
            current?.desc = value
        case "category":
            if current?.category == nil { current?.category = value }
            if !value.isEmpty { current?.categories.append(value) }
        case "date":
            if current != nil, value.count >= 4, let y = Int(value.prefix(4)) { current?.year = y }
        case "length":
            if let n = Int(value) { current?.lengthMinutes = n }
        case "episode-num":
            parseEpisode(value, system: episodeSystem)
            episodeSystem = nil
        case "actor":
            if !value.isEmpty, (current?.actors.count ?? 9) < 8 { current?.actors.append(value) }
        case "director":
            if !value.isEmpty { current?.directors.append(value) }
        case "value":
            if parent == "rating" { current?.contentRating = value }
            else if parent == "star-rating" { current?.starRating = value }
        case "programme":
            if let p = current, !Self.placeholderTitles.contains(p.title.lowercased().trimmingCharacters(in: .whitespaces)) {
                programmes[p.channelKey, default: []].append(p)
                if (samples[p.channelKey]?.count ?? 0) < 1500 {
                    samples[p.channelKey, default: ""] += " " + p.title + ". " + (p.desc ?? "")
                }
            }
            current = nil
        default:
            break
        }
        text = ""
    }

    /// xmltv_ns "1.4.0/1" (zero-based season.episode), onscreen "S02E05" / "2x05", dd_progid "EP0123.0045".
    private func parseEpisode(_ v: String, system: String?) {
        switch system {
        case "xmltv_ns":
            let parts = v.split(separator: ".", omittingEmptySubsequences: false).map { $0.split(separator: "/").first.map(String.init) ?? "" }
            if parts.count > 0, let s = Int(parts[0].trimmingCharacters(in: .whitespaces)) { current?.season = s + 1 }
            if parts.count > 1, let e = Int(parts[1].trimmingCharacters(in: .whitespaces)) { current?.episode = e + 1 }
        case "dd_progid":
            current?.progID = v
        default:
            if let r = v.range(of: #"(?i)S(\d{1,3})\s*E(\d{1,4})"#, options: .regularExpression) {
                let nums = v[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if nums.count == 2 { current?.season = nums[0]; current?.episode = nums[1] }
            } else if let r = v.range(of: #"(\d{1,3})x(\d{1,4})"#, options: .regularExpression) {
                let nums = v[r].split(separator: "x").compactMap { Int($0) }
                if nums.count == 2 { current?.season = nums[0]; current?.episode = nums[1] }
            }
        }
    }

    /// Parses XMLTV timestamps like `20240101120000 +0100` (offset optional, defaults to UTC).
    static func date(_ s: String) -> Date? {
        let u = Array(s.utf8)
        guard u.count >= 12 else { return nil }
        func num(_ from: Int, _ len: Int) -> Int? {
            var v = 0
            for i in from..<(from + len) {
                guard i < u.count, u[i] >= 48, u[i] <= 57 else { return nil }
                v = v * 10 + Int(u[i] - 48)
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(4, 2), let d = num(6, 2), let h = num(8, 2), let mi = num(10, 2) else { return nil }
        let sec = num(12, 2) ?? 0
        var offset = 0
        if let signIdx = u.firstIndex(where: { $0 == 43 || $0 == 45 }), signIdx >= 12,
           let oh = num(signIdx + 1, 2), let om = num(signIdx + 3, 2) {
            offset = (oh * 3600 + om * 60) * (u[signIdx] == 45 ? -1 : 1)
        }
        // Days from civil (Howard Hinnant's algorithm), avoids slow Calendar calls.
        let yy = mo <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let mp = (mo + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146097 + doe - 719468
        let epoch = days * 86400 + h * 3600 + mi * 60 + sec - offset
        return Date(timeIntervalSince1970: TimeInterval(epoch))
    }
}
