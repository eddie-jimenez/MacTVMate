import SwiftUI

/// User preferences (TiViMate's General / EPG / Appearance / Playback screens).
struct AppSettings: Codable, Equatable {
    // General
    var startOnLastChannel = true
    var previewOnFocus = true
    var hideAdultGroups = true

    // EPG
    /// Extra XMLTV sources merged with the playlist's own guide, matched to channels by id or name.
    var extraEPGURLs: [String] = AppSettings.defaultGuides
    static let defaultGuides = ["https://epgtalk.com/US_guide.xml.gz", "https://epg.iptv.cat/epg.xml"]
    /// Turn sports/event channel names ("NFL 01: Commanders @ 49ers | 8:15 PM") into guide entries.
    var eventsFromChannelNames = true
    var pastEPGDays = 1
    var epgOffsetMinutes = 0

    // Appearance
    var accent = "Blue"
    /// TiViMate font/row size: 0 Small, 1 Medium, 2 Large, 3 Very large.
    var guideSize = 1
    var showChannelNumbers = true
    var showGroupColumn = true
    var dimPastProgrammes = true

    // Playback
    /// TiViMate buffer sizes: 0 Small, 1 Medium, 2 Large, 3 Very large.
    var bufferSize = 1
    var hardwareDecoding = true
    var preferredAudioLanguage = ""
    var preferredSubtitleLanguage = ""

    // Remote
    var webRemoteEnabled = true
    /// Private key in the iPhone remote's link; without it the page and API refuse requests.
    var remoteToken = AppSettings.newToken()
    static func newToken() -> String {
        let chars = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return String((0..<12).map { _ in chars.randomElement()! })
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        startOnLastChannel = v(.startOnLastChannel, d.startOnLastChannel)
        previewOnFocus = v(.previewOnFocus, d.previewOnFocus)
        hideAdultGroups = v(.hideAdultGroups, d.hideAdultGroups)
        extraEPGURLs = v(.extraEPGURLs, d.extraEPGURLs)
        eventsFromChannelNames = v(.eventsFromChannelNames, d.eventsFromChannelNames)
        pastEPGDays = v(.pastEPGDays, d.pastEPGDays)
        epgOffsetMinutes = v(.epgOffsetMinutes, d.epgOffsetMinutes)
        accent = v(.accent, d.accent)
        guideSize = v(.guideSize, d.guideSize)
        showChannelNumbers = v(.showChannelNumbers, d.showChannelNumbers)
        showGroupColumn = v(.showGroupColumn, d.showGroupColumn)
        dimPastProgrammes = v(.dimPastProgrammes, d.dimPastProgrammes)
        bufferSize = v(.bufferSize, d.bufferSize)
        hardwareDecoding = v(.hardwareDecoding, d.hardwareDecoding)
        preferredAudioLanguage = v(.preferredAudioLanguage, d.preferredAudioLanguage)
        preferredSubtitleLanguage = v(.preferredSubtitleLanguage, d.preferredSubtitleLanguage)
        webRemoteEnabled = v(.webRemoteEnabled, d.webRemoteEnabled)
        remoteToken = v(.remoteToken, d.remoteToken)
    }

    static let bufferNames = ["Small", "Medium", "Large", "Very large"]
    /// Seconds of data before resuming after a stall (TiViMate's after-rebuffer thresholds).
    static let bufferResumeSeconds: [Double] = [4, 5, 7, 10]
    static let sizeNames = ["Small", "Medium", "Large", "Very large"]
    /// TiViMate row heights per size (dp at 960 wide).
    static let rowHeights: [CGFloat] = [34, 41, 50, 64]

    /// TiViMate's accent palette (M500 values).
    static let accents: [(String, UInt32)] = [
        ("Blue", 0x2196f3), ("Light blue", 0x03a9f4), ("Cyan", 0x00bcd4), ("Teal", 0x009688),
        ("Green", 0x4caf50), ("Lime", 0xcddc39), ("Amber", 0xffc107), ("Orange", 0xff9800),
        ("Deep orange", 0xff5722), ("Red", 0xf44336), ("Pink", 0xe91e63), ("Purple", 0x9c27b0),
        ("Deep purple", 0x673ab7), ("Indigo", 0x3f51b5), ("Grey", 0x9e9e9e),
    ]

    var accentColor: Color {
        Color(hex: Self.accents.first { $0.0 == accent }?.1 ?? 0x2196f3)
    }

    /// Group names that look adult (used by "Hide adult groups").
    static let adultGroupPattern = #"(?i)(^|\W)(xxx|adult|adults|18\+|porn|for adults)($|\W)"#
}
