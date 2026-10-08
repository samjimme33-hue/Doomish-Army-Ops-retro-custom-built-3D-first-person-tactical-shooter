import Foundation

// Tile codes stored in Level.cells
enum Tile {
    static let floor: UInt8 = 0
    static let door: UInt8 = 10
    static let exit: UInt8 = 11
    /// A false wall: solid, but drawn with the subtly-different secret texture so
    /// a player who looks can tell there is a room behind it.
    static let secret: UInt8 = 8
    /// 1...7  ->  wall with texture (code - 1)
    static func isWall(_ c: UInt8) -> Bool { c >= 1 && c <= 7 }
    static func wallTex(_ c: UInt8) -> Int { max(0, min(TexLib.wallCount - 1, Int(c) - 1)) }
    /// Every cell that blocks movement, secret walls included.
    static func isSolidCell(_ c: UInt8) -> Bool { c != floor && c != door }
}

struct Rect {
    var x0: Int, y0: Int, x1: Int, y1: Int
    var w: Int { x1 - x0 + 1 }
    var h: Int { y1 - y0 + 1 }
    var cx: Double { Double(x0 + x1) / 2.0 + 0.5 }
    var cy: Double { Double(y0 + y1) / 2.0 + 0.5 }
    func contains(_ x: Int, _ y: Int) -> Bool { x >= x0 && x <= x1 && y >= y0 && y <= y1 }
}

enum PickupKind: Int {
    case medikit, stimpack, armor, blueArmor
    case bullets, shells, cells
    case shotgun, chaingun
    case rockets, rifle, launcher
    // ---- army additions ----
    case saw          // M249 squad automatic weapon
    case dmr          // MK12 designated marksman rifle
    case sniper       // M24 bolt-action sniper rifle
    case berserk      // temporary fire-rate / damage rage
    case invulnerability
    case megahealth
    case ammoBox      // tops up every ammo type

    var sprite: Sprite {
        switch self {
        case .medikit: return .medikit
        case .stimpack: return .stimpack
        case .armor: return .armor
        case .blueArmor: return .blueArmor
        case .bullets: return .bullets
        case .shells: return .shells
        case .cells: return .cells
        case .shotgun: return .shotgunPickup
        case .chaingun: return .chaingunPickup
        case .rockets: return .rockets
        case .rifle: return .riflePickup
        case .launcher: return .launcherPickup
        case .saw: return .sawPickup
        case .dmr: return .dmrPickup
        case .sniper: return .sniperPickup
        case .berserk: return .berserk
        case .invulnerability: return .invuln
        case .megahealth: return .megahealth
        case .ammoBox: return .ammoBox
        }
    }

    /// Army gear shows up as the campaign advances.
    var minLevel: Int {
        switch self {
        case .rockets: return 2
        case .launcher: return 3
        case .rifle: return 1
        case .saw: return 3
        case .dmr: return 4
        case .sniper: return 5
        case .berserk: return 3
        case .invulnerability: return 4
        case .megahealth: return 5
        case .ammoBox: return 2
        default: return 1
        }
    }

    /// Powerups stack for a while rather than being consumed outright, so the
    /// HUD can show a running timer.
    var isPowerup: Bool {
        self == .berserk || self == .invulnerability
    }

    var displayName: String {
        switch self {
        case .medikit: return "MEDIKIT"
        case .stimpack: return "STIMPACK"
        case .armor: return "ARMOR"
        case .blueArmor: return "MEGAARMOR"
        case .bullets: return "BULLETS"
        case .shells: return "SHELLS"
        case .cells: return "CELLS"
        case .shotgun: return "SHOTGUN"
        case .chaingun: return "CHAINGUN"
        case .rockets: return "ROCKETS"
        case .rifle: return "ASSAULT RIFLE"
        case .launcher: return "ROCKET LAUNCHER"
        case .saw: return "M249 SAW"
        case .dmr: return "MK12 DMR"
        case .sniper: return "M24 SNIPER"
        case .berserk: return "BERSERK"
        case .invulnerability: return "INVULNERABILITY"
        case .megahealth: return "MEGAHEALTH"
        case .ammoBox: return "AMMO CRATE"
        }
    }
}

