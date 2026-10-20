import AppKit
import IOKit.hid
import MediaPlayer

/// Remote controls: NVIDIA Shield and other Bluetooth/HID remotes, media keys, AirPods and Control Center.
/// - D-pad / OK arrive as ordinary arrow/Return key events (handled by the app's key monitor).
/// - Back / Home / Menu arrive as HID "consumer control" usages that macOS ignores, so they're read here.
/// - Play/Pause, next/previous, skip go through MPRemoteCommandCenter (Now Playing).
@MainActor
final class RemoteControl: ObservableObject {
    enum Action: String { case back, home, menu, ok, up, down, left, right, playPause, play, pause,
                              channelUp, channelDown, seekForward, seekBackward }

    struct Input: Identifiable {
        let id = UUID()
        let time = Date()
        let source: String
        let detail: String
        let action: String?
    }

    @Published private(set) var log: [Input] = []
    @Published private(set) var devices: [String] = []
    @Published private(set) var hidStatus = "Starting…"
    /// While the tester is open, every input is logged.
    var testing = false
    var handler: ((Action) -> Void)?

    private var manager: IOHIDManager?

    init() {
        setUpNowPlaying()
        startHID()
    }

    // MARK: HID consumer control (Back / Home / Menu …)

    /// Consumer-page usages (0x0C) → actions. Media usages are left to macOS so they aren't handled twice.
    private static let consumerMap: [UInt32: Action] = [
        0x224: .back,        // AC Back
        0x223: .home,        // AC Home
        0x040: .menu,        // Menu
        0x041: .ok,          // Menu Pick
        0x042: .up, 0x043: .down, 0x044: .left, 0x045: .right,   // Menu Up/Down/Left/Right
        0x09C: .channelUp, 0x09D: .channelDown,                  // Channel Increment/Decrement
    ]
    private static let mediaUsages: Set<UInt32> = [0xCD, 0xB0, 0xB1, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xE2, 0xE9, 0xEA]

    private func startHID() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer, kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(m, matching as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(m, { ctx, _, _, value in
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let pressed = IOHIDValueGetIntegerValue(value) != 0
            let device = IOHIDElementGetDevice(element)
            let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "HID device"
            let me = Unmanaged<RemoteControl>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.hidInput(page: page, usage: usage, pressed: pressed, device: name) }
        }, ctx)
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, _ in
            let me = Unmanaged<RemoteControl>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.refreshDevices() }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, _ in
            let me = Unmanaged<RemoteControl>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.refreshDevices() }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
        if r == kIOReturnSuccess {
            hidStatus = "Listening for remote buttons"
        } else {
            hidStatus = "Remote buttons need permission: System Settings ▸ Privacy & Security ▸ Input Monitoring ▸ MacTVMate (error \(r))"
        }
        refreshDevices()
    }

    private func refreshDevices() {
        guard let m = manager, let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> else { devices = []; return }
        devices = set.compactMap { IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String }.sorted()
    }

    private func hidInput(page: UInt32, usage: UInt32, pressed: Bool, device: String) {
        guard pressed, page == UInt32(kHIDPage_Consumer), usage != 0 else { return }
        let action = Self.consumerMap[usage]
        let media = Self.mediaUsages.contains(usage)
        if testing || action == nil {
            record("Remote · \(device)", String(format: "consumer 0x%03X", usage), action?.rawValue ?? (media ? "media key (via Now Playing)" : nil))
        }
        if let action { handler?(action) }
    }

    func logKey(_ e: NSEvent, action: String?) {
        guard testing else { return }
        let name = Self.keyName(e)
        record("Key", "\(name) (code \(e.keyCode))", action)
    }

    private func record(_ source: String, _ detail: String, _ action: String?) {
        log.insert(Input(source: source, detail: detail, action: action), at: 0)
        if log.count > 14 { log.removeLast() }
    }

    func clearLog() { log = [] }

    static func keyName(_ e: NSEvent) -> String {
        switch e.keyCode {
        case 123: return "←"; case 124: return "→"; case 125: return "↓"; case 126: return "↑"
        case 36: return "Return"; case 76: return "Enter"; case 53: return "Esc"; case 51: return "Backspace"
        case 49: return "Space"; case 116: return "Page Up"; case 121: return "Page Down"; case 110: return "Menu key"
        default: return e.charactersIgnoringModifiers.map { "“\($0)”" } ?? "key"
        }
    }

    // MARK: Now Playing (media keys, AirPods, Control Center, Touch Bar)

    private func setUpNowPlaying() {
        let c = MPRemoteCommandCenter.shared()
        func on(_ cmd: MPRemoteCommand, _ a: Action) {
            cmd.isEnabled = true
            cmd.addTarget { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.testing == true { self?.record("Now Playing", "\(a.rawValue) command", a.rawValue) }
                    self?.handler?(a)
                }
                return .success
            }
        }
        on(c.togglePlayPauseCommand, .playPause)
        on(c.playCommand, .play)
        on(c.pauseCommand, .pause)
        on(c.nextTrackCommand, .channelUp)
        on(c.previousTrackCommand, .channelDown)
        c.skipForwardCommand.preferredIntervals = [30]
        c.skipBackwardCommand.preferredIntervals = [30]
        on(c.skipForwardCommand, .seekForward)
        on(c.skipBackwardCommand, .seekBackward)
    }

    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?

    /// Shows what's playing in Control Center / the menu bar Now Playing widget.
    func updateNowPlaying(title: String?, subtitle: String?, art: URL?, duration: Double, position: Double, paused: Bool, live: Bool) {
        let center = MPNowPlayingInfoCenter.default()
        guard let title else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle ?? "",
            MPNowPlayingInfoPropertyIsLiveStream: live,
            MPNowPlayingInfoPropertyPlaybackRate: paused ? 0.0 : 1.0,
        ]
        if !live, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        }
        if let artwork, artworkURL == art { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = paused ? .paused : .playing

        if let art, art != artworkURL {
            artworkURL = art
            artwork = nil
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: art), let image = NSImage(data: data) else { return }
                let a = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                if self.artworkURL == art {
                    self.artwork = a
                    var i = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    i[MPMediaItemPropertyArtwork] = a
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = i
                }
            }
        }
    }
}
