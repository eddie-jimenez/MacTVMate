import AppKit
import SwiftUI

/// TiViMate-style settings: a panel that slides over the right side of whatever is on screen.
struct SettingsPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { if !model.library.sources.isEmpty { model.showSettings = false } }

            HStack(spacing: 0) {
                // Sections
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings").font(.title.weight(.semibold)).padding(.bottom, 14).padding(.leading, 10)
                    ForEach(SettingsSection.allCases) { s in
                        Button { model.settingsSection = s } label: {
                            Label(s.rawValue, systemImage: s.icon)
                                .padding(.vertical, 8).padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(model.settingsSection == s ? Theme.focus : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(model.settingsSection == s ? Theme.focusText : Theme.text)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(20)
                .frame(width: 220)
                .background(Theme.accent.opacity(0.18))

                // Content
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(model.settingsSection.rawValue).font(.title2.weight(.semibold))
                        Spacer()
                        if !model.library.sources.isEmpty {
                            Button { model.showSettings = false } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                                .buttonStyle(.borderless).foregroundStyle(Theme.dim).help("Close (Esc)")
                        }
                    }
                    .padding(.bottom, 16)
                    ScrollView {
                        section.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 30)
                    }
                }
                .padding(24)
                .frame(width: 560)
                .background(Theme.bg)
            }
            .frame(maxHeight: .infinity)
            .shadow(radius: 30)
            .transition(.move(edge: .trailing))
        }
    }

    @ViewBuilder private var section: some View {
        switch model.settingsSection {
        case .general: GeneralSettings()
        case .playlists: PlaylistsSettings()
        case .epg: EPGSettings()
        case .groups: GroupManager()
        case .appearance: AppearanceSettings()
        case .playback: PlaybackSettings()
        case .keyboard: RemoteSettings()
        case .about: AboutSettings()
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Theme.faint)
            content
        }
        .padding(.bottom, 22)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        SettingsGroup(title: "Startup") {
            Toggle("Play the last channel on start", isOn: $model.settings.startOnLastChannel)
        }
        SettingsGroup(title: "TV guide") {
            Toggle("Preview the focused channel", isOn: $model.settings.previewOnFocus)
        }
        SettingsGroup(title: "Content") {
            Toggle("Hide adult groups (XXX, Adult, 18+)", isOn: $model.settings.hideAdultGroups)
        }
        SettingsGroup(title: "Data") {
            HStack {
                Button("Update playlist & guide now") { Task { await model.reload(force: true) } }
                Button("Show data folder") {
                    NSWorkspace.shared.open(Persistence().dir)
                }
            }
            Text("Playlists, favourites and settings are stored in ~/Library/Application Support/MacTVMate (readable by your user only).")
                .font(.caption).foregroundStyle(Theme.dim)
        }
    }
}

