import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The small reminders that drop in below the menu bar and fade on their own.
enum NudgeKind: Equatable {
    case posture
    case water
    case custom(CustomPopup)

    /// Stable identity for queueing and message rotation (a custom popup keeps its id when edited).
    var key: String {
        switch self {
        case .posture: return "posture"
        case .water: return "water"
        case .custom(let p): return p.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .posture: return "Straighten your back"
        case .water: return "Time for some water"
        case .custom(let p): return p.title
        }
    }

    var symbol: String {
        switch self {
        case .posture: return "figure.stand"
        case .water: return "drop.fill"
        case .custom(let p): return p.symbol
        }
    }

    var colors: [Color] {
        switch self {
        case .posture: return [Palette.mint, Palette.teal]
        case .water: return [Palette.water, Color(hex: 0x3D7BF5)]
        case .custom(let p): return p.colors
        }
    }

    /// Water stays a little longer so there's time to log a glass.
    var duration: TimeInterval {
        switch self {
        case .posture: return 5
        case .water: return 8
        case .custom: return 6
        }
    }

    var messages: [String] {
        switch self {
        case .posture: return [
            "Shrimp mode detected. Unfold yourself. 🦐",
            "Your spine called. It misses being straight.",
            "You're slowly turning into a question mark. ❓",
            "Uncurl. You're a human, not a croissant. 🥐",
            "Shoulders back, chin up, you magnificent coder.",
            "Sit like you're about to get your photo taken. 📸",
            "Gravity is winning. Fight back.",
            "Imagine a string pulling your head to the ceiling.",
            "Posture check! Your future self says thanks.",
            "Less goblin, more giraffe. 🦒",
        ]
        case .water: return [
            "You're about 60% water. Top up before you hit 59. 💧",
            "Coffee is not water. Nice try. ☕",
            "You're basically a fancy houseplant. Water yourself. 🪴",
            "Your brain is turning into a raisin. Plump it up. 🍇",
            "Your kidneys just opened a support ticket.",
            "Bugs are easier to spot when you're hydrated. 🐛",
            "Sip sip, hooray! 🎉",
            "Hydrate now, thank yourself at 4 pm.",
            "Even your code needs a flush sometimes. Go get water. 🚰",
            "Achievement unlocked: stand up, find water. 🏆",
        ]
        case .custom(let p): return [p.message]
        }
    }
}

final class NudgeModel: ObservableObject {
    @Published var kind: NudgeKind = .posture
    @Published var message = ""
    @Published var progress: Double = 1   // 1 → 0 over the visible duration
    /// Set once a glass is logged from the water nudge.
    @Published var loggedNote: String?
}

