import AppKit

/// Arrow / OK / Back / Menu navigation for every screen. Keyboard, the Shield remote and the iPhone remote all come
/// through `nav(_:)`, so they behave the same.
extension AppModel {
    /// Rail order: Search, TV, Movies, Shows, Recordings, My list, Settings.
    static let railCount = 7

    var railIndexForScreen: Int {
        switch screen {
        case .guide, .player: return 1
        case .movies: return 2
        case .shows: return 3
        case .recordings: return 4
        case .myList: return 5
        }
    }

    @discardableResult
    func nav(_ k: NavKey) -> Bool {
        if actionMenu != nil { menuNav(k); return true }
        if showSearch {
            if k == .back { showSearch = false; return true }
            return false
        }
        if showSettings { return settingsNav(k) }
        if sheetForm.engaged { return sheetNav(k) }
        if zone == .rail, screen != .player { return railNav(k) }
        switch screen {
        case .guide: return guideNav(k)
        case .player: return playerNav(k)
        case .movies, .shows:
            if let handled = browserKeys?(k), handled { return true }
            if k == .back { showGuide(); return true }
            if k == .left { enterRail(); return true }
            return false
        case .recordings, .myList: return screenNav(k)
        }
    }

    // MARK: Zones

    func enterRail() {
        railIndex = railIndexForScreen
        zone = .rail
        screenForm.engaged = false
    }

    func leaveRail() {
        zone = .main
        if screen == .recordings || screen == .myList { screenForm.engage() }
    }

    private func railNav(_ k: NavKey) -> Bool {
        switch k {
        case .up: railIndex = max(0, railIndex - 1)
        case .down: railIndex = min(Self.railCount - 1, railIndex + 1)
        case .select, .right: activateRail(railIndex)
        case .back: leaveRail()
        default: break
        }
        return true
    }

    func activateRail(_ i: Int) {
        zone = .main
        switch i {
        case 0: openSearch()
        case 6: showSettings = true
        default:
            showSettings = false
            let target: Screen = [1: .guide, 2: .movies, 3: .shows, 4: .recordings, 5: .myList][i] ?? .guide
            if target == .guide { if screen != .guide { showGuide() } } else { screen = target }
        }
    }

    // MARK: Options menu

    private func menuNav(_ k: NavKey) {
        guard var m = actionMenu else { return }
        switch k {
        case .up: m.index = max(0, m.index - 1); actionMenu = m
        case .down: m.index = min(m.actions.count - 1, m.index + 1); actionMenu = m
        case .select:
            actionMenu = nil
            if m.actions.indices.contains(m.index) { m.actions[m.index].run() }
        case .back, .menu, .hold, .left: actionMenu = nil
        default: break
        }
    }

    func showOptions(_ title: String, subtitle: String? = nil, _ actions: [MenuAction]) {
        guard !actions.isEmpty else { return }
        actionMenu = ActionMenu(title: title, subtitle: subtitle, actions: actions)
    }

    /// Watch · catch-up · favourite · record · remind, for a channel and (optionally) a programme.
    func channelOptions(_ ch: Channel, _ p: Programme?) -> [MenuAction] {
        var a: [MenuAction] = []
        let live = p.map { $0.isLive(at: now) } ?? true
        if live {
            a.append(MenuAction(title: "Watch", icon: "play.fill") { [weak self] in self?.play(ch) })
        }
        if let p, ch.hasCatchup, p.stop <= now || live {
            a.append(MenuAction(title: live ? "Watch from start" : "Watch (catch-up)", icon: "gobackward") { [weak self] in
                self?.playCatchup(ch, p)
            })
        }
        let fav = library.isFavourite(ch)
        a.append(MenuAction(title: fav ? "Remove from favourites" : "Add to favourites", icon: fav ? "star.slash" : "star") { [weak self] in
            self?.library.toggleFavourite(ch)
        })
        if let p, p.stop > now {
            if let r = recorder.recording(for: ch, p), r.status == .scheduled || r.status == .recording {
                a.append(MenuAction(title: r.status == .recording ? "Stop recording" : "Cancel recording", icon: "stop.circle", role: .destructive) { [weak self] in
                    self?.recorder.cancel(r)
                })
            } else {
                a.append(MenuAction(title: live ? "Record" : "Record when it starts", icon: "record.circle") { [weak self] in self?.record(ch, p) })
            }
        } else if p == nil {
            a.append(MenuAction(title: "Record 1 hour", icon: "record.circle") { [weak self] in self?.record(ch, nil) })
        }
        if let p, p.start > now {
            if recorder.hasReminder(ch, p) {
                a.append(MenuAction(title: "Cancel reminder", icon: "bell.slash") { [weak self] in self?.recorder.removeReminder(ch, p) })
            } else {
                a.append(MenuAction(title: "Remind me", icon: "bell") { [weak self] in self?.recorder.remind(ch, p) })
            }
        }
        return a
    }