struct EPGSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var newURL = ""

    var body: some View {
        let lib = model.library
        SettingsGroup(title: "Status") {
            if let at = lib.epgLoadedAt {
                Text("Updated \(at.formatted(date: .abbreviated, time: .shortened)) · \(lib.epgMatchedCount) of \(lib.channels.count) channels have listings")
                    .foregroundStyle(Theme.dim)
            }
            ForEach(lib.guideSources) { s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: s.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(s.ok ? .green : .orange)
                    Text(s.name).fontWeight(.medium)
                    Text(s.note).font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
                }
            }
            Button("Update guide now") { Task { await model.reload(force: true) } }
        }
        SettingsGroup(title: "Extra guide sources (XMLTV)") {
            Text("Added to your playlist's own guide. Channels are matched by tvg-id or by name, so a public guide can fill in channels your provider leaves empty.")
                .font(.callout).foregroundStyle(Theme.dim)
            ForEach(lib.settings.extraEPGURLs, id: \.self) { url in
                HStack {
                    Text(url).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(role: .destructive) { model.library.settings.extraEPGURLs.removeAll { $0 == url } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("https://… .xml or .xml.gz", text: $newURL).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let u = newURL.trimmingCharacters(in: .whitespaces)
                    guard !u.isEmpty, !model.library.settings.extraEPGURLs.contains(u) else { return }
                    model.library.settings.extraEPGURLs.append(u)
                    newURL = ""
                    Task { await model.reload(force: false) }
                }
                .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        SettingsGroup(title: "Listings") {
            Toggle("Show events from channel names (e.g. “NFL 01: Commanders @ 49ers 8:15 PM”)", isOn: $model.settings.eventsFromChannelNames)
            Stepper("Keep \(lib.settings.pastEPGDays) past day\(lib.settings.pastEPGDays == 1 ? "" : "s")", value: $model.settings.pastEPGDays, in: 1...30)
            Stepper("Guide time offset: \(lib.settings.epgOffsetMinutes >= 0 ? "+" : "")\(lib.settings.epgOffsetMinutes) min",
                    value: $model.settings.epgOffsetMinutes, in: -720...720, step: 15)
        }
    }
}

struct AppearanceSettings: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        SettingsGroup(title: "Accent colour") {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10), count: 8), alignment: .leading, spacing: 10) {
                ForEach(AppSettings.accents, id: \.0) { name, hex in
                    Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                        .overlay(Circle().stroke(.white, lineWidth: model.library.settings.accent == name ? 3 : 0))
                        .onTapGesture { model.library.settings.accent = name }
                        .help(name)
                }
            }
        }
        SettingsGroup(title: "TV guide") {
            Picker("Size", selection: $model.settings.guideSize) {
                ForEach(0..<4) { Text(AppSettings.sizeNames[$0]).tag($0) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 380)
            Toggle("Show group column", isOn: $model.settings.showGroupColumn)
            Toggle("Show channel numbers", isOn: $model.settings.showChannelNumbers)
            Toggle("Dim past programmes", isOn: $model.settings.dimPastProgrammes)
        }
    }
}

