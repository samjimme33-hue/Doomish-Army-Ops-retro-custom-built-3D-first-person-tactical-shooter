import Foundation

// MARK: - Deterministic noise

@inline(__always) func hash2(_ x: Int, _ y: Int, _ s: UInt32) -> UInt32 {
    var h = UInt32(truncatingIfNeeded: x &* 374761393)
    h = h &+ UInt32(truncatingIfNeeded: y &* 668265263)
    h = h &+ (s &* 2246822519)
    h = (h ^ (h >> 13)) &* 1274126177
    h = h ^ (h >> 16)
    return h
}

@inline(__always) func rnd01(_ x: Int, _ y: Int, _ s: UInt32) -> Double {
    Double(hash2(x, y, s) & 0xFFFFFF) / 16777216.0
}

struct RNG {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    /// 0..<1
    mutating func f() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    mutating func range(_ a: Int, _ b: Int) -> Int { a + int(b - a + 1) }
    mutating func chance(_ p: Double) -> Bool { f() < p }
}

// MARK: - Pixel canvas

struct Tex {
    var w: Int
    var h: Int
    var px: [UInt8]   // RGBA, origin top-left

    init(w: Int, h: Int) {
        self.w = w
        self.h = h
        self.px = [UInt8](repeating: 0, count: w * h * 4)
    }

    @inline(__always) mutating func put(_ x: Int, _ y: Int, _ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) {
        if x < 0 || y < 0 || x >= w || y >= h { return }
        let i = (y * w + x) * 4
        px[i] = UInt8(clamping: r); px[i + 1] = UInt8(clamping: g)
        px[i + 2] = UInt8(clamping: b); px[i + 3] = UInt8(clamping: a)
    }

    @inline(__always) func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        if x < 0 || y < 0 || x >= w || y >= h { return (0, 0, 0) }
        let i = (y * w + x) * 4
        return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
    }

    @inline(__always) func alphaAt(_ x: Int, _ y: Int) -> Int {
        if x < 0 || y < 0 || x >= w || y >= h { return 0 }
        return Int(px[(y * w + x) * 4 + 3])
    }

    mutating func fill(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) {
        for y in 0..<h { for x in 0..<w { put(x, y, r, g, b, a) } }
    }

    mutating func clear() { for i in stride(from: 0, to: px.count, by: 4) { px[i + 3] = 0 } }

    // tuple-colour conveniences
    mutating func put(_ x: Int, _ y: Int, _ c: (Int, Int, Int), _ a: Int = 255) {
        put(x, y, c.0, c.1, c.2, a)
    }

    mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: (Int, Int, Int), _ a: Int = 255) {
        rect(x, y, rw, rh, c.0, c.1, c.2, a)
    }

    mutating func outline(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: (Int, Int, Int)) {
        outline(x, y, rw, rh, c.0, c.1, c.2)
    }

    mutating func disc(_ cx: Int, _ cy: Int, _ rad: Int, _ c: (Int, Int, Int)) {
        disc(cx, cy, rad, c.0, c.1, c.2)
    }

    mutating func hline(_ x0: Int, _ x1: Int, _ y: Int, _ c: (Int, Int, Int), _ a: Int = 255) {
        hline(x0, x1, y, c.0, c.1, c.2, a)
    }

    mutating func vline(_ x: Int, _ y0: Int, _ y1: Int, _ c: (Int, Int, Int), _ a: Int = 255) {
        vline(x, y0, y1, c.0, c.1, c.2, a)
    }

    mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) {
        // A negative w/h (or a zero one) makes the clamped range below invert and
        // traps at runtime, which is how a sprite table built at startup can kill
        // the app before the window appears.
        guard rw > 0, rh > 0 else { return }
        let x1 = min(w, x + rw), y1 = min(h, y + rh)
        let x0 = max(0, x), y0 = max(0, y)
        guard x1 > x0, y1 > y0 else { return }
        for yy in y0..<y1 { for xx in x0..<x1 { put(xx, yy, r, g, b, a) } }
    }

    mutating func hline(_ x0: Int, _ x1: Int, _ y: Int, _ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) {
        let lo = min(x0, x1), hi = max(x0, x1)
        guard lo < hi else { return }
        for x in lo..<hi { put(x, y, r, g, b, a) }
    }

    mutating func vline(_ x: Int, _ y0: Int, _ y1: Int, _ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) {
        let lo = min(y0, y1), hi = max(y0, y1)
        guard lo < hi else { return }
        for y in lo..<hi { put(x, y, r, g, b, a) }
    }

    mutating func outline(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ r: Int, _ g: Int, _ b: Int) {
        hline(x, x + rw - 1, y, r, g, b); hline(x, x + rw - 1, y + rh - 1, r, g, b)
        vline(x, y, y + rh - 1, r, g, b); vline(x + rw - 1, y, y + rh - 1, r, g, b)
    }

    mutating func disc(_ cx: Int, _ cy: Int, _ rad: Int, _ r: Int, _ g: Int, _ b: Int) {
        guard rad >= 0 else { return }
        for y in (cy - rad)...(cy + rad) {
            for x in (cx - rad)...(cx + rad) {
                let dx = Double(x - cx), dy = Double(y - cy)
                if dx * dx + dy * dy <= Double(rad * rad) { put(x, y, r, g, b) }
            }
        }
    }

    /// Multiply every pixel's brightness by f (0...1.2) to fake lighting.
    mutating func shade(_ f: Double) {
        for i in stride(from: 0, to: px.count, by: 4) {
            guard px[i + 3] > 0 else { continue }
            px[i] = UInt8(clamping: Int(Double(px[i]) * f))
            px[i + 1] = UInt8(clamping: Int(Double(px[i + 1]) * f))
            px[i + 2] = UInt8(clamping: Int(Double(px[i + 2]) * f))
        }
    }

    /// Light a circle region (used for lamps / glows). Transparent pixels stay
    /// transparent so glows can be used on sprites without boxing them in.
    mutating func glow(_ cx: Int, _ cy: Int, _ rad: Int, _ r: Int, _ g: Int, _ b: Int) {
        guard rad >= 0 else { return }
        for y in (cy - rad)...(cy + rad) {
            for x in (cx - rad)...(cx + rad) {
                let dx = Double(x - cx), dy = Double(y - cy)
                let d = (dx * dx + dy * dy).squareRoot()
                if d <= Double(rad) {
                    guard alphaAt(x, y) > 0 else { continue }
                    let f = 1.0 - d / Double(rad)
                    let (or_, og, ob) = rgb(x, y)
                    put(x, y, Int(Double(or_) + Double(r) * f * 0.6),
                           Int(Double(og) + Double(g) * f * 0.6),
                           Int(Double(ob) + Double(b) * f * 0.6))
                }
            }
        }
    }

    /// Add film grain. Pixels that are still fully transparent stay that way.
    mutating func noise(_ amount: Int, _ seed: UInt32) {
        for y in 0..<h { for x in 0..<w {
            guard alphaAt(x, y) > 0 else { continue }
            let n = Int(rnd01(x, y, seed) * Double(amount)) - amount / 2
            let (r, g, b) = rgb(x, y)
            put(x, y, r + n, g + n, b + n)
        } }
    }
}

// MARK: - Texture library

enum Sprite: Int {
    case imp, impAttack, impDie
    case brute, bruteAttack, bruteDie
    case soldier, soldierAttack, soldierDie
    case heavy, heavyAttack, heavyDie
    case medikit, stimpack, armor, blueArmor
    case bullets, shells, cells
    case shotgunPickup, chaingunPickup
    case rockets, riflePickup, launcherPickup
    case barrel, barrelFlash
    case rocketBall
    // ---- army additions ----
    case grenadier, grenadierAttack, grenadierDie
    case marksman, marksmanAttack, marksmanDie
    case rioter, rioterAttack, rioterDie
    case sawPickup, dmrPickup, sniperPickup
    case berserk, invuln, megahealth, ammoBox
    case secretWall