struct NudgeView: View {
    @ObservedObject var model: NudgeModel
    let onLogWater: () -> Void
    let onDismiss: () -> Void
    private static let radius: CGFloat = 22

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: model.kind.colors, startPoint: .bottomLeading, endPoint: .topTrailing))
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topLeading,
                                         startRadius: 0, endRadius: 36))
                Image(systemName: model.loggedNote == nil ? model.kind.symbol : "checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .shadow(color: model.kind.colors.last!.opacity(0.45), radius: 8, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.kind.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize()
                if let line = model.loggedNote ?? (model.message.isEmpty ? nil : model.message) {
                    Text(line)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize()
                }
            }

            if model.kind == .water, model.loggedNote == nil {
                Button(action: onLogWater) {
                    HStack(spacing: 6) {
                        Text("Drank a glass")
                        KeyCap("⌃⌥W")
                    }
                }
                .buttonStyle(PillButtonStyle(fontSize: 13))
                .padding(.leading, 6)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .padding(.vertical, 14)
        // The panel keeps its size after a glass is logged; fill it so the glass edge stays aligned.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Palette.navyTop.opacity(0.2), Palette.navyBottom.opacity(0.3)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) {
            // Thin bar showing how long the nudge stays.
            GeometryReader { geo in
                Capsule()
                    .fill(model.kind.colors.first!.opacity(0.7))
                    .frame(width: geo.size.width * model.progress, height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 2)
            .padding(.horizontal, Self.radius)
            .padding(.bottom, 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .onTapGesture(perform: onDismiss)   // the button above still gets its own clicks
        .environment(\.colorScheme, .dark)
    }
}

/// The small pet that steps out from behind a nudge and acts it out; it cheers once a glass is logged.
private struct NudgePetView: View {
    @ObservedObject var model: NudgeModel
    let cast: BreakPet.Cast

    var body: some View {
        BreakPet(groundInset: 6, cast: cast, cheer: model.loggedNote != nil)
    }
}

/// Shows posture, water and custom nudges one at a time below the menu bar. No focus is taken;
/// each fades out on its own, or straight away when clicked. A nudge that arrives while
/// another is visible waits its turn.
final class NudgeToastController {
    /// Logs a glass and returns today's total.
    var onLogWater: (() -> Int)?

    private let model = NudgeModel()
    private var panel: NSPanel?
    /// The pet beside the nudge, if pets are on.
    private var petPanel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    private var queue: [NudgeKind] = []
    private let hotKeys = HotKeys()
    private var lastMessage: [String: String] = [:]

    func show(_ kind: NudgeKind) {
        if panel != nil {
            if model.kind.key != kind.key, !queue.contains(where: { $0.key == kind.key }) { queue.append(kind) }
            return
        }
        present(kind)
    }

    /// Removes the visible nudge and anything waiting (e.g. when a break starts).
    func hideAll() {
        queue.removeAll()
        hide(animated: true, next: false)
    }

    func hide(_ kind: NudgeKind) {
        queue.removeAll { $0.key == kind.key }
        if panel != nil, model.kind.key == kind.key { hide(animated: true, next: true) }
    }

    /// Drops a deleted or disabled custom popup.
    func hideCustom(id: UUID) {
        queue.removeAll { $0.key == id.uuidString }
        if panel != nil, model.kind.key == id.uuidString { hide(animated: true, next: true) }
    }

    private func present(_ kind: NudgeKind) {
        let message = kind.messages.filter { $0 != lastMessage[kind.key] }.randomElement()
            ?? kind.messages.first ?? ""
        lastMessage[kind.key] = message
        model.kind = kind
        model.message = message
        model.loggedNote = nil
        model.progress = 1

        let hosting = NSHostingView(rootView: NudgeView(model: model,
                                                    onLogWater: { [weak self] in self?.logWater() },
                                                    onDismiss: { [weak self] in self?.hide(animated: true, next: true) }))
        let size = hosting.fittingSize

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.maskImage = .roundedMask(radius: 22)
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        let visible = ReminderPanelController.activeScreen().visibleFrame
        let finalFrame = NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 44,
                                width: size.width, height: size.height)

        let panel = NSPanel(contentRect: finalFrame.offsetBy(dx: 0, dy: 12),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = effect
        panel.alphaValue = 0

        // The pet's window sits just under the nudge's right edge, so the pet walks out from behind it.
        var petFrame = NSRect.zero
        if let cast = BreakPet.Cast(choice: BreakPet.choice, nudge: kind) {
            petFrame = NSRect(x: finalFrame.maxX - 10, y: finalFrame.minY, width: 130, height: max(size.height, 70) + 6)
            let pet = NSPanel(contentRect: petFrame.offsetBy(dx: 0, dy: 12),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            pet.isOpaque = false
            pet.backgroundColor = .clear
            pet.hasShadow = false
            pet.ignoresMouseEvents = true
            pet.level = .statusBar
            pet.hidesOnDeactivate = false
            pet.isReleasedWhenClosed = false
            pet.collectionBehavior = panel.collectionBehavior
            pet.contentView = NSHostingView(rootView: NudgePetView(model: model, cast: cast))
            pet.alphaValue = 0
            pet.orderFrontRegardless()
            petPanel = pet
        }

        panel.orderFrontRegardless()
        self.panel = panel

        if kind == .water {
            hotKeys.register(keyCode: kVK_ANSI_W) { [weak self] in self?.logWater() }
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
            petPanel?.animator().alphaValue = 1
            petPanel?.animator().setFrame(petFrame, display: true)
        }
        withAnimation(.linear(duration: kind.duration)) { model.progress = 0 }
        scheduleDismiss(after: kind.duration)
    }

    private func logWater() {
        guard model.kind == .water, model.loggedNote == nil, let count = onLogWater?() else { return }
        hotKeys.unregisterAll()
        TickFeedback.shared.tick()
        withAnimation(.easeOut(duration: 0.2)) {
            model.loggedNote = "Nice. \(count) of \(WaterLog.dailyGoal) glasses today 💧"
        }
        scheduleDismiss(after: 1.8)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true, next: true) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func hide(animated: Bool, next: Bool) {
        dismissWork?.cancel()
        dismissWork = nil
        hotKeys.unregisterAll()
        guard let panel else { return }
        self.panel = nil
        let pet = petPanel
        petPanel = nil
        let showNext = { [weak self] in
            guard next, let self, self.panel == nil, !self.queue.isEmpty else { return }
            self.present(self.queue.removeFirst())
        }
        guard animated else { panel.orderOut(nil); pet?.orderOut(nil); showNext(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
            pet?.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            pet?.orderOut(nil)
            // Small gap so two nudges don't look like one flickering popup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: showNext)
        })
    }
}