    /// R in the guide: record the focused programme, or cancel it if it's already set.
    func toggleRecord(_ ch: Channel, _ p: Programme?) {
        if let p, let r = recorder.recording(for: ch, p), r.status == .scheduled || r.status == .recording {
            recorder.cancel(r)
        } else if p.map({ $0.stop > now }) ?? true {
            record(ch, p)
        }
    }

    // MARK: Guide

    private var groupColumnVisible: Bool { library.settings.showGroupColumn }

    private func guideNav(_ k: NavKey) -> Bool {
        if zone == .side {
            let groups = library.groups
            let i = groups.firstIndex { $0.name == selectedGroup } ?? 0
            switch k {
            case .up, .down:
                let j = min(groups.count - 1, max(0, i + (k == .down ? 1 : -1)))
                if groups.indices.contains(j), j != i { selectedGroup = groups[j].name; guideRow = 0 }
            case .select, .right, .back: zone = .main
            case .left: enterRail()
            default: break
            }
            return true
        }
        let flip = library.settings.guideArrowsChangeChannelNumber
        switch k {
        case .up: guideMove(rows: flip ? 1 : -1)
        case .down: guideMove(rows: flip ? -1 : 1)
        case .left:
            if guideAtLeftEdge { if groupColumnVisible { zone = .side } else { enterRail() } }
            else { guideMove(programmes: -1) }
        case .right: guideMove(programmes: 1)
        case .select: guideActivate()
        case .hold, .menu:
            guard let ch = guideSelectedChannel else { return true }
            let p = guideSelectedProgramme
            showOptions(p?.displayTitle ?? ch.name, subtitle: p.map { "\(ch.name) · \(Theme.range($0))" } ?? ch.name,
                        channelOptions(ch, p))
        case .favourite: if let ch = guideSelectedChannel { library.toggleFavourite(ch) }
        case .record: if let ch = guideSelectedChannel { toggleRecord(ch, guideSelectedProgramme) }
        case .back: if playing != nil { screen = .player; flashInfoBar() }
        }
        return true
    }

    /// ← on the current programme (nothing earlier to move to) leaves the grid for the groups / rail.
    private var guideAtLeftEdge: Bool {
        guard let ch = guideSelectedChannel else { return true }
        let p = guideSelectedProgramme
        if let p, p.start > now { return false }
        if p == nil { return guideTime <= now.addingTimeInterval(60) }
        guard ch.hasCatchup, let p else { return true }
        let list = library.programmes(for: ch)
        return (list.firstIndex(of: p) ?? 0) == 0
    }

    // MARK: Player

    private func playerNav(_ k: NavKey) -> Bool {
        if showControls { return controlsNav(k) }
        if showChannelList { return listNav(k) }
        let seekable = playing?.isSeekable ?? false
        switch k {
        case .up: if seekable { showControlsBar() } else { zap(1) }
        case .down: if seekable { showControlsBar() } else { zap(-1) }
        case .left: if seekable { player.seek(relative: -30); flashInfoBar() } else { openChannelList() }
        case .right: if seekable { player.seek(relative: 30); flashInfoBar() } else { flashInfoBar() }
        case .select: if seekable { showControlsBar() } else { openChannelList() }
        case .hold, .menu: showControlsBar()
        case .favourite: if let p = playing, p.isLive { library.toggleFavourite(p.channel); flashInfoBar() }
        case .record: toggleRecording()
        case .back:
            if showInfoBar { showInfoBar = false } else if isFullScreen { toggleFullScreen() } else { showGuide() }
        }
        return true
    }