    /// One entry per VehicleDef id, plus a burnt-out hulk for each.
    /// Vehicles are keyed by id in `TexLib.vehicleTex` / `TexLib.vehicleWreckTex`
    /// rather than by enum case: Swift cannot add cases at runtime, and the
    /// synthetic raw values this used to invent silently collided with nil.
    case vehiclePlaceholder = 100
}

extension Sprite {
    /// Live vehicle sprite for a VehicleDef id.
    static func vehicle(_ id: String) -> Sprite { .vehiclePlaceholder }
}

enum TexLib {
    static let wallSize = 64
    static let wallCount = 7

    static let walls: [Tex] = {
        var out: [Tex] = []
        for i in 0..<wallCount { out.append(wallTexture(i)) }
        return out
    }()

    static let door: Tex = doorTexture()
    static let exit: Tex = exitTexture()
    static let floor: Tex = floorTexture()
    static let ceiling: Tex = ceilingTexture()
    static let sprites: [Sprite: Tex] = makeSprites()

    // ---- walls -------------------------------------------------------

    static func wallTexture(_ idx: Int) -> Tex {
        let n = wallSize
        var t = Tex(w: n, h: n)
        let seed = UInt32(idx &* 977 + 31)
        switch idx {
        case 0:  // grey tech plate
            t.fill(96, 96, 104)
            for y in stride(from: 0, to: n, by: 16) { t.hline(0, n - 1, y, 62, 62, 70) }
            for x in stride(from: 0, to: n, by: 16) { t.vline(x, 0, n - 1, 70, 70, 78) }
            for y in stride(from: 0, to: n, by: 16) { t.hline(0, n - 1, y + 1, 118, 118, 126) }
            for (cx, cy) in [(4, 4), (28, 4), (44, 4), (4, 28), (28, 28), (44, 28)] {
                t.disc(cx, cy, 2, 140, 140, 148); t.put(cx, cy, 60, 60, 66)
            }
            t.noise(18, seed)
        case 1:  // tan/marble panel
            t.fill(128, 106, 78)
            for y in stride(from: 0, to: n, by: 32) { t.hline(0, n - 1, y, 92, 74, 52) }
            for x in stride(from: 0, to: n, by: 32) { t.vline(x, 0, n - 1, 100, 82, 58) }
            for y in 0..<n { for x in 0..<n {
                let v = rnd01(x, y, seed)
                if v > 0.86 { let (r, g, b) = t.rgb(x, y); t.put(x, y, r + 26, g + 18, b + 6) }
            } }
            t.rect(8, 8, 48, 6, 148, 126, 92)
            t.noise(16, seed)
        case 2:  // red rock
            t.fill(112, 46, 40)
            for i in 0..<26 {
                let x = Int(rnd01(i, 3, seed) * Double(n))
                let y = Int(rnd01(i, 7, seed) * Double(n))
                var px2 = x, py2 = y
                for _ in 0..<24 {
                    let (r, g, b) = t.rgb(px2, py2)
                    t.put(px2, py2, r - 30, g - 16, b - 12)
                    px2 += Int(rnd01(px2, py2, seed) * 3.0) - 1
                    py2 += Int(rnd01(py2, px2, seed + 5) * 3.0) - 1
                    if px2 < 0 || py2 < 0 || px2 >= n || py2 >= n { break }
                }
            }
            t.noise(22, seed)
        case 3:  // blue metal with stripes
            t.fill(58, 78, 118)
            for y in stride(from: 0, to: n, by: 8) { t.hline(0, n - 1, y, 40, 56, 88) }
            for x in stride(from: 0, to: n, by: 21) { t.vline(x, 0, n - 1, 84, 108, 152) }
            t.rect(4, 4, 20, 20, 30, 44, 72); t.outline(4, 4, 20, 20, 110, 140, 190)
            t.rect(7, 7, 14, 14, 90, 160, 210)
            t.noise(14, seed)
        case 4:  // green pipes
            t.fill(56, 84, 56)
            for x in stride(from: 6, to: n, by: 16) {
                t.vline(x, 0, n - 1, 40, 60, 40); t.vline(x + 1, 0, n - 1, 96, 130, 96)
                for y in stride(from: 4, to: n, by: 24) { t.rect(x - 2, y, 7, 4, 120, 120, 110) }
            }
            t.noise(16, seed)
        case 5:  // dark bricks
            t.fill(74, 62, 58)
            for y in stride(from: 0, to: n, by: 8) {
                t.hline(0, n - 1, y, 48, 40, 38)
                let off = (y / 8) % 2 == 0 ? 0 : 16
                for x in stride(from: off, to: n + 32, by: 32) { t.vline(x % n, y, y + 7, 48, 40, 38) }
            }
            t.noise(20, seed)
        default: // orange/rust hazard
            t.fill(146, 96, 40)
            for y in 0..<n { for x in 0..<n {
                if ((x + y) / 8) % 2 == 0 { let (r, g, b) = t.rgb(x, y); t.put(x, y, r - 40, g - 28, b - 20) }
            } }
            t.rect(0, 28, n, 8, 40, 36, 34)
            t.noise(18, seed)
        }
        return t
    }

    static func doorTexture() -> Tex {
        let n = wallSize
        var t = Tex(w: n, h: n)
        t.fill(78, 72, 86)
        t.rect(0, 0, n, 6, 52, 48, 60)
        t.rect(0, n - 6, n, 6, 52, 48, 60)
        t.rect(2, 6, 28, 52, 96, 90, 104); t.outline(2, 6, 28, 52, 40, 36, 46)
        t.rect(34, 6, 28, 52, 96, 90, 104); t.outline(34, 6, 28, 52, 40, 36, 46)
        t.rect(14, 26, 36, 12, 26, 26, 34)
        t.glow(32, 32, 7, 255, 90, 60)
        t.rect(30, 30, 4, 4, 255, 200, 120)
        t.noise(12, 7)
        return t
    }

    static func exitTexture() -> Tex {
        let n = wallSize
        var t = Tex(w: n, h: n)
        t.fill(48, 44, 52)
        t.outline(4, 4, n - 8, n - 8, 150, 40, 30)
        t.rect(8, 8, n - 16, n - 16, 70, 20, 16)
        t.rect(20, 14, 24, 18, 26, 26, 30)
        t.glow(32, 30, 14, 255, 220, 90)
        t.rect(28, 40, 8, 14, 200, 200, 210)
        t.disc(14, 46, 4, 60, 230, 90)
        t.noise(10, 11)
        return t
    }

    static func floorTexture() -> Tex {
        let n = wallSize
        var t = Tex(w: n, h: n)
        t.fill(58, 56, 62)
        t.rect(0, 0, n, 1, 36, 34, 40); t.rect(0, 0, 1, n, 36, 34, 40)
        t.rect(0, n / 2, n, 1, 44, 42, 48); t.rect(n / 2, 0, 1, n, 44, 42, 48)
        for i in 0..<10 {
            let x = Int(rnd01(i, 1, 3) * Double(n)), y = Int(rnd01(i, 2, 5) * Double(n))
            t.rect(x, y, 2, 2, 72, 70, 78)
        }
        t.rect(20, 20, 24, 24, 40, 40, 46)
        for k in 0..<5 { t.hline(20, 44, 23 + k * 5, 58, 58, 66) }
        t.noise(16, 21)
        return t
    }

    static func ceilingTexture() -> Tex {
        let n = wallSize
        var t = Tex(w: n, h: n)
        t.fill(40, 42, 56)
        t.rect(0, 0, n, 2, 26, 28, 38); t.rect(0, 0, 2, n, 26, 28, 38)
        t.rect(14, 14, 36, 36, 52, 56, 72)
        t.outline(14, 14, 36, 36, 30, 32, 44)
        t.glow(32, 32, 15, 210, 210, 170)
        t.noise(12, 33)
        return t
    }

