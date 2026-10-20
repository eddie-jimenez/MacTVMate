import SwiftUI

/// Remote-style navigation: every screen can be driven with the arrows, OK, Back and Menu
/// (keyboard, Shield remote or the iPhone remote).
enum NavKey: Equatable {
    case up, down, left, right
    case select          // OK / Return
    case hold            // OK held down: options for the focused item
    case back            // Esc / Back
    case menu            // Menu ≡: options (player: controls)
    case favourite, record
}

/// Where arrow focus is on browse screens: the left rail, the side column (groups, categories,
/// settings sections) or the main content.
enum FocusZone: Equatable { case rail, side, main }

/// A spot in a navigable layout: rows top to bottom, columns left to right.
struct FocusSpot: Hashable, Comparable {
    var row: Int
    var col: Int = 0
    static func < (a: Self, b: Self) -> Bool { (a.row, a.col) < (b.row, b.col) }
}

/// What a focused control does. `left`/`right` adjust a value (pickers, steppers) instead of moving.
struct FocusTarget {
    var activate: () -> Void
    var left: (() -> Void)?
    var right: (() -> Void)?
    var options: (() -> [MenuAction])?
}

/// A registry of focusable controls for one layer (a screen, a sheet, the settings content, the player controls).
/// Controls register themselves with `.focusSpot(...)`; arrows move between registered spots.
@MainActor
final class FocusForm: ObservableObject {
    @Published var spot = FocusSpot(row: 0)
    @Published var engaged = false
    private var targets: [FocusSpot: FocusTarget] = [:]
    private var owners: [AnyHashable: FocusSpot] = [:]

    func register(_ spot: FocusSpot, owner: AnyHashable, _ target: FocusTarget) {
        if let old = owners[owner], old != spot, !owners.contains(where: { $0.key != owner && $0.value == old }) { targets[old] = nil }
        // A new control taking an occupied spot replaces the previous owner.
        for (k, v) in owners where v == spot && k != owner { owners[k] = nil }
        owners[owner] = spot
        targets[spot] = target
    }

    func unregister(owner: AnyHashable) {
        guard let s = owners.removeValue(forKey: owner) else { return }
        // Only drop the action if no other control has since claimed this spot.
        if !owners.values.contains(s) { targets[s] = nil }
    }

    var isEmpty: Bool { targets.isEmpty }
    var current: FocusTarget? { targets[spot] }

    /// Puts focus on the first control (or keeps it if it still exists).
    func engage(reset: Bool = false) {
        if reset || targets[spot] == nil, let first = targets.keys.min() { spot = first }
        engaged = true
    }

    func focus(_ s: FocusSpot) { if targets[s] != nil { spot = s } }

    /// Moves focus; returns false at an edge (so the caller can hand focus to the side column or rail).
    func move(_ key: NavKey) -> Bool {
        if targets[spot] == nil, let first = targets.keys.min() { spot = first; return true }
        switch key {
        case .up, .down:
            let rows = Set(targets.keys.map(\.row)).sorted()
            let next = key == .down ? rows.first { $0 > spot.row } : rows.last { $0 < spot.row }
            guard let r = next else { return false }
            let cols = targets.keys.filter { $0.row == r }.map(\.col)
            let c = cols.min { abs($0 - spot.col) < abs($1 - spot.col) } ?? 0
            spot = FocusSpot(row: r, col: c)
            return true
        case .left, .right:
            if let t = targets[spot] {
                if key == .left, let l = t.left { l(); return true }
                if key == .right, let r = t.right { r(); return true }
            }
            let cols = targets.keys.filter { $0.row == spot.row }.map(\.col).sorted()
            let next = key == .right ? cols.first { $0 > spot.col } : cols.last { $0 < spot.col }
            guard let c = next else { return false }
            spot.col = c
            return true
        default:
            return false
        }
    }

    func activate() { targets[spot]?.activate() }

    func clear() { targets = [:]; owners = [:]; engaged = false }
}

/// One entry in an Options menu.
struct MenuAction: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var role: ButtonRole? = nil
    var run: () -> Void
}

/// TiViMate-style Options list (hold OK or press Menu).
struct ActionMenu {
    var title: String
    var subtitle: String? = nil
    var actions: [MenuAction]
    var index = 0
}

// MARK: - Views

/// Accent ring used for remote focus everywhere.
struct FocusRing: ViewModifier {
    let on: Bool
    var radius: CGFloat = 8
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.accent, lineWidth: on ? 3 : 0).padding(-3))
            .scaleEffect(on ? 1.02 : 1)
            .animation(.easeOut(duration: 0.12), value: on)
    }
}

