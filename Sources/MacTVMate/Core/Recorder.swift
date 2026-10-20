import AppKit
import Foundation

/// Scheduled recordings (TiViMate: record a programme, padding before/after, raw .ts output) and reminders.
/// Each recording runs `ffmpeg -c copy` on its own connection while the app is open.
@MainActor
final class Recorder: ObservableObject {
    static let ffmpeg = "/opt/homebrew/bin/ffmpeg"
    static let paddingBefore: TimeInterval = 2 * 60
    static let paddingAfter: TimeInterval = 5 * 60

    @Published private(set) var dueReminder: Reminder?
    private var processes: [UUID: Process] = [:]
    private unowned let library: Library
    private var timer: Timer?

    init(library: Library) {
        self.library = library
        // Anything marked "recording" from a previous run was interrupted.
        for i in library.recordings.indices where library.recordings[i].status == .recording {
            library.recordings[i].status = .failed
            library.recordings[i].error = "Interrupted (app quit)"
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.processes.values.forEach { $0.terminate() } }
        }
        tick()
    }

    static var folder: URL {
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacTVMate")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Scheduling

    func schedule(_ channel: Channel, _ p: Programme, userAgent: String) {
        guard !isScheduled(channel, p) else { return }
        library.recordings.append(Recording(
            channelID: channel.id, channelName: channel.name, title: p.title,
            start: p.start.addingTimeInterval(-Self.paddingBefore), stop: p.stop.addingTimeInterval(Self.paddingAfter),
            url: channel.url, userAgent: userAgent))
        tick()
    }

    /// TiViMate's "Record now": until the programme ends (or 1 hour without guide data).
    func recordNow(_ channel: Channel, programme: Programme?, userAgent: String) {
        let stop = programme.map { $0.stop.addingTimeInterval(Self.paddingAfter) } ?? Date().addingTimeInterval(3600)
        library.recordings.append(Recording(
            channelID: channel.id, channelName: channel.name, title: programme?.title ?? channel.name,
            start: Date(), stop: stop, url: channel.url, userAgent: userAgent))
        tick()
    }

    func isScheduled(_ channel: Channel, _ p: Programme) -> Bool {
        library.recordings.contains { $0.channelID == channel.id && $0.title == p.title
            && abs($0.start.addingTimeInterval(Self.paddingBefore).timeIntervalSince(p.start)) < 60
            && ($0.status == .scheduled || $0.status == .recording) }
    }

    func recording(for channel: Channel, _ p: Programme) -> Recording? {
        library.recordings.first { $0.channelID == channel.id && $0.title == p.title
            && abs($0.start.addingTimeInterval(Self.paddingBefore).timeIntervalSince(p.start)) < 60 }
    }

    func cancel(_ r: Recording) {
        processes[r.id]?.terminate()
        update(r.id) { $0.status = $0.status == .recording ? .done : .cancelled }
    }

    func delete(_ r: Recording) {
        processes[r.id]?.terminate()
        if let f = r.file { try? FileManager.default.trashItem(at: URL(fileURLWithPath: f), resultingItemURL: nil) }
        library.recordings.removeAll { $0.id == r.id }
    }

    var activeCount: Int { processes.count }

    // MARK: Reminders

    func remind(_ channel: Channel, _ p: Programme) {
        guard !hasReminder(channel, p) else { return }
        library.reminders.append(Reminder(channelID: channel.id, channelName: channel.name, title: p.title, start: p.start))
    }

    func hasReminder(_ channel: Channel, _ p: Programme) -> Bool {
        library.reminders.contains { $0.channelID == channel.id && abs($0.start.timeIntervalSince(p.start)) < 60 }
    }

    func removeReminder(_ channel: Channel, _ p: Programme) {
        library.reminders.removeAll { $0.channelID == channel.id && abs($0.start.timeIntervalSince(p.start)) < 60 }
    }

    func dismissReminder() { dueReminder = nil }

    // MARK: Engine

    private func tick() {
        let now = Date()
        for r in library.recordings {
            if r.status == .scheduled, r.start <= now, now < r.stop { start(r) }
            if r.status == .scheduled, r.stop <= now { update(r.id) { $0.status = .failed; $0.error = "Missed (app wasn't running)" } }
        }
        // Reminders fire one minute before the start.
        if dueReminder == nil, let due = library.reminders.first(where: { $0.start.addingTimeInterval(-60) <= now }) {
            library.reminders.removeAll { $0.id == due.id }
            if due.start.addingTimeInterval(15 * 60) > now {
                dueReminder = due
                NSApp.requestUserAttention(.informationalRequest)
                NSSound(named: "Glass")?.play()
            }
        }
    }

    private func start(_ r: Recording) {
        guard FileManager.default.isExecutableFile(atPath: Self.ffmpeg) else {
            update(r.id) { $0.status = .failed; $0.error = "ffmpeg not found (brew install ffmpeg)" }
            return
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        let safe = "\(r.channelName) - \(r.title) \(f.string(from: r.start))"
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let out = Self.folder.appendingPathComponent("\(safe).ts")
        let seconds = max(10, Int(r.stop.timeIntervalSinceNow))

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.ffmpeg)
        p.arguments = ["-hide_banner", "-loglevel", "error", "-nostdin",
                       "-user_agent", r.userAgent.isEmpty ? Defaults.userAgent : r.userAgent,
                       "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "10",
                       "-i", r.url.absoluteString, "-map", "0", "-c", "copy", "-t", String(seconds), "-f", "mpegts", out.path]
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = FileHandle.nullDevice
        let id = r.id
        p.terminationHandler = { [weak self] proc in
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                guard let self else { return }
                self.processes[id] = nil
                let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
                self.update(id) { rec in
                    if rec.status == .recording {
                        rec.status = size > 0 ? .done : .failed
                        if size == 0 { rec.error = err?.split(separator: "\n").last.map(String.init) ?? "No data received" }
                    }
                }
            }
        }
        do {
            try p.run()
            processes[r.id] = p
            update(r.id) { $0.status = .recording; $0.file = out.path; $0.error = nil }
        } catch {
            update(r.id) { $0.status = .failed; $0.error = error.localizedDescription }
        }
    }

    private func update(_ id: UUID, _ change: (inout Recording) -> Void) {
        guard let i = library.recordings.firstIndex(where: { $0.id == id }) else { return }
        change(&library.recordings[i])
    }
}