    // ---- sprites -----------------------------------------------------

    static func makeSprites() -> [Sprite: Tex] {
        var m: [Sprite: Tex] = [:]
        m[.imp] = impFrame(attack: false, dead: false)
        m[.impAttack] = impFrame(attack: true, dead: false)
        m[.impDie] = impFrame(attack: false, dead: true)
        m[.brute] = bruteFrame(attack: false, dead: false)
        m[.bruteAttack] = bruteFrame(attack: true, dead: false)
        m[.bruteDie] = bruteFrame(attack: false, dead: true)
        m[.soldier] = soldierFrame(attack: false, dead: false)
        m[.soldierAttack] = soldierFrame(attack: true, dead: false)
        m[.soldierDie] = soldierFrame(attack: false, dead: true)
        m[.heavy] = heavyFrame(attack: false, dead: false)
        m[.heavyAttack] = heavyFrame(attack: true, dead: false)
        m[.heavyDie] = heavyFrame(attack: false, dead: true)
        m[.medikit] = medikit(big: true)
        m[.stimpack] = medikit(big: false)
        m[.armor] = armorTex(blue: false)
        m[.blueArmor] = armorTex(blue: true)
        m[.bullets] = pickupBox(body: (196, 176, 48), top: (232, 216, 96), mark: "bullet")
        m[.shells] = pickupBox(body: (168, 56, 48), top: (208, 80, 64), mark: "shell")
        m[.cells] = pickupBox(body: (48, 96, 176), top: (80, 148, 230), mark: "cell")
        m[.rockets] = pickupBox(body: (58, 84, 58), top: (96, 132, 84), mark: "rocket")
        m[.shotgunPickup] = gunPickup(style: 0)
        m[.chaingunPickup] = gunPickup(style: 1)
        m[.riflePickup] = gunPickup(style: 2)
        m[.launcherPickup] = gunPickup(style: 3)
        m[.sawPickup] = gunPickup(style: 4)
        m[.dmrPickup] = gunPickup(style: 5)
        m[.sniperPickup] = gunPickup(style: 6)
        m[.grenadier] = grenadierFrame(attack: false, dead: false)
        m[.grenadierAttack] = grenadierFrame(attack: true, dead: false)
        m[.grenadierDie] = grenadierFrame(attack: false, dead: true)
        m[.marksman] = marksmanFrame(attack: false, dead: false)
        m[.marksmanAttack] = marksmanFrame(attack: true, dead: false)
        m[.marksmanDie] = marksmanFrame(attack: false, dead: true)
        m[.rioter] = rioterFrame(attack: false, dead: false)
        m[.rioterAttack] = rioterFrame(attack: true, dead: false)
        m[.rioterDie] = rioterFrame(attack: false, dead: true)
        m[.berserk] = powerOrb(body: (216, 60, 44), glow: (255, 190, 60), mark: "rage")
        m[.invuln] = powerOrb(body: (120, 150, 230), glow: (200, 230, 255), mark: "shield")
        m[.megahealth] = medikit(big: true, green: true)
        m[.ammoBox] = pickupBox(body: (92, 84, 48), top: (140, 128, 72), mark: "crate")
        m[.secretWall] = secretWallTex()
        m[.barrel] = barrelTex(burning: false)
        m[.barrelFlash] = barrelTex(burning: true)
        m[.rocketBall] = rocketBallTex()
        for v in Army.vehicles {
            vehicleTex[v.id] = vehicleSprite(v, dead: false)
            vehicleWreckTex[v.id] = vehicleSprite(v, dead: true)
        }
        return m
    }

    // ---- vehicles -----------------------------------------------------
    //
    // Vehicles are drawn as billboards like everything else, so the sprite has
    // to read as the *side* of the vehicle: hull low and wide, turret above it,
    // barrel running out to one side. Class drives the silhouette:
    //   light -> short hood, high cabin
    //   ifv   -> low sloped front, long hull
    //   mbt   -> heavy slab hull, big turret, long barrel
    //   spg   -> hull with a raised howitzer box
    //   air   -> fuselage, tail boom, skids, rotor disc

    /// Live vehicle body art, keyed by VehicleDef id. Filled by makeSprites().
    static var vehicleTex: [String: Tex] = [:]
    /// Burnt-out hulk art, keyed the same way.
    static var vehicleWreckTex: [String: Tex] = [:]

    static func vehicleSprite(_ v: VehicleDef, dead: Bool) -> Tex {
        let n = 64
        var t = Tex(w: n, h: n)
        t.clear()
        let base: (Int, Int, Int) = dead ? (46, 40, 34) : oliveBody(v.cls)
        let dark = shade3(base, 0.55)
        let lightC = shade3(base, 1.22)
        let glass = (120, 150, 165)
        let steel = (108, 112, 118)

        if dead {
            // burnt-out hulk: same silhouette, blackened and slumped
            t.rect(8, 40, 48, 14, base.0, base.1, base.2)
            t.rect(8, 40, 48, 4, dark.0, dark.1, dark.2)
            if v.cls == .air {
                t.rect(10, 46, 30, 6, base.0, base.1, base.2)
                t.rect(42, 52, 14, 3, dark.0, dark.1, dark.2)
                t.rect(6, 36, 4, 6, dark.0, dark.1, dark.2)
                t.rect(54, 36, 4, 6, dark.0, dark.1, dark.2)
                t.rect(6, 26, 52, 2, 70, 62, 52)
            } else {
                t.rect(20, 50, 26, 8, dark.0, dark.1, dark.2)
                t.rect(46, 50, 16, 4, steel.0, steel.1, steel.2)
            }
            t.noise(34, 907)
            t.shade(0.62)
            return t
        }

        switch v.cls {
        case .air:
            // fuselage
            t.rect(14, 30, 34, 12, base.0, base.1, base.2)
            t.rect(14, 30, 34, 3, lightC.0, lightC.1, lightC.2)
            t.rect(16, 33, 8, 6, glass.0, glass.1, glass.2)          // canopy
            // tail boom + fin
            t.rect(46, 32, 14, 4, base.0, base.1, base.2)
            t.rect(56, 40, 4, 12, base.0, base.1, base.2)
            // rotor mast + disc
            t.rect(30, 42, 4, 5, steel.0, steel.1, steel.2)
            t.rect(2, 45, 60, 3, 150, 150, 158, 190)
            t.rect(28, 43, 8, 2, 40, 40, 44)
            // stub wings + weapon pylons
            t.rect(18, 40, 28, 3, dark.0, dark.1, dark.2)
            t.rect(22, 36, 3, 5, steel.0, steel.1, steel.2)
            t.rect(38, 36, 3, 5, steel.0, steel.1, steel.2)
            // skids
            t.rect(12, 24, 3, 8, steel.0, steel.1, steel.2)
            t.rect(46, 24, 3, 8, steel.0, steel.1, steel.2)
            t.rect(8, 22, 46, 3, steel.0, steel.1, steel.2)

        case .mbt:
            // slab hull, wide and low
            t.rect(4, 34, 56, 18, base.0, base.1, base.2)
            t.rect(4, 34, 56, 4, lightC.0, lightC.1, lightC.2)
            t.rect(4, 48, 56, 4, dark.0, dark.1, dark.2)            // track run
            for i in 0..<5 { t.rect(8 + i * 11, 49, 7, 7, 36, 36, 32) }
            // turret
            t.rect(20, 46, 30, 10, lightC.0, lightC.1, lightC.2)
            t.rect(20, 52, 30, 3, dark.0, dark.1, dark.2)
            // long main gun
            t.rect(48, 47, 16, 4, steel.0, steel.1, steel.2)
            t.rect(60, 46, 4, 6, dark.0, dark.1, dark.2)
            // commander sight + stowage
            t.rect(24, 56, 6, 5, dark.0, dark.1, dark.2)
            t.rect(40, 56, 7, 4, 96, 84, 56)

        case .ifv:
            t.rect(6, 36, 50, 16, base.0, base.1, base.2)
            t.rect(6, 36, 50, 4, lightC.0, lightC.1, lightC.2)
            t.rect(6, 48, 50, 4, dark.0, dark.1, dark.2)
            for i in 0..<4 { t.rect(10 + i * 12, 49, 8, 7, 36, 36, 32) }
            // sloped glacis
            for i in 0..<6 { t.rect(50 - i, 36 + i, 2, 16 - i * 2, lightC.0, lightC.1, lightC.2) }
            // low turret with a chunky autocannon
            t.rect(24, 48, 24, 8, lightC.0, lightC.1, lightC.2)
            t.rect(46, 50, 14, 4, steel.0, steel.1, steel.2)
            t.rect(58, 49, 4, 6, dark.0, dark.1, dark.2)
            t.rect(20, 42, 6, 6, 40, 40, 44)                          // sight

        case .spg:
            t.rect(6, 34, 52, 16, base.0, base.1, base.2)
            t.rect(6, 34, 52, 4, lightC.0, lightC.1, lightC.2)
            t.rect(6, 48, 52, 4, dark.0, dark.1, dark.2)
            for i in 0..<4 { t.rect(10 + i * 12, 49, 8, 7, 36, 36, 32) }
            // raised fighting compartment
            t.rect(18, 48, 30, 12, lightC.0, lightC.1, lightC.2)
            t.rect(18, 56, 30, 3, dark.0, dark.1, dark.2)
            // howitzer, elevated
            for i in 0..<10 { t.rect(46 + i, 62 - i, 2, 3, steel.0, steel.1, steel.2) }

        case .light:
            t.rect(8, 38, 46, 14, base.0, base.1, base.2)
            t.rect(8, 38, 46, 3, lightC.0, lightC.1, lightC.2)
            t.rect(8, 50, 46, 3, dark.0, dark.1, dark.2)
            // wheels
            for cx in [14, 26, 40, 50] { t.disc(cx, 50, 5, 34, 34, 30) }
            // high cabin
            t.rect(16, 50, 24, 10, base.0, base.1, base.2)
            t.rect(18, 52, 8, 5, glass.0, glass.1, glass.2)
            t.rect(30, 52, 8, 5, glass.0, glass.1, glass.2)
            // roof hatch + gun ring
            t.rect(26, 60, 6, 3, dark.0, dark.1, dark.2)
            t.rect(28, 54, 3, 6, steel.0, steel.1, steel.2)
        }

        // hashValue is signed and routinely negative; UInt32(...) on a negative
        // Int traps, which would kill the app during startup texture building.
        t.noise(16, UInt32(truncatingIfNeeded: v.id.hashValue &+ 977))
        return t
    }

