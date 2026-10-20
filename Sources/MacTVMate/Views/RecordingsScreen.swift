import AppKit
import SwiftUI

/// TiViMate's Recordings: scheduled, in progress and finished recordings, plus reminders.
struct RecordingsScreen: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let recs = model.library.recordings
        let upcoming = recs.filter { $0.status == .scheduled || $0.status == .recording }.sorted { $0.start < $1.start }
        let finished = recs.filter { $0.status != .scheduled && $0.status != .recording }.sorted { $0.start > $1.start }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Recordings").font(.largeTitle.weight(.semibold))
                    Spacer()
                    Button { NSWorkspace.shared.open(Recorder.folder) } label: { Label("Show in Finder", systemImage: "folder") }
                }
                Text("Pick a programme in the guide and choose Record. Recordings run while MacTVMate is open, use a second connection, and are saved as .ts files in ~/Movies/MacTVMate (2 min before / 5 min after padding).")
                    .font(.callout).foregroundStyle(Theme.dim)

                section("Scheduled & recording", upcoming, empty: "Nothing scheduled.")
                section("Recorded", finished, empty: "No recordings yet.")

                if !model.library.reminders.isEmpty {
                    Text("Reminders").font(.title3.weight(.semibold))
                    ForEach(model.library.reminders.sorted { $0.start < $1.start }) { r in
                        HStack {
                            Image(systemName: "bell.fill").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading) {
                                Text(r.title).font(.headline)
                                Text("\(r.channelName) · \(r.start.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Button(role: .destructive) { model.library.reminders.removeAll { $0.id == r.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                        .padding(10).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    @ViewBuilder private func section(_ title: String, _ items: [Recording], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            if items.isEmpty { Text(empty).foregroundStyle(Theme.faint) }
            ForEach(items) { r in row(r) }
        }
    }

    private func row(_ r: Recording) -> some View {
        HStack(spacing: 12) {
            statusIcon(r)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.title).font(.headline).lineLimit(1)
                Text("\(r.channelName) · \(r.start.formatted(date: .abbreviated, time: .shortened)) – \(r.stop.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(Theme.dim)
                if let e = r.error { Text(e).font(.caption).foregroundStyle(.orange).lineLimit(1) }
            }
            Spacer()
            if r.status == .done, let f = r.file {
                Button { model.playVOD(title: r.title, url: URL(fileURLWithPath: f), poster: nil, key: "recording|\(r.id)", group: "Recordings") } label: {
                    Label("Play", systemImage: "play.fill")
                }
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)]) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless)
            }
            if r.status == .scheduled || r.status == .recording {
                Button(r.status == .recording ? "Stop" : "Cancel") { model.recorder.cancel(r) }
            }
            Button(role: .destructive) { model.recorder.delete(r) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help(r.file != nil ? "Delete (moves the file to the Trash)" : "Remove")
        }
        .padding(10)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func statusIcon(_ r: Recording) -> some View {
        let (icon, color): (String, Color) = {
            switch r.status {
            case .scheduled: return ("clock", Theme.accent)
            case .recording: return ("record.circle.fill", Theme.live)
            case .done: return ("checkmark.circle.fill", .green)
            case .failed: return ("exclamationmark.triangle.fill", .orange)
            case .cancelled: return ("xmark.circle", Theme.faint)
            }
        }()
        return Image(systemName: icon).foregroundStyle(color).font(.title3).frame(width: 26)
    }
}

/// Pops up when a reminder is due.
struct ReminderBanner: View {
    @EnvironmentObject var model: AppModel
    let reminder: Reminder

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.badge.fill").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Starting \(reminder.start <= Date() ? "now" : "at " + Theme.time.string(from: reminder.start))").font(.caption).foregroundStyle(Theme.dim)
                Text(reminder.title).font(.headline)
                Text(reminder.channelName).font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 20)
            Button("Watch") {
                if let c = model.library.channels.first(where: { $0.id == reminder.channelID }) { model.play(c) }
                model.recorder.dismissReminder()
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
            Button("Dismiss") { model.recorder.dismissReminder() }
        }
        .padding(16)
        .frame(width: 520)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
    }
}