struct EnemySpec {
    var x: Double, y: Double, type: Int   // 0 imp, 1 brute, 2 soldier, 3 heavy
}

struct PickupSpec {
    var x: Double, y: Double, kind: PickupKind
}

final class Level {
    let w: Int
    let h: Int
    var cells: [UInt8]
    var doorProgress: [Double]     // 0 closed ... 1 fully open
    var name: String
    var startPos: (x: Double, y: Double, ang: Double)
    var enemySpecs: [EnemySpec] = []
    var pickupSpecs: [PickupSpec] = []
    var barrelSpecs: [(x: Double, y: Double)] = []
    var rooms: [Rect] = []
    /// Sealed chambers holding a reward. The wall in front stays solid, so the
    /// only way in is to blow it open -- the game calls these "secrets".
    var secrets: [Rect] = []
    /// Centre of the exit switch, cached so the HUD compass does not rescan the
    /// grid every frame.
    var exitPos: (x: Double, y: Double)?
    /// Secret chambers, in the order the builder made them. A chamber counts as
    /// found once a player stands in any of its cells.
    var secretFound: [Bool]

    func markSecret(index: Int) {
        guard secretFound.indices.contains(index) else { return }
        secretFound[index] = true
    }

    /// The exit switch is solid until touched, but the tile is what the renderer
    /// and the automap key off.
    var exitTile: (x: Int, y: Int)? {
        guard let e = exitPos else { return nil }
        return (Int(e.x), Int(e.y))
    }

    init(w: Int, h: Int) {
        self.w = w
        self.h = h
        self.cells = [UInt8](repeating: 1, count: w * h)
        self.doorProgress = [Double](repeating: 0, count: w * h)
        self.name = "E1M1"
        self.startPos = (2.5, 2.5, 0)
        self.exitPos = nil
        self.secretFound = []
    }

    @inline(__always) func inBounds(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h }
    @inline(__always) func at(_ x: Int, _ y: Int) -> UInt8 {
        guard inBounds(x, y) else { return 1 }
        return cells[y * w + x]
    }
    @inline(__always) func set(_ x: Int, _ y: Int, _ v: UInt8) {
        guard inBounds(x, y) else { return }
        cells[y * w + x] = v
    }

    /// Solid for walking (doors block until they have slid most of the way open).
    @inline(__always) func solid(_ x: Int, _ y: Int, doorsPassable: Bool) -> Bool {
        let c = at(x, y)
        if c == Tile.floor { return false }
        if c == Tile.door {
            if doorsPassable { return false }
            return doorProgress[y * w + x] < 0.65
        }
        return true
    }

    func solidAtPoint(_ px: Double, _ py: Double, radius: Double, doorsPassable: Bool) -> Bool {
        let minX = Int((px - radius).rounded(.down)), maxX = Int((px + radius).rounded(.down))
        let minY = Int((py - radius).rounded(.down)), maxY = Int((py + radius).rounded(.down))
        for ty in minY...maxY {
            for tx in minX...maxX {
                let cx = min(max(tx, 0), w - 1), cy = min(max(ty, 0), h - 1)
                if tx < 0 || ty < 0 || tx >= w || ty >= h { return true }
                if solid(cx, cy, doorsPassable: doorsPassable) {
                    // corner check: is the circle overlapping this cell?
                    let nx = min(max(px, Double(tx)), Double(tx + 1))
                    let ny = min(max(py, Double(ty)), Double(ty + 1))
                    let dx = px - nx, dy = py - ny
                    if dx * dx + dy * dy < radius * radius { return true }
                }
            }
        }
        return false
    }