    /// Olive-drab family, tinted by class so armour reads at a glance.
    private static func oliveBody(_ cls: VehicleClass) -> (Int, Int, Int) {
        switch cls {
        case .light: return (108, 112, 74)
        case .ifv: return (98, 102, 68)
        case .mbt: return (92, 96, 62)
        case .spg: return (88, 92, 60)
        case .air: return (84, 90, 72)
        }
    }

    private static func shade3(_ c: (Int, Int, Int), _ f: Double) -> (Int, Int, Int) {
        (Int(min(255, Double(c.0) * f)), Int(min(255, Double(c.1) * f)), Int(min(255, Double(c.2) * f)))
    }

    static func impFrame(attack: Bool, dead: Bool) -> Tex {
        var t = Tex(w: 64, h: 64)
        t.clear()
        let flesh = (150, 84, 60), dark = (92, 46, 34), horn = (216, 200, 176)
        if dead {
            // slumped corpse
            t.disc(30, 40, 16, flesh)
            t.disc(22, 36, 8, flesh)
            t.put(20, 34, 255, 40, 30); t.put(24, 36, 255, 40, 30)
            t.rect(40, 36, 20, 12, dark)
            t.rect(8, 44, 18, 8, dark)
            t.noise(18, 5)
            t.shade(0.7)
            return t
        }
        // legs
        t.rect(22, 42, 8, 18, dark); t.rect(34, 42, 8, 18, dark)
        t.rect(20, 56, 12, 5, (52, 34, 26)); t.rect(32, 56, 12, 5, (52, 34, 26))
        // torso
        t.rect(22, 22, 20, 22, flesh)
        t.rect(22, 30, 20, 4, (120, 62, 44))
        t.rect(30, 22, 4, 22, dark)
        // arms
        if attack {
            t.rect(10, 16, 12, 6, flesh); t.rect(42, 16, 12, 6, flesh)
            t.rect(8, 16, 6, 14, flesh); t.rect(50, 16, 6, 14, flesh)
            t.rect(6, 8, 8, 10, dark); t.rect(50, 8, 8, 10, dark)
        } else {
            t.rect(16, 24, 6, 18, flesh); t.rect(42, 24, 6, 18, flesh)
            t.rect(14, 40, 8, 6, dark); t.rect(42, 40, 8, 6, dark)
        }
        // head + horns
        t.rect(25, 6, 14, 14, flesh)
        t.rect(25, 6, 14, 3, horn); t.rect(25, 17, 14, 3, horn)
        t.rect(27, 10, 3, 3, 255, 40, 30); t.rect(34, 10, 3, 3, 255, 40, 30)
        t.rect(29, 15, 6, 3, dark)
        t.noise(16, 9)
        return t
    }

    static func bruteFrame(attack: Bool, dead: Bool) -> Tex {
        var t = Tex(w: 64, h: 64)
        t.clear()
        let skin = (96, 118, 82), dark = (58, 74, 48), metal = (140, 146, 156)
        if dead {
            t.disc(32, 42, 20, skin)
            t.disc(20, 38, 10, skin)
            t.put(18, 36, 255, 60, 20); t.put(24, 38, 255, 60, 20)
            t.rect(44, 34, 16, 20, dark)
            t.noise(20, 17)
            t.shade(0.7)
            return t
        }
        t.rect(18, 40, 12, 22, dark); t.rect(34, 40, 12, 22, dark)
        t.rect(16, 58, 16, 6, (44, 40, 34)); t.rect(32, 58, 16, 6, (44, 40, 34))
        t.rect(16, 20, 32, 24, skin)
        t.rect(16, 28, 32, 5, metal)
        if attack {
            t.rect(6, 12, 12, 8, skin); t.rect(46, 12, 12, 8, skin)
            t.rect(4, 2, 10, 12, dark); t.rect(50, 2, 10, 12, dark)
        } else {
            t.rect(8, 22, 8, 22, skin); t.rect(48, 22, 8, 22, skin)
            t.rect(6, 40, 10, 8, dark); t.rect(48, 40, 10, 8, dark)
        }
        t.rect(22, 4, 20, 15, skin)
        t.rect(22, 4, 20, 4, metal)
        t.rect(25, 9, 4, 4, 255, 120, 20); t.rect(35, 9, 4, 4, 255, 120, 20)
        t.rect(28, 14, 8, 4, dark)
        t.noise(18, 23)
        return t
    }

