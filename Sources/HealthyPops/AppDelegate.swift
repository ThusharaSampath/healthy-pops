import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let scheduler = BreakScheduler()
    private let reminder = ReminderPanelController()
    private let overlay = BreakOverlayController()
    private let nudges = NudgeToastController()
    private let editor = PopupEditorController()
    private let customStore = CustomPopupStore.shared

    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the 1s timer accurate; App Nap would otherwise throttle a background accessory app.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Tracking screen time for eye breaks"
        )

        setUpStatusItem()
        wireScheduler()
        observeSystemEvents()
        scheduler.start()
        refreshStatusItem()
    }

    // MARK: - Wiring

    private func wireScheduler() {
        reminder.onStartBreak = { [weak self] in self?.scheduler.startBreak() }
        reminder.onSnooze = { [weak self] s in self?.scheduler.snooze(s) }
        overlay.onSkip = { [weak self] in self?.scheduler.skipBreak() }
        overlay.onAdjustingChange = { [weak self] held in self?.scheduler.holdBreak(held) }
        overlay.onDurationApply = { [weak self] s in self?.scheduler.setBreakDuration(TimeInterval(s)) }
        nudges.onLogWater = { [weak self] in self?.logWater() ?? WaterLog.today }

        scheduler.onNudgeDue = { [weak self] kind in self?.nudges.show(kind) }
        scheduler.customPopups = { CustomPopupStore.shared.popups }

        editor.onSave = { [weak self] popup in
            guard let self else { return }
            customStore.upsert(popup)
            scheduler.resetCustom(id: popup.id)
            // Show it once so the user sees exactly what they made.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.nudges.show(.custom(popup)) }
        }
        editor.onClose = { [weak self] in self?.scheduler.uiHold = false }
        scheduler.callCheck = { CallDetector.isInCall() }

        scheduler.onPhaseChange = { [weak self] old, new in
            guard let self else { return }
            if new != .warning { reminder.hide() }
            if new != .working { nudges.hideAll() }   // the eye reminder takes the same spot
            if old == .onBreak {
                overlay.hide()
                NSSound(named: "Glass")?.play()
            }
        }

        scheduler.onTick = { [weak self] in
            guard let self else { return }
            switch scheduler.phase {
            case .warning:
                reminder.show(
                    remaining: scheduler.remaining,
                    total: scheduler.config.warningLead,
                    breakDuration: scheduler.config.breakDuration
                )
            case .onBreak:
                overlay.show(breakDuration: Int(scheduler.config.breakDuration), pet: BreakPet.choice,
                             petWater: scheduler.config.waterEnabled)
                overlay.update(remaining: scheduler.breakRemaining, total: scheduler.config.breakDuration)
            case .working:
                if scheduler.inCall { nudges.hideAll() }
            }
            refreshStatusItem()
        }
    }

    private func observeSystemEvents() {
        let ws = NSWorkspace.shared.notificationCenter
        let pairs: [(NSNotification.Name, NSNotification.Name, String)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "display"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session"),
        ]
        for (down, up, reason) in pairs {
            ws.addObserver(forName: down, object: nil, queue: .main) { [weak self] _ in self?.scheduler.suspend(reason) }
            ws.addObserver(forName: up, object: nil, queue: .main) { [weak self] _ in self?.scheduler.unsuspend(reason) }
        }

        let dnc = DistributedNotificationCenter.default()
        let distributed: [(String, String, String)] = [
            ("com.apple.screenIsLocked", "com.apple.screenIsUnlocked", "lock"),
            ("com.apple.screensaver.didstart", "com.apple.screensaver.didstop", "screensaver"),
        ]
        for (down, up, reason) in distributed {
            dnc.addObserver(forName: .init(down), object: nil, queue: .main) { [weak self] _ in self?.scheduler.suspend(reason) }
            dnc.addObserver(forName: .init(up), object: nil, queue: .main) { [weak self] _ in self?.scheduler.unsuspend(reason) }
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Text only: the time left, or a word for the current state.
    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let title: String

        if scheduler.isPaused {
            title = "Paused"
        } else {
            switch scheduler.phase {
            case .onBreak:
                title = "\(Int(scheduler.breakRemaining.rounded(.up)))s"
            case .warning:
                title = formatClock(scheduler.remaining)
            case .working where scheduler.inCall:
                title = "In call"
            case .working:
                let r = scheduler.remaining
                title = r >= 60 ? "\(Int((r / 60).rounded(.up)))m" : "\(Int(r.rounded(.up)))s"
            }
        }

        button.image = nil
        button.title = title
        button.setAccessibilityLabel("Healthy Pops: \(statusDescription())")
        statusLine.title = statusDescription()
    }

    private func statusDescription() -> String {
        if let until = scheduler.pausedUntil {
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if scheduler.isSuspended { return "Away – timer reset" }
        switch scheduler.phase {
        case .onBreak: return "Break in progress"
        case .warning: return "Break starting…"
        case .working:
            if scheduler.inCall { return "In a call. Breaks will wait." }
            let r = scheduler.remaining
            return r >= 60
                ? "Next break in \(Int((r / 60).rounded(.up))) min"
                : "Next break in \(Int(r.rounded(.up))) sec"
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        statusLine.isEnabled = false
        statusLine.title = statusDescription()
        menu.addItem(statusLine)
        menu.addItem(.separator())

        if scheduler.config.waterEnabled {
            let waterCount = NSMenuItem(title: "Water today: \(WaterLog.today) / \(WaterLog.dailyGoal) glasses",
                                        action: nil, keyEquivalent: "")
            waterCount.isEnabled = false
            menu.addItem(waterCount)
            menu.addItem(item("I Drank Water", #selector(drankWaterFromMenu), key: "w"))
            menu.addItem(.separator())
        }

        let breakNow = item("Take a Break Now", #selector(takeBreakNow), key: "b")
        breakNow.isEnabled = !scheduler.isPaused && scheduler.phase != .onBreak
        menu.addItem(breakNow)
        menu.addItem(item("Reset Timer", #selector(resetTimer), key: "r"))
        menu.addItem(.separator())

        let remindersHeader = NSMenuItem(title: "Reminders", action: nil, keyEquivalent: "")
        remindersHeader.isEnabled = false
        menu.addItem(remindersHeader)
        let waterToggle = item("Water Reminders", #selector(toggleWater), key: "")
        waterToggle.state = scheduler.config.waterEnabled ? .on : .off
        menu.addItem(waterToggle)
        let postureToggle = item("Posture Reminders", #selector(togglePosture), key: "")
        postureToggle.state = scheduler.config.postureEnabled ? .on : .off
        menu.addItem(postureToggle)
        let petMenu = NSMenu()
        for choice in BreakPet.Choice.allCases {
            if choice == .off { petMenu.addItem(.separator()) }
            let i = item(choice.title, #selector(setBreakPet(_:)), key: "")
            i.representedObject = choice.rawValue
            i.state = BreakPet.choice == choice ? .on : .off
            petMenu.addItem(i)
        }
        let pet = NSMenuItem(title: "Break Pet", action: nil, keyEquivalent: "")
        pet.submenu = petMenu
        menu.addItem(pet)
        let callToggle = item("Hold Breaks During Calls", #selector(toggleHoldDuringCalls), key: "")
        callToggle.state = scheduler.config.holdDuringCalls ? .on : .off
        menu.addItem(callToggle)
        let custom = NSMenuItem(title: "Custom Popups", action: nil, keyEquivalent: "")
        custom.submenu = customPopupsMenu()
        menu.addItem(custom)
        menu.addItem(.separator())

        let timersHeader = NSMenuItem(title: "Timers", action: nil, keyEquivalent: "")
        timersHeader.isEnabled = false
        menu.addItem(timersHeader)
        menu.addItem(.stepper(title: "Screen time", value: minutes(scheduler.config.workInterval)) { [weak self] dir in
            guard let self else { return "" }
            scheduler.setWorkInterval(Self.snap(scheduler.config.workInterval, step: 5 * 60, dir: dir))
            return minutes(scheduler.config.workInterval)
        })
        menu.addItem(.stepper(title: "Look away", value: seconds(scheduler.config.breakDuration)) { [weak self] dir in
            guard let self else { return "" }
            scheduler.setBreakDuration(Self.snap(scheduler.config.breakDuration, step: 5, dir: dir))
            return seconds(scheduler.config.breakDuration)
        })
        if scheduler.config.waterEnabled {
            menu.addItem(.stepper(title: "Water", value: minutes(scheduler.config.waterInterval)) { [weak self] dir in
                guard let self else { return "" }
                scheduler.setWaterInterval(Self.snap(scheduler.config.waterInterval, step: 15 * 60, dir: dir))
                return minutes(scheduler.config.waterInterval)
            })
        }
        if scheduler.config.postureEnabled {
            menu.addItem(.stepper(title: "Posture", value: minutes(scheduler.config.postureInterval)) { [weak self] dir in
                guard let self else { return "" }
                scheduler.setPostureInterval(Self.snap(scheduler.config.postureInterval, step: 5 * 60, dir: dir))
                return minutes(scheduler.config.postureInterval)
            })
        }
        menu.addItem(.separator())

        if scheduler.isPaused {
            menu.addItem(item("Resume", #selector(resume), key: ""))
        } else {
            let pauseMenu = NSMenu()
            for (title, minutes) in [("30 Minutes", 30), ("1 Hour", 60), ("2 Hours", 120)] {
                let i = item(title, #selector(pauseFor(_:)), key: "")
                i.tag = minutes
                pauseMenu.addItem(i)
            }
            pauseMenu.addItem(item("Until Tomorrow", #selector(pauseUntilTomorrow), key: ""))
            let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
            pause.submenu = pauseMenu
            menu.addItem(pause)
        }
        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin), key: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit Healthy Pops", #selector(quit), key: "q"))
    }

    /// Next multiple of `step` in direction `dir`, so odd values (e.g. 9 s from the dial) land on the grid.
    private static func snap(_ value: TimeInterval, step: TimeInterval, dir: Int) -> TimeInterval {
        dir > 0
            ? (value / step).rounded(.down) * step + step
            : (value / step).rounded(.up) * step - step
    }

    private func minutes(_ s: TimeInterval) -> String { "\(Int(s / 60)) min" }
    private func seconds(_ s: TimeInterval) -> String { "\(Int(s)) s" }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @discardableResult
    private func logWater() -> Int {
        let count = WaterLog.addGlass()
        scheduler.drankWater()
        return count
    }

    @objc private func drankWaterFromMenu() { logWater() }
    // MARK: - Custom popups

    private func customPopupsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("New Popup…", #selector(newCustomPopup), key: "n"))
        let popups = customStore.popups
        if !popups.isEmpty { menu.addItem(.separator()) }
        for popup in popups {
            let row = NSMenuItem(title: "\(popup.title)  ·  \(popup.intervalLabel)", action: nil, keyEquivalent: "")
            row.image = NSImage(systemSymbolName: popup.symbol, accessibilityDescription: nil)
            if !popup.enabled {
                row.attributedTitle = NSAttributedString(
                    string: "\(popup.title)  ·  off",
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor])
            }
            let sub = NSMenu()
            let enabled = customItem("Enabled", #selector(toggleCustomPopup(_:)), popup)
            enabled.state = popup.enabled ? .on : .off
            sub.addItem(enabled)
            sub.addItem(customItem("Edit…", #selector(editCustomPopup(_:)), popup))
            sub.addItem(customItem("Show Now", #selector(previewCustomPopup(_:)), popup))
            sub.addItem(.separator())
            sub.addItem(customItem("Delete", #selector(deleteCustomPopup(_:)), popup))
            row.submenu = sub
            menu.addItem(row)
        }
        return menu
    }

    private func customItem(_ title: String, _ action: Selector, _ popup: CustomPopup) -> NSMenuItem {
        let i = item(title, action, key: "")
        i.representedObject = popup.id
        return i
    }

    private func customPopup(from sender: NSMenuItem) -> CustomPopup? {
        (sender.representedObject as? UUID).flatMap(customStore.popup(id:))
    }

    private func openEditor(_ popup: CustomPopup?) {
        scheduler.uiHold = true
        nudges.hideAll()
        editor.open(editing: popup)
    }

    @objc private func newCustomPopup() { openEditor(nil) }

    @objc private func editCustomPopup(_ sender: NSMenuItem) {
        guard let popup = customPopup(from: sender) else { return }
        openEditor(popup)
    }

    @objc private func previewCustomPopup(_ sender: NSMenuItem) {
        guard let popup = customPopup(from: sender) else { return }
        nudges.show(.custom(popup))
    }

    @objc private func toggleCustomPopup(_ sender: NSMenuItem) {
        guard var popup = customPopup(from: sender) else { return }
        popup.enabled.toggle()
        customStore.upsert(popup)
        scheduler.resetCustom(id: popup.id)
        if !popup.enabled { nudges.hideCustom(id: popup.id) }
    }

    @objc private func deleteCustomPopup(_ sender: NSMenuItem) {
        guard let popup = customPopup(from: sender) else { return }
        customStore.remove(id: popup.id)
        nudges.hideCustom(id: popup.id)
    }

    @objc private func toggleHoldDuringCalls() {
        scheduler.setHoldDuringCalls(!scheduler.config.holdDuringCalls)
    }

    @objc private func toggleWater() {
        scheduler.setWaterEnabled(!scheduler.config.waterEnabled)
        if !scheduler.config.waterEnabled { nudges.hide(.water) }
    }

    @objc private func setBreakPet(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = BreakPet.Choice(rawValue: raw) else { return }
        BreakPet.choice = choice
    }

    @objc private func togglePosture() {
        scheduler.setPostureEnabled(!scheduler.config.postureEnabled)
        if !scheduler.config.postureEnabled { nudges.hide(.posture) }
    }

    @objc private func takeBreakNow() { scheduler.startBreak(manual: true) }
    @objc private func resetTimer() { scheduler.resetCycle() }
    @objc private func resume() { scheduler.resume() }

    @objc private func pauseFor(_ sender: NSMenuItem) {
        scheduler.pause(until: Date().addingTimeInterval(TimeInterval(sender.tag * 60)))
    }

    @objc private func pauseUntilTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!)
        scheduler.pause(until: tomorrow)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove Healthy Pops.app to /Applications and try again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