    /// Distance to the first blocking cell along a ray. This is the same DDA the
    /// player's shooting and movement use, so level generation can probe for open
    /// space without a second, subtly different notion of "blocked".
    func wallDistance(_ ox: Double, _ oy: Double, _ dx: Double, _ dy: Double,
                      _ maxDist: Double, doorsPassable: Bool = false) -> Double {
        var mapX = Int(ox.rounded(.down)), mapY = Int(oy.rounded(.down))
        let deltaX = abs(1.0 / (dx == 0 ? 1e-9 : dx))
        let deltaY = abs(1.0 / (dy == 0 ? 1e-9 : dy))
        var stepX: Int, stepY: Int
        var sideDistX: Double, sideDistY: Double
        if dx < 0 { stepX = -1; sideDistX = (ox - Double(mapX)) * deltaX }
        else { stepX = 1; sideDistX = (Double(mapX + 1) - ox) * deltaX }
        if dy < 0 { stepY = -1; sideDistY = (oy - Double(mapY)) * deltaY }
        else { stepY = 1; sideDistY = (Double(mapY + 1) - oy) * deltaY }
        var dist = 0.0
        var guardCount = 0
        while dist < maxDist && guardCount < 256 {
            guardCount += 1
            if sideDistX < sideDistY {
                dist = sideDistX; sideDistX += deltaX; mapX += stepX
            } else {
                dist = sideDistY; sideDistY += deltaY; mapY += stepY
            }
            if solid(mapX, mapY, doorsPassable: doorsPassable) { return dist }
        }
        return maxDist
    }

    /// Breadth-first distance (in tiles) from a tile over walkable ground.
    func flowField(from: (Int, Int), doorsPassable: Bool = true) -> [Int] {
        var dist = [Int](repeating: -1, count: w * h)
        guard inBounds(from.0, from.1) else { return dist }
        var q = [Int]()
        q.reserveCapacity(w * h)
        dist[from.1 * w + from.0] = 0
        q.append(from.1 * w + from.0)
        var head = 0
        while head < q.count {
            let cur = q[head]; head += 1
            let cx = cur % w, cy = cur / w
            let d = dist[cur]
            for (nx, ny) in [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)] {
                guard inBounds(nx, ny) else { continue }
                let ni = ny * w + nx
                if dist[ni] != -1 { continue }
                let c = at(nx, ny)
                if c != Tile.floor && !(c == Tile.door && doorsPassable) { continue }
                dist[ni] = d + 1
                q.append(ni)
            }
        }
        return dist
    }
}

// MARK: - Procedural level builder

enum LevelBuilder {

    /// One enemy type, weighted by campaign depth. Imps and brutes thin out as the
    /// army takes over, and the specialists only appear once the player has the
    /// tools to answer them. The table is explicit rather than a chain of
    /// cumulative ranges: a single reweight then cannot silently starve a type.
    static func pickEnemyType(rng: inout RNG, level: Int) -> Int {
        var weights: [(type: Int, w: Double)] = [
            (EnemyType.imp, 34.0),
            (EnemyType.brute, 12.0 + Double(min(level, 6)) * 2.0),
            (EnemyType.soldier, 20.0 + Double(min(level, 5)) * 4.0),
        ]
        if level >= 3 {
            weights.append((EnemyType.heavy, 8.0 + Double(min(level - 2, 5)) * 2.0))
        }
        if level >= 3 { weights.append((EnemyType.rioter, 5.0)) }
        if level >= 5 { weights.append((EnemyType.grenadier, 5.0)) }
        if level >= 6 { weights.append((EnemyType.marksman, 4.0)) }
        let total = weights.reduce(0.0) { $0 + $1.w }
        var roll = rng.f() * total
        for e in weights {
            roll -= e.w
            if roll <= 0 { return e.type }
        }
        return weights[weights.count - 1].type
    }