    static func soldierFrame(attack: Bool, dead: Bool) -> Tex {
        var t = Tex(w: 64, h: 64)
        t.clear()
        let olive = (84, 92, 62), vest = (58, 64, 44), skin = (176, 132, 96)
        let kit = (46, 50, 40), metal = (150, 154, 162)
        if dead {
            t.disc(32, 42, 17, olive)
            t.rect(10, 40, 44, 12, vest)
            t.rect(14, 36, 8, 8, skin)
            t.put(16, 39, 200, 30, 20)
            t.rect(40, 38, 16, 8, kit)
            t.noise(18, 41)
            t.shade(0.7)
            return t
        }
        // legs
        t.rect(24, 40, 7, 20, vest); t.rect(33, 40, 7, 20, vest)
        t.rect(22, 56, 11, 5, kit); t.rect(31, 56, 11, 5, kit)
        // torso + webbing
        t.rect(22, 20, 20, 22, olive)
        t.rect(22, 28, 20, 5, kit)
        t.rect(24, 34, 7, 8, kit); t.rect(33, 34, 7, 8, kit)
        t.rect(22, 20, 20, 3, (108, 118, 80))
        // arms: raised with the rifle when firing
        if attack {
            t.rect(12, 14, 12, 6, olive); t.rect(40, 14, 12, 6, olive)
            t.rect(10, 18, 6, 10, skin); t.rect(48, 18, 6, 10, skin)
            t.rect(8, 22, 16, 4, kit)        // rifle body
            t.rect(20, 21, 8, 6, metal)      // magazine
            t.rect(6, 23, 6, 2, (40, 42, 46))
        } else {
            t.rect(16, 22, 6, 18, olive); t.rect(42, 22, 6, 18, olive)
            t.rect(14, 38, 8, 6, skin); t.rect(42, 38, 8, 6, skin)
            t.rect(12, 26, 40, 3, kit)      // rifle held low across the chest
            t.rect(44, 24, 6, 7, metal)
        }
        // helmet + face
        t.rect(26, 6, 12, 12, skin)
        t.rect(24, 4, 16, 6, olive)
        t.rect(24, 4, 16, 2, (112, 122, 84))
        t.rect(25, 10, 3, 3, 20, 20, 24); t.rect(34, 10, 3, 3, 20, 20, 24)
        t.rect(28, 15, 8, 2, (70, 60, 50))
        t.noise(16, 43)
        return t
    }

    static func heavyFrame(attack: Bool, dead: Bool) -> Tex {
        var t = Tex(w: 64, h: 64)
        t.clear()
        let armor = (72, 78, 92), dark = (44, 48, 58), metal = (168, 172, 182)
        let visor = (255, 150, 40)
        if dead {
            t.disc(32, 43, 20, armor)
            t.rect(8, 38, 48, 14, dark)
            t.rect(12, 32, 10, 8, visor)
            t.rect(44, 36, 14, 10, metal)
            t.noise(20, 47)
            t.shade(0.7)
            return t
        }
        t.rect(16, 38, 14, 24, dark); t.rect(34, 38, 14, 24, dark)
        t.rect(14, 58, 18, 6, (34, 36, 44)); t.rect(32, 58, 18, 6, (34, 36, 44))
        t.rect(14, 18, 36, 22, armor)          // bulky torso
        t.rect(14, 26, 36, 5, dark)
        t.rect(20, 32, 10, 8, dark); t.rect(34, 32, 10, 8, dark)
        t.rect(14, 18, 36, 3, metal)
        if attack {
            // shoulder-mounted minigun
            t.rect(4, 8, 12, 10, dark); t.rect(48, 8, 12, 10, dark)
            t.rect(2, 6, 20, 5, metal); t.rect(42, 6, 20, 5, metal)
            for i in 0..<3 { t.rect(2 + i * 6, 11, 4, 8, (30, 32, 38)) }
            t.rect(24, 30, 16, 8, metal)
        } else {
            t.rect(6, 20, 8, 22, armor); t.rect(50, 20, 8, 22, armor)
            t.rect(4, 38, 12, 9, dark); t.rect(48, 38, 12, 9, dark)
            t.rect(8, 24, 48, 4, metal)        // gun across the body
            t.rect(44, 22, 12, 8, (30, 32, 38))
        }
        t.rect(22, 4, 20, 14, dark)            // helm
        t.rect(22, 4, 20, 4, metal)
        t.rect(25, 10, 14, 6, visor)
        t.rect(27, 18, 10, 3, (30, 32, 38))
        t.noise(18, 53)
        return t
    }

    /// Glowing warhead used for rockets in flight.
    static func rocketBallTex() -> Tex {
        var t = Tex(w: 24, h: 24)
        t.clear()
        t.disc(12, 12, 6, 255, 200, 90)
        t.disc(12, 12, 4, 255, 250, 220)
        t.disc(9, 10, 2, 255, 255, 255)
        t.glow(12, 12, 11, 255, 120, 30)
        return t
    }

    static func medikit(big: Bool, green: Bool = false) -> Tex {
        var t = Tex(w: 32, h: 32)
        t.clear()
        let s = big ? 24 : 18
        let o = (32 - s) / 2
        t.rect(o, o, s, s, 208, 206, 200)
        t.outline(o, o, s, s, 70, 70, 70)
        t.rect(o + 2, o + 2, s - 4, 4, 236, 236, 230)
        let bar = s / 2 - 2
        let cross: (Int, Int, Int) = green ? (40, 190, 70) : (190, 40, 40)
        t.rect(16 - bar / 2, 16 - bar / 2, bar, bar * 2, cross)
        t.rect(16 - bar, 16 - bar / 2 + bar / 2, bar * 2, bar, cross)
        t.noise(10, 13)
        if green { t.glow(16, 16, 20, 60, 220, 90) }
        return t
    }

    /// Glowing powerup sphere. The `mark` picks the emblem painted on the face.
    static func powerOrb(body: (Int, Int, Int), glow: (Int, Int, Int), mark: String) -> Tex {
        var t = Tex(w: 32, h: 32)
        t.clear()
        t.disc(16, 16, 12, body)
        t.disc(16, 16, 9, (min(255, body.0 + 40), min(255, body.1 + 40), min(255, body.2 + 40)))
        switch mark {
        case "rage":
            // flame licks
            for i in 0..<4 {
                t.rect(12 + i * 2, 8 + (i % 2) * 3, 2, 8 - (i % 2) * 3, 255, 200, 70)
            }
            t.rect(13, 16, 6, 8, 255, 150, 50)
        default:
            // shield chevron
            t.rect(10, 12, 12, 2, 240, 246, 255)
            t.rect(12, 15, 8, 2, 240, 246, 255)
            t.rect(14, 18, 4, 4, 240, 246, 255)
        }
        t.glow(16, 16, 15, glow.0, glow.1, glow.2)
        return t
    }

    /// A false wall: solid, but subtly different from the surrounding masonry so
    /// a careful player can tell there is something behind it.
    static func secretWallTex() -> Tex {
        var t = wallTexture(5)
        // seam lines that do not line up with the brick courses
        t.vline(20, 2, 61, 96, 92, 86)
        t.vline(21, 2, 61, 52, 48, 46)
        t.rect(18, 30, 5, 4, 118, 112, 96)
        t.noise(14, 61)
        return t
    }

    // ---- army infantry: grenadier, marksman, riot trooper ----