    func showControlsBar() {
        showChannelList = false
        showControls = true
        showInfoBar = true
        controlsForm.engage(reset: true)
        // After the bar has registered its buttons: start on Play/Pause.
        DispatchQueue.main.async { [weak self] in
            self?.controlsForm.engage(reset: true)
            self?.controlsForm.focus(FocusSpot(row: 0, col: 1))
        }
        pokeControls()
    }

    func hideControls() {
        showControls = false
        controlsForm.engaged = false
        showInfoBar = false
        controlsTimer?.invalidate()
    }

    /// Keeps the controls up while they're being used; they fade after 8 s without input.
    func pokeControls() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideControls() }
        }
    }

    private func controlsNav(_ k: NavKey) -> Bool {
        pokeControls()
        switch k {
        case .left, .right: _ = controlsForm.move(k)
        case .select: controlsForm.activate()
        case .up, .down, .back, .menu, .hold: hideControls()
        case .favourite: if let p = playing, p.isLive { library.toggleFavourite(p.channel) }
        case .record: toggleRecording()
        }
        return true
    }

    private func listNav(_ k: NavKey) -> Bool {
        let codes: [NavKey: UInt16] = [.up: 126, .down: 125, .left: 123, .right: 124, .select: 36, .back: 53]
        if let c = codes[k] { return handleListKey(code: c) }
        let list = groupChannels
        guard !channelListFocusGroups, list.indices.contains(listSelection) else { return true }
        let ch = list[listSelection]
        switch k {
        case .favourite: library.toggleFavourite(ch)
        case .hold, .menu:
            let p = library.programme(for: ch, at: now)
            showOptions(ch.name, subtitle: p?.displayTitle, channelOptions(ch, p))
        case .record: toggleRecord(ch, library.programme(for: ch, at: now))
        default: break
        }
        return true
    }

    // MARK: Recordings / My list

    private func screenNav(_ k: NavKey) -> Bool {
        if !screenForm.engaged { screenForm.engage() }
        switch k {
        case .up, .down, .right: _ = screenForm.move(k)
        case .left: if !screenForm.move(.left) { enterRail() }
        case .select: screenForm.activate()
        case .hold, .menu:
            if let opts = screenForm.current?.options?(), !opts.isEmpty { showOptions("Options", opts) }
        case .back: showGuide()
        default: break
        }
        return true
    }

    // MARK: Sheets (movie / show details)

    private func sheetNav(_ k: NavKey) -> Bool {
        switch k {
        case .up, .down, .left, .right: _ = sheetForm.move(k)
        case .select: sheetForm.activate()
        case .back:
            // Release the sheet's focus right away; its close animation finishes after the next keys arrive.
            let close = sheetBack
            sheetForm.clear()
            sheetBack = nil
            close?()
        default: break
        }
        return true
    }

    // MARK: Settings

    private func settingsNav(_ k: NavKey) -> Bool {
        let sections = SettingsSection.allCases
        if settingsZone == .side {
            let i = sections.firstIndex(of: settingsSection) ?? 0
            switch k {
            case .up: settingsSection = sections[max(0, i - 1)]
            case .down: settingsSection = sections[min(sections.count - 1, i + 1)]
            case .select, .right:
                settingsZone = .main
                settingsForm.engage(reset: true)
            case .back, .left: if !library.sources.isEmpty { showSettings = false }
            default: break
            }
            return true
        }
        switch k {
        case .up, .down, .right: _ = settingsForm.move(k)
        case .left: if !settingsForm.move(.left) { settingsZone = .side; settingsForm.engaged = false }
        case .select: settingsForm.activate()
        case .back: settingsZone = .side; settingsForm.engaged = false
        default: break
        }
        return true
    }
}
