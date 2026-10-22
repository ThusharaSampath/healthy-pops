import AppKit
import SwiftUI

/// State shared by the overlay windows on every display.
final class BreakOverlayModel: ObservableObject {
    static let range = 5...60

    @Published var adjusting = false
    /// Share of the break left, 1 → 0; drives the timeline bar.
    @Published var progress: Double = 1
    /// This break's pet, or nil when pets are switched off.
    @Published var pet: BreakPet.Cast?
    @Published private(set) var duration = 20

    /// Set without feedback (e.g. when the overlay opens).
    func load(_ seconds: Int) {
        duration = Self.clamp(seconds)
    }

    /// Set from user input; ticks once per changed second.
    func set(_ seconds: Int) {
        let value = Self.clamp(seconds)
        guard value != duration else { return }
        duration = value
        TickFeedback.shared.tick()
    }

    func step(_ delta: Int) { set(duration + delta) }

    var fraction: Double {
        Double(duration - Self.range.lowerBound) / Double(Self.range.upperBound - Self.range.lowerBound)
    }

    private static func clamp(_ v: Int) -> Int { min(max(v, range.lowerBound), range.upperBound) }
}

/// Deliberately minimal: no countdown or tips to read, so the eyes go elsewhere.
/// The reminder pill gives the instructions; a quiet shrinking bar shows time left
/// at a glance, and a sound marks the end of the break.
struct BreakView: View {
    @ObservedObject var model: BreakOverlayModel
    let onSkip: () -> Void
    let onAdjust: () -> Void
    let onApply: () -> Void
    /// Where the pet stands on this display, or nil for no pet here.
    let petGround: CGFloat?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0B0A24, opacity: 0.18), Color(hex: 0x2B1F86, opacity: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if let cast = model.pet, let petGround {
                BreakPet(groundInset: petGround, cast: cast)
            }

            if model.adjusting {
                adjustContent.transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                restContent.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.adjusting)
        .environment(\.colorScheme, .dark)
    }

    private var restContent: some View {
        VStack(spacing: 28) {
            VStack(spacing: 20) {
                Text("Nothing here to look at.")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                BreakTimeline(progress: model.progress)
            }

            VStack(spacing: 8) {
                Button("Skip", action: onSkip)
                    .buttonStyle(PillButtonStyle(filled: true))
                Text("or press Esc")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 8)

            Button(action: onAdjust) {
                HStack(spacing: 6) {
                    KeyCap("T")
                    Text("adjust break length")
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var adjustContent: some View {
        VStack(spacing: 26) {
            Text("Break length")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            DurationDial(model: model)

            HStack(spacing: 14) {
                hint(keys: ["←", "→"], text: "or drag / scroll")
                hint(keys: ["⇧"], text: "±5s")
            }

            HStack(spacing: 10) {
                Button("Apply", action: onApply)
                    .buttonStyle(PillButtonStyle(filled: true))
            }
            Text("Return to apply · Esc to cancel")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func hint(keys: [String], text: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { KeyCap($0) }
            Text(text).padding(.leading, 2)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.5))
    }
}

/// Thin glowing bar that shrinks from both ends toward the centre as the break runs out.
private struct BreakTimeline: View {
    var progress: Double
    private let width: CGFloat = 280

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: width, height: 4)
            Capsule()
                .fill(
                    LinearGradient(colors: [Palette.pink, Palette.coral, Palette.peach],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: max(4, width * progress), height: 4)
                .shadow(color: Palette.pink.opacity(0.55), radius: 6)
                .opacity(progress > 0 ? 1 : 0)
        }
        .frame(width: width, height: 10)
        .accessibilityHidden(true)
    }
}

/// 270° rotary dial, 5–60 s in 1 s detents. Drag around it, scroll, or use arrow keys.
struct DurationDial: View {
    @ObservedObject var model: BreakOverlayModel

    private let size: CGFloat = 220
    private let startAngle = -135.0   // degrees clockwise from 12 o'clock
    private let sweep = 270.0

    var body: some View {
        let radius = size / 2
        ZStack {
            // Tick marks every 5 s, major ones every 15 s.
            ForEach(Array(stride(from: BreakOverlayModel.range.lowerBound,
                                 through: BreakOverlayModel.range.upperBound, by: 5)), id: \.self) { v in
                Capsule()
                    .fill(Color.white.opacity(v <= model.duration ? 0.8 : 0.22))
                    .frame(width: 2, height: v % 15 == 0 ? 11 : 6)
                    .offset(y: -(radius + 18))
                    .rotationEffect(.degrees(angle(for: v)))
            }

            Circle()
                .trim(from: 0, to: sweep / 360)
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(startAngle + 270))   // trim starts at 3 o'clock

            Circle()
                .trim(from: 0, to: sweep / 360 * model.fraction)
                .stroke(
                    AngularGradient(colors: [Palette.pink, Palette.coral, Palette.peach], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(sweep)),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(startAngle + 270))
                .shadow(color: Palette.pink.opacity(0.45), radius: 10)

            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                .offset(y: -radius)
                .rotationEffect(.degrees(startAngle + sweep * model.fraction))

            VStack(spacing: 0) {
                Text("\(model.duration)")
                    .font(.system(size: 60, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text("seconds")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.18, dampingFraction: 0.85), value: model.duration)
        .padding(30)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { g in
                let center = CGPoint(x: size / 2 + 30, y: size / 2 + 30)
                model.set(value(at: g.location, center: center))
            }
        )
    }

    private func angle(for value: Int) -> Double {
        let r = BreakOverlayModel.range
        return startAngle + sweep * Double(value - r.lowerBound) / Double(r.upperBound - r.lowerBound)
    }

    private func value(at point: CGPoint, center: CGPoint) -> Int {
        let r = BreakOverlayModel.range
        var a = atan2(point.x - center.x, center.y - point.y) * 180 / .pi   // clockwise from top
        let end = startAngle + sweep
        if a > end || a < startAngle {
            // In the gap at the bottom: stick to whichever end we're already near.
            a = model.fraction > 0.5 ? end : startAngle
        }
        let f = (a - startAngle) / sweep
        return r.lowerBound + Int((f * Double(r.upperBound - r.lowerBound)).rounded())
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen blurred overlay on every display for the duration of the break.
final class BreakOverlayController {
    var onSkip: (() -> Void)?
    /// Dial opened (true) or closed (false); the break countdown is held while open.
    var onAdjustingChange: ((Bool) -> Void)?
    var onDurationApply: ((Int) -> Void)?

    private let model = BreakOverlayModel()
    private var windows: [NSWindow] = []
    private var monitors: [Any] = []
    private var scrollAccumulator: CGFloat = 0
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { !windows.isEmpty }

    func show(breakDuration: Int, pet: BreakPet.Choice, petWater: Bool) {
        guard windows.isEmpty else { return }
        model.load(breakDuration)
        model.adjusting = false
        model.progress = 1
        // Picked once per break; the pet mentions water when water reminders are on.
        model.pet = BreakPet.Cast(choice: pet, water: petWater)

        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        // One pet, on the display the pointer is on.
        let petScreen = ReminderPanelController.activeScreen()
        for screen in NSScreen.screens {
            let window = makeWindow(for: screen, pet: screen == petScreen)
            window.alphaValue = 0
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first { $0.screen == ReminderPanelController.activeScreen() }?.makeKey()
            ?? windows.first?.makeKey()

        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] in self?.handleKey($0) }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] in self?.handleScroll($0) }) {
            monitors.append(m)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.6
            windows.forEach { $0.animator().alphaValue = 1 }
        }
    }

    /// Called every scheduler tick; animates the bar smoothly between one-second updates.
    func update(remaining: TimeInterval, total: TimeInterval) {
        guard total > 0 else { return }
        let value = max(0, min(1, remaining / total))
        guard abs(value - model.progress) > 0.0001 else { return }   // held while the dial is open
        // Refills (new break length applied) ease back; normal ticks drain linearly.
        let animation: Animation = value > model.progress ? .easeOut(duration: 0.4) : .linear(duration: 1)
        withAnimation(animation) { model.progress = value }
    }

    func hide() {
        guard !windows.isEmpty else { return }
        if model.adjusting {
            // Overlay closing mid-adjust (lock, sleep, ...): keep what was dialled in.
            model.adjusting = false
            onDurationApply?(model.duration)
        }
        let closing = windows
        windows = []
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        TickFeedback.shared.stop()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            closing.forEach { $0.orderOut(nil) }
            self?.previousApp?.activate(options: [])
            self?.previousApp = nil
        })
    }

    // MARK: - Dial

    private var durationBeforeAdjust = 20

    private func beginAdjust() {
        guard !model.adjusting else { return }
        durationBeforeAdjust = model.duration
        scrollAccumulator = 0
        model.adjusting = true
        onAdjustingChange?(true)
    }

    private func apply() {
        guard model.adjusting else { return }
        model.adjusting = false
        onDurationApply?(model.duration)
    }

    private func cancelAdjust() {
        guard model.adjusting else { return }
        model.load(durationBeforeAdjust)
        model.adjusting = false
        onAdjustingChange?(false)
    }

    // MARK: - Input

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let key = event.charactersIgnoringModifiers?.lowercased()
        let big = event.modifierFlags.contains(.shift) ? 5 : 1

        guard model.adjusting else {
            switch (event.keyCode, key) {
            case (53, _): onSkip?()          // Esc
            case (_, "t"): beginAdjust()
            default: return event
            }
            return nil
        }

        switch (event.keyCode, key) {
        case (123, _), (125, _): model.step(-big)      // ← ↓
        case (124, _), (126, _): model.step(big)       // → ↑
        case (36, _), (76, _), (_, "t"): apply()        // Return, Enter, T
        case (53, _): cancelAdjust()                    // Esc
        default: return event
        }
        return nil
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard model.adjusting else { return event }
        if event.phase == .began { scrollAccumulator = 0 }
        // Trackpads send many small precise deltas; mouse wheels send whole lines.
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 8 : 1
        let delta = event.scrollingDeltaY + event.scrollingDeltaX
        scrollAccumulator += event.isDirectionInvertedFromDevice ? delta : -delta
        while abs(scrollAccumulator) >= threshold {
            let step = scrollAccumulator > 0 ? 1 : -1
            model.step(step)
            scrollAccumulator -= CGFloat(step) * threshold
        }
        return nil
    }

    private func makeWindow(for screen: NSScreen, pet: Bool) -> NSWindow {
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)

        let view = BreakView(
            model: model,
            onSkip: { [weak self] in self?.onSkip?() },
            onAdjust: { [weak self] in self?.beginAdjust() },
            onApply: { [weak self] in self?.apply() },
            // Stand on top of the Dock; near the bottom edge if it's hidden or on a side.
            petGround: pet ? max(screen.visibleFrame.minY - screen.frame.minY + 6, 36) : nil
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        window.contentView = effect
        window.setFrame(screen.frame, display: false)
        return window
    }
}