    /// Grenadier: webbing over a smock, throwing arm cocked back.
    static func grenadierFrame(attack: Bool, dead: Bool) -> Tex {
        var t = Tex(w: 64, h: 64)
        t.clear()
        let smock = (74, 82, 56), vest = (52, 58, 40), skin = (172, 128, 94)
        let kit = (44, 48, 38), metal = (146, 150, 158)
        if dead {
            t.disc(31, 42, 17, smock)
            t.rect(10, 40, 44, 12, vest)
            t.rect(15, 36, 8, 8, skin)
            t.rect(40, 38, 15, 8, kit)
            t.noise(18, 67)
            t.shade(0.7)
            return t
        }
        t.rect(24, 40, 7, 20, vest); t.rect(33, 40, 7, 20, vest)
        t.rect(22, 56, 11, 5, kit); t.rect(31, 56, 11, 5, kit)
        t.rect(22, 20, 20, 22, smock)
        t.rect(22, 28, 20, 5, kit)                      // ammo webbing
        t.rect(24, 34, 7, 8, kit); t.rect(33, 34, 7, 8, kit)
        t.rect(22, 20, 20, 3, (96, 106, 72))
        if attack {
            // one arm thrown forward, the other cocked: mid-lob
            t.rect(12, 16, 12, 6, smock)
            t.rect(10, 18, 6, 9, skin)
            t.rect(42, 12, 12, 6, smock)
            t.rect(50, 8, 6, 9, skin)
            t.rect(46, 4, 8, 8, (52, 60, 44))            // grenade in the raised hand
            t.put(49, 7, 90, 100, 70)
            t.rect(8, 22, 16, 4, kit)                    // rifle slung across
            t.rect(20, 21, 8, 6, metal)
        } else {
            t.rect(16, 22, 6, 18, smock); t.rect(42, 22, 6, 18, smock)
            t.rect(14, 38, 8, 6, skin); t.rect(42, 38, 8, 6, skin)
            t.rect(12, 26, 40, 3, kit)
            t.rect(44, 24, 6, 7, metal)
        }
        // steel pot + chin strap
        t.rect(26, 6, 12, 12, skin)
        t.rect(24, 4, 16, 6, kit)
        t.rect(24, 4, 16, 2, (86, 92, 64))
        t.rect(25, 10, 3, 3, 20, 20, 24); t.rect(34, 10, 3, 3, 20, 20, 24)
        t.rect(28, 15, 8, 2, (66, 58, 48))
        t.noise(16, 71)
        return t
    }

    /// Marksman: ghillie-ish, long rifle, low silhouette.
    static func marksmanFrame(attack: Bool, dead: Bool) -> Tex {
        var t = Tex(w: 64, h: 64)
        t.clear()
        let ghillie = (86, 84, 52), dark = (58, 58, 36), skin = (168, 126, 92)
        let wood = (96, 66, 36), metal = (140, 144, 152)
        if dead {
            t.disc(32, 43, 15, ghillie)
            t.rect(6, 38, 52, 10, dark)
            t.rect(12, 34, 7, 6, skin)
            t.rect(44, 40, 14, 5, wood)
            t.noise(18, 73)
            t.shade(0.7)
            return t
        }
        // crouched legs
        t.rect(20, 42, 10, 18, dark); t.rect(34, 42, 10, 18, dark)
        t.rect(18, 56, 14, 5, (40, 40, 32)); t.rect(32, 56, 14, 5, (40, 40, 32))
        t.rect(20, 22, 26, 21, ghillie)
        // hanging rag strips give the ghillie suit its silhouette
        for i in 0..<7 {
            t.rect(19 + i * 4, 34 + (i % 2) * 2, 3, 10 - (i % 3) * 2, dark)
        }
        t.rect(20, 30, 26, 4, dark)
        if attack {
            t.rect(10, 18, 12, 6, ghillie)
            t.rect(8, 20, 6, 9, skin)
            t.rect(42, 18, 12, 6, ghillie)
            t.rect(48, 20, 6, 9, skin)
            // shouldered long rifle with a big scope
            t.rect(2, 20, 52, 4, wood)
            t.rect(2, 20, 52, 1, (120, 86, 48))
            t.rect(16, 14, 22, 5, metal)
            t.rect(18, 15, 18, 2, (160, 210, 240))
            t.rect(28, 25, 7, 8, dark)
        } else {
            t.rect(14, 24, 6, 18, ghillie); t.rect(44, 24, 6, 18, ghillie)
            t.rect(12, 40, 8, 6, skin); t.rect(44, 40, 8, 6, skin)
            t.rect(8, 28, 44, 3, wood)
            t.rect(20, 16, 20, 5, metal)
            t.rect(22, 17, 16, 2, (160, 210, 240))
        }
        // boonie hat over a lowered face
        t.rect(26, 8, 12, 11, skin)
        t.rect(22, 5, 20, 5, ghillie)
        t.rect(20, 9, 24, 2, dark)
        t.rect(25, 12, 3, 3, 20, 20, 24); t.rect(34, 12, 3, 3, 20, 20, 24)
        t.noise(16, 79)
        return t
    }

    /// Riot trooper: bulky, carries a scratched ballistic shield.
    static func rioterFrame(attack: Bool, dead: Bool) -> Tex {
        var t = Tex(w: 64, h: 64)
        t.clear()
        let armor = (58, 64, 80), dark = (36, 40, 52), visor = (180, 200, 230)
        let shield = (58, 92, 150), shieldEdge = (120, 170, 220)
        if dead {
            t.disc(32, 43, 19, armor)
            t.rect(8, 38, 48, 13, dark)
            t.rect(6, 34, 18, 22, shield)
            t.rect(8, 36, 14, 18, shieldEdge)
            t.noise(20, 83)
            t.shade(0.7)
            return t
        }
        t.rect(18, 40, 12, 20, dark); t.rect(34, 40, 12, 20, dark)
        t.rect(16, 56, 16, 5, (28, 30, 38)); t.rect(32, 56, 16, 5, (28, 30, 38))
        t.rect(16, 20, 32, 21, armor)
        t.rect(16, 27, 32, 5, dark)
        t.rect(16, 20, 32, 3, (86, 94, 114))
        if attack {
            // baton swung out to the right, shield still forward
            t.rect(46, 14, 12, 6, armor)
            t.rect(52, 10, 4, 12, (30, 32, 40))
            t.rect(10, 20, 8, 18, armor)
            t.rect(6, 30, 8, 8, (150, 150, 158))
        } else {
            t.rect(48, 22, 8, 18, armor)
            t.rect(50, 38, 8, 7, (150, 150, 158))
            t.rect(10, 20, 8, 18, armor)
        }
        // the shield, held on the left arm, covers most of the torso
        t.rect(6, 24, 16, 30, shield)
        t.rect(7, 25, 14, 28, shieldEdge)
        t.rect(9, 30, 10, 3, (30, 50, 80))
        t.rect(9, 36, 10, 3, (30, 50, 80))
        t.rect(9, 42, 10, 3, (30, 50, 80))
        // helm + visor
        t.rect(24, 4, 18, 14, dark)
        t.rect(24, 4, 18, 4, (86, 94, 114))
        t.rect(26, 11, 14, 5, visor)
        t.rect(29, 18, 8, 2, (24, 26, 32))
        t.noise(16, 89)
        return t
    }

    static func armorTex(blue: Bool) -> Tex {
        var t = Tex(w: 32, h: 32)
        t.clear()
        let main = blue ? (70, 96, 200) : (96, 168, 72)
        let edge = blue ? (36, 52, 120) : (48, 96, 34)
        t.rect(8, 6, 16, 22, main)
        t.rect(4, 10, 5, 14, main); t.rect(23, 10, 5, 14, main)
        t.rect(12, 4, 8, 4, main)
        t.outline(8, 6, 16, 22, edge)
        t.rect(11, 10, 10, 12, edge)
        t.hline(4, 27, 12, edge)
        t.noise(10, 17)
        return t
    }