struct PlaybackSettings: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        SettingsGroup(title: "Buffer size") {
            Picker("", selection: $model.settings.bufferSize) {
                ForEach(0..<4) { Text(AppSettings.bufferNames[$0]).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
            Text("Larger buffers ride out unstable streams but take longer to recover after a stall.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
        SettingsGroup(title: "Decoding") {
            Toggle("Hardware decoding (VideoToolbox)", isOn: $model.settings.hardwareDecoding)
        }
        SettingsGroup(title: "Preferred languages") {
            TextField("Audio (e.g. eng,spa)", text: $model.settings.preferredAudioLanguage).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
            TextField("Subtitles (e.g. eng)", text: $model.settings.preferredSubtitleLanguage).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
        }
    }
}

struct AboutSettings: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        SettingsGroup(title: "Metadata sources") {
            switch model.meta.imdbState {
            case .missing: Text("IMDb data: not downloaded yet").foregroundStyle(Theme.dim)
            case .building(let s): HStack { ProgressView().controlSize(.small); Text("IMDb data: \(s)") }
            case .ready(let d): Text("IMDb data: ready (built \(d.formatted(date: .abbreviated, time: .shortened)), refreshed weekly)").foregroundStyle(Theme.dim)
            case .failed(let e): Label("IMDb data: \(e)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Text("Ratings from IMDb's official datasets (personal, non-commercial use). Show art from TVmaze. Live scores from ESPN. Guide data from your provider, EPGtalk (Gracenote) and iptv.cat.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
        SettingsGroup(title: "MacTVMate") {
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
            Text("A personal macOS IPTV player modelled on TiViMate. Playback by libmpv/FFmpeg.")
                .foregroundStyle(Theme.dim)
        }
    }
}

/// Settings ▸ Remote & keyboard: pairing help, live button tester, mapping.
struct RemoteSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsGroup(title: "TV guide navigation") {
            Toggle("↑ / ↓ change channel number (↓ = 44 → 43, like a TV remote)", isOn: $model.settings.guideArrowsFollowChannelNumbers)
            Text("Off: ↑ / ↓ move up and down the grid on screen instead.").font(.caption).foregroundStyle(Theme.dim)
        }
        SettingsGroup(title: "iPhone / iPad remote") {
            Toggle("Allow remote control from devices on this Wi-Fi", isOn: $model.settings.webRemoteEnabled)
                .onChange(of: model.settings.webRemoteEnabled) { _, on in on ? model.webRemote.start() : model.webRemote.stop() }
            if model.settings.webRemoteEnabled, let url = model.webRemote.url {
                HStack(alignment: .top, spacing: 18) {
                    QRCode(text: url.absoluteString).frame(width: 150, height: 150)
                        .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scan with the iPhone camera, then tap Share ▸ Add to Home Screen for an app-like remote.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text(url.absoluteString).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(Theme.dim)
                        if let ip = model.webRemote.ipURL {
                            Text("If that doesn't open: \(ip.absoluteString)").font(.caption.monospaced()).textSelection(.enabled)
                                .foregroundStyle(Theme.faint)
                        }
                        Text(model.webRemote.status + (model.webRemote.clients > 0 ? " · \(model.webRemote.clients) connected" : ""))
                            .font(.caption).foregroundStyle(Theme.dim)
                        Button("New link (disconnects old devices)") { model.settings.remoteToken = AppSettings.newToken() }
                            .controlSize(.small)
                    }
                }
            }
        }
        SettingsGroup(title: "NVIDIA Shield remote") {
            Text("Pair it with this Mac: hold Back + Home for about 5 seconds until the light blinks, then select it in System Settings ▸ Bluetooth.")
                .font(.callout).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            Label(model.remote.hidStatus, systemImage: model.remote.hidStatus.hasPrefix("Listening") ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle")
                .foregroundStyle(model.remote.hidStatus.hasPrefix("Listening") ? Theme.dim : .orange)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.remote.devices.isEmpty ? "No remote-type devices connected." : "Connected: " + model.remote.devices.joined(separator: ", "))
                .font(.caption).foregroundStyle(Theme.faint)
        }
        SettingsGroup(title: "Button tester") {
            HStack {
                Text("Press buttons on the remote — each one shows up here.").font(.callout).foregroundStyle(Theme.dim)
                Spacer()
                Button("Clear") { model.remote.clearLog() }
            }
            VStack(alignment: .leading, spacing: 4) {
                if model.remote.log.isEmpty { Text("Waiting for input…").foregroundStyle(Theme.faint) }
                ForEach(model.remote.log) { i in
                    HStack {
                        Text(i.time.formatted(date: .omitted, time: .standard)).font(.caption.monospacedDigit()).foregroundStyle(Theme.faint)
                        Text(i.source).font(.caption).foregroundStyle(Theme.dim)
                        Text(i.detail).font(.callout.monospaced())
                        Spacer()
                        Text(i.action ?? "—").font(.caption.weight(.semibold)).foregroundStyle(i.action == nil ? Theme.faint : Theme.accent)
                    }
                }
            }
            .padding(10)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        }
        SettingsGroup(title: "Shield remote buttons") {
            ForEach([("D-pad", "Move around the guide, lists and menus"), ("OK", "Select / open channel list while watching"),
                     ("Back", "Back (closes panels, leaves full screen, returns to the guide)"), ("Home", "TV guide"),
                     ("Menu  ≡", "Channel list while watching, otherwise Settings"), ("Play/Pause", "Pause / resume"),
                     ("⏩ / ⏪", "Seek 30 s in movies & catch-up; channel up/down on live TV"),
                     ("Volume", "Mac volume")], id: \.0) { k, v in
                HStack(alignment: .top) {
                    Text(k).font(.callout.weight(.semibold)).frame(width: 110, alignment: .leading)
                    Text(v).font(.callout).foregroundStyle(Theme.dim)
                }
            }
        }
        ShortcutsHelp()
            .onAppear { model.remote.testing = true }
            .onDisappear { model.remote.testing = false }
    }
}

/// QR code image (CoreImage).
struct QRCode: View {
    let text: String
    var body: some View {
        if let img = Self.make(text) {
            Image(nsImage: img).interpolation(.none).resizable().aspectRatio(1, contentMode: .fit)
        }
    }
    static func make(_ text: String) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
