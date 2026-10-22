import SwiftUI

// MARK: - Timing helpers

private func smooth(_ x: Double) -> CGFloat {
    let t = min(max(x, 0), 1)
    return CGFloat(t * t * (3 - 2 * t))
}

/// 0 → 1 over `dur` seconds from `start`.
private func ramp(_ t: Double, _ start: Double, _ dur: Double) -> CGFloat { smooth((t - start) / dur) }

/// Up over `fade`, held, and back down so it ends at `start + dur`.
private func pulse(_ t: Double, _ start: Double, _ dur: Double, _ fade: Double) -> CGFloat {
    ramp(t, start, fade) * (1 - ramp(t, start + dur - fade, fade))
}

extension CGPoint {
    func moved(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

// MARK: - Pose, props, frame

struct PetPose {
    enum Eyes { case open, happy, closed }

    var x: CGFloat
    var facingRight: Bool
    var walking = false
    /// Floating down on the balloon: legs paddle, floppy ears fly up.
    var airborne = false
    /// Distance walked so far, in drawing units; drives the leg cycle so paws don't slide.
    var distance: CGFloat = 0
    /// Vertical offset from standing on the ground: negative is up in the air, positive is below the ground.
    var lift: CGFloat = 0
    /// 1 is normal; less is squashed flat (landing).
    var squash: CGFloat = 1
    /// Blend amounts from standing toward sitting, lying (loaf), a play-bow stretch and sitting up tall.
    var sit: CGFloat = 0
    var lie: CGFloat = 0
    var bow: CGFloat = 0
    var upright: CGFloat = 0
    /// Near front paw raised (0...1) toward `pawAngle`.
    var pawUp: CGFloat = 0
    var pawAngle: CGFloat = -2.4
    /// Raise from the shoulder instead of the elbow, for waving and reaching up.
    var pawHigh: CGFloat = 0
    /// Front paws taking turns: kneading (cats) or digging (dogs).
    var knead: CGFloat = 0
    var dig: CGFloat = 0
    /// Whole-body shake, like a wet dog.
    var shake: CGFloat = 0
    var headTilt: CGFloat = 0
    /// Where the pupils look, roughly -1...1 each way, in the pet's own facing direction.
    var gaze = CGPoint.zero
    var eyes = Eyes.open
    var mouthOpen: CGFloat = 0
    /// Cats: tongue tip while grooming or lapping. Dogs: tongue out, panting.
    var tongue = false
}

struct PetProp {
    var text: String
    var position: CGPoint
    var size: CGFloat
    var opacity: Double = 1
    var rotation: Double = 0
    var scaleX: CGFloat = 1
    var color: Color = .white
    var glow: Color?
}

struct PetFrame {
    var pose: PetPose
    var props: [PetProp] = []
    /// Balloon string, in screen coordinates.
    var string: (CGPoint, CGPoint)?
    var bubble: (text: String, progress: Double)?
    /// Cardboard box the cat sits in: centre on the ground, and how far it has popped in.
    var box: (x: CGFloat, progress: CGFloat)?
    /// Water bowl: centre of its base, on the ground.
    var bowl: CGPoint?
}

// MARK: - Show

/// Everything the pet does in one appearance: how it arrives, then one activity on a loop.
final class PetShow {
    enum Entrance: String, CaseIterable {
        case left, right, balloon, popUp
    }

    enum Action: String, CaseIterable {
        // Both
        case wave, stretch, nap, butterfly, hearts
        // Cats
        case groom, yarn, knead, box, laser, birdwatch
        // Dogs
        case fetch, zoomies, bark, sniff, dig, beg, shake, howl, headTilt
        // Reminder nudges only
        case drink, sitTall

        static func all(_ species: PetCoat.Species) -> [Action] {
            switch species {
            case .cat: return [.wave, .stretch, .nap, .butterfly, .hearts, .groom, .yarn, .knead, .box, .laser, .birdwatch]
            case .dog: return [.wave, .stretch, .nap, .butterfly, .hearts, .fetch, .zoomies, .bark, .sniff, .dig, .beg,
                               .shake, .howl, .headTilt]
            }
        }

        func line(_ species: PetCoat.Species) -> String {
            let dog = species == .dog
            switch self {
            case .wave: return dog ? "Paw! 🐾 Now look far away" : "Hi, human! 👋 Look far away for a bit"
            case .stretch: return dog ? "Big stretch! Your turn 🐶" : "Stretch with me! 🐾"
            case .nap: return dog ? "Zzz… rest your eyes too 😴" : "Shh… rest your eyes too 😴"
            case .butterfly: return "Ooh! Look at something far away 🦋"
            case .hearts: return dog ? "You're my favourite human 💗" : "I like you. Take a deep breath 💗"
            case .groom: return "Self-care o'clock. Blink slowly 😌"
            case .yarn: return "Playtime! Eyes off the screen 🧶"
            case .knead: return "Making biscuits. Relax your shoulders 😌"
            case .box: return "If I fits, I sits 📦 Sit back for a bit"
            case .laser: return "Eyes off the screen! Except the red dot 🔴"
            case .birdwatch: return "Bird! Look out the window too 🐦"
            case .fetch: return "Fetch break! Eyes off the screen 🎾"
            case .zoomies: return "Zoomies! Get up and move a bit 🏃"
            case .bark: return "Woof! Look at something far away 👀"
            case .sniff: return "Sniff sniff… take a little walk 🐾"
            case .dig: return "Digging for treats. Look away a bit 🦴"
            case .beg: return "Sitting pretty! Sit up straight too 🦴"
            case .shake: return "Shake it off! Stretch your arms 💦"
            case .howl: return "Awoooo! Time to rest your eyes 🌙"
            case .headTilt: return "Huh? Look at something far away 👀"
            case .drink: return "Drink some water 💧"
            case .sitTall: return "Sit up tall with me ✨"
            }
        }
    }

    let species: PetCoat.Species
    let entrance: Entrance
    let action: Action
    let scale: CGFloat
    var size: CGSize { CGSize(width: PetFigure.box.width * scale, height: PetFigure.box.height * scale) }
    private let lines: [String]

    private var plannedWidth: CGFloat = -1
    private var spot: CGFloat = 0
    private var startX: CGFloat = 0
    private var facingRight = true
    /// When the entrance is over and the activity starts.
    private var arrival: Double = 0

    /// Offsets below are tuned for the break overlay's size; `k` scales them for smaller pets.
    private var k: CGFloat { scale / 1.1 }
    private var dir: CGFloat { facingRight ? 1 : -1 }

    init(species: PetCoat.Species, entrance: Entrance, action: Action, water: Bool, scale: CGFloat = 1.1,
         talks: Bool = true) {
        self.species = species
        self.entrance = entrance
        self.action = action
        self.scale = scale
        var general = [
            "Look at something far away 👀",
            "Roll your shoulders back",
            "Unclench your jaw",
            species == .dog ? "Woof. Eyes off the screen, human" : "Meow. Eyes off the screen, human",
        ]
        if water { general += ["Drink some water 💧", "Have you had water lately? 💧"] }
        lines = talks ? [action.line(species)] + general.shuffled() : []
    }

    /// Converts a point in the pet's drawing box to screen coordinates.
    func toScene(_ p: CGPoint, pose: PetPose, groundY: CGFloat) -> CGPoint {
        let sign: CGFloat = pose.facingRight ? 1 : -1
        return CGPoint(x: pose.x + (p.x - PetFigure.box.width / 2) * scale * sign,
                       y: groundY + pose.lift - (PetFigure.box.height - p.y) * scale)
    }

    private func plan(width w: CGFloat) {
        plannedWidth = w
        // Keep the spot far enough from the edges for the bubble (and the zoomies) to fit.
        var lo = max(180, w * 0.12), hi = min(w - 180, w * 0.88)
        if hi <= lo { lo = w / 2; hi = w / 2 }
        let speed = 130 * k
        switch entrance {
        case .left:
            facingRight = true
            startX = -100 * k
            spot = .random(in: lo...min(hi, lo + w * 0.2))
            arrival = Double((spot - startX) / speed)
        case .right:
            facingRight = false
            startX = w + 100 * k
            spot = .random(in: max(lo, hi - w * 0.2)...hi)
            arrival = Double((startX - spot) / speed)
        case .balloon, .popUp:
            spot = .random(in: lo...hi)
            startX = spot
            facingRight = spot < w / 2   // face into the screen, where the toys are
            arrival = entrance == .balloon ? 3.3 : 1.2
        }
    }

    func frame(at t: Double, width: CGFloat, groundY: CGFloat) -> PetFrame {
        if abs(width - plannedWidth) > 1 { plan(width: width) }
        var frame = PetFrame(pose: PetPose(x: spot, facingRight: facingRight))
        enter(t, &frame, groundY: groundY)
        if t >= arrival {
            let tau = t - arrival
            act(tau, &frame.pose, groundY: groundY)
            decorate(tau, &frame, groundY: groundY)

            // A line every 9 s, each shown for 5.5 s.
            let since = tau - 0.5
            if since >= 0 && !lines.isEmpty {
                let i = Int(since / 9)
                let local = since - Double(i) * 9
                if local < 5.5 {
                    frame.bubble = (lines[i % lines.count], Self.pop(elapsed: local, remaining: 5.5 - local))
                }
            }
        }
        return frame
    }

    /// Happy reaction (e.g. a glass of water was logged): smiling eyes and hearts.
    func cheer(_ frame: inout PetFrame, t: Double, groundY: CGFloat) {
        frame.pose.eyes = .happy
        frame.pose.tongue = true
        frame.pose.mouthOpen = 0
        let top = toScene(PetFigure.headTop(frame.pose), pose: frame.pose, groundY: groundY)
        frame.props += floating("💗", from: top.moved(dir * 22 * k, 26 * k), after: 0, tau: t, count: 3, every: 0.5,
                                period: 1.5, drift: dir * 20 * k, size: 13 * k, grow: 3, rise: 40 * k)
    }

    // MARK: Entrances

    private func enter(_ t: Double, _ frame: inout PetFrame, groundY: CGFloat) {
        let petHeight = size.height
        switch entrance {
        case .left, .right:
            if t < arrival {
                frame.pose.x = startX + (spot - startX) * CGFloat(t / arrival)
                frame.pose.walking = true
                frame.pose.distance = abs(frame.pose.x - startX) / scale
                frame.pose.tongue = species == .dog
            }
        case .balloon:
            let height = groundY + petHeight * 1.6
            if t < 0.4 {
                frame.pose.lift = -height
            } else if t < 3.0 {
                let p = (t - 0.4) / 2.6
                frame.pose.lift = -height * CGFloat(pow(1 - p, 3))   // eases to a soft landing
                frame.pose.x = spot + CGFloat(sin(p * .pi * 3) * 18 * (1 - p))
                frame.pose.airborne = true
                frame.pose.eyes = .happy
                frame.pose.mouthOpen = 0.4
            } else if t < 3.3 {
                frame.pose.squash = 1 - 0.16 * CGFloat(sin((t - 3.0) / 0.3 * .pi))
            }
            // The balloon, held by a string on the pet's back, then let go to float away.
            if t < 3.0 {
                let anchor = toScene(PetFigure.backTop(frame.pose), pose: frame.pose, groundY: groundY)
                let balloon = CGPoint(x: anchor.x - dir * 8 + CGFloat(sin(t * 2.3)) * 4, y: anchor.y - 74)
                frame.string = (anchor, balloon.moved(0, 18))
                frame.props.append(PetProp(text: "🎈", position: balloon, size: 40, rotation: sin(t * 2.3) * 0.08))
            } else if t < 6 {
                let landed = PetPose(x: spot, facingRight: facingRight)
                let anchor = toScene(PetFigure.backTop(landed), pose: landed, groundY: groundY)
                let r = t - 3.0
                let balloon = CGPoint(x: anchor.x - dir * 8 + CGFloat(sin(r * 3)) * 12,
                                      y: anchor.y - 74 - CGFloat(r * 180 + r * r * 60))
                frame.props.append(PetProp(text: "🎈", position: balloon, size: 40,
                                           opacity: 1 - min(1, max(0, (r - 1.6) / 1.0)), rotation: sin(r * 3) * 0.12))
            }
        case .popUp:
            let depth = petHeight * 1.05
            if t < 0.6 {
                frame.pose.lift = depth
            } else if t < 1.15 {
                let q = (t - 0.6) / 0.55 - 1
                frame.pose.lift = depth * CGFloat(1 - (1 + 2.70158 * q * q * q + 1.70158 * q * q))   // slight hop
            }
            if t >= 0.6 && t < 2.0 {
                frame.pose.eyes = .happy
                frame.pose.mouthOpen = species == .dog ? 0 : 0.5
            }
            if t >= 1.0 && t < 2.0 {
                let top = toScene(PetFigure.headTop(frame.pose), pose: frame.pose, groundY: groundY)
                let p = (t - 1.0) / 1.0
                for (i, dx) in [-46.0, 50, -20].enumerated() {
                    let twinkle = 0.6 + 0.4 * sin(t * 14 + Double(i) * 2)
                    frame.props.append(PetProp(text: "✨",
                                               position: top.moved(CGFloat(dx), 30 - CGFloat(i) * 16 - CGFloat(p) * 10),
                                               size: 18, opacity: (1 - p) * twinkle))
                }
            }
        }
    }

    // MARK: Activities

    private func act(_ tau: Double, _ pose: inout PetPose, groundY: CGFloat) {
        let dog = species == .dog
        switch action {
        case .wave:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 7)
            let w = pulse(c, 0.7, 3.0, 0.35)
            pose.pawUp = w
            pose.pawHigh = 1
            pose.pawAngle = -2.25 + CGFloat(sin(tau * 9)) * 0.3
            if w > 0.5 {
                pose.eyes = .happy
                if !dog { pose.mouthOpen = 0.55 }
            }
            pose.tongue = dog
        case .stretch:
            let c = tau.truncatingRemainder(dividingBy: 9)
            pose.bow = pulse(c, 0.2, 3.0, 0.6)
            pose.sit = ramp(c, 4.0, 0.6) * (1 - ramp(c, 8.4, 0.5))
            pose.mouthOpen = pulse(c, 1.1, 1.6, 0.4)   // big yawn mid-stretch
            if pose.mouthOpen > 0.3 { pose.eyes = .closed }
            pose.tongue = dog && c > 4.6
        case .nap:
            pose.sit = ramp(tau, 0, 0.5)
            pose.lie = ramp(tau, 1.8, 1.0)
            pose.mouthOpen = pulse(tau, 0.6, 1.0, 0.3)
            if tau > 2.3 || pose.mouthOpen > 0.3 { pose.eyes = .closed }
        case .butterfly:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 5)
            let hop = pulse(c, 3.3, 0.8, 0.15)
            pose.sit *= 1 - 0.6 * hop
            if c >= 3.4 && c < 4.0 { pose.lift = -32 * k * CGFloat(sin((c - 3.4) / 0.6 * .pi)) }
            pose.pawUp = hop
            pose.pawHigh = 1
            pose.pawAngle = -2.1
            pose.mouthOpen = dog ? 0 : 0.5 * hop
            pose.tongue = dog
            look(at: butterfly(tau, groundY: groundY), &pose, groundY: groundY)
        case .hearts:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 3.2)
            if c > 1.6 && c < 2.5 { pose.eyes = .happy }   // slow blink: "I love you"
            pose.headTilt = CGFloat(sin(tau * 1.1)) * 0.1
            pose.tongue = dog
        case .groom:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 6)
            let g = pulse(c, 0.7, 3.4, 0.35)
            pose.pawUp = g
            pose.pawAngle = -2.75 + CGFloat(sin(tau * 7)) * 0.12
            pose.headTilt = 0.1 * g
            if g > 0.5 {
                pose.eyes = .happy
                pose.tongue = sin(tau * 7) > 0
            }
        case .yarn, .fetch:
            pose.gaze = CGPoint(x: 0.9, y: 0.6)
            pose.tongue = dog
            guard tau >= 1.2 else { return }
            let c = (tau - 1.2).truncatingRemainder(dividingBy: 5.2)
            pounce(c, start: 1.8, &pose)
            pose.sit = ramp(c, 2.3, 0.4) * (1 - ramp(c, 4.8, 0.4))
            if c > 2.5 && c < 3.6 { pose.eyes = .happy }
        case .knead:
            pose.sit = ramp(tau, 0, 0.5)
            pose.knead = ramp(tau, 0.6, 0.3)
            let c = tau.truncatingRemainder(dividingBy: 6)
            if c > 0.8 && c < 4.8 { pose.eyes = .happy }
            pose.headTilt = CGFloat(sin(tau * 0.9)) * 0.06
        case .box:
            // Hops into a box, then ducks down out of sight and pops back up.
            let boxX = spot + dir * 64 * k
            if tau < 0.45 {
                pose.gaze = CGPoint(x: 0.8, y: 0.5)
            } else if tau < 1.0 {
                let p = (tau - 0.45) / 0.55
                pose.x = spot + (boxX - spot) * CGFloat(p)
                pose.lift = (-40 * CGFloat(sin(p * .pi)) + 20 * smooth(p)) * k
                pose.airborne = p < 0.85
                pose.eyes = .happy
            } else {
                pose.x = boxX
                pose.sit = ramp(tau, 1.0, 0.3)
                let c = (tau - 1.0).truncatingRemainder(dividingBy: 5)
                let duck = pulse(c, 2.6, 1.6, 0.25)
                pose.lift = (20 + 30 * duck) * k
                if c > 4.1 { pose.eyes = .happy }
            }
        case .laser:
            let c = tau.truncatingRemainder(dividingBy: 3.2)
            pounce(c, start: 2.1, &pose)
            look(at: laserDot(tau, groundY: groundY), &pose, groundY: groundY)
            pose.headTilt *= 0.5
        case .birdwatch:
            pose.sit = ramp(tau, 0, 0.5)
            look(at: bird(tau, groundY: groundY), &pose, groundY: groundY)
            let c = tau.truncatingRemainder(dividingBy: 4)
            let chatter = pulse(c, 1.0, 1.8, 0.1)
            pose.mouthOpen = chatter * 0.45 * CGFloat(abs(sin(tau * 24)))
        case .zoomies:
            // Two laps back and forth at full speed, then a happy pant, on a loop.
            let range = 150 * k, speed = 380 * k
            let lap = Double(4 * range / speed)
            let c = tau.truncatingRemainder(dividingBy: lap * 2 + 2)
            pose.tongue = true
            if c < lap * 2 {
                let s = CGFloat(c) * speed
                let phase = (s + range).truncatingRemainder(dividingBy: 4 * range)
                let forward = phase < 2 * range
                let offset = forward ? phase - range : range - (phase - 2 * range)
                pose.x = spot + dir * offset
                pose.facingRight = forward == facingRight
                pose.walking = true
                pose.distance = s / scale
            } else {
                pose.eyes = .happy
            }
        case .bark:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 2.6)
            let woof = max(pulse(c, 0.3, 0.35, 0.08), pulse(c, 0.8, 0.35, 0.08))
            pose.mouthOpen = woof * 0.9
            pose.headTilt = -0.12 * woof
            pose.tongue = woof < 0.1
            if c > 1.4 && c < 2.2 { pose.eyes = .happy }
        case .sniff:
            // Nose down, sniffs a few steps forward, finds a bone, then sniffs back the other way.
            let c = tau.truncatingRemainder(dividingBy: 9)
            let back = c >= 4.5
            let leg = back ? c - 4.5 : c
            let travel = 60 * k * smooth(leg / 2.4)
            pose.x = back ? spot + dir * (60 * k - travel) : spot + dir * travel
            pose.facingRight = back ? !facingRight : facingRight
            pose.bow = 0.4 * ramp(leg, 0, 0.3) * (1 - ramp(leg, 2.3, 0.3))
            if leg < 2.4 {
                pose.walking = true
                pose.distance = CGFloat(leg) * 26 * k / scale
            }
            pose.sit = ramp(leg, 2.5, 0.4) * (1 - ramp(leg, 4.1, 0.35))
            pose.tongue = leg > 2.5
            if leg > 2.6 && leg < 4.0 { pose.eyes = .happy }
        case .dig:
            let c = tau.truncatingRemainder(dividingBy: 5)
            pose.bow = 0.55 * pulse(c, 0, 3.1, 0.3)
            pose.dig = pulse(c, 0.3, 2.6, 0.2)
            pose.sit = ramp(c, 3.0, 0.4) * (1 - ramp(c, 4.6, 0.4))
            if c > 3.2 {
                pose.eyes = .happy
                pose.tongue = true
            }
        case .beg:
            pose.upright = ramp(tau, 0, 0.6)
            let c = tau.truncatingRemainder(dividingBy: 3.6)
            pose.lift = -10 * k * pulse(c, 2.4, 0.5, 0.12)   // little hop for the treat
            pose.tongue = true
            if c > 2.3 && c < 3.1 { pose.eyes = .happy }
            pose.gaze = CGPoint(x: 0.1, y: -0.8)
        case .shake:
            let c = tau.truncatingRemainder(dividingBy: 4.2)
            pose.shake = pulse(c, 0.4, 1.4, 0.12)
            if pose.shake > 0.3 {
                pose.eyes = .closed
            } else if c > 1.9 && c < 3.4 {
                pose.eyes = .happy
                pose.tongue = true
            }
        case .howl:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 4.5)
            let h = pulse(c, 0.5, 2.6, 0.4)
            pose.headTilt = -0.5 * h
            pose.mouthOpen = 0.6 * h
            if h > 0.5 { pose.eyes = .closed }
        case .headTilt:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 3.4)
            let side: CGFloat = c < 1.7 ? 1 : -1
            pose.headTilt = side * 0.35 * pulse(c.truncatingRemainder(dividingBy: 1.7), 0.15, 1.4, 0.25)
        case .drink:
            pose.bow = 0.8 * ramp(tau, 0, 0.4)
            pose.tongue = sin(tau * 10) > -0.2   // lapping
            pose.eyes = .happy
        case .sitTall:
            pose.upright = ramp(tau, 0, 0.5)
            pose.headTilt = -0.08 * ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 3)
            if c > 1.8 && c < 2.6 { pose.eyes = .happy }
            pose.tongue = dog
        }
    }

    /// Crouch with a wiggle, then pounce with a paw out, starting at `start` seconds into the cycle.
    private func pounce(_ c: Double, start: Double, _ pose: inout PetPose) {
        pose.bow = ramp(c, start - 1.8, 0.4) * 0.75 * (1 - ramp(c, start, 0.25))
        if c < start && c > start - 1.2 { pose.lift = CGFloat(sin(c * 28)) * 0.8 }
        if c >= start && c < start + 0.5 { pose.lift = -26 * k * CGFloat(sin((c - start) / 0.5 * .pi)) }
        pose.pawUp = pulse(c, start, 0.6, 0.15)
        pose.pawAngle = -1.9
    }

    /// Points eyes and head at something on screen.
    private func look(at target: CGPoint, _ pose: inout PetPose, groundY: CGFloat) {
        let head = toScene(PetFigure.rig(for: pose).head, pose: pose, groundY: groundY)
        let dx = (target.x - head.x) * (pose.facingRight ? 1 : -1), dy = target.y - head.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        pose.gaze = CGPoint(x: dx / len, y: dy / len)
        pose.headTilt = 0.2 * (dy / len)
    }

    // MARK: Props

    private func decorate(_ tau: Double, _ frame: inout PetFrame, groundY: CGFloat) {
        let pose = frame.pose
        let top = toScene(PetFigure.headTop(pose), pose: pose, groundY: groundY)
        let side: CGFloat = pose.facingRight ? 1 : -1
        switch action {
        case .nap:
            frame.props += floating("z", from: top.moved(dir * 34 * k, 26 * k), after: 2.6, tau: tau, count: 3, every: 0.9,
                                    period: 2.7, drift: dir * 30 * k, size: 13 * k, grow: 6 * k, rise: 70 * k)
        case .hearts:
            frame.props += floating("💗", from: top.moved(dir * 40 * k, 30 * k), after: 0.6, tau: tau, count: 3, every: 1.1,
                                    period: 3.3, drift: dir * 34 * k, size: 15 * k, grow: 4 * k, rise: 70 * k)
        case .knead:
            frame.props += floating("prr", from: top.moved(dir * 40 * k, 50 * k), after: 1.0, tau: tau, count: 2, every: 1.3,
                                    period: 2.6, drift: dir * 24 * k, size: 12 * k, grow: 2, rise: 40 * k)
        case .bark:
            let c = tau.truncatingRemainder(dividingBy: 2.6)
            for start in [0.3, 0.8] {
                let since = c - start
                guard since > 0 && since < 1.1 else { continue }
                frame.props.append(PetProp(text: "Woof!",
                                           position: top.moved(dir * (48 + CGFloat(since) * 14) * k, (22 - CGFloat(since) * 26) * k),
                                           size: 15 * k, opacity: 1 - since / 1.1, rotation: Double(-dir) * 0.15))
            }
        case .howl:
            let c = tau.truncatingRemainder(dividingBy: 4.5)
            if c > 0.9 && c < 3.2 {
                let p = CGFloat((c - 0.9) / 2.3)
                frame.props.append(PetProp(text: "Awoo~", position: top.moved(dir * (40 + p * 30) * k, (10 - p * 34) * k),
                                           size: (14 + p * 4) * k, opacity: Double(min(1, (1 - p) * 3)),
                                           rotation: Double(-dir) * 0.2))
                frame.props.append(PetProp(text: "🎵", position: top.moved(dir * (10 + p * 20) * k, (-6 - p * 40) * k),
                                           size: 14 * k, opacity: Double(1 - p)))
            }
        case .headTilt:
            let c = tau.truncatingRemainder(dividingBy: 3.4)
            let tilt: CGFloat = c < 1.7 ? 1 : -1
            let shown = pulse(c.truncatingRemainder(dividingBy: 1.7), 0.3, 1.2, 0.2)
            frame.props.append(PetProp(text: "?", position: top.moved(side * tilt * 34 * k, 16 * k),
                                       size: 22 * k, opacity: Double(shown), rotation: Double(side * tilt) * 0.25))
        case .yarn, .fetch:
            let ball = ballPosition(tau)
            let tennis = action == .fetch
            frame.props.append(PetProp(text: tennis ? "🎾" : "🧶",
                                       position: CGPoint(x: spot + dir * ball.x * k,
                                                         y: groundY - (tennis ? 11 : 13) * k - ball.hop * (tennis ? 1.6 : 1) * k),
                                       size: (tennis ? 22 : 26) * k, rotation: Double(dir * ball.x / 13)))
        case .butterfly:
            let flap = 0.45 + 0.55 * abs(sin(tau * 16))
            let heading: CGFloat = cos(tau * 0.8) >= 0 ? dir : -dir
            frame.props.append(PetProp(text: "🦋", position: butterfly(tau, groundY: groundY), size: 24 * k,
                                       scaleX: CGFloat(flap) * -heading))
        case .box:
            frame.box = (spot + dir * 64 * k, smooth(tau / 0.35))
        case .laser:
            frame.props.append(PetProp(text: "●", position: laserDot(tau, groundY: groundY), size: 11 * k,
                                       color: Color(hex: 0xFF2D3D), glow: Color(hex: 0xFF2D3D)))
        case .birdwatch:
            let heading: CGFloat = dir   // flies the way the cat faces
            frame.props.append(PetProp(text: "🐦", position: bird(tau, groundY: groundY), size: 22 * k,
                                       scaleX: -heading))
            let c = tau.truncatingRemainder(dividingBy: 4)
            if c > 1.0 && c < 2.8 {
                frame.props.append(PetProp(text: "ek ek", position: top.moved(dir * 44 * k, 30 * k), size: 12 * k,
                                           opacity: Double(pulse(c, 1.0, 1.8, 0.2)), rotation: Double(-dir) * 0.15))
            }
        case .sniff:
            let c = tau.truncatingRemainder(dividingBy: 9)
            let leg = c >= 4.5 ? c - 4.5 : c
            let nose = toScene(PetFigure.rig(for: pose).head.moved(18, 4), pose: pose, groundY: groundY)
            if leg < 2.4 {
                let blink = (leg * 1.6).truncatingRemainder(dividingBy: 1)
                frame.props.append(PetProp(text: "sniff", position: nose.moved(side * 14 * k, CGFloat(-10 - blink * 14) * k),
                                           size: 11 * k, opacity: 1 - blink))
            } else {
                frame.props.append(bone(at: CGPoint(x: nose.x + side * 6 * k, y: groundY - 7 * k),
                                        progress: pulse(leg, 2.4, 2.0, 0.25)))
            }
        case .dig:
            let c = tau.truncatingRemainder(dividingBy: 5)
            let paws = toScene(CGPoint(x: 96, y: 98), pose: pose, groundY: groundY)
            if pose.dig > 0.2 {
                for i in 0..<7 {
                    let p = CGFloat((tau * 1.8 + Double(i) / 7).truncatingRemainder(dividingBy: 1))
                    frame.props.append(PetProp(text: "●", position: paws.moved(-side * (6 + 80 * p) * k, -70 * p * (1 - p) * 4 * k / 2),
                                               size: CGFloat(5 + i % 3) * k, opacity: Double((1 - p) * pose.dig),
                                               color: Color(hex: i % 2 == 0 ? 0x8B5A2B : 0xA8743F)))
                }
            }
            frame.props.append(bone(at: CGPoint(x: spot + dir * 70 * k, y: groundY - 7 * k), progress: pulse(c, 3.1, 1.8, 0.25)))
        case .beg:
            frame.props.append(PetProp(text: "🦴", position: top.moved(dir * 8 * k, CGFloat(-12 + 4 * sin(tau * 3)) * k),
                                       size: 20 * k, rotation: 0.4))
        case .shake:
            let c = tau.truncatingRemainder(dividingBy: 4.2)
            let body = toScene(PetFigure.rig(for: pose).body, pose: pose, groundY: groundY)
            if pose.shake > 0.2 {
                for i in 0..<8 {
                    let angle = Double(i) / 8 * 2 * .pi + 0.3
                    let p = CGFloat(((c - 0.4) * 2.2 + Double(i) * 0.13).truncatingRemainder(dividingBy: 1))
                    let reach = (24 + 60 * p) * k
                    frame.props.append(PetProp(text: "💧",
                                               position: body.moved(CGFloat(cos(angle)) * reach, (CGFloat(sin(angle)) * 0.7 - 0.3) * reach),
                                               size: 10 * k, opacity: Double((1 - p) * pose.shake)))
                }
            }
        case .drink:
            frame.bowl = toScene(CGPoint(x: 120, y: PetFigure.box.height), pose: pose, groundY: groundY)
            if let bowl = frame.bowl {
                let p = CGFloat((tau * 1.3).truncatingRemainder(dividingBy: 1))
                frame.props.append(PetProp(text: "💧", position: bowl.moved(side * 8 * k * p, (-16 - 18 * p) * k),
                                           size: 9 * k, opacity: Double(1 - p)))
            }
        case .sitTall:
            for (i, dx) in [-30.0, 34, 4].enumerated() {
                let twinkle = 0.5 + 0.5 * sin(tau * 5 + Double(i) * 2.1)
                frame.props.append(PetProp(text: "✨", position: top.moved(CGFloat(dx) * k, CGFloat(14 - i * 10) * k),
                                           size: 13 * k, opacity: twinkle))
            }
        case .wave, .stretch, .groom, .zoomies:
            break
        }
    }

    private func bone(at p: CGPoint, progress: CGFloat) -> PetProp {
        PetProp(text: "🦴", position: p.moved(0, (1 - progress) * 10 * k), size: 20 * k * max(0.01, progress),
                opacity: Double(progress), rotation: 0.2)
    }

    /// Repeating text that floats up and fades (z's, hearts, purrs).
    private func floating(_ text: String, from: CGPoint, after start: Double, tau: Double, count: Int, every: Double,
                          period: Double, drift: CGFloat, size: CGFloat, grow: CGFloat, rise: CGFloat) -> [PetProp] {
        (0..<count).compactMap { i in
            let since = tau - start - Double(i) * every
            guard since > 0 else { return nil }
            let ph = since.truncatingRemainder(dividingBy: period)
            let p = CGFloat(ph / period)
            return PetProp(text: text,
                           position: from.moved(drift * p + CGFloat(sin(ph * 3 + Double(i))) * 5 * k, -p * rise),
                           size: size + grow * p,
                           opacity: (1 - Double(p)) * min(1, ph * 4))
        }
    }

    /// Ball distance in front of the pet (overlay units), and how high it bounces.
    private func ballPosition(_ tau: Double) -> (x: CGFloat, hop: CGFloat) {
        if tau < 1.2 { return (300 - 220 * CGFloat(1 - pow(1 - tau / 1.2, 2)), 0) }   // rolls in
        let c = (tau - 1.2).truncatingRemainder(dividingBy: 5.2)
        switch c {
        case ..<2.05:
            return (80, 0)
        case ..<3.05:   // batted away
            let p = (c - 2.05) / 1.0
            return (80 + 140 * CGFloat(1 - pow(1 - p, 2)), 16 * CGFloat(sin(min(p * 2, 1) * .pi)))
        case ..<3.6:
            return (220, 0)
        case ..<5.0:    // rolls back
            return (220 - 140 * smooth((c - 3.6) / 1.4), 0)
        default:
            return (80, 0)
        }
    }

    private func butterfly(_ tau: Double, groundY: CGFloat) -> CGPoint {
        let hover = CGPoint(x: spot + dir * (60 + 45 * CGFloat(sin(tau * 0.8))) * k,
                            y: groundY - size.height * 1.3 + 22 * k * CGFloat(sin(tau * 1.9)))
        let from = CGPoint(x: spot + dir * 420 * k, y: groundY - 380 * k)
        return .lerp(from, hover, smooth(tau / 1.6))
    }

    /// Jittery red dot on the floor that zips away whenever the cat pounces.
    private func laserDot(_ tau: Double, groundY: CGFloat) -> CGPoint {
        let c = tau.truncatingRemainder(dividingBy: 3.2)
        var x = 90 + 40 * sin(tau * 2.3) + 22 * sin(tau * 5.1)
        x += 150 * Double(smooth((c - 2.2) / 0.3))
        return CGPoint(x: spot + dir * CGFloat(x) * k, y: groundY - 4 * k)
    }

    /// A bird flying across above the cat, again and again.
    private func bird(_ tau: Double, groundY: CGFloat) -> CGPoint {
        let p = (tau / 6).truncatingRemainder(dividingBy: 1)
        return CGPoint(x: spot + dir * CGFloat(-320 + 640 * p) * k,
                       y: groundY - size.height * 2.1 + 16 * k * CGFloat(sin(tau * 4)))
    }

    /// Springy pop-in over 0.35 s (overshoots slightly past 1), fade-out over the last 0.25 s.
    private static func pop(elapsed: Double, remaining: Double) -> Double {
        let p = min(max(elapsed / 0.35, 0), 1) - 1
        let easeOutBack = 1 + 2.70158 * p * p * p + 1.70158 * p * p
        return min(easeOutBack, remaining / 0.25)
    }
}