    static func pickupBox(body: (Int, Int, Int), top: (Int, Int, Int), mark: String) -> Tex {
        var t = Tex(w: 32, h: 32)
        t.clear()
        t.rect(4, 10, 24, 18, body.0, body.1, body.2)
        t.rect(4, 10, 24, 5, top.0, top.1, top.2)
        t.outline(4, 10, 24, 18, 24, 22, 20)
        switch mark {
        case "bullet":
            for i in 0..<4 { t.rect(7 + i * 5, 2, 3, 9, 210, 190, 90) }
            for i in 0..<4 { t.put(8 + i * 5, 2, 230, 120, 60) }
        case "shell":
            for i in 0..<3 { t.rect(8 + i * 6, 3, 4, 8, 190, 50, 40) }
        case "rocket":
            for i in 0..<3 {
                t.rect(6 + i * 7, 1, 4, 11, 150, 160, 130)
                t.put(6 + i * 7, 0, 240, 200, 90)
                t.rect(6 + i * 7, 4, 4, 2, 200, 60, 50)
            }
        case "crate":
            // a lidded ammunition crate with a stencilled shell mark
            t.rect(2, 8, 28, 18, body.0, body.1, body.2)
            t.rect(2, 8, 28, 5, top.0, top.1, top.2)
            t.outline(2, 8, 28, 18, 30, 28, 24)
            t.rect(6, 15, 20, 2, 40, 36, 30)
            for i in 0..<3 { t.rect(9 + i * 6, 17, 3, 5, 230, 190, 90) }
        default:
            t.rect(12, 15, 4, 8, 240, 240, 120); t.rect(14, 17, 8, 4, 240, 240, 120)
        }
        t.noise(10, 19)
        return t
    }

    /// style: 0 shotgun, 1 chaingun, 2 assault rifle, 3 rocket launcher,
    ///        4 M249 SAW, 5 MK12 DMR, 6 M24 sniper
    static func gunPickup(style: Int) -> Tex {
        var t = Tex(w: 48, h: 32)
        t.clear()
        let metal = (150, 152, 160), dark = (86, 88, 96)
        t.rect(2, 14, 34, 6, metal)
        t.rect(36, 16, 10, 3, dark)
        t.rect(4, 20, 8, 10, (110, 76, 44))
        t.rect(14, 20, 18, 4, dark)
        switch style {
        case 0:
            t.rect(2, 12, 40, 3, dark)
            t.rect(40, 10, 6, 6, dark)
            t.rect(2, 12, 40, 2, (190, 190, 196))
        case 1:
            t.rect(6, 10, 24, 5, dark)
            t.rect(28, 8, 8, 9, dark)
            t.rect(8, 6, 3, 6, (190, 190, 196)); t.rect(16, 6, 3, 6, (190, 190, 196))
            t.rect(24, 6, 3, 6, (190, 190, 196))
        case 2:
            t.rect(4, 11, 30, 4, dark)
            t.rect(6, 7, 16, 4, (74, 78, 70))       // carry handle / optic
            t.rect(26, 9, 8, 7, dark)
            t.rect(12, 15, 5, 6, (60, 64, 58))       // magazine
        case 4:
            // M249: light machine gun, top-mounted box magazine
            t.rect(2, 12, 38, 5, dark)
            t.rect(2, 12, 38, 1, (108, 110, 118))
            t.rect(10, 5, 14, 8, (74, 78, 66))      // ammo box on the receiver
            t.rect(11, 6, 12, 2, (96, 100, 84))
            t.rect(18, 17, 6, 12, (62, 66, 56))      // pistol grip
            t.rect(30, 8, 6, 9, dark)               // carry handle
            t.rect(38, 14, 8, 3, metal)             // barrel shroud
            for i in 0..<3 { t.rect(40, 15 + i * 2, 6, 1, (48, 50, 56)) }
        case 5:
            // MK12: long-barrelled DMR with a magnified optic and bipod
            t.rect(2, 12, 42, 4, dark)
            t.rect(2, 12, 42, 1, (104, 106, 114))
            t.rect(14, 6, 20, 6, (72, 76, 66))      // scope body
            t.rect(16, 7, 16, 3, (150, 200, 230))
            t.rect(18, 17, 6, 11, (60, 64, 56))
            t.rect(26, 16, 6, 9, (66, 70, 60))      // magazine
            t.rect(38, 15, 8, 2, (96, 98, 106))    // bipod legs
            t.rect(40, 17, 2, 6, (96, 98, 106))
            t.rect(44, 15, 2, 6, (96, 98, 106))
        case 6:
            // M24: bolt-action sniper rifle, long heavy barrel
            t.rect(2, 13, 44, 4, dark)
            t.rect(2, 13, 44, 1, (112, 114, 122))
            t.rect(12, 5, 24, 7, (70, 74, 64))      // big scope
            t.rect(14, 6, 20, 4, (160, 215, 245))
            t.rect(12, 4, 4, 9, (88, 92, 82))       // scope rings
            t.rect(34, 4, 4, 9, (88, 92, 82))
            t.rect(24, 18, 6, 11, (58, 62, 54))     // grip
            t.rect(34, 9, 6, 3, metal)              // bolt handle
            t.rect(44, 12, 4, 6, (60, 62, 70))      // muzzle brake
            t.rect(46, 13, 1, 4, (40, 42, 48))
        default:
            t.rect(2, 10, 40, 8, (78, 86, 66))       // launcher tube
            t.rect(2, 10, 40, 3, metal)
            t.rect(6, 18, 8, 10, (60, 66, 52))       // grip
            t.rect(16, 18, 14, 5, dark)              // scope
            t.rect(18, 17, 10, 1, (150, 200, 230))
            t.rect(42, 12, 5, 5, (200, 70, 50))      // warhead tip
        }
        t.noise(10, 27)
        return t
    }

    static func barrelTex(burning: Bool) -> Tex {
        var t = Tex(w: 32, h: 32)
        t.clear()
        t.rect(6, 2, 20, 28, 120, 84, 40)
        t.rect(6, 2, 6, 28, 150, 108, 54)
        t.rect(6, 8, 20, 3, 80, 56, 26); t.rect(6, 21, 20, 3, 80, 56, 26)
        t.rect(6, 2, 20, 3, 160, 120, 60)
        t.rect(10, 13, 12, 6, 40, 40, 44)
        if burning {
            t.rect(12, 15, 8, 2, 255, 180, 40)
            t.glow(16, 16, 14, 255, 110, 30)
        }
        t.noise(12, 31)
        return t
    }

    // ---- first-person weapon views -----------------------------------

    /// One first-person view per `Game.weapons` entry.
    static let weaponViews: [Tex] = [
        weaponView(0),   // pistol
        weaponView(1),   // shotgun
        weaponView(2),   // chaingun
        weaponView(3),   // assault rifle
        weaponView(4),   // AT4 rocket launcher
        weaponView(4),   // M320 GL shares the launcher tube
        weaponView(5),   // M249 SAW
        weaponView(6),   // MK12 DMR
        weaponView(7)    // M24 sniper
    ]

