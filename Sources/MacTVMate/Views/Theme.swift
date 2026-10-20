import SwiftUI

enum Theme {
    // TiViMate's default (blue) palette: neutrals #131313/#202020, accent #2196f3 with dark tints #142b3d/#1f415c.
    static let bg = Color(hex: 0x131313)
    static let panel = Color(hex: 0x1a1a1a)
    static let cell = Color(hex: 0x202020)
    static let cellLive = Color(hex: 0x142b3d)
    static let focus = Color.white
    static let focusText = Color.black
    static let text = Color.white
    static let dim = Color.white.opacity(0.6)
    static let faint = Color.white.opacity(0.35)
    /// Set from Appearance settings.
    static var accent = Color(hex: 0x2196f3)

    /// Interface scale: 1 on a monitor; larger on a TV across the room (Settings ▸ Appearance ▸ Interface size).
    static var uiScale: CGFloat = 1

    /// A scaled size (layout widths, paddings, spacing).
    static func s(_ v: CGFloat) -> CGFloat { (v * uiScale).rounded() }

    /// Native controls (buttons, pickers, toggles) don't follow font sizes, so step their size up with the scale.
    static func control(_ base: ControlSize) -> ControlSize {
        let sizes: [ControlSize] = [.mini, .small, .regular, .large, .extraLarge]
        let steps = uiScale >= 1.4 ? 2 : uiScale >= 1.15 ? 1 : 0
        let i = sizes.firstIndex(of: base) ?? 2
        return sizes[min(sizes.count - 1, i + steps)]
    }

    /// macOS text styles at the current interface scale.
    static func f(_ style: Font.TextStyle) -> Font {
        let (size, weight): (CGFloat, Font.Weight) = {
            switch style {
            case .largeTitle: return (26, .regular)
            case .title: return (22, .regular)
            case .title2: return (17, .regular)
            case .title3: return (15, .regular)
            case .headline: return (13, .bold)
            case .subheadline: return (11, .regular)
            case .body: return (13, .regular)
            case .callout: return (12, .regular)
            case .footnote: return (10, .regular)
            case .caption: return (10, .regular)
            case .caption2: return (10, .regular)
            @unknown default: return (13, .regular)
            }
        }()
        return .system(size: size * uiScale, weight: weight)
    }
    static let live = Color(red: 0.93, green: 0.26, blue: 0.24)

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()

    /// "Today", "Tomorrow", "Yesterday" or "Mon, Oct 19" (TiViMate's day labels), optionally with the time.
    static func dayLabel(_ d: Date, withTime: Bool = false) -> String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(d) { day = "Today" }
        else if cal.isDateInTomorrow(d) { day = "Tomorrow" }
        else if cal.isDateInYesterday(d) { day = "Yesterday" }
        else { day = Theme.day.string(from: d) }
        return withTime ? "\(day) \(time.string(from: d))" : day
    }

    static func range(_ p: Programme) -> String {
        "\(time.string(from: p.start)) – \(time.string(from: p.stop))"
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

struct ChannelLogo: View {
    let url: URL?
    var size: CGFloat = 36

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "tv").foregroundStyle(Theme.faint)
            }
        }
        .frame(width: Theme.s(size * 1.4), height: Theme.s(size))
    }
}

struct ProgressLine: View {
    let value: Double
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(color).frame(width: g.size.width * value)
            }
        }
        .frame(height: Theme.s(3))
    }
}

struct Badge: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.system(size: Theme.uiScale * 10, weight: .bold))
            .padding(.horizontal, Theme.s(5)).padding(.vertical, Theme.s(2))
            .background(color.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.white)
    }
}
