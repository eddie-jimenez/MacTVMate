import AppKit
import CMPV
import Combine

/// Owns the libmpv handle, exposes playback state to SwiftUI.
final class MPVController: ObservableObject {
    @Published private(set) var isPaused = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isIdle = true
    @Published private(set) var videoSize: CGSize = .zero
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRecording = false
    @Published var volume: Double = 100 { didSet { setDouble("volume", volume) } }
    @Published var isMuted = false { didSet { setFlag("mute", isMuted) } }
    @Published private(set) var audioTracks: [Track] = []
    @Published private(set) var subtitleTracks: [Track] = []
    /// Seconds into a seekable stream (catch-up), and its duration.
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0

    struct Track: Identifiable, Hashable {
        let id: Int
        let title: String
        let selected: Bool
    }

    let handle: OpaquePointer
    private let eventQueue = DispatchQueue(label: "mpv.events")
    fileprivate var renderContext: OpaquePointer?
    private var pending: Current?

    // Recovery, modelled on TiViMate 4.6.1: up to 5 retries (1 s apart from the 2nd), reset once playback runs;
    // restart a live stream that ends; restart after a 20 s buffering stall.
    private struct Current { let url: URL; let userAgent: String; let referrer: String?; let isLive: Bool; var startAt: Double? }
    private var current: Current?
    private var retries = 0
    private var stallWatchdog: DispatchWorkItem?
    static let maxRetries = 5
    static let stallTimeout: TimeInterval = 20

    init() {
        handle = mpv_create()
        // Rendering goes through the render API in MPVLayer.
        setOption("vo", "libmpv")
        setOption("hwdec", "auto-safe")
        setOption("keep-open", "no")
        setOption("idle", "yes")
        setOption("input-default-bindings", "no")
        setOption("osc", "no")
        setOption("cache", "yes")
        setOption("demuxer-max-bytes", "64MiB")
        // TiViMate buffers up to 60 s ahead; resumes after ~5 s once it has had to rebuffer ("Medium").
        setOption("demuxer-readahead-secs", "60")
        setOption("cache-secs", "60")
        setOption("cache-pause-wait", "5")
        setOption("network-timeout", "15")
        setOption("stream-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=5")
        setOption("terminal", "no")
        setOption("msg-level", "all=warn")
        mpv_initialize(handle)

        observe("pause", MPV_FORMAT_FLAG)
        observe("paused-for-cache", MPV_FORMAT_FLAG)
        observe("core-idle", MPV_FORMAT_FLAG)
        observe("idle-active", MPV_FORMAT_FLAG)
        observe("width", MPV_FORMAT_INT64)
        observe("height", MPV_FORMAT_INT64)
        observe("time-pos", MPV_FORMAT_DOUBLE)
        observe("duration", MPV_FORMAT_DOUBLE)
        observe("track-list/count", MPV_FORMAT_INT64)

        mpv_set_wakeup_callback(handle, { ctx in
            let me = Unmanaged<MPVController>.fromOpaque(ctx!).takeUnretainedValue()
            me.eventQueue.async { me.drainEvents() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        if let rc = renderContext { mpv_render_context_free(rc) }
        mpv_terminate_destroy(handle)
    }

    // MARK: Render context (created by MPVLayer once it has a GL context)

    func createRenderContext() {
        guard renderContext == nil else { return }
        let api = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var initParams = mpv_opengl_init_params()
        initParams.get_proc_address = { _, name in
            guard let name else { return nil }
            let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
            let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
            return CFBundleGetFunctionPointerForName(bundle, symbol)
        }
        var advanced: CInt = 1
        withUnsafeMutablePointer(to: &initParams) { ip in
            withUnsafeMutablePointer(to: &advanced) { adv in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(ip)),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: UnsafeMutableRawPointer(adv)),
                    mpv_render_param(),
                ]
                mpv_render_context_create(&renderContext, handle, &params)
            }
        }
        if let pending {
            self.pending = nil
            DispatchQueue.main.async {
                self.load(pending.url, userAgent: pending.userAgent, referrer: pending.referrer, isLive: pending.isLive, startAt: pending.startAt)
            }
        }
    }

    func setRenderUpdateCallback(_ cb: mpv_render_update_fn, context: UnsafeMutableRawPointer) {
        guard let rc = renderContext else { return }
        mpv_render_context_set_update_callback(rc, cb, context)
    }