    static func weaponView(_ kind: Int) -> Tex {
        var t = Tex(w: 80, h: 48)
        t.clear()
        let metal = (176, 178, 188), dark = (96, 98, 108), deep = (54, 56, 64)
        let wood = (128, 84, 44)
        let olive = (86, 94, 64), oliveDark = (56, 62, 44)
        switch kind {
        case 0:
            t.rect(28, 4, 24, 20, metal)          // slide
            t.rect(28, 4, 6, 20, deep)
            t.rect(32, 6, 16, 4, deep)
            t.rect(30, 24, 20, 20, dark)          // grip
            t.rect(36, 26, 6, 6, deep)
            t.rect(30, 30, 20, 14, wood)          // hand
            t.rect(24, 26, 8, 6, deep)
        case 1:
            t.rect(4, 10, 66, 8, deep)            // barrel
            t.rect(4, 10, 66, 3, metal)
            t.rect(58, 6, 12, 16, dark)           // magazine
            t.rect(60, 8, 8, 12, deep)
            t.rect(10, 18, 46, 6, dark)           // pump
            t.rect(12, 18, 42, 2, metal)
            t.rect(14, 24, 40, 22, wood)          // stock/hands
            t.rect(20, 30, 30, 10, (168, 120, 76))
            t.rect(6, 12, 10, 4, deep)
        case 2:
            t.rect(6, 8, 40, 22, dark)            // chaingun body
            t.rect(6, 8, 40, 4, metal)
            for i in 0..<4 { t.rect(44, 6 + i * 6, 28, 4, deep) }  // barrels
            t.rect(48, 8, 3, 20, metal)
            t.rect(10, 16, 8, 10, (60, 60, 66))
            t.rect(12, 28, 34, 20, (150, 150, 158))  // hands
            t.rect(18, 34, 24, 8, deep)
            t.rect(4, 4, 6, 30, deep)
        case 3:
            t.rect(2, 8, 70, 7, olive)            // receiver + handguard
            t.rect(2, 8, 70, 2, (118, 128, 90))
            t.rect(0, 10, 6, 4, deep)             // flash hider
            t.rect(24, 4, 22, 5, oliveDark)       // optic
            t.rect(26, 5, 18, 2, (150, 210, 240))
            t.rect(30, 15, 8, 14, oliveDark)      // magazine
            t.rect(44, 12, 6, 10, (108, 120, 84))
            t.rect(16, 22, 22, 18, oliveDark)     // grip
            t.rect(40, 26, 34, 20, (150, 150, 158))   // hands
            t.rect(48, 32, 26, 8, deep)
        case 4:
            t.rect(0, 14, 74, 14, olive)          // launcher tube
            t.rect(0, 14, 74, 3, (118, 128, 90))
            t.rect(0, 24, 74, 4, oliveDark)
            t.rect(0, 12, 8, 18, deep)            // muzzle
            t.rect(66, 8, 14, 6, (200, 70, 50))   // warhead
            t.rect(24, 4, 30, 7, oliveDark)       // sight
            t.rect(28, 5, 22, 2, (150, 210, 240))
            t.rect(20, 28, 12, 18, oliveDark)     // grip
            t.rect(40, 30, 36, 18, (150, 150, 158))
            t.rect(48, 36, 28, 8, deep)
        case 5:
            // M249: flat receiver, box magazine on top, vented shroud to the right
            t.rect(0, 10, 40, 14, olive)          // receiver
            t.rect(0, 10, 40, 2, (128, 140, 100))
            t.rect(0, 22, 40, 3, oliveDark)
            t.rect(8, 0, 22, 10, (92, 102, 72))   // ammo box
            t.rect(10, 2, 18, 3, (120, 132, 96))
            t.rect(6, 1, 3, 8, (70, 78, 56))
            t.rect(40, 13, 38, 9, oliveDark)      // barrel shroud
            t.rect(40, 13, 38, 2, (118, 128, 90))
            for i in 0..<4 { t.rect(44 + i * 8, 16, 4, 4, (44, 46, 52)) }
            t.rect(76, 14, 4, 7, deep)            // muzzle
            t.rect(14, 24, 11, 16, oliveDark)     // pistol grip
            t.rect(44, 28, 32, 18, (156, 156, 164))  // hands
            t.rect(52, 34, 24, 8, deep)
        case 6:
            // MK12: slim receiver, long barrel to the right, modest optic
            t.rect(0, 12, 38, 12, olive)
            t.rect(0, 12, 38, 2, (128, 140, 100))
            t.rect(0, 22, 38, 3, oliveDark)
            t.rect(38, 15, 40, 5, (74, 80, 66))   // long barrel
            t.rect(38, 15, 40, 1, (108, 116, 92))
            t.rect(74, 13, 6, 9, deep)            // muzzle brake
            t.rect(76, 15, 2, 5, (40, 42, 48))
            t.rect(12, 5, 24, 7, (74, 82, 64))    // optic
            t.rect(14, 6, 20, 4, (150, 210, 240))
            t.rect(10, 4, 3, 9, (96, 100, 86))
            t.rect(35, 4, 3, 9, (96, 100, 86))
            t.rect(14, 24, 10, 16, oliveDark)     // grip
            t.rect(26, 24, 7, 10, (64, 70, 56))   // magazine
            t.rect(46, 28, 30, 18, (156, 156, 164))
            t.rect(54, 34, 22, 8, deep)
        default:
            // M24: heavier receiver, fat scope with a bright lens, bolt proud
            t.rect(0, 14, 36, 12, olive)
            t.rect(0, 14, 36, 2, (128, 140, 100))
            t.rect(0, 24, 36, 3, oliveDark)
            t.rect(36, 17, 42, 6, (74, 80, 66))   // heavy barrel
            t.rect(36, 17, 42, 1, (108, 116, 92))
            t.rect(74, 15, 6, 10, (60, 64, 70))   // muzzle brake
            t.rect(75, 17, 1, 6, (40, 42, 48))
            t.rect(76, 17, 1, 6, (40, 42, 48))
            t.rect(10, 4, 30, 10, (74, 82, 64))   // scope
            t.rect(12, 6, 26, 6, (160, 215, 245))  // lens
            t.rect(8, 3, 4, 12, (96, 100, 86))     // scope rings
            t.rect(38, 3, 4, 12, (96, 100, 86))
            t.rect(46, 10, 10, 3, (176, 178, 186)) // bolt handle
            t.rect(14, 27, 10, 15, oliveDark)      // grip
            t.rect(44, 28, 32, 18, (156, 156, 164))
            t.rect(52, 34, 24, 8, deep)
        }
        t.noise(10, 41)
        return t
    }
}

// MARK: - 3x5 bitmap font

enum Font3x5 {
    // 5 rows of 3 bits (bit 2 = leftmost column)
    static let glyphs: [Character: (UInt8, UInt8, UInt8, UInt8, UInt8)] = [
        "0": (7, 5, 5, 5, 7), "1": (2, 6, 2, 2, 7), "2": (7, 1, 7, 4, 7), "3": (7, 1, 7, 1, 7),
        "4": (5, 5, 7, 1, 1), "5": (7, 4, 7, 1, 7), "6": (7, 4, 7, 5, 7), "7": (7, 1, 1, 1, 1),
        "8": (7, 5, 7, 5, 7), "9": (7, 5, 7, 1, 7),
        "A": (7, 5, 7, 5, 5), "B": (6, 5, 6, 5, 6), "C": (7, 4, 4, 4, 7), "D": (6, 5, 5, 5, 6),
        "E": (7, 4, 7, 4, 7), "F": (7, 4, 7, 4, 4), "G": (7, 4, 5, 5, 7), "H": (5, 5, 7, 5, 5),
        "I": (7, 2, 2, 2, 7), "J": (1, 1, 1, 5, 7), "K": (5, 5, 6, 5, 5), "L": (4, 4, 4, 4, 7),
        "M": (5, 7, 7, 5, 5), "N": (6, 5, 5, 5, 5), "O": (7, 5, 5, 5, 7), "P": (7, 5, 7, 4, 4),
        "Q": (7, 5, 5, 7, 1), "R": (7, 5, 7, 6, 5), "S": (7, 4, 7, 1, 7), "T": (7, 2, 2, 2, 2),
        "U": (5, 5, 5, 5, 7), "V": (5, 5, 5, 5, 2), "W": (5, 5, 7, 7, 5), "X": (5, 5, 2, 5, 5),
        "Y": (5, 5, 2, 2, 2), "Z": (7, 1, 2, 4, 7),
        "%": (5, 1, 2, 4, 5), "+": (0, 2, 7, 2, 0), "-": (0, 0, 7, 0, 0), "/": (1, 1, 2, 4, 4),
        ".": (0, 0, 0, 0, 2), "!": (2, 2, 2, 0, 2), ":": (0, 2, 0, 2, 0), "*": (5, 2, 7, 2, 5),
        "(": (1, 2, 2, 2, 1), ")": (4, 2, 2, 2, 4), ">": (4, 2, 1, 2, 4), "<": (1, 2, 4, 2, 1),
        "=": (0, 7, 0, 7, 0), "'": (2, 2, 0, 0, 0)
    ]
}
