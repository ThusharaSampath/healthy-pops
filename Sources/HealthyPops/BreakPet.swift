import SwiftUI

/// A small cat or dog that turns up during a break or next to a reminder and does one cute thing
/// that fits it, saying something now and then on breaks. Each appearance picks a different coat,
/// entrance side and activity from the last one. Drawn in code.
struct BreakPet: View {
    /// Distance from the bottom of the view to the pet's paws.
    let groundInset: CGFloat
    /// One appearance's pet, picked when it's shown. Views are rebuilt every tick,
    /// so nothing may be picked here.
    let cast: Cast
    /// Happy reaction, e.g. after a glass of water is logged.
    var cheer = false

    enum Choice: String, CaseIterable {
        case both, cats, dogs, off

        var title: String {
            switch self {
            case .both: return "Cats & Dogs"
            case .cats: return "Cats"
            case .dogs: return "Dogs"
            case .off: return "Off"
            }
        }
    }

    private static let choiceKey = "breakPet"
    static var choice: Choice {
        get {
            let defaults = UserDefaults.standard
            if let raw = defaults.string(forKey: choiceKey), let choice = Choice(rawValue: raw) { return choice }
            // Before dogs, there was only an on/off "Break Cat" switch.
            if defaults.object(forKey: "breakCat") as? Bool == false { return .off }
            return .both
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: choiceKey) }
    }

    final class Cast {
        let coat: PetCoat
        let show: PetShow
        let start = Date()

        /// The pet for an eye break; nil when pets are switched off.
        convenience init?(choice: Choice, water: Bool) {
            guard let species = Self.species(for: choice) else { return nil }
            let entrance = BreakPet.pickFresh(PetShow.Entrance.allCases, key: "breakPetLastEntrance", id: \.rawValue)
            let action = BreakPet.pickFresh(PetShow.Action.all(species), key: "breakPetLastAction.\(species.rawValue)",
                                            id: \.rawValue)
            self.init(species: species, show: PetShow(species: species, entrance: entrance, action: action, water: water))
        }

        /// A small pet that steps out from behind a reminder and acts it out; nil when pets are switched off.
        convenience init?(choice: Choice, nudge: NudgeKind) {
            guard let species = Self.species(for: choice) else { return nil }
            let action: PetShow.Action
            switch nudge {
            case .water: action = .drink
            case .posture: action = .sitTall
            case .custom: action = .wave
            }
            self.init(species: species, show: PetShow(species: species, entrance: .left, action: action, water: false,
                                                      scale: 0.6, talks: false))
        }

        private init(species: PetCoat.Species, show: PetShow) {
            coat = BreakPet.pickFresh(PetCoat.all(species), key: "breakPetLastCoat.\(species.rawValue)", id: \.name)
            self.show = show
        }

        /// Cats & Dogs takes turns.
        private static func species(for choice: Choice) -> PetCoat.Species? {
            let species: PetCoat.Species
            switch choice {
            case .off: return nil
            case .cats: species = .cat
            case .dogs: species = .dog
            case .both:
                let last = UserDefaults.standard.string(forKey: "breakPetLastSpecies")
                species = last == PetCoat.Species.cat.rawValue ? .dog : .cat
            }
            UserDefaults.standard.set(species.rawValue, forKey: "breakPetLastSpecies")
            return species
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                scene(t: context.date.timeIntervalSince(cast.start), in: geo.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func scene(t: Double, in size: CGSize) -> some View {
        let show = cast.show
        let groundY = size.height - groundInset
        var frame = show.frame(at: t, width: size.width, groundY: groundY)
        if cheer { show.cheer(&frame, t: t, groundY: groundY) }
        let pose = frame.pose
        let petSize = show.size
        let k = show.scale
        let stretch = 1 + (1 - pose.squash) * 0.8
        let headTop = show.toScene(PetFigure.headTop(pose), pose: pose, groundY: groundY)
        let bubbleX = min(max(headTop.x, 170), size.width - 170)

        return ZStack {
            if let string = frame.string {
                Path { p in
                    p.move(to: string.0)
                    p.addLine(to: string.1)
                }
                .stroke(Color.white.opacity(0.75), lineWidth: 1.2)
            }

            PetFigure(pose: pose, coat: cast.coat, time: t)
                .frame(width: petSize.width, height: petSize.height)
                .scaleEffect(x: (pose.facingRight ? 1 : -1) * stretch, y: pose.squash, anchor: .bottom)
                .offset(y: pose.lift)
                // Everything below the ground line is hidden, so the pet can rise from behind the Dock.
                .frame(width: petSize.width, height: groundY, alignment: .bottom)
                .clipped()
                .position(x: pose.x, y: groundY / 2)

            if let bowl = frame.bowl {
                WaterBowl()
                    .frame(width: 30 * k, height: 14 * k)
                    .position(x: bowl.x, y: groundY - 7 * k)
            }

            if let box = frame.box {
                CardboardBox()
                    .frame(width: 104 * k, height: 44 * k)
                    .scaleEffect(box.progress, anchor: .bottom)
                    .position(x: box.x, y: groundY - 22 * k)
            }

            ForEach(Array(frame.props.enumerated()), id: \.offset) { _, prop in
                Text(prop.text)
                    .font(.system(size: prop.size, weight: .heavy, design: .rounded))
                    .foregroundStyle(prop.color)
                    .shadow(color: prop.glow ?? .clear, radius: prop.glow == nil ? 0 : 6)
                    .scaleEffect(x: prop.scaleX, y: 1)
                    .rotationEffect(.radians(prop.rotation))
                    .opacity(prop.opacity)
                    .position(prop.position)
            }

            if let bubble = frame.bubble {
                SpeechBubble(text: bubble.text, tailOffset: headTop.x - bubbleX)
                    .scaleEffect(0.7 + 0.3 * bubble.progress, anchor: .bottom)
                    .opacity(min(1, bubble.progress))
                    .frame(width: 340, height: 140, alignment: .bottom)
                    .position(x: bubbleX, y: headTop.y - 14 - 70)
            }
        }
    }

    /// Random pick that differs from the previous one, so consecutive appearances look different.
    fileprivate static func pickFresh<T>(_ all: [T], key: String, id: (T) -> String) -> T {
        let last = UserDefaults.standard.string(forKey: key)
        let pick = all.filter { id($0) != last }.randomElement() ?? all[0]
        UserDefaults.standard.set(id(pick), forKey: key)
        return pick
    }
}

// MARK: - Props drawn in code

/// Open cardboard box, flaps out. Drawn over the cat so it looks like it's sitting inside.
struct CardboardBox: View {
    var body: some View {
        Canvas { ctx, size in
            // The box itself is the middle 80% of the width; the flaps stick out past it.
            let w = size.width * 0.8, h = size.height * 0.78
            let x0 = (size.width - w) / 2, y0 = size.height - h
            let flap = Color(hex: 0xD9A86C)
            var left = Path()
            left.addLines([CGPoint(x: x0, y: y0), CGPoint(x: x0 - w * 0.12, y: y0 - h * 0.28),
                           CGPoint(x: x0 + w * 0.22, y: y0 - h * 0.3), CGPoint(x: x0 + w * 0.3, y: y0)])
            left.closeSubpath()
            var right = Path()
            right.addLines([CGPoint(x: x0 + w * 0.7, y: y0), CGPoint(x: x0 + w * 0.78, y: y0 - h * 0.3),
                            CGPoint(x: x0 + w * 1.12, y: y0 - h * 0.28), CGPoint(x: x0 + w, y: y0)])
            right.closeSubpath()
            ctx.fill(left, with: .color(flap))
            ctx.fill(right, with: .color(flap))
            ctx.fill(Path(CGRect(x: x0, y: y0 - 2, width: w, height: 5)), with: .color(Color(hex: 0x8E5E32)))
            ctx.fill(Path(roundedRect: CGRect(x: x0, y: y0 + 2, width: w, height: h - 2), cornerRadius: 3),
                     with: .color(Color(hex: 0xC9935A)))
            ctx.fill(Path(CGRect(x: x0 + w * 0.42, y: y0 + 2, width: w * 0.16, height: h * 0.45)),
                     with: .color(Color(hex: 0xE2C08F).opacity(0.8)))
        }
    }
}

/// Small blue water bowl for the water reminder.
struct WaterBowl: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var bowl = Path()
            bowl.addLines([CGPoint(x: 0, y: h * 0.3), CGPoint(x: w, y: h * 0.3),
                           CGPoint(x: w * 0.84, y: h), CGPoint(x: w * 0.16, y: h)])
            bowl.closeSubpath()
            ctx.fill(bowl, with: .color(Color(hex: 0x4F86EC)))
            ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h * 0.6)), with: .color(Color(hex: 0x7FA9F5)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.1, y: h * 0.1, width: w * 0.8, height: h * 0.4)),
                     with: .color(Color(hex: 0xA8E6FF)))
        }
    }
}

// MARK: - Speech bubble

struct SpeechBubble: View {
    let text: String
    /// Horizontal offset of the tail from the bubble's centre, so it points at the pet's head.
    let tailOffset: CGFloat

    private static let fill = Color(hex: 0xFFFDF8)

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.navyTop)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Self.fill))
            .overlay {
                GeometryReader { g in
                    let limit = g.size.width / 2 - 22
                    BubbleTail()
                        .fill(Self.fill)
                        .frame(width: 18, height: 10)
                        .position(x: g.size.width / 2 + min(max(tailOffset, -limit), limit), y: g.size.height + 4.5)
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
    }
}

private struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
