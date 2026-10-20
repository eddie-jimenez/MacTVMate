import AppKit
import SwiftUI

/// TiViMate's Recordings: scheduled, in progress and finished recordings, plus reminders.
struct RecordingsScreen: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let recs = model.library.recordings
        let upcoming = recs.filter { $0.status == .scheduled || $0.status == .recording }.sorted { $0.start < $1.start }
        let finished = recs.filter { $0.status != .scheduled && $0.status != .recording }.sorted { $0.start > $1.start }
        let form = model.screenForm
        FocusScroller(form: form) { _ in ScrollView {
            VStack(alignment: .leading, spacing: Theme.s(24)) {
                HStack {
                    Text("Recordings").font(Theme.f(.largeTitle).weight(.semibold))
                    Spacer()
                    Button { NSWorkspace.shared.open(Recorder.folder) } label: { Label("Show in Finder", systemImage: "folder") }
                        .focusSpot(form, row: 0) { NSWorkspace.shared.open(Recorder.folder) }
                }
                Text("Pick a programme in the guide and choose Record. Recordings run while MacTVMate is open, use a second connection, and are saved as .ts files in ~/Movies/MacTVMate (2 min before / 5 min after padding).")
                    .font(Theme.f(.callout)).foregroundStyle(Theme.dim)

                section("Scheduled & recording", upcoming, empty: "Nothing scheduled.", firstRow: 1)
                section("Recorded", finished, empty: "No recordings yet.", firstRow: 1 + upcoming.count)

                if !model.library.reminders.isEmpty {
                    Text("Reminders").font(Theme.f(.title3).weight(.semibold))
                    let reminderRow = 1 + upcoming.count + finished.count
                    ForEach(Array(model.library.reminders.sorted { $0.start < $1.start }.enumerated()), id: \.element.id) { i, r in
                        HStack {
                            Image(systemName: "bell.fill").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading) {
                                Text(r.title).font(Theme.f(.headline))
                                Text("\(r.channelName) · \(r.start.formatted(date: .abbreviated, time: .shortened))").font(Theme.f(.caption)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Button(role: .destructive) { model.library.reminders.removeAll { $0.id == r.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                        .padding(Theme.s(10)).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                        .focusSpot(form, row: reminderRow + i, owner: r.id, options: {
                            [MenuAction(title: "Delete reminder", icon: "trash", role: .destructive) { [model] in
                                model.library.reminders.removeAll { $0.id == r.id } }]
                        }) { [model] in model.library.reminders.removeAll { $0.id == r.id } }
                    }
                }
            }
            .padding(Theme.s(28))
        } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .onAppear { DispatchQueue.main.async { model.screenForm.engage(reset: true) } }
    }

    @ViewBuilder private func section(_ title: String, _ items: [Recording], empty: String, firstRow: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.s(8)) {
            Text(title).font(Theme.f(.title3).weight(.semibold))
            if items.isEmpty { Text(empty).foregroundStyle(Theme.faint) }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, r in
                row(r).focusSpot(model.screenForm, row: firstRow + i, owner: r.id, options: { options(r) }) { activate(r) }
            }
        }
    }

    /// OK: play a finished recording; on a scheduled one, open its options.
    private func activate(_ r: Recording) {
        if r.status == .done, r.file != nil { play(r) } else { model.showOptions(r.title, subtitle: r.channelName, options(r)) }
    }

    private func play(_ r: Recording) {
        guard let f = r.file else { return }
        model.playVOD(title: r.title, url: URL(fileURLWithPath: f), poster: nil, key: "recording|\(r.id)", group: "Recordings")
    }

    private func options(_ r: Recording) -> [MenuAction] {
        var a: [MenuAction] = []
        if r.status == .done, let f = r.file {
            a.append(MenuAction(title: "Play", icon: "play.fill") { play(r) })
            a.append(MenuAction(title: "Show in Finder", icon: "folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)]) })
        }
        if r.status == .scheduled || r.status == .recording {
            a.append(MenuAction(title: r.status == .recording ? "Stop recording" : "Cancel recording", icon: "stop.circle", role: .destructive) { [model] in
                model.recorder.cancel(r)
            })
        } else {
            a.append(MenuAction(title: "Delete", icon: "trash", role: .destructive) { [model] in model.recorder.delete(r) })
        }
        return a
    }

    private func row(_ r: Recording) -> some View {
        HStack(spacing: Theme.s(12)) {
            statusIcon(r)
            VStack(alignment: .leading, spacing: Theme.s(3)) {
                Text(r.title).font(Theme.f(.headline)).lineLimit(1)
                Text("\(r.channelName) · \(r.start.formatted(date: .abbreviated, time: .shortened)) – \(r.stop.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.f(.caption)).foregroundStyle(Theme.dim)
                if let e = r.error { Text(e).font(Theme.f(.caption)).foregroundStyle(.orange).lineLimit(1) }
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
        .padding(Theme.s(10))
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
        return Image(systemName: icon).foregroundStyle(color).font(Theme.f(.title3)).frame(width: Theme.s(26))
    }
}

/// Pops up when a reminder is due.
struct ReminderBanner: View {
    @EnvironmentObject var model: AppModel
    let reminder: Reminder

    var body: some View {
        HStack(spacing: Theme.s(14)) {
            Image(systemName: "bell.badge.fill").font(Theme.f(.title2)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: Theme.s(2)) {
                Text("Starting \(reminder.start <= Date() ? "now" : "at " + Theme.time.string(from: reminder.start))").font(Theme.f(.caption)).foregroundStyle(Theme.dim)
                Text(reminder.title).font(Theme.f(.headline))
                Text(reminder.channelName).font(Theme.f(.caption)).foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 20)
            Button("Watch") {
                if let c = model.library.channels.first(where: { $0.id == reminder.channelID }) { model.play(c) }
                model.recorder.dismissReminder()
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
            Button("Dismiss") { model.recorder.dismissReminder() }
        }
        .padding(Theme.s(16))
        .frame(width: Theme.s(520))
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
    }
}
