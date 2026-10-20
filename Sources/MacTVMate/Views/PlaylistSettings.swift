import SwiftUI

/// Settings ▸ Playlists.
struct PlaylistsSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: PlaylistSource?
    @State private var isNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s(14)) {
            if model.library.sources.isEmpty {
                Text("Add an M3U playlist or Xtream Codes login to get started.").foregroundStyle(Theme.dim)
            }
            VStack(spacing: Theme.s(8)) {
                ForEach(model.library.sources) { s in
                    SourceRow(source: s, active: s.id == model.library.activeSource?.id) {
                        editing = s; isNew = false
                    }
                }
            }
            HStack {
                Button {
                    editing = PlaylistSource(name: "My playlist", kind: .xtream(server: "", username: "", password: ""))
                    isNew = true
                } label: { Label("Add playlist", systemImage: "plus") }
                Spacer()
                if let status = model.library.status {
                    ProgressView().controlSize(Theme.control(.small)); Text(status).foregroundStyle(Theme.dim)
                } else if let err = model.library.error {
                    Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(2)
                } else if !model.library.channels.isEmpty {
                    Text("\(model.library.channels.count) channels").foregroundStyle(Theme.dim)
                }
            }
        }
        .sheet(item: $editing) { s in
            SourceEditor(source: s, isNew: isNew) { saved in
                if let i = model.library.sources.firstIndex(where: { $0.id == saved.id }) {
                    model.library.sources[i] = saved
                } else {
                    model.library.sources.append(saved)
                }
                model.library.activeSourceID = saved.id
                Task { await model.reload(force: true) }
            }
        }
    }
}

struct SourceRow: View {
    @EnvironmentObject var model: AppModel
    let source: PlaylistSource
    let active: Bool
    let edit: () -> Void

    var body: some View {
        HStack(spacing: Theme.s(12)) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle").foregroundStyle(active ? Theme.accent : Theme.faint)
            VStack(alignment: .leading, spacing: Theme.s(2)) {
                Text(source.name).font(Theme.f(.headline))
                Text(summary).font(Theme.f(.caption)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer()
            Button { Task { await model.reload(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh playlist and EPG").disabled(!active)
            Button("Edit", action: edit)
            Button(role: .destructive) { model.library.remove(source); Task { await model.reload() } } label: { Image(systemName: "trash") }
        }
        .buttonStyle(.borderless)
        .padding(Theme.s(12))
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !active else { return }
            model.library.activeSourceID = source.id
            Task { await model.reload() }
        }
    }

    private var summary: String {
        switch source.kind {
        case .m3u(let url, _): return "M3U · \(url)"
        case .xtream(let server, let user, _): return "Xtream · \(user) @ \(server)"
        }
    }
}

struct SourceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var source: PlaylistSource
    let isNew: Bool
    let onSave: (PlaylistSource) -> Void

    @State private var type = 0
    @State private var playlistURL = ""
    @State private var epgURL = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s(16)) {
            Text(isNew ? "Add playlist" : "Edit playlist").font(Theme.f(.title2).weight(.semibold))
            Picker("", selection: $type) {
                Text("M3U playlist").tag(0)
                Text("Xtream Codes").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Form {
                TextField("Name", text: $source.name)
                if type == 0 {
                    HStack {
                        TextField("Playlist URL or file", text: $playlistURL)
                        Button("Choose…") { pickFile { playlistURL = $0 } }
                    }
                    HStack {
                        TextField("EPG (XMLTV) URL — optional", text: $epgURL)
                        Button("Choose…") { pickFile { epgURL = $0 } }
                    }
                } else {
                    TextField("Server (http://host:port)", text: $server)
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    Toggle("Use HLS (.m3u8) instead of MPEG-TS", isOn: $source.preferHLS)
                }
                TextField("User-Agent — optional", text: $source.userAgent)
                Stepper("Refresh every \(source.refreshHours) h", value: $source.refreshHours, in: 1...72)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    source.kind = type == 0
                        ? .m3u(playlistURL: playlistURL.trimmingCharacters(in: .whitespaces), epgURL: epgURL.trimmingCharacters(in: .whitespaces))
                        : .xtream(server: server.trimmingCharacters(in: .whitespaces), username: username, password: password)
                    onSave(source)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(type == 0 ? playlistURL.isEmpty : (server.isEmpty || username.isEmpty))
            }
        }
        .padding(Theme.s(24))
        .frame(width: Theme.s(560))
        .onAppear {
            switch source.kind {
            case let .m3u(p, e): type = 0; playlistURL = p; epgURL = e
            case let .xtream(s, u, p): type = 1; server = s; username = u; password = p
            }
        }
    }

    private func pickFile(_ done: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { done(url.path) }
    }
}

struct ShortcutsHelp: View {
    private let rows: [(String, String)] = [
        ("↑ / ↓", "Change channel (player) · move row (guide)"),
        ("← / →", "Channel list / info (live) · seek 30s (catch-up) · move programme (guide)"),
        ("Return", "Channel list (player) · play / catch-up (guide)"),
        ("G", "TV guide"),
        ("0–9", "Jump to channel number"),
        ("Backspace / L", "Previous channel"),
        ("I", "Info bar"),
        ("Space", "Pause"),
        ("R", "Record current stream to ~/Movies/MacTVMate"),
        ("F  ·  ⌘↩", "Full screen (player) · favourite (guide / list) · ⌘↩ full screen anywhere"),
        ("/  ·  ⌘F", "Search channels and programmes"),
        ("M  ·  + / −", "Mute · volume"),
        ("Esc", "Back"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s(6)) {
            Text("Keyboard").font(Theme.f(.headline))
            ForEach(rows, id: \.0) { k, v in
                HStack(alignment: .top) {
                    Text(k).font(Theme.f(.callout).monospaced()).frame(width: Theme.s(130), alignment: .leading)
                    Text(v).font(Theme.f(.callout)).foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

/// Settings ▸ Groups: show/hide whole channel groups (TiViMate's "Hide groups"). Hidden groups drop out of
/// All channels, the group column, search and channel up/down; channel numbers still work.
struct GroupManager: View {
    @EnvironmentObject var model: AppModel
    @State private var filter = ""

    var body: some View {
        let groups = model.library.allGroups
        let hidden = groups.filter { model.library.isHidden($0.name) }.count
        VStack(alignment: .leading, spacing: Theme.s(10)) {
            Toggle("Hide adult groups (XXX, Adult, 18+)", isOn: $model.settings.hideAdultGroups)
            HStack {
                Text("\(groups.count - hidden) shown · \(hidden) hidden").foregroundStyle(Theme.dim)
                Spacer()
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: Theme.s(160))
                Button("Show all") { groups.forEach { model.library.setHidden($0.name, false) } }
            }
            VStack(alignment: .leading, spacing: Theme.s(2)) {
                ForEach(groups.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }) { g in
                    let adult = model.library.isHiddenByAdultFilter(g.name)
                    Toggle(isOn: Binding(get: { !model.library.isHidden(g.name) },
                                         set: { model.library.setHidden(g.name, !$0) })) {
                        HStack {
                            Text(g.name)
                            if adult { Text("hidden by adult filter").font(Theme.f(.caption)).foregroundStyle(Theme.faint) }
                            Spacer()
                            Text("\(g.count)").foregroundStyle(Theme.faint).font(Theme.f(.caption))
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(adult)
                    .padding(.vertical, Theme.s(3))
                }
            }
        }
    }
}