    static func build(level index: Int) -> Level {
        let w = 48, h = 34
        var rng = RNG(seed: UInt64(index &* 7919 &+ 104729))
        let lv = Level(w: w, h: h)
        lv.name = "E1M\(index)"

        // 1. rooms
        var rooms: [Rect] = []
        // later levels are bigger: more rooms, and occasionally a big arena
        let roomCap = 8 + index / 2
        for _ in 0..<600 {
            if rooms.count >= roomCap { break }
            let rw = rng.range(6, 11), rh = rng.range(5, 9)
            let rx = rng.range(1, w - rw - 2), ry = rng.range(1, h - rh - 2)
            let r = Rect(x0: rx, y0: ry, x1: rx + rw - 1, y1: ry + rh - 1)
            var clash = false
            for o in rooms {
                if r.x0 - 1 <= o.x1 && o.x0 - 1 <= r.x1 && r.y0 - 1 <= o.y1 && o.y0 - 1 <= r.y1 { clash = true; break }
            }
            if !clash { rooms.append(r) }
        }
        if rooms.count < 3 {
            // extremely unlikely; fall back to a simple arena
            lv.set(w / 2 - 6, h / 2 - 5, 0); lv.set(w / 2 + 6, h / 2 + 5, 0)
            rooms = [Rect(x0: w / 2 - 6, y0: h / 2 - 5, x1: w / 2 + 6, y1: h / 2 + 5)]
        }
        lv.rooms = rooms
        for r in rooms {
            for y in r.y0...r.y1 { for x in r.x0...r.x1 { lv.set(x, y, Tile.floor) } }
        }

        // 2. corridors: chain the rooms, plus a couple of loops
        func carveH(_ y: Int, _ from: Double, _ to: Double) {
            let a = Int(min(from, to).rounded()), b = Int(max(from, to).rounded())
            for x in a...b { if lv.at(x, y) == 1 { lv.set(x, y, Tile.floor) } }
        }
        func carveV(_ x: Int, _ from: Double, _ to: Double) {
            let a = Int(min(from, to).rounded()), b = Int(max(from, to).rounded())
            for y in a...b { if lv.at(x, y) == 1 { lv.set(x, y, Tile.floor) } }
        }
        func connect(_ a: Rect, _ b: Rect) {
            if rng.chance(0.5) {
                carveH(Int(a.cy - 0.5), a.cx, b.cx)
                carveV(Int(b.cx - 0.5), a.cy, b.cy)
            } else {
                carveV(Int(a.cx - 0.5), a.cy, b.cy)
                carveH(Int(b.cy - 0.5), a.cx, b.cx)
            }
        }
        for i in 1..<rooms.count { connect(rooms[i - 1], rooms[i]) }
        if rooms.count > 3 {
            connect(rooms[0], rooms[2])
            if rooms.count > 4 { connect(rooms[1], rooms[rooms.count - 2]) }
        }

        // 3. doors where corridors meet rooms
        for r in rooms {
            for y in (r.y0 - 1)...(r.y1 + 1) {
                for x in (r.x0 - 1)...(r.x1 + 1) {
                    if lv.at(x, y) != Tile.floor { continue }
                    var inRoom = false
                    for o in rooms where o.contains(x, y) && !(o.x0 == x && o.y0 == y) { inRoom = true; break }
                    if inRoom { continue }
                    guard lv.at(x, y) == Tile.floor else { continue }
                    // count orthogonal wall neighbours -> corridor mouth
                    var walls = 0
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where lv.at(x + dx, y + dy) == 1 { walls += 1 }
                    guard walls >= 2 else { continue }
                    // don't place next to another door
                    var nearDoor = false
                    for (dx, dy) in [(2, 0), (-2, 0), (0, 2), (0, -2)] where lv.at(x + dx, y + dy) == Tile.door { nearDoor = true }
                    if nearDoor { continue }
                    if rng.chance(0.30) { lv.set(x, y, Tile.door) }
                }
            }
        }

        // 4. wall texturing by region (keeps large surfaces consistent)
        for y in 0..<h {
            for x in 0..<w where Tile.isWall(lv.at(x, y)) {
                let qx = x / 5, qy = y / 5
                let r = Int(rnd01(qx, qy, 3) * 100.0)
                var tex: Int
                if r < 46 { tex = 0 }
                else if r < 62 { tex = 1 }
                else if r < 74 { tex = 2 }
                else if r < 84 { tex = 3 }
                else if r < 92 { tex = 4 }
                else if r < 97 { tex = 5 }
                else { tex = 6 }
                lv.set(x, y, UInt8(1 + tex))
            }
        }

        // 5. pillars inside big rooms
        for r in rooms where r.w >= 8 && r.h >= 7 && rng.chance(0.7) {
            let px = r.x0 + rng.range(2, r.w - 3), py = r.y0 + rng.range(2, r.h - 3)
            lv.set(px, py, UInt8(1 + rng.int(TexLib.wallCount)))
            if r.w >= 9 && rng.chance(0.5) { lv.set(px + r.w / 2, py, UInt8(1 + rng.int(TexLib.wallCount))) }
        }

        // 6. player start
        let startRoom = rooms[0]
        let sx = Double(startRoom.x0 + 1) + 0.5, sy = Double(startRoom.y0 + 1) + 0.5
        var ang = 0.0
        if rooms.count > 1 {
            ang = atan2(rooms[1].cy - sy, rooms[1].cx - sx)
        }
        // A pillar dropped in step 5 can land on or beside the spawn tile, which
        // leaves the player wedged in a corner: W does nothing while A/D still
        // slide along the wall, so movement reads as broken. Clear the spawn
        // pocket before choosing a heading.
        for y in (startRoom.y0 - 1)...(startRoom.y0 + 2) {
            for x in (startRoom.x0 - 1)...(startRoom.x0 + 2) {
                if lv.inBounds(x, y), Tile.isWall(lv.at(x, y)) {
                    // only clear it if that does not open a hole to the outside
                    // world: keep the map border intact
                    if x > 0 && y > 0 && x < w - 1 && y < h - 1 { lv.set(x, y, Tile.floor) }
                }
            }
        }
        // The spawn tile is a room *corner*, and the corridor to the next room is
        // carved along some other row/column -- so "face the next room" very
        // often means facing a wall. Then W does nothing at all while A/D still
        // slide along it, which reads as "W/S are broken". Probe with the same
        // primitive the player collides with and pick the most open heading.
        // ray distance alone is not enough: a doorway one tile wide gives a long
        // clear ray but the player still only shuffles sideways through it. Score
        // each candidate by how far the actual collision shape can travel.
        func travelAhead(_ a: Double, _ ox: Double, _ oy: Double) -> Double {
            var x = ox, y = oy
            let dx = cos(a) * 0.1, dy = sin(a) * 0.1
            for _ in 0..<30 {
                let nx = x + dx, ny = y + dy
                if lv.solidAtPoint(nx, ny, radius: 0.24, doorsPassable: false) { break }
                x = nx; y = ny
            }
            return hypot(x - ox, y - oy)
        }
        func chooseAngle(_ ox: Double, _ oy: Double, preferred: Double) -> Double {
            var bestAng = preferred, bestOpen = travelAhead(preferred, ox, oy)
            for k in 0..<72 {
                let a = Double(k) / 72.0 * 2 * .pi
                let d = travelAhead(a, ox, oy)
                if d > bestOpen + 0.001 {
                    bestOpen = d
                    bestAng = a
                }
            }
            return bestAng
        }
        ang = chooseAngle(sx, sy, preferred: ang)
        lv.startPos = (sx, sy, ang)

        // reachability map
        let flow = lv.flowField(from: (Int(sx), Int(sy)))

        // 7. exit switch: a wall cell beside a floor cell in the farthest room
        var bestRoom = rooms[rooms.count - 1]
        var bestRoomIndex = rooms.count - 1
        var bestDist = -1
        for (i, r) in rooms.enumerated() {
            var d = 0
            for y in r.y0...r.y1 { for x in r.x0...r.x1 where flow[y * w + x] > 0 { d = max(d, flow[y * w + x]) } }
            if d > bestDist { bestDist = d; bestRoom = r; bestRoomIndex = i }
        }
        var exitX = -1, exitY = -1
        var exitScore = -1.0
        for y in (bestRoom.y0 - 1)...(bestRoom.y1 + 1) {
            for x in (bestRoom.x0 - 1)...(bestRoom.x1 + 1) {
                guard Tile.isWall(lv.at(x, y)) else { continue }
                var touches = false
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where lv.at(x + dx, y + dy) == Tile.floor { touches = true }
                guard touches else { continue }
                let d = hypot(Double(x) - bestRoom.cx, Double(y) - bestRoom.cy)
                if d > exitScore { exitScore = d; exitX = x; exitY = y }
            }
        }
        if exitX >= 0 {
            lv.set(exitX, exitY, Tile.exit)
            lv.exitPos = (Double(exitX) + 0.5, Double(exitY) + 0.5)
        }

        // 7b. secret chambers: a small sealed room with a reward, walled off from
        // the rest of the level. The only way in is to blow the front wall, which
        // costs a rocket or a barrel -- a deliberate risk/reward detour.
        let secretCount = index >= 4 ? 2 : (index >= 2 ? 1 : 0)
        var secretsPlaced = 0
        var secretGuard = 0
        while secretsPlaced < secretCount && secretGuard < 200 {
            secretGuard += 1
            let sw = 3, sh = 3
            let sx0 = rng.range(2, w - sw - 3), sy0 = rng.range(2, h - sh - 3)
            let chamber = Rect(x0: sx0, y0: sy0, x1: sx0 + sw - 1, y1: sy0 + sh - 1)
            // must not touch any room, or the "secret" is just a room
            var nearRoom = false
            for r in rooms {
                if !(chamber.x1 + 2 < r.x0 || r.x1 + 2 < chamber.x0
                     || chamber.y1 + 2 < r.y0 || r.y1 + 2 < chamber.y0) { nearRoom = true; break }
            }
            if nearRoom { continue }
            // and must not clip an existing secret
            var clash = false
            for s in lv.secrets {
                if !(chamber.x1 + 3 < s.x0 || s.x1 + 3 < chamber.x0
                     || chamber.y1 + 3 < s.y0 || s.y1 + 3 < chamber.y0) { clash = true; break }
            }
            if clash { continue }
            for y in chamber.y0...chamber.y1 {
                for x in chamber.x0...chamber.x1 { lv.set(x, y, Tile.floor) }
            }
            // the front wall is a normal wall cell painted with the false-wall art
            lv.set(chamber.x0, (chamber.y0 + chamber.y1) / 2, Tile.secret)
            lv.secrets.append(chamber)
            secretsPlaced += 1
        }
        lv.secretFound = [Bool](repeating: false, count: lv.secrets.count)

        // 8. contents
        func freeFloor(x: Int, y: Int, minDist: Int) -> Bool {
            guard lv.inBounds(x, y), lv.at(x, y) == Tile.floor else { return false }
            let d = flow[y * w + x]
            return d > minDist
        }

        // enemy quota per room
        for (i, r) in rooms.enumerated() {
            if i == 0 { continue }
            let area = r.w * r.h
            // gentle growth: doubling the room count already adds plenty of bodies,
            // so the per-room quota only creeps up
            var count = max(1, area / 18) + index / 2
            count = min(count, 6)
            var placed = 0
            for _ in 0..<(count * 6) where placed < count {
                let x = rng.range(r.x0, r.x1), y = rng.range(r.y0, r.y1)
                guard freeFloor(x: x, y: y, minDist: 7) else { continue }
                lv.enemySpecs.append(EnemySpec(x: Double(x) + 0.5, y: Double(y) + 0.5,
                                               type: pickEnemyType(rng: &rng, level: index)))
                placed += 1
            }
        }

        // secret rewards: each chamber gets a good one, chosen from the deeper
        // half of the arsenal so finding it actually changes the run
        for s in lv.secrets {
            let reward: PickupKind
            switch rng.int(4) {
            case 0: reward = index >= 5 ? .sniper : .saw
            case 1: reward = index >= 4 ? .dmr : .blueArmor
            case 2: reward = .ammoBox
            default: reward = .megahealth
            }
            lv.pickupSpecs.append(PickupSpec(x: s.cx, y: s.cy, kind: reward))
        }

        // pickups
        let shotgunRoomIndex = rooms.count > 2 ? rng.range(1, min(3, rooms.count - 1)) : rooms.count - 1
        let shotgunRoom = rooms[shotgunRoomIndex]
        let chainRoom = bestRoom
        for r in rooms {
            let area = r.w * r.h
            let rolls = max(1, area / 22)
            for _ in 0..<rolls {
                let x = rng.range(r.x0, r.x1), y = rng.range(r.y0, r.y1)
                guard freeFloor(x: x, y: y, minDist: 3) else { continue }
                let roll = rng.f()
                var kind: PickupKind
                if roll < 0.18 { kind = .bullets }
                else if roll < 0.30 { kind = .stimpack }
                else if roll < 0.41 { kind = .medikit }
                else if roll < 0.50 { kind = .armor }
                else if roll < 0.57 { kind = .shells }
                else if roll < 0.64 { kind = index >= 2 ? .rockets : .cells }
                else if roll < 0.72 { kind = .ammoBox }
                else if roll < 0.79 { kind = rng.chance(0.5) ? .blueArmor : .medikit }
                else if roll < 0.84 { kind = .berserk }
                else if roll < 0.88 { kind = .invulnerability }
                else if roll < 0.92 { kind = .megahealth }
                else if roll < 0.96 { kind = .saw }
                else { kind = .dmr }
                if kind.minLevel > index { kind = .bullets }
                lv.pickupSpecs.append(PickupSpec(x: Double(x) + 0.5, y: Double(y) + 0.5, kind: kind))
            }
        }
        // guaranteed weapon placements
        func placeInRoom(_ r: Rect, _ kind: PickupKind, minDist: Int) {
            for _ in 0..<80 {
                let x = rng.range(r.x0, r.x1), y = rng.range(r.y0, r.y1)
                guard freeFloor(x: x, y: y, minDist: minDist) else { continue }
                lv.pickupSpecs.append(PickupSpec(x: Double(x) + 0.5, y: Double(y) + 0.5, kind: kind))
                return
            }
        }
        placeInRoom(shotgunRoom, .shotgun, minDist: 6)
        if bestRoomIndex != shotgunRoomIndex { placeInRoom(chainRoom, .chaingun, minDist: 4) }
        placeInRoom(rooms[0], .bullets, minDist: 2)
        placeInRoom(rooms[0], .stimpack, minDist: 2)
        // army gear, one guaranteed placement per tier so the campaign has a
        // defined power curve rather than relying on random rolls
        let rifleRoom = rooms[min(1, rooms.count - 1)]
        placeInRoom(rifleRoom, .rifle, minDist: 3)
        if index >= 2 { placeInRoom(rooms[min(2, rooms.count - 1)], .rockets, minDist: 3) }
        if index >= 3 { placeInRoom(rooms[rooms.count - 1], .launcher, minDist: 5) }
        if index >= 3 { placeInRoom(rooms[min(2, rooms.count - 1)], .saw, minDist: 5) }
        if index >= 4 { placeInRoom(rooms[rooms.count - 1], .dmr, minDist: 6) }
        if index >= 5 { placeInRoom(rooms[min(1, rooms.count - 1)], .sniper, minDist: 6) }
        if index >= 6 { placeInRoom(rooms[min(3, rooms.count - 1)], .ammoBox, minDist: 3) }

        // barrels: near walls, in corridors and rooms
        // Barrels want a wall-adjacent reachable tile, which is a narrow target, so
        // they get a generous number of attempts: with too few tries a level can
        // come out with no explosive cover at all.
        var barrels = 3 + index
        for _ in 0..<(barrels * 40) where barrels > 0 {
            let x = rng.range(1, w - 2), y = rng.range(1, h - 2)
            guard lv.at(x, y) == Tile.floor, flow[y * w + x] > 3 else { continue }
            var nearWall = false
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where lv.at(x + dx, y + dy) == 1 { nearWall = true }
            guard nearWall else { continue }
            lv.barrelSpecs.append((Double(x) + 0.5, Double(y) + 0.5))
            barrels -= 1
        }

        return lv
    }
}