private struct FocusSpotModifier: ViewModifier {
    @ObservedObject var form: FocusForm
    let spot: FocusSpot
    let explicitOwner: AnyHashable?
    let target: FocusTarget
    var radius: CGFloat
    /// Each control instance owns its registration, so a page that's going away can't unregister
    /// the same spot on the page replacing it.
    @State private var uid = UUID()
    private var owner: AnyHashable { explicitOwner ?? AnyHashable(uid) }

    func body(content: Content) -> some View {
        // Re-registering on every render keeps the actions current (cheap: a dictionary write, nothing published).
        let _ = form.register(spot, owner: owner, target)
        content
            .modifier(FocusRing(on: form.engaged && form.spot == spot, radius: radius))
            .id(spot)
            .onDisappear { form.unregister(owner: owner) }
    }
}

extension View {
    /// Makes a control reachable with the arrows. `owner` should be stable for the control (defaults to the spot).
    func focusSpot(_ form: FocusForm, row: Int, col: Int = 0, owner: AnyHashable? = nil, radius: CGFloat = 8,
                   left: (() -> Void)? = nil, right: (() -> Void)? = nil, options: (() -> [MenuAction])? = nil,
                   activate: @escaping () -> Void) -> some View {
        let s = FocusSpot(row: row, col: col)
        return modifier(FocusSpotModifier(form: form, spot: s, explicitOwner: owner,
                                          target: FocusTarget(activate: activate, left: left, right: right, options: options),
                                          radius: radius))
    }

    func focusRing(_ on: Bool, radius: CGFloat = 8) -> some View { modifier(FocusRing(on: on, radius: radius)) }

    /// A focusable Toggle: OK flips it.
    func focusToggle(_ form: FocusForm, row: Int, col: Int = 0, _ value: Binding<Bool>) -> some View {
        focusSpot(form, row: row, col: col) { value.wrappedValue.toggle() }
    }

    /// A focusable picker/stepper: ←/→ step through the values, OK steps forward.
    func focusChoice<T: Equatable>(_ form: FocusForm, row: Int, col: Int = 0, _ value: Binding<T>, _ options: [T]) -> some View {
        func step(_ d: Int) {
            guard !options.isEmpty else { return }
            let i = options.firstIndex(of: value.wrappedValue) ?? 0
            value.wrappedValue = options[min(options.count - 1, max(0, i + d))]
        }
        return focusSpot(form, row: row, col: col, left: { step(-1) }, right: { step(1) }) {
            let i = options.firstIndex(of: value.wrappedValue) ?? 0
            value.wrappedValue = options[(i + 1) % max(1, options.count)]
        }
    }
}

/// Scrolls a ScrollView so the focused spot stays visible.
struct FocusScroller<Content: View>: View {
    @ObservedObject var form: FocusForm
    var anchor: UnitPoint? = .center
    @ViewBuilder let content: (ScrollViewProxy) -> Content

    var body: some View {
        ScrollViewReader { proxy in
            content(proxy)
                .onChange(of: form.spot) { _, s in
                    guard form.engaged else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(s, anchor: anchor) }
                }
        }
    }
}

/// The Options list drawn over everything.
struct ActionMenuView: View {
    @EnvironmentObject var model: AppModel
    let menu: ActionMenu

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.actionMenu = nil }
            VStack(alignment: .leading, spacing: Theme.s(4)) {
                Text(menu.title).font(Theme.f(.title3).weight(.semibold)).lineLimit(2)
                if let s = menu.subtitle { Text(s).font(Theme.f(.callout)).foregroundStyle(Theme.dim).lineLimit(2) }
                Divider().padding(.vertical, Theme.s(6))
                ForEach(Array(menu.actions.enumerated()), id: \.element.id) { i, a in
                    let on = i == menu.index
                    HStack(spacing: Theme.s(12)) {
                        Image(systemName: a.icon).frame(width: Theme.s(22))
                        Text(a.title)
                        Spacer()
                    }
                    .font(Theme.f(.body).weight(on ? .semibold : .regular))
                    .padding(.horizontal, Theme.s(14)).padding(.vertical, Theme.s(10))
                    .background(on ? Theme.focus : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(on ? Theme.focusText : (a.role == .destructive ? Theme.live : Theme.text))
                    .contentShape(Rectangle())
                    .onTapGesture { model.actionMenu = nil; a.run() }
                    .onHover { if $0 { model.actionMenu?.index = i } }
                }
                Text("OK to choose · Back to close").font(Theme.f(.caption)).foregroundStyle(Theme.faint).padding(.top, Theme.s(6))
            }
            .padding(Theme.s(20))
            .frame(width: Theme.s(380))
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 30)
        }
    }
}
