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
        .frame(width: size * 1.4, height: size)
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
        .frame(height: 3)
    }
}

struct Badge: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.white)
    }
}