    func render(fbo: Int32, width: Int32, height: Int32) {
        guard let rc = renderContext else { return }
        var data = mpv_opengl_fbo(fbo: fbo, w: width, h: height, internal_format: 0)
        var flip: CInt = 1
        withUnsafeMutablePointer(to: &data) { d in
            withUnsafeMutablePointer(to: &flip) { f in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(d)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(f)),
                    mpv_render_param(),
                ]
                mpv_render_context_render(rc, &params)
            }
        }
    }

    func reportSwap() {
        if let rc = renderContext { mpv_render_context_report_swap(rc) }
    }

    /// Must be called on the render thread: lets mpv do work requested via ADVANCED_CONTROL.
    func renderUpdate() -> UInt64 {
        guard let rc = renderContext else { return 0 }
        return mpv_render_context_update(rc)
    }

    // MARK: Playback

    func load(_ url: URL, userAgent: String = "", referrer: String? = nil, isLive: Bool = true, startAt: Double? = nil) {
        errorMessage = nil
        let next = Current(url: url, userAgent: userAgent, referrer: referrer, isLive: isLive, startAt: startAt)
        guard renderContext != nil else {
            pending = next
            return
        }
        if isRecording { stopRecording() }
        current = next
        retries = 0
        start()
    }

    private func start() {
        guard let c = current else { return }
        let url = c.url, userAgent = c.userAgent, referrer = c.referrer
        // Movies/episodes resume where they were left (also used when retrying after an error).
        setString("start", c.startAt.map { String(Int($0)) } ?? "none")
        setString("user-agent", userAgent.isEmpty ? Defaults.userAgent : userAgent)
        setString("referrer", referrer ?? "")
        command(["loadfile", url.absoluteString, "replace"])
        setFlag("pause", false)
    }

    func stop() {
        current = nil
        stallWatchdog?.cancel()
        if isRecording { stopRecording() }
        command(["stop"])
    }

    func togglePause() { setFlag("pause", !isPaused) }
    func seek(relative seconds: Double) { command(["seek", String(seconds), "relative"]) }
    func seek(absolute seconds: Double) { command(["seek", String(seconds), "absolute"]) }

    func selectAudio(_ id: Int) { setString("aid", String(id)); refreshTracks() }
    func selectSubtitle(_ id: Int?) { setString("sid", id.map(String.init) ?? "no"); refreshTracks() }

    /// Dumps the incoming stream to disk as-is (mpv `stream-record`).
    func startRecording(to url: URL) {
        setString("stream-record", url.path)
        isRecording = true
    }

    func stopRecording() {
        setString("stream-record", "")
        isRecording = false
    }

    /// Applies Playback settings (TiViMate's buffer size, decoder, preferred languages).
    func apply(_ s: AppSettings) {
        setString("hwdec", s.hardwareDecoding ? "auto-safe" : "no")
        setString("cache-pause-wait", String(AppSettings.bufferResumeSeconds[min(3, max(0, s.bufferSize))]))
        setString("alang", s.preferredAudioLanguage)
        setString("slang", s.preferredSubtitleLanguage)
    }

    /// Saves the current decoded video frame (no OSD/UI).
    func screenshot(to url: URL) {
        command(["screenshot-to-file", url.path, "video"])
    }

    // MARK: mpv plumbing

    private func setOption(_ name: String, _ value: String) {
        mpv_set_option_string(handle, name, value)
    }

    private func setString(_ name: String, _ value: String) {
        mpv_set_property_string(handle, name, value)
    }

    private func setFlag(_ name: String, _ value: Bool) {
        var v: CInt = value ? 1 : 0
        mpv_set_property(handle, name, MPV_FORMAT_FLAG, &v)
    }

    private func setDouble(_ name: String, _ value: Double) {
        var v = value
        mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &v)
    }

    private func getString(_ name: String) -> String? {
        guard let c = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(c) }
        return String(cString: c)
    }

    private func observe(_ name: String, _ format: mpv_format) {
        mpv_observe_property(handle, 0, name, format)
    }

    private func command(_ args: [String]) {
        var cargs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        cargs.append(nil)
        defer { cargs.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        mpv_command_async(handle, 0, &cargs)
    }

    private func drainEvents() {
        while true {
            guard let ev = mpv_wait_event(handle, 0) else { return }
            let event = ev.pointee
            switch event.event_id {
            case MPV_EVENT_NONE:
                return
            case MPV_EVENT_PROPERTY_CHANGE:
                handleProperty(event.data.assumingMemoryBound(to: mpv_event_property.self).pointee)
            case MPV_EVENT_END_FILE:
                let end = event.data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if end.reason == MPV_END_FILE_REASON_ERROR {
                    let msg = String(cString: mpv_error_string(end.error))
                    DispatchQueue.main.async { self.handleFailure("Playback failed: \(msg)") }
                } else if end.reason == MPV_END_FILE_REASON_EOF {
                    // A live stream should never end; reconnect at the live edge.
                    DispatchQueue.main.async { if self.current?.isLive == true { self.start() } }
                }
            case MPV_EVENT_PLAYBACK_RESTART:
                DispatchQueue.main.async { self.retries = 0 }
            case MPV_EVENT_FILE_LOADED:
                DispatchQueue.main.async { self.errorMessage = nil; self.refreshTracks() }
            case MPV_EVENT_SHUTDOWN:
                return
            default:
                break
            }
        }
    }

    private func handleProperty(_ p: mpv_event_property) {
        let name = String(cString: p.name)
        func flag() -> Bool { p.format == MPV_FORMAT_FLAG && p.data.assumingMemoryBound(to: CInt.self).pointee != 0 }
        func int() -> Int { p.format == MPV_FORMAT_INT64 ? Int(p.data.assumingMemoryBound(to: Int64.self).pointee) : 0 }
        func dbl() -> Double { p.format == MPV_FORMAT_DOUBLE ? p.data.assumingMemoryBound(to: Double.self).pointee : 0 }
        switch name {
        case "pause": let v = flag(); DispatchQueue.main.async { self.isPaused = v }
        case "paused-for-cache": let v = flag(); DispatchQueue.main.async { self.isBuffering = v; self.armStallWatchdog(v) }
        case "idle-active": let v = flag(); DispatchQueue.main.async { self.isIdle = v }
        case "core-idle": let v = flag(); DispatchQueue.main.async { if !v { self.isBuffering = false } }
        case "width": let v = int(); DispatchQueue.main.async { self.videoSize.width = CGFloat(v) }
        case "height": let v = int(); DispatchQueue.main.async { self.videoSize.height = CGFloat(v) }
        case "time-pos": let v = dbl(); DispatchQueue.main.async { self.position = v }
        case "duration": let v = dbl(); DispatchQueue.main.async { self.duration = v }
        case "track-list/count": DispatchQueue.main.async { self.refreshTracks() }
        default: break
        }
    }

    private func handleFailure(_ message: String) {
        guard current != nil, retries < Self.maxRetries else {
            errorMessage = message
            return
        }
        retries += 1
        if current?.isLive == false, position > 5 { current?.startAt = position }
        let delay: TimeInterval = retries >= 2 ? 1 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.start() }
    }

    private func armStallWatchdog(_ buffering: Bool) {
        stallWatchdog?.cancel()
        guard buffering, current != nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isBuffering, self.current != nil else { return }
            self.start()
        }
        stallWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stallTimeout, execute: item)
    }

    private func refreshTracks() {
        let count = Int(getString("track-list/count") ?? "0") ?? 0
        var audio: [Track] = []
        var subs: [Track] = []
        for i in 0..<count {
            let type = getString("track-list/\(i)/type") ?? ""
            let id = Int(getString("track-list/\(i)/id") ?? "") ?? 0
            let lang = getString("track-list/\(i)/lang")
            let title = getString("track-list/\(i)/title")
            let codec = getString("track-list/\(i)/codec") ?? ""
            let label = [title, lang?.uppercased(), codec.uppercased()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            let selected = getString("track-list/\(i)/selected") == "yes"
            let track = Track(id: id, title: label.isEmpty ? "Track \(id)" : label, selected: selected)
            if type == "audio" { audio.append(track) } else if type == "sub" { subs.append(track) }
        }
        audioTracks = audio
        subtitleTracks = subs
    }
}

enum Defaults {
    static let userAgent = "MacTVMate/1.0 (Macintosh; libmpv)"
    /// Fallback used after HTTP 401/403, same as TiViMate's playlist downloader.
    static let browserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/95.0.4638.54 Safari/537.36"
}
