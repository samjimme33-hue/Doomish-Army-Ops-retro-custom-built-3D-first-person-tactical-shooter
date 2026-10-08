import Foundation

// MARK: - Actors

enum ActorState { case idle, chase, pain, attack, dead }

final class Enemy {
    var x: Double, y: Double
    var angle: Double
    var radius: Double = 0.26
    var hp: Double
    var maxHP: Double
    var speed: Double
    var type: Int                 // see EnemyType
    var state: ActorState = .idle
    var fireCooldown: Double = 0
    var deadTimer: Double = 0
    var painTimer: Double = 0
    var flash: Double = 0
    var attackAnim: Double = 0
    var wanderAngle: Double = 0
    var wanderTimer: Double = 0
    var alertTimer: Double = 0
    var dead = false
    var gore: Double = 0           // visual damage tint 0...1
    /// Difficulty the enemy was spawned at; armour penetration scales with it.
    let difficulty: Int

    init(x: Double, y: Double, type: Int, difficulty: Int) {
        self.x = x; self.y = y
        self.type = type
        self.angle = 0
        self.difficulty = difficulty
        let d = Double(difficulty) * Difficulty.current.enemyHealth
        switch type {
        case 1:
            maxHP = 86 + d * 9
            speed = (1.05 + Double(difficulty) * 0.02) * Difficulty.current.enemySpeed
            radius = 0.34
        case 2:
            maxHP = 30 + d * 4
            speed = (1.95 + Double(difficulty) * 0.03) * Difficulty.current.enemySpeed
        case 3:
            maxHP = 130 + d * 12
            speed = (0.95 + Double(difficulty) * 0.02) * Difficulty.current.enemySpeed
            radius = 0.36
        case EnemyType.grenadier:
            maxHP = 44 + d * 5
            speed = (1.55 + Double(difficulty) * 0.02) * Difficulty.current.enemySpeed
        case EnemyType.marksman:
            maxHP = 26 + d * 3
            speed = (1.7 + Double(difficulty) * 0.03) * Difficulty.current.enemySpeed
        case EnemyType.rioter:
            maxHP = 70 + d * 7
            speed = (1.15 + Double(difficulty) * 0.02) * Difficulty.current.enemySpeed
            radius = 0.32
        default:
            maxHP = 34 + d * 4
            speed = (1.75 + Double(difficulty) * 0.03) * Difficulty.current.enemySpeed
        }
        hp = maxHP
        wanderAngle = Double.random(in: 0..<(2 * .pi))
    }

    /// Ranged infantry: keeps its distance and shoots from far away.
    var isArmy: Bool { type != 0 && type != 1 }

    var minDamage: Double {
        switch type {
        case 1: return 9
        case 2: return 4
        case 3: return 7
        case EnemyType.grenadier: return 14
        case EnemyType.marksman: return 16
        case EnemyType.rioter: return 6
        default: return 3
        }
    }
    var maxDamage: Double {
        switch type {
        case 1: return 18
        case 2: return 9
        case 3: return 15
        case EnemyType.grenadier: return 26
        case EnemyType.marksman: return 30
        case EnemyType.rioter: return 13
        default: return 8
        }
    }
    var sightRange: Double {
        switch type {
        case 1: return 13
        case 2: return 19
        case 3: return 15
        case EnemyType.grenadier: return 21
        case EnemyType.marksman: return 30
        case EnemyType.rioter: return 12
        default: return 16
        }
    }
    var attackSound: String {
        switch type {
        case 1: return "bruteshot"
        case 2: return "rifle"
        case 3: return "chain"
        case EnemyType.grenadier: return "thrownoise"
        case EnemyType.marksman: return "snipershot"
        case EnemyType.rioter: return "rifle"
        default: return "impshot"
        }
    }
    var attackCooldown: Double {
        switch type {
        case 1: return 1.7
        case 2: return 1.25
        case 3: return 1.9
        case EnemyType.grenadier: return 2.4
        case EnemyType.marksman: return 2.2
        case EnemyType.rioter: return 1.6
        default: return 1.3
        }
    }
    /// Soldiers and heavies are shooters, so they hold the trigger from further out.
    var attackRange: Double {
        switch type {
        case 2: return 7.5
        case 3: return 6.0
        case EnemyType.grenadier: return 11.0
        case EnemyType.marksman: return 18.0
        case EnemyType.rioter: return 1.9
        default: return 1.6
        }
    }
    /// Ranged troops keep a stand-off distance; melee types close all the way in.
    /// `updateEnemies` uses this instead of inferring it from the attack range.
    var preferredRange: Double {
        switch type {
        case EnemyType.marksman: return 12.0
        case EnemyType.grenadier: return 8.0
        case 2: return 4.5
        case 3: return 4.5
        case EnemyType.rioter: return 1.0
        default: return 1.05
        }
    }
    /// Grenadiers lob a projectile; everyone else fires hitscan.
    var throwsGrenade: Bool { type == EnemyType.grenadier }
    /// Marksmen hit hard but reload slowly, so one aimed shot is a real threat.
    var isMarksman: Bool { type == EnemyType.marksman }
    /// A rioter's ballistic shield blunts frontal fire.
    var armored: Bool { type == EnemyType.rioter }

    var name: String {
        switch type {
        case 1: return "BRUTE"
        case 2: return "SOLDIER"
        case 3: return "HEAVY"
        case EnemyType.grenadier: return "GRENADIER"
        case EnemyType.marksman: return "MARKSMAN"
        case EnemyType.rioter: return "RIOT TROOPER"
        default: return "IMP"
        }
    }
    var scoreValue: Int {
        switch type {
        case 1: return 250
        case 2: return 150
        case 3: return 400
        case EnemyType.grenadier: return 200
        case EnemyType.marksman: return 175
        case EnemyType.rioter: return 225
        default: return 100
        }
    }
}

/// Enemy type codes. Kept as plain Ints because they are stored in `Enemy.type`
/// and in the level generator's `EnemySpec`; the names live here so no switch
/// statement has to repeat a magic number.
enum EnemyType {
    static let imp = 0
    static let brute = 1
    static let soldier = 2
    static let heavy = 3
    static let grenadier = 4
    static let marksman = 5
    static let rioter = 6
    static let count = 7
}

/// Campaign difficulty. Selected on the title screen and in the Game menu; it
/// rescales enemy health, speed and damage, and the score multiplier.
enum Difficulty: Int, CaseIterable {
    case rookie = 0
    case veteran = 1
    case elite = 2

    var name: String {
        switch self {
        case .rookie: return "ROOKIE"
        case .veteran: return "VETERAN"
        case .elite: return "ELITE"
        }
    }
    var blurb: String {
        switch self {
        case .rookie: return "THEY HIT LIKE THE WEATHER"
        case .veteran: return "HOLD THE LINE"
        case .elite: return "GOOD MEN DIE FAST"
        }
    }
    var enemyHealth: Double {
        switch self {
        case .rookie: return 0.7
        case .veteran: return 1.0
        case .elite: return 1.45
        }
    }
    var enemySpeed: Double {
        switch self {
        case .rookie: return 0.88
        case .veteran: return 1.0
        case .elite: return 1.12
        }
    }
    var enemyDamage: Double {
        switch self {
        case .rookie: return 0.6
        case .veteran: return 1.0
        case .elite: return 1.35
        }
    }
    /// Player damage taken scales with this too, so elite is not a bullet sponge.
    var scoreMultiplier: Double {
        switch self {
        case .rookie: return 0.8
        case .veteran: return 1.0
        case .elite: return 1.5
        }
    }
    /// Reads the global set in `Game.difficulty`; used by `Enemy` before the
    /// owning game exists.
    static var current: Difficulty {
        get { Difficulty(rawValue: Game.difficultySetting) ?? .veteran }
        set { Game.difficultySetting = newValue.rawValue }
    }
}

final class Pickup {
    var x: Double, y: Double
    var kind: PickupKind
    var taken = false
    var phase: Double

    init(x: Double, y: Double, kind: PickupKind) {
        self.x = x; self.y = y; self.kind = kind
        self.phase = Double.random(in: 0..<(2 * .pi))
    }
}

final class Barrel {
    var x: Double, y: Double
    var hp: Double = 12
    var burning = false
    var flash: Double = 0
    var gone = false

    init(x: Double, y: Double) { self.x = x; self.y = y }
}

final class Particle {
    var x: Double, y: Double, z: Double
    var vz: Double
    var life: Double
    var maxLife: Double
    var r: Int, g: Int, b: Int
    var size: Double
    var gravity: Double = 2.4

    init(x: Double, y: Double, z: Double, vz: Double, life: Double, color: (Int, Int, Int), size: Double = 0.035) {
        self.x = x; self.y = y; self.z = z; self.vz = vz
        self.life = life; self.maxLife = life
        self.r = color.0; self.g = color.1; self.b = color.2
        self.size = size
    }
}

/// A rocket in flight. Unlike bullets these travel, so they can blow up
/// several enemies (or a barrel chain) at once.
final class Projectile {
    var x: Double, y: Double, z: Double
    var vx: Double, vy: Double
    var damage: Double
    var life = 4.0
    /// Index of the player who fired, so a splash kill is credited to them.
    var owner: Int?
    /// 0..1 armour penetration. A rifle round is stopped by a tank hull; a
    /// tank shell or an AT4 goes through.
    var penetration: Double = 0.1
    /// Radius of the blast; 0 for a direct hit only.
    var splashRadius: Double = 0
    /// An enemy grenade rather than a player rocket. It skips enemy and vehicle
    /// collisions on the way in, so it passes over the shooter and only blows on
    /// its fuse, a wall, or a player.
    var hostile = false

    init(x: Double, y: Double, z: Double, vx: Double, vy: Double, damage: Double,
         owner: Int? = nil, penetration: Double = 0.1, splashRadius: Double = 0) {
        self.x = x; self.y = y; self.z = z
        self.vx = vx; self.vy = vy
        self.damage = damage
        self.owner = owner
        self.penetration = penetration
        self.splashRadius = splashRadius
    }
}

struct WeaponDef {
    let name: String
    let damage: Double
    let pellets: Int
    let spread: Double
    let delay: Double
    let automatic: Bool
    let ammoType: Int
    let sound: String
    let recoil: Double
    let bobAmount: Double
    /// true for the rocket launcher, which spawns a travelling projectile
    let projectile: Bool
    /// 0..1 armour penetration. Ordinary rifles cannot hurt a tank; the AT4 can.
    var penetration: Double = 0.1
    /// splash radius for projectile weapons
    var splash: Double = 3.0
}

enum GameState: Int { case playing = 0, dead = 1, levelDone = 2, victory = 3, start = 4
    var rawValueIfAvailable: Int { rawValue } }

/// Maximum number of local players sharing one keyboard.
let maxLocalPlayers = 3

final class Game {
    // ---- level / flow ----
    var level = Level(w: 8, h: 8)
    var levelIndex = 1
    let maxLevels = 12
    var state: GameState = .start
    var stateTimer = 0.0
    var message = ""
    var messageTimer = 0.0
    var totalScore = 0
    var totalKills = 0
    var time = 0.0
    var showAutomap = false
    var paused = false
    var killFeed: [(text: String, timer: Double)] = []
    /// How many players are in this session (1...maxLocalPlayers).
    var playerCount = 1

    /// All local players. Player 0 is the "real" viewpoint; the others are the
    /// split-screen co-op views.
    var players: [Player] = [Player(index: 0)]

    // ---- entities (shared by all players) ----
    var enemies: [Enemy] = []
    var pickups: [Pickup] = []
    var barrels: [Barrel] = []
    var particles: [Particle] = []
    var projectiles: [Projectile] = []
    var vehicles: [Vehicle] = []
    var totalEnemies = 0

    /// What the player is riding, if anything. `seat` is 0 for driver.
    var riding: Vehicle?
    var ridingSeat = 0

    // ---- weapons / rules ----
    let runSpeed = 3.4

    // ---- difficulty ----
    /// Campaign difficulty, 0...2 (see `Difficulty`). Stored as an Int so it can
    /// live in a static: `Enemy` reads it before any `Game` instance exists.
    static var difficultySetting = Difficulty.veteran.rawValue
    var difficulty: Difficulty {
        get { Difficulty(rawValue: Game.difficultySetting) ?? .veteran }
        set { Game.difficultySetting = newValue.rawValue }
    }

    // ---- end-of-level tally, shown on the victory screen ----
    var levelShots = 0
    var levelHits = 0
    var levelSecrets = 0
    /// Level timer, used for the "clear the level fast" bonus and the summary.
    var levelTime = 0.0
    /// Secret rooms found this level, and the total across the campaign.
    var secretsFound = 0
    var secretsTotal = 0
    /// Best accuracy percentage seen this run, for the victory summary.
    var bestAccuracy = 0

    // ---- player-0 shims ----
    // A huge amount of existing code (renderer, HUD, tests) reads the world from
    // the primary player. Rather than rewrite all of it for co-op, these keep the
    // single-player view reading from player 0; multi-player HUD reads
    // `players[i]` directly.
    var p0: Player { players[0] }
    /// Where the level's exit switch is, for the HUD compass. Nil until the level
    /// has been built or no exit tile exists.
    var exitPoint: (x: Double, y: Double)?
    var px: Double { get { p0.x } set { p0.x = newValue } }
    var py: Double { get { p0.y } set { p0.y = newValue } }
    var pang: Double { get { p0.ang } set { p0.ang = newValue } }
    var health: Double { get { p0.health } set { p0.health = newValue } }
    var armor: Double { get { p0.armor } set { p0.armor = newValue } }
    var ammo: [Int] { get { p0.ammo } set { p0.ammo = newValue } }
    var owned: [Bool] { get { p0.owned } set { p0.owned = newValue } }
    var weapon: Int { get { p0.weapon } set { p0.weapon = newValue } }
    var bobPhase: Double { get { p0.bobPhase } set { p0.bobPhase = newValue } }
    var weaponBob: Double { get { p0.weaponBob } set { p0.weaponBob = newValue } }
    var recoil: Double { get { p0.recoil } set { p0.recoil = newValue } }
    var muzzleFlash: Double { get { p0.muzzleFlash } set { p0.muzzleFlash = newValue } }
    var kick: Double { get { p0.kick } set { p0.kick = newValue } }
    var painTimer: Double { get { p0.painTimer } set { p0.painTimer = newValue } }
    var spawnGrace: Double { get { p0.spawnGrace } set { p0.spawnGrace = newValue } }
    var hitMarker: Double { get { p0.hitMarker } set { p0.hitMarker = newValue } }
    var damageFlash: Double { get { p0.damageFlash } set { p0.damageFlash = newValue } }
    var streak: Int { get { p0.streak } set { p0.streak = newValue } }
    var pickupFlash: Double { get { p0.pickupFlash } set { p0.pickupFlash = newValue } }
    var shake: Double { get { p0.shake } set { p0.shake = newValue } }
    var fireCooldown: Double { get { p0.fireCooldown } set { p0.fireCooldown = newValue } }
    var weaponSwitching: Double { get { p0.weaponSwitching } set { p0.weaponSwitching = newValue } }
    var input: InputState { get { p0.input } set { p0.input = newValue } }
    var clicked: Bool { get { p0.clicked } set { p0.clicked = newValue } }
    var mouseDx: Double { get { p0.mouseDx } set { p0.mouseDx = newValue } }
    var mouseDy: Double { get { p0.mouseDy } set { p0.mouseDy = newValue } }
    var firePressed: Bool { get { p0.firePressed } set { p0.firePressed = newValue } }
    // Score/kills live on the player; these read player 0 for single-player HUD.
    var score: Int { get { p0.score } set { p0.score = newValue } }
    var kills: Int { get { p0.kills } set { p0.kills = newValue } }

    let weapons = [
        WeaponDef(name: "PISTOL", damage: 13, pellets: 1, spread: 0.012, delay: 0.24, automatic: false,
                  ammoType: 0, sound: "pistol", recoil: 0.55, bobAmount: 0.6, projectile: false),
        WeaponDef(name: "SHOTGUN", damage: 11, pellets: 8, spread: 0.075, delay: 0.72, automatic: false,
                  ammoType: 1, sound: "shotgun", recoil: 1.5, bobAmount: 1.4, projectile: false),
        WeaponDef(name: "CHAINGUN", damage: 9, pellets: 1, spread: 0.05, delay: 0.075, automatic: true,
                  ammoType: 0, sound: "chain", recoil: 0.35, bobAmount: 0.9, projectile: false),
        WeaponDef(name: "RIFLE", damage: 8, pellets: 1, spread: 0.03, delay: 0.095, automatic: true,
                  ammoType: 0, sound: "rifle", recoil: 0.3, bobAmount: 1.0, projectile: false),
        WeaponDef(name: "AT4 CS", damage: 150, pellets: 1, spread: 0.0, delay: 1.5, automatic: false,
                  ammoType: 3, sound: "launch", recoil: 1.9, bobAmount: 1.3, projectile: true,
                  penetration: 0.95, splash: 3.4),
        WeaponDef(name: "M320 GL", damage: 100, pellets: 1, spread: 0.0, delay: 1.0, automatic: false,
                  ammoType: 3, sound: "launch", recoil: 1.5, bobAmount: 1.3, projectile: true,
                  penetration: 0.5, splash: 2.8),
        // ---- army additions ----
        WeaponDef(name: "M249 SAW", damage: 10, pellets: 1, spread: 0.024, delay: 0.075, automatic: true,
                  ammoType: 0, sound: "chain", recoil: 0.42, bobAmount: 1.2, projectile: false,
                  penetration: 0.18),
        WeaponDef(name: "MK12 DMR", damage: 20, pellets: 1, spread: 0.006, delay: 0.2, automatic: false,
                  ammoType: 0, sound: "rifle", recoil: 0.9, bobAmount: 0.8, projectile: false,
                  penetration: 0.35),
        WeaponDef(name: "M24 SNIPER", damage: 46, pellets: 1, spread: 0.002, delay: 1.1, automatic: false,
                  ammoType: 0, sound: "rifle", recoil: 1.4, bobAmount: 0.6, projectile: false,
                  penetration: 0.4)
    ]
    var maxAmmo = [200, 50, 300, 60]

    /// Index of the SAW / DMR / sniper in `weapons`. The first six are the
    /// original Doom order and several call sites hard-code them.
    static let sawIndex = 6
    static let dmrIndex = 7
    static let sniperIndex = 8

    /// Three-letter tags for the arms rack, one per weapon.
    static let weaponTags = ["PST", "SHT", "CHN", "RIF", "AT4", "GLW", "SAW", "DMR", "SPR"]

    init() { }

    /// Short name for the ammo type a weapon uses (status bar / dry-fire warning).
    func ammoLabel(for index: Int) -> String {
        switch index {
        case 1: return "SHELLS"
        case 2: return "CELLS"
        case 3: return "ROCKETS"
        default: return "BULLETS"
        }
    }

    /// Grow/shrink the local roster, keeping player 0 intact so a mid-game change
    /// to player count does not teleport the player you are already controlling.
    func setPlayerCount(_ n: Int) {
        playerCount = max(1, min(maxLocalPlayers, n))
        while players.count > playerCount { players.removeLast() }
        while players.count < playerCount {
            let p = Player(index: players.count)
            p.reset(at: spawnPoint(for: p.index), keepScore: false)
            // join with some kit so a late joiner is not helpless
            p.owned[1] = true; p.ammo[1] = 12
            players.append(p)
        }
        // nobody may spawn inside a wall, even on a mid-game roster change
        for p in players { unstick(p) }
    }

    /// Nudge a spawn position off any wall it happens to land in.
    func unstick(_ p: Player) {
        if !level.solidAtPoint(p.x, p.y, radius: 0.24, doorsPassable: false) { return }
        let s = spawnPoint(for: p.index)
        p.x = s.x
        p.y = s.y
        p.ang = s.ang
    }

    /// Player 0 uses the level's designed spawn; co-op partners fan out behind
    /// them so three views never start stacked on one tile.
    func spawnPoint(for index: Int) -> (x: Double, y: Double, ang: Double) {
        let base = level.startPos
        guard index > 0 else { return base }
        let offsets: [(Double, Double)] = [(0, -1.1), (0, 1.1), (-1.1, 0), (1.1, 0), (-0.8, -0.8), (0.8, 0.8)]
        let ox = offsets[(index - 1) % offsets.count].0
        let oy = offsets[(index - 1) % offsets.count].1
        let x = base.x + cos(base.ang + .pi / 2) * ox - cos(base.ang) * oy
        let y = base.y + sin(base.ang + .pi / 2) * ox - sin(base.ang) * oy
        if !level.solidAtPoint(x, y, radius: 0.24, doorsPassable: false) {
            return (x, y, base.ang)
        }
        return base
    }

    // MARK: level control

    func startNewGame() {
        totalScore = 0
        totalKills = 0
        secretsFound = 0
        bestAccuracy = 0
        levelIndex = 1
        loadLevel()
    }

    /// Death restart: same level, keep the campaign progress.
    func restartLevel() {
        loadLevel()
    }

    func loadLevel() {
        level = LevelBuilder.build(level: levelIndex)
        if players.isEmpty { players = [Player(index: 0)] }
        for p in players { p.reset(at: spawnPoint(for: p.index), keepScore: false) }
        levelShots = 0
        levelHits = 0
        levelSecrets = 0
        levelTime = 0
        secretsTotal = level.secrets.count
        exitPoint = level.exitPos
        enemies = level.enemySpecs.map { Enemy(x: $0.x, y: $0.y, type: $0.type, difficulty: levelIndex) }
        pickups = level.pickupSpecs.map { Pickup(x: $0.x, y: $0.y, kind: $0.kind) }
        barrels = level.barrelSpecs.map { Barrel(x: $0.x, y: $0.y) }
        vehicles = spawnVehicles()
        riding = nil
        ridingSeat = 0
        for p in players { p.rides = nil }
        particles.removeAll()
        projectiles.removeAll()
        totalEnemies = enemies.count
        killFeed.removeAll()
        paused = false
        state = .playing
        stateTimer = 0
        showAutomap = false
        setMessage(playerCount > 1
                   ? "LEVEL \(levelIndex)  -  \(playerCount) PLAYERS  -  FIND THE EXIT"
                   : "LEVEL \(levelIndex)  -  FIND THE EXIT", 2.6)
    }

    func nextLevel() {
        levelIndex += 1
        if levelIndex > maxLevels {
            state = .victory
            stateTimer = 0
        } else {
            loadLevel()
        }
    }

    func setMessage(_ m: String, _ t: Double) {
        message = m
        messageTimer = t
    }

    // MARK: geometry helpers

    /// Populate a level with vehicles. A few are parked as drivable wrecks-to-be
    /// (friendly, parked) and the rest are hostile and start driving at you.
    /// Count and mix scale with the campaign so level 1 is not a tank graveyard.
    private func spawnVehicles() -> [Vehicle] {
        var out: [Vehicle] = []
        let count = min(6, 1 + levelIndex / 2)
        let start = level.startPos
        var placed = 0
        var guardCount = 0
        // Try a ring of candidate spots around the level centre, walking outward
        // from the start so nothing spawns on top of the players.
        while placed < count && guardCount < 400 {
            guardCount += 1
            let a = Double.random(in: 0..<(2 * .pi))
            let r = 6 + Double.random(in: 0...7)
            let x = min(max(1.5, start.x + cos(a) * r), Double(level.w) - 1.5)
            let y = min(max(1.5, start.y + sin(a) * r), Double(level.h) - 1.5)
            guard let def = pickVehicleDef() else { break }
            if level.solidAtPoint(x, y, radius: def.radius, doorsPassable: false) { continue }
            // keep them apart so they do not stack into one sprite
            if out.contains(where: { hypot($0.x - x, $0.y - y) < 3.5 }) { continue }
            let hostile = placed >= 1 || levelIndex > 1
            out.append(Vehicle(def: def, x: x, y: y, ang: a + .pi, hostile: hostile))
            placed += 1
        }
        return out
    }

    private func pickVehicleDef() -> VehicleDef? {
        // Weight toward what the campaign has introduced: air and heavy armour
        // turn up later, light tactical early.
        let pool: [String]
        if levelIndex <= 1 { pool = ["humvee", "mrap", "jlvt"] }
        else if levelIndex <= 3 { pool = Army.groundRoster + ["blackhawk", "lakota"] }
        else { pool = Army.vehicles.map { $0.id } }
        let id = pool.randomElement()!
        return Army.def(id)
    }

    /// True when this player is on the gun rather than the driver's seat.
    func ridingSeatIsGunner(_ p: Player) -> Bool {
        guard let v = riding, v === p.rides else { return false }
        return v.gunner == p.index && v.driver != p.index
    }

    func solidAt(_ x: Double, _ y: Double, doorsPassable: Bool = false) -> Bool {
        level.solidAtPoint(x, y, radius: 0.001, doorsPassable: doorsPassable)
    }

    /// Distance to the first blocking wall along a ray.
    func wallDistance(_ ox: Double, _ oy: Double, _ dx: Double, _ dy: Double,
                      _ maxDist: Double, doorsPassable: Bool = false) -> Double {
        level.wallDistance(ox, oy, dx, dy, maxDist, doorsPassable: doorsPassable)
    }

    func lineOfSight(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
        let dx = x1 - x0, dy = y1 - y0
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > 0.0001 else { return true }
        return wallDistance(x0, y0, dx / d, dy / d, d, doorsPassable: true) >= d - 0.05
    }

    // MARK: update

    func update(_ dt: Double) {
        if paused {
            for p in players { p.input.firePressed = false }
            p0.mouseDx = 0
            p0.mouseDy = 0
            return
        }
        time += dt
        messageTimer = max(0, messageTimer - dt)
        for p in players {
            p.shake = max(0, p.shake - dt * 3.2)
            p.damageFlash = max(0, p.damageFlash - dt * 2.2)
            p.pickupFlash = max(0, p.pickupFlash - dt * 3.0)
            p.weaponSwitching = max(0, p.weaponSwitching - dt)
            p.fireCooldown = max(0, p.fireCooldown - dt)
            p.painTimer = max(0, p.painTimer - dt)
            p.hitMarker = max(0, p.hitMarker - dt * 3.0)
            p.spawnGrace = max(0, p.spawnGrace - dt)
            p.berserk = max(0, p.berserk - dt)
            p.invulnerable = max(0, p.invulnerable - dt)
            if p.streak > 0 {
                p.streakTimer -= dt
                if p.streakTimer <= 0 {
                    p.streak = 0
                    p.streakTimer = 0
                }
            }
                // NB: the firePressed edge is cleared at the *end* of the frame, not
            // here. Clearing it before updatePlayer runs swallows the click that
            // started the frame, so single-shot weapons never fire.
        }
        for i in killFeed.indices { killFeed[i].timer -= dt }
        killFeed.removeAll { $0.timer <= 0 }
        updateParticles(dt)
        updateDoors(dt)
        updateProjectiles(dt)
        updateVehicles(dt)

        switch state {
        case .start:
            // a real click or a movement key, never mouse *movement*: AppKit sends a
            // mouseMoved the moment the window appears under the pointer, and that
            // used to skip the title and grab the cursor before the player was ready
            if p0.input.firePressed || p0.input.fire || p0.firePressed || p0.clicked
                || p0.input.forward != 0 || p0.input.strafe != 0 {
                p0.clicked = false
                startNewGame()
            }
        case .dead:
            stateTimer += dt
            if stateTimer > 1.4 && (p0.input.firePressed || p0.input.fire || p0.firePressed) {
                restartLevel()
                p0.input.firePressed = false
                p0.firePressed = false
            }
        case .levelDone:
            stateTimer += dt
            if stateTimer > 1.6 { stateTimer = 0; nextLevel() }
        case .victory:
            stateTimer += dt
            if stateTimer > 0.6 && (p0.input.firePressed || p0.input.fire || p0.firePressed) {
                startNewGame()
                p0.input.firePressed = false
                p0.firePressed = false
            }
        case .playing:
            levelTime += dt
            for p in players { updatePlayer(p, dt) }
            checkSecrets()
            updateEnemies(dt)
            updateBarrels(dt)
            updatePickups(dt)
            checkExit()
        }

        // end-of-frame edge cleanup: a click or key-press is a one-frame event
        for p in players {
            p.input.firePressed = false
            p.firePressed = false
            p.clicked = false
            p.mouseDx = 0
            p.mouseDy = 0
        }
    }

    // MARK: projectiles

    private func updateProjectiles(_ dt: Double) {
        guard !projectiles.isEmpty else { return }
        var survivors: [Projectile] = []
        // substep so fast rockets cannot tunnel through a wall or an enemy
        let steps = 4
        for p in projectiles {
            p.life -= dt
            var detonated = p.life <= 0
            for _ in 0..<steps where !detonated {
                p.x += p.vx * dt / Double(steps)
                p.y += p.vy * dt / Double(steps)
                if solidAt(p.x, p.y, doorsPassable: false) {
                    detonated = true
                    break
                }
                if !p.hostile {
                    for e in enemies where !e.dead {
                        if hypot(e.x - p.x, e.y - p.y) < e.radius + 0.2 {
                            detonated = true
                            break
                        }
                    }
                    if detonated { break }
                }
                for b in barrels where !b.gone {
                    if hypot(b.x - p.x, b.y - p.y) < 0.42 {
                        detonated = true
                        break
                    }
                }
                for v in vehicles where !v.dead {
                    if hypot(v.x - p.x, v.y - p.y) < v.def.radius + 0.2 {
                        detonated = true
                        break
                    }
                }
                // an enemy grenade is the one projectile that hurts the thrower's
                // side, so it stops on a player too
                if p.hostile {
                    for pl in players where !pl.down {
                        if hypot(pl.x - p.x, pl.y - p.y) < 0.42 {
                            detonated = true
                            break
                        }
                    }
                }
            }
            if detonated {
                explodeRocket(p)
            } else {
                survivors.append(p)
            }
        }
        projectiles = survivors
    }

    private func explodeRocket(_ p: Projectile) {
        shakeAll(1.0)
        Sound.play("explode", position: (p.x, p.y), listener: (p0.x, p0.y, p0.ang), maxDistance: 36)
        for _ in 0..<30 {
            particles.append(Particle(x: p.x, y: p.y, z: p.z + Double.random(in: -0.15...0.25),
                                      vz: Double.random(in: 0.5...3.2),
                                      life: Double.random(in: 0.25...0.8),
                                      color: (255, 150, 60), size: 0.07))
        }
        for _ in 0..<10 {
            particles.append(Particle(x: p.x, y: p.y, z: p.z,
                                      vz: Double.random(in: 0.2...1.2),
                                      life: Double.random(in: 0.3...0.6),
                                      color: (90, 90, 96), size: 0.09))
        }
        let radius = p.splashRadius > 0 ? p.splashRadius : 3.0
        let credit = p.owner.flatMap { i in i < players.count ? players[i] : nil }
        for e in enemies where !e.dead {
            let d = hypot(e.x - p.x, e.y - p.y)
            if d < radius {
                damageEnemy(e, damage: p.damage * (1.0 - d / radius * 0.6), by: credit)
            }
        }
        for b in barrels where !b.gone && hypot(b.x - p.x, b.y - p.y) < radius {
            explodeBarrel(b, damage: p.damage, by: credit)
        }
        for v in vehicles where !v.dead {
            let d = hypot(v.x - p.x, v.y - p.y)
            if d < radius + v.def.radius {
                damageVehicle(v, p.damage * (1.0 - d / (radius + v.def.radius) * 0.5),
                              penetration: p.penetration, by: credit)
            }
        }
        // splash hurts every player in range, including the one who fired
        for pl in players where !pl.down {
            if pl.spawnGrace > 0 { continue }
            let d = hypot(pl.x - p.x, pl.y - p.y)
            if d < radius { hurt(pl, (1.0 - d / radius) * 55, ignoreArmor: false) }
        }
    }

    private func updateParticles(_ dt: Double) {
        for p in particles {
            p.life -= dt
            p.z += p.vz * dt
            p.vz -= p.gravity * dt
            if p.z < 0.02 { p.z = 0.02; p.vz = abs(p.vz) * 0.35 }
        }
        if !particles.isEmpty { particles.removeAll { $0.life <= 0 } }
        // a chain of explosions can spawn hundreds of sparks; keep the draw cost
        // bounded by dropping the oldest ones
        let maxParticles = 420
        if particles.count > maxParticles { particles.removeFirst(particles.count - maxParticles) }
    }

    private func updateDoors(_ dt: Double) {
        let w = level.w, h = level.h
        for y in 0..<h {
            for x in 0..<w where level.at(x, y) == Tile.door {
                let i = y * w + x
                let cx = Double(x) + 0.5, cy = Double(y) + 0.5
                var wantOpen = false
                for p in players where !p.down && hypot(p.x - cx, p.y - cy) < 1.9 { wantOpen = true; break }
                if !wantOpen {
                    for e in enemies where !e.dead && hypot(e.x - cx, e.y - cy) < 1.6 { wantOpen = true; break }
                }
                let rate = wantOpen ? 1.5 : 0.85
                level.doorProgress[i] = min(1, max(0, level.doorProgress[i] + (wantOpen ? rate : -rate) * dt))
            }
        }
    }

    // MARK: player

    private func updatePlayer(_ p: Player, _ dt: Double) {
        // A downed player is out until their respawn timer runs out.
        if p.down {
            p.respawnTimer -= dt
            p.input.fire = false
            p.input.firePressed = false
            if p.respawnTimer <= 0 {
                leaveVehicle(p)
                p.reset(at: spawnPoint(for: p.index), keepScore: true)
                p.spawnGrace = 1.4
                setMessage("\(p.name) IS BACK IN", 1.4)
                Sound.play("switch")
            }
            return
        }

        // riding: the view is the vehicle's, movement drives it
        if riding !== nil {
            if p.index == 0 { updateDriver(p, dt) }
            p.input.firePressed = false
            return
        }

        p.ang += p.mouseDx * 0.0032
        p.ang += p.input.turn * 2.6 * dt
        let f = p.input.forward, s = p.input.strafe
        let speed = (p.input.run ? runSpeed * 1.5 : runSpeed) * (p.painTimer > 0 ? 0.82 : 1.0)
        var dx = 0.0, dy = 0.0
        let dirX = cos(p.ang), dirY = sin(p.ang)
        if f != 0 || s != 0 {
            let len = (f * f + s * s).squareRoot()
            let nf = f / len, ns = s / len
            dx = dirX * nf * speed * dt - dirY * ns * speed * dt
            dy = dirY * nf * speed * dt + dirX * ns * speed * dt
            p.bobPhase += Double(len) * dt * 11
            if f != 0 { p.weaponBob = min(1.6, p.weaponBob + dt * 6) }
            else { p.weaponBob = min(1.6, p.weaponBob + dt * 2) }
        } else {
            p.weaponBob = max(0, p.weaponBob - dt * 6)
        }
        moveActor(&p.x, &p.y, dx, dy, radius: 0.24, pusher: p)

        p.recoil = max(0, p.recoil - dt * 5.5)
        p.kick = max(0, p.kick - dt * 9.0)
        p.muzzleFlash = max(0, p.muzzleFlash - dt * 14)

        // weapon switching (number keys / wheel handled by view)
        let inp = p.input
        if inp.wantWeapon >= 0 && inp.wantWeapon < weapons.count {
            if p.owned[inp.wantWeapon] && inp.wantWeapon != p.weapon {
                p.weapon = inp.wantWeapon
                p.weaponSwitching = 0.22
                Sound.play("switch")
            }
            inp.wantWeapon = -1
        }
        for i in 0..<inp.nextWeapons.count {
            let target = inp.nextWeapons[i]
            if target >= 0 && target < p.owned.count && p.owned[target] && target != p.weapon {
                p.weapon = target
                p.weaponSwitching = 0.22
                Sound.play("switch")
            }
        }
        inp.nextWeapons.removeAll()

        // firing
        let w = weapons[p.weapon]
        let wantFire = w.automatic ? (inp.fire || inp.firePressed) : inp.firePressed
        if wantFire && p.weaponSwitching <= 0 && p.fireCooldown <= 0 {
            if p.ammo[w.ammoType] > 0 {
                fire(p)
            } else {
                p.fireCooldown = 0.3
                Sound.play("click")
                let what = p.weapon == 0 ? "OUT OF BULLETS" : "OUT OF \(ammoLabel(for: w.ammoType))"
                setMessage("\(p.name)  \(what) - SWITCH WEAPON", 1.0)
            }
        }
        inp.firePressed = false
    }

    /// Translate the driver's movement keys into hull heading and throttle, and
    /// keep the camera glued to the vehicle so the view feels like the vehicle.
    private func updateDriver(_ p: Player, _ dt: Double) {
        guard let v = riding, !v.dead else { return }
        let throttle = p.input.forward
        let steer = p.input.strafe

        // mouse steers the hull when driving, turret when on the gun
        if ridingSeat == 0 {
            p.ang += p.mouseDx * 0.0026
            v.ang = p.ang
        } else {
            v.turretAng = clampAngle(v.turretAng + p.mouseDx * 0.0030, -2.2, 2.2)
            p.ang = v.ang + v.turretAng
        }
        p.mouseDx = 0
        p.mouseDy = 0

        if ridingSeat == 0 {
            let turn = steer * v.def.turnRate * dt * (v.speed >= 0 ? 1 : -1)
            v.ang = wrapAngle(v.ang + turn)
            p.ang = v.ang
            let target = v.def.maxSpeed * throttle
            v.speed += (target - v.speed) * min(1, dt * v.def.accel * 0.5)
            let step = v.speed * dt
            let nx = v.x + cos(v.ang) * step
            let ny = v.y + sin(v.ang) * step
            if !level.solidAtPoint(nx, ny, radius: v.def.radius, doorsPassable: false) {
                v.x = nx
                v.y = ny
            } else {
                v.speed *= -0.2
                p.addShake(0.4)
            }
        }

        // the camera rides with the vehicle
        p.x = v.x
        p.y = v.y
        p.bobPhase += abs(v.speed) * dt * 4
        p.weaponBob = min(1.2, p.weaponBob + abs(v.speed) * dt * 0.5)
        p.muzzleFlash = max(0, p.muzzleFlash - dt * 12)
    }

    private func clampAngle(_ a: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, a))
    }

    private func moveActor(_ x: inout Double, _ y: inout Double, _ dx: Double, _ dy: Double,
                           radius: Double, pusher: Player? = nil) {
        let steps = 3
        let sx = dx / Double(steps), sy = dy / Double(steps)
        for _ in 0..<steps {
            if !level.solidAtPoint(x + sx, y, radius: radius, doorsPassable: false) { x += sx }
            if !level.solidAtPoint(x, y + sy, radius: radius, doorsPassable: false) { y += sy }
        }
        // body-block the other players: three views stacked on one tile is both
        // unfair and unreadable
        if let pusher {
            for o in players where o !== pusher && !o.down {
                let dx = x - o.x, dy = y - o.y
                let d2 = dx * dx + dy * dy
                let minD = radius + o.radius
                if d2 < minD * minD && d2 > 0.000001 {
                    let d = d2.squareRoot()
                    let push = (minD - d)
                    let ux = dx / d, uy = dy / d
                    if !level.solidAtPoint(x + ux * push, y, radius: radius, doorsPassable: false) { x += ux * push }
                    if !level.solidAtPoint(x, y + uy * push, radius: radius, doorsPassable: false) { y += uy * push }
                }
            }
        }
    }

    private func fire(_ p: Player) {
        let w = weapons[p.weapon]
        p.ammo[w.ammoType] = max(0, p.ammo[w.ammoType] - 1)
        // Berserk halves the time between shots, which is what makes it worth
        // picking up on a chaingun rather than a pistol.
        p.fireCooldown = w.delay * (p.berserk > 0 ? 0.5 : 1.0)
        p.recoil = w.recoil
        p.kick = w.recoil
        p.muzzleFlash = 1.0
        p.ang += Double.random(in: -0.006...0.006)
        p.addShake(w.recoil * 0.35)
        p.shotsFired += 1
        let dmg = w.damage * (p.berserk > 0 ? 1.5 : 1.0)
        Sound.play(w.sound)
        if w.projectile {
            projectiles.append(Projectile(x: p.x + cos(p.ang) * 0.4, y: p.y + sin(p.ang) * 0.4,
                                          z: Renderer.eyeHeight,
                                          vx: cos(p.ang) * 15.0, vy: sin(p.ang) * 15.0,
                                          damage: dmg, owner: p.index,
                                          penetration: w.penetration, splashRadius: w.splash))
            return
        }
        var anyHit = false
        for _ in 0..<w.pellets {
            let a = p.ang + Double.random(in: -w.spread...w.spread)
            if shoot(angle: a, damage: dmg, from: p, penetration: w.penetration) { anyHit = true }
        }
        if anyHit {
            p.shotsHit += 1
            levelHits += 1
        }
        levelShots += 1
        if let acc = accuracy { bestAccuracy = max(bestAccuracy, Int(acc * 100)) }
    }

    /// Hitscan shot. Returns true if it hit something. The nearest actor along the
    /// ray wins, so a barrel in front of an enemy absorbs the shot.
    @discardableResult
    private func shoot(angle: Double, damage: Double, from shooter: Player,
                       penetration: Double = 0.1) -> Bool {
        let ox = shooter.x, oy = shooter.y
        let dx = cos(angle), dy = sin(angle)
        let maxDist = 40.0
        let dist = wallDistance(ox, oy, dx, dy, maxDist, doorsPassable: false)
        var bestT = dist
        var hitEnemy: Enemy?
        var hitBarrel: Barrel?
        var hitVehicle: Vehicle?

        for e in enemies where !e.dead {
            let rx = e.x - ox, ry = e.y - oy
            let t = rx * dx + ry * dy
            guard t > 0 && t < bestT else { continue }
            let perp = abs(rx * dy - ry * dx)
            if perp < e.radius + 0.12 {
                bestT = t
                hitEnemy = e
                hitBarrel = nil
                hitVehicle = nil
            }
        }

        for b in barrels where !b.gone {
            let rx = b.x - ox, ry = b.y - oy
            let t = rx * dx + ry * dy
            guard t > 0 && t < bestT else { continue }
            let perp = abs(rx * dy - ry * dx)
            if perp < 0.32 {
                bestT = t
                hitBarrel = b
                hitEnemy = nil
                hitVehicle = nil
            }
        }

        // vehicles are big and opaque: a shot that reaches one stops there
        for v in vehicles where !v.dead {
            let rx = v.x - ox, ry = v.y - oy
            let t = rx * dx + ry * dy
            guard t > 0 && t < bestT else { continue }
            let perp = abs(rx * dy - ry * dx)
            if perp < v.def.radius {
                bestT = t
                hitVehicle = v
                hitEnemy = nil
                hitBarrel = nil
            }
        }

        if let e = hitEnemy {
            damageEnemy(e, damage: damage, by: shooter)
            shooter.hitMarker = 1.0
            for _ in 0..<7 {
                particles.append(Particle(x: e.x, y: e.y, z: 0.45 + Double.random(in: 0...0.35),
                                          vz: Double.random(in: 0.4...2.0),
                                          life: Double.random(in: 0.18...0.5),
                                          color: (150, 20, 24)))
            }
            return true
        }
        if let b = hitBarrel {
            explodeBarrel(b, damage: damage)
            return true
        }
        if let v = hitVehicle {
            damageVehicle(v, damage, penetration: penetration, by: shooter)
            for _ in 0..<6 {
                particles.append(Particle(x: v.x + dx * bestT, y: v.y + dy * bestT, z: 0.5,
                                          vz: Double.random(in: 0.4...1.6),
                                          life: Double.random(in: 0.12...0.35),
                                          color: (230, 200, 120), size: 0.025))
            }
            return true
        }

        // wall impact sparks
        let hx = ox + dx * dist, hy = oy + dy * dist
        for _ in 0..<4 {
            particles.append(Particle(x: hx, y: hy, z: 0.5, vz: Double.random(in: 0.2...1.0),
                                      life: Double.random(in: 0.08...0.2),
                                      color: (200, 190, 160), size: 0.02))
        }
        return false
    }

    /// Single funnel for every source of enemy damage (hitscan, splash, rockets).
    /// `credit` is the player who earned the kill, if it was a player at all.
    /// Fraction of `damage` a rioter's ballistic shield soaks. Frontal fire
    /// from the player's own viewpoint is what the shield is for, so the check
    /// is done by the caller (which knows the shot direction) and passed in.
    func damageEnemy(_ e: Enemy, damage: Double, by credit: Player? = nil, frontal: Bool = true) {
        var dmg = damage
        if e.armored && frontal { dmg *= 0.55 }
        e.hp -= dmg
        e.flash = 0.12
        e.alertTimer = 10
        e.gore = min(1, e.gore + 0.12)
        if e.hp <= 0 {
            killEnemy(e, by: credit)
        } else if e.state == .idle || e.state == .chase {
            e.state = .pain
            e.painTimer = e.type == 0 ? 0.16 : 0.10
            Sound.play("imp")
        }
    }

    private func killEnemy(_ e: Enemy, by credit: Player?) {
        // guard: without this the corpse keeps acting and counts twice
        guard !e.dead else { return }
        e.dead = true
        e.state = .dead
        e.deadTimer = 0
        totalKills += 1
        // credit goes to the shooter; when nobody shot it (rocket splash on a
        // corpse chain, say) it goes to whoever is nearest, and if nobody is left
        // to care it is simply uncounted
        let who = credit ?? nearestPlayer(to: e.x, e.y)
        let mult = Difficulty.current.scoreMultiplier
        if let p = who {
            p.kills += 1
            // the streak is bumped *before* the score is priced, so the first kill
            // is worth face value and the second already carries a bonus
            p.streak += 1
            p.streakTimer = Game.streakWindow
            if p.streak > p.bestStreak { p.bestStreak = p.streak }
        }
        let pts = Int(Double(e.scoreValue) * (who?.streakMultiplier ?? 1.0) * mult)
        who?.score += pts
        totalScore += pts
        let tag = who.map { "\($0.name)  " } ?? ""
        var text = "\(tag)\(e.name)  +\(pts)"
        if let p = who, p.streak >= 3 {
            text += "  X\(String(format: "%.1f", p.streakMultiplier))"
        }
        killFeed.append((text: text, timer: 3.0))
        if killFeed.count > 5 { killFeed.removeFirst(killFeed.count - 5) }
        setMessage("\(tag)\(e.name) DESTROYED  +\(pts)", 1.1)
        if e.isMarksman { Sound.play("marksmandeath") } else { Sound.play("death") }
        for _ in 0..<14 {
            particles.append(Particle(x: e.x, y: e.y, z: 0.4 + Double.random(in: 0...0.4),
                                      vz: Double.random(in: 0.3...2.2),
                                      life: Double.random(in: 0.25...0.7),
                                      color: (128, 16, 20), size: 0.05))
        }
    }

    /// Seconds a kill streak stays alive without another kill.
    static let streakWindow = 6.0

    private func nearestPlayer(to x: Double, _ y: Double) -> Player? {
        var best: Player?
        var bestD = Double.infinity
        for p in players where !p.down {
            let d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)
            if d < bestD { bestD = d; best = p }
        }
        return best
    }

    private func explodeBarrel(_ b: Barrel, damage: Double, by credit: Player? = nil) {
        b.hp -= damage
        b.flash = 0.1
        if b.hp <= 0 && !b.gone {
            b.gone = true
            shakeAll(1.0)
            Sound.play("explode")
            for _ in 0..<26 {
                particles.append(Particle(x: b.x, y: b.y, z: 0.3 + Double.random(in: 0...0.5),
                                          vz: Double.random(in: 0.5...3.0),
                                          life: Double.random(in: 0.3...0.8),
                                          color: (255, 140, 40),
                                          size: 0.06))
            }
            // splash damage
            for e in enemies where !e.dead {
                let d = hypot(e.x - b.x, e.y - b.y)
                if d < 2.4 {
                    damageEnemy(e, damage: (1.0 - d / 2.4) * 130, by: credit)
                }
            }
            // splash hits every player, including whoever set it off
            for p in players where !p.down && p.spawnGrace <= 0 {
                let d = hypot(p.x - b.x, p.y - b.y)
                if d < 2.4 { hurt(p, (1.0 - d / 2.4) * 45, ignoreArmor: false) }
            }
            // chain reaction
            for other in barrels where !other.gone {
                if hypot(other.x - b.x, other.y - b.y) < 1.6 { explodeBarrel(other, damage: 40, by: credit) }
            }
        }
    }

    /// Test hook: detonate a barrel on demand so the splash path can be checked
    /// without having to land a shot first.
    func explodeBarrelForTest(_ b: Barrel, damage: Double) {
        b.hp = 0
        explodeBarrel(b, damage: damage)
    }

    /// Camera shake is shared: a blast goes off for everybody.
    private func shakeAll(_ amount: Double) {
        for p in players { p.addShake(amount) }
    }

    func hurt(_ p: Player, _ amount: Double, ignoreArmor: Bool) {
        guard state == .playing, !p.down else { return }
        // invulnerability eats the hit outright, but still shows the flash so the
        // player knows something happened
        if p.invulnerable > 0 {
            p.damageFlash = min(1.0, p.damageFlash + 0.2)
            Sound.play("click")
            return
        }
        var dmg = amount * Difficulty.current.enemyDamage
        if !ignoreArmor && p.armor > 0 {
            let absorbed = min(p.armor, dmg / 3.0)
            p.armor -= absorbed
            dmg -= absorbed
        }
        p.health = max(0, p.health - dmg)
        p.painTimer = 0.35
        p.damageFlash = min(1.0, p.damageFlash + 0.45)
        p.addShake(0.35)
        Sound.play("hurt")
        if p.health <= 0 {
            p.down = true
            p.respawnTimer = Player.respawnDelay
            // the player who fired most recently hears the death sting, and the
            // team gets told who is down
            setMessage(playerCount > 1 ? "\(p.name) IS DOWN  -  REDEPLOY IN \(Int(Player.respawnDelay))"
                                       : "YOU DIED  -  PRESS FIRE", 99)
            if playerCount == 1 {
                state = .dead
                stateTimer = 0
            }
        }
    }

    // MARK: enemies

    // MARK: vehicles

    /// Board or leave the nearest vehicle. Bound to F.
    func toggleVehicle(for p: Player) {
        if riding != nil { leaveVehicle(p); return }
        var best: Vehicle?
        var bestD = 2.2
        for v in vehicles where !v.dead && !v.hostile {
            let d = hypot(v.x - p.x, v.y - p.y)
            if d < bestD + v.def.radius {
                bestD = d
                best = v
            }
        }
        guard let v = best else {
            setMessage("NO VEHICLE NEARBY", 1.0)
            return
        }
        if v.driver < 0 { v.driver = p.index } else if v.gunner < 0 { v.gunner = p.index }
        riding = v
        p.rides = v
        ridingSeat = v.driver == p.index ? 0 : 1
        p.ang = v.ang + (ridingSeat == 0 ? 0 : v.turretAng)
        p.input.firePressed = false
        p.recoil = 0
        Sound.play("switch")
        setMessage("\(p.name)  MOUNTED \(v.def.name)", 1.6)
    }

    func leaveVehicle(_ p: Player) {
        guard let v = riding else { return }
        // step out to the side, never into a wall
        let side = v.ang + .pi / 2
        for off in [0.9, -0.9, 1.6, -1.6, 2.4, -2.4] {
            let nx = v.x + cos(side) * off
            let ny = v.y + sin(side) * off
            if !level.solidAtPoint(nx, ny, radius: p.radius, doorsPassable: false) {
                p.x = nx; p.y = ny
                break
            }
        }
        if v.driver == p.index { v.driver = -1 }
        if v.gunner == p.index { v.gunner = -1 }
        riding = nil
        p.rides = nil
        ridingSeat = 0
        Sound.play("switch")
    }

    private func updateVehicles(_ dt: Double) {
        for v in vehicles {
            if v.dead {
                v.deadTimer += dt
                continue
            }
            v.flash = max(0, v.flash - dt * 4)
            v.fireCooldown = max(0, v.fireCooldown - dt)
            v.secondaryCooldown = max(0, v.secondaryCooldown - dt)
            v.alertTimer = max(0, v.alertTimer - dt)
            v.animPhase += dt * 6
            if v.def.flying { v.rotorPhase += dt * 30 }

            if v.hostile && v.driver < 0 {
                driveAI(v, dt)
            } else if v.driver >= 0 {
                // human-driven: speed was set by the input path this frame
            } else {
                v.speed *= max(0, 1 - dt * 3)   // parked, roll to a stop
            }

            // anyone riding shoots through the vehicle's gun
            for (seat, who) in [(0, v.driver), (1, v.gunner)] where who >= 0 {
                guard let p = players.first(where: { $0.index == who }), !p.down else { continue }
                let gun = seat == 0 ? v.def.gun : (v.def.secondary ?? v.def.gun)
                let wantFire = gun.automatic ? p.input.fire : p.input.firePressed
                if wantFire && v.fireCooldown <= 0 {
                    fireVehicleGun(v, gun, by: p, seat: seat)
                }
            }
        }
        // wrecks eventually get cleaned up so a long level does not fill with sprites
        vehicles.removeAll { $0.dead && $0.deadTimer > 30 }
    }

    /// Drive and shoot a hostile vehicle. Helicopters strafe and hover; ground
    /// vehicles drive at the nearest player and keep a stand-off distance.
    private func driveAI(_ v: Vehicle, _ dt: Double) {
        guard let tp = nearestPlayer(to: v.x, v.y) else {
            v.speed *= max(0, 1 - dt * 2)
            return
        }
        let dx = tp.x - v.x, dy = tp.y - v.y
        let dist = (dx * dx + dy * dy).squareRoot()
        let sees = dist < 20 && lineOfSight(v.x, v.y, tp.x, tp.y)
        if sees { v.alertTimer = 8 }

        let want = atan2(dy, dx)
        // turret always tracks the target
        v.turretAng = angleLerp(v.turretAng, wrapAngle(want - v.ang), min(1, dt * 2.4))

        v.aiTimer -= dt
        if v.aiTimer <= 0 {
            v.aiTimer = 0.6 + Double.random(in: 0...0.8)
            v.aiWander = Double.random(in: -0.6...0.6)
        }

        if v.alertTimer > 0 {
            // close to a preferred stand-off, then hold
            let standoff = v.def.cls == .mbt ? 7.0 : (v.def.flying ? 6.0 : 4.5)
            if dist > standoff * 1.25 { driveToward(v, want, 1.0, dt) }
            else if dist < standoff * 0.6 { driveToward(v, want + .pi, 0.8, dt) }
            else { v.speed *= max(0, 1 - dt * 4) }

            if sees && v.fireCooldown <= 0 && dist < v.def.gun.range {
                let by = players.first { $0.index == 0 }
                fireVehicleGun(v, v.def.gun, by: by, seat: 0)
            }
            // missiles at range on the attack helicopters
            if let sec = v.def.secondary, sees && v.secondaryCooldown <= 0 && dist > 5 {
                fireVehicleGun(v, sec, by: players.first { $0.index == 0 }, seat: 1)
            }
        } else {
            // patrol: wander, bumping off walls
            driveToward(v, v.ang + v.aiWander * 0.4, 0.45, dt)
        }
    }

    private func driveToward(_ v: Vehicle, _ heading: Double, _ throttle: Double, _ dt: Double) {
        let d = wrapAngle(heading - v.ang)
        v.ang = angleLerp(v.ang, v.ang + d, min(1, dt * 2.2))
        v.speed += (v.def.maxSpeed * throttle - v.speed) * min(1, dt * 3)
        let step = v.speed * dt
        let nx = v.x + cos(v.ang) * step
        let ny = v.y + sin(v.ang) * step
        if !level.solidAtPoint(nx, ny, radius: v.def.radius, doorsPassable: false) {
            v.x = nx
            v.y = ny
        } else {
            // nose into a wall: turn on the spot, and kick up a little dust
            v.ang += (v.aiWander >= 0 ? 1 : -1) * dt * 2.5
            v.speed *= 0.3
            if v.animPhase.truncatingRemainder(dividingBy: 0.4) < dt {
                particles.append(Particle(x: v.x, y: v.y, z: 0.2, vz: 0.5, life: 0.5,
                                          color: (130, 120, 96), size: 0.05))
            }
        }
    }

    /// Fire a vehicle weapon. `by` is the player credited with a hit.
    private func fireVehicleGun(_ v: Vehicle, _ gun: MountedGun, by p: Player?, seat: Int) {
        v.fireCooldown = gun.rof
        if seat == 1 { v.secondaryCooldown = gun.rof * 1.4 }
        let a = v.muzzleAngle + Double.random(in: -gun.spread...gun.spread)
        let origin = v.seatOffset(seat)
        Sound.play(gun.sound, position: (origin.x, origin.y), listener: (p0.x, p0.y, p0.ang), volume: 0.9, maxDistance: 34)
        if p != nil && seat == 0 { p?.addShake(gun.shake * 0.4) }

        if gun.hitscan {
            vehicleHitscan(v, gun, from: origin, angle: a, credit: p)
        } else {
            projectiles.append(Projectile(x: origin.x, y: origin.y, z: Renderer.eyeHeight,
                                          vx: cos(a) * 15, vy: sin(a) * 15,
                                          damage: gun.damage, owner: p?.index,
                                          penetration: gun.penetration, splashRadius: gun.splash))
        }
        // muzzle flash puff at the gun
        for _ in 0..<3 {
            particles.append(Particle(x: origin.x + cos(a) * 0.5, y: origin.y + sin(a) * 0.5,
                                      z: 0.5, vz: 0.4, life: 0.12,
                                      color: (255, 220, 150), size: 0.03))
        }
    }

    /// Vehicle fire against infantry, other vehicles, barrels and walls.
    private func vehicleHitscan(_ v: Vehicle, _ gun: MountedGun,
                                from origin: (x: Double, y: Double),
                                angle: Double, credit p: Player?) {
        let dx = cos(angle), dy = sin(angle)
        let maxDist = min(gun.range, Double(level.w + level.h))
        var best = wallDistance(origin.x, origin.y, dx, dy, maxDist, doorsPassable: false)
        var hitPlayer: Player?
        var hitVehicle: Vehicle?
        var hitBarrel: Barrel?

        for pl in players where !pl.down && pl.index != v.driver && pl.index != v.gunner {
            // a freshly spawned player is untouchable, the same as from infantry:
            // without this a level that rolls several vehicles near the start
            // opens with a barrage the player could not have dodged
            if pl.spawnGrace > 0 { continue }
            let t = actorRayHit(origin.x, origin.y, dx, dy, pl.x, pl.y, pl.radius, best)
            if t < best { best = t; hitPlayer = pl; hitVehicle = nil; hitBarrel = nil }
        }
        for o in vehicles where !o.dead && o !== v {
            let t = actorRayHit(origin.x, origin.y, dx, dy, o.x, o.y, o.def.radius, best)
            if t < best { best = t; hitVehicle = o; hitPlayer = nil; hitBarrel = nil }
        }
        for b in barrels where !b.gone {
            let t = actorRayHit(origin.x, origin.y, dx, dy, b.x, b.y, 0.3, best)
            if t < best { best = t; hitBarrel = b; hitPlayer = nil; hitVehicle = nil }
        }

        let hx = origin.x + dx * best, hy = origin.y + dy * best
        if let pl = hitPlayer {
            hurt(pl, gun.damage, ignoreArmor: true)
            pl.addShake(0.7)
            for _ in 0..<4 {
                particles.append(Particle(x: hx, y: hy, z: 0.5, vz: 0.6, life: 0.3,
                                          color: (180, 40, 30), size: 0.03))
            }
        } else if let ov = hitVehicle {
            ov.damage(ov.absorbed(gun.damage, penetration: gun.penetration))
            if p != nil { p?.hitMarker = 1 }
            for _ in 0..<4 {
                particles.append(Particle(x: hx, y: hy, z: 0.5, vz: 0.7, life: 0.25,
                                          color: (210, 190, 120), size: 0.03))
            }
        } else if let b = hitBarrel {
            explodeBarrel(b, damage: gun.damage, by: p)
        } else {
            for _ in 0..<3 {
                particles.append(Particle(x: hx, y: hy, z: 0.5, vz: 0.5, life: 0.16,
                                          color: (180, 150, 120), size: 0.02))
            }
        }
    }

    /// Ray vs circle in 2D. Returns the hit distance, or `max` if it misses.
    func actorRayHit(_ ox: Double, _ oy: Double, _ dx: Double, _ dy: Double,
                     _ cx: Double, _ cy: Double, _ r: Double, _ max: Double) -> Double {
        let mx = ox - cx, my = oy - cy
        let b = mx * dx + my * dy
        let c = mx * mx + my * my - r * r
        if c > 0 && b > 0 { return max }
        let disc = b * b - c
        if disc < 0 { return max }
        let t = -b - disc.squareRoot()
        if t < 0 || t > max { return max }
        return t
    }

    private func wrapAngle(_ a: Double) -> Double {
        var d = a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    func damageVehicle(_ v: Vehicle, _ raw: Double, penetration: Double, by p: Player?) {
        guard !v.dead else { return }
        let dealt = v.absorbed(raw, penetration: penetration)
        v.damage(dealt)
        if p != nil { p?.hitMarker = 1 }
        if v.dead { explodeVehicle(v, by: p) }
    }

    private func explodeVehicle(_ v: Vehicle, by p: Player?) {
        Sound.play("explode", position: (v.x, v.y), listener: (p0.x, p0.y, p0.ang), volume: 1.0, maxDistance: 40)
        for _ in 0..<26 {
            particles.append(Particle(x: v.x + Double.random(in: -0.4...0.4),
                                      y: v.y + Double.random(in: -0.4...0.4),
                                      z: 0.2, vz: Double.random(in: 0.5...2.0),
                                      life: Double.random(in: 0.4...0.9),
                                      color: (255, 150, 60), size: 0.06))
        }
        shakeAll(1.0)
            // splash: hurt anyone standing next to it
            for pl in players where !pl.down && pl.spawnGrace <= 0 {
                let d = hypot(pl.x - v.x, pl.y - v.y)
                if d < 2.5 { hurt(pl, (1 - d / 2.5) * 60, ignoreArmor: true) }
            }
        // chain into barrels
        for b in barrels where !b.gone {
            if hypot(b.x - v.x, b.y - v.y) < 2.0 { explodeBarrel(b, damage: 60, by: p) }
        }
        // and into other vehicles
        for o in vehicles where !o.dead && o !== v {
            if hypot(o.x - v.x, o.y - v.y) < 2.4 {
                o.damage(o.absorbed(50, penetration: 0.3))
                if o.dead { explodeVehicle(o, by: p) }
            }
        }
        if let r = riding, r === v {
            if let p = players.first(where: { $0.index == r.driver || $0.index == r.gunner }) {
                leaveVehicle(p)
                hurt(p, 40, ignoreArmor: true)
            }
            riding = nil
        }
        for pl in players { pl.rides = nil }
        if p != nil { p?.score += 500 }
    }

    private func updateEnemies(_ dt: Double) {
        for e in enemies {
            if e.dead {
                e.deadTimer += dt
                continue
            }
            e.flash = max(0, e.flash - dt)
            e.gore = max(0, e.gore - dt * 0.4)
            e.attackAnim = max(0, e.attackAnim - dt * 3)
            e.fireCooldown = max(0, e.fireCooldown - dt)
            e.alertTimer = max(0, e.alertTimer - dt)
            e.painTimer = max(0, e.painTimer - dt)
            if e.state == .pain && e.painTimer <= 0 { e.state = e.alertTimer > 0 ? .chase : .idle }

            // everyone standing up is a valid target, nearest first
            let tgt = nearestPlayer(to: e.x, e.y)
            guard let tp = tgt else { continue }   // whole squad is down: nothing to chase
            let dxp = tp.x - e.x, dyp = tp.y - e.y
            let dist = (dxp * dxp + dyp * dyp).squareRoot()
            let seesPlayer = dist < e.sightRange && lineOfSight(e.x, e.y, tp.x, tp.y)
            if seesPlayer { e.alertTimer = 8 }

            if e.alertTimer > 0 {
                e.state = .chase
            } else if e.state == .chase {
                e.state = .idle
            }

            switch e.state {
            case .chase:
                e.angle = angleLerp(e.angle, atan2(dyp, dxp), min(1, dt * 7))
                // shooters hold `preferredRange`, melee demons close in
                let engageDist = e.preferredRange
                if dist > engageDist {
                    let sp = e.speed * (e.painTimer > 0 ? 0.4 : 1.0)
                    var mx = cos(e.angle) * sp * dt
                    var my = sin(e.angle) * sp * dt
                    // separation
                    for o in enemies where o !== e && !o.dead {
                        let ox = e.x - o.x, oy = e.y - o.y
                        let d2 = (ox * ox + oy * oy).squareRoot()
                        if d2 < 0.9 && d2 > 0.001 {
                            mx += ox / d2 * dt * 1.4
                            my += oy / d2 * dt * 1.4
                        }
                    }
                    moveActor(&e.x, &e.y, mx, my, radius: e.radius)
                } else if e.attackRange <= 3 && dist < e.preferredRange * 0.85 {
                    // melee types: back off so they do not glue themselves to you
                    moveActor(&e.x, &e.y, -cos(e.angle) * e.speed * 0.4 * dt, -sin(e.angle) * e.speed * 0.4 * dt, radius: e.radius)
                } else if e.attackRange > 3 && dist < e.preferredRange * 0.6 {
                    // shooters: too close, give ground
                    moveActor(&e.x, &e.y, -cos(e.angle) * e.speed * 0.5 * dt, -sin(e.angle) * e.speed * 0.5 * dt, radius: e.radius)
                }
                if dist < e.attackRange && e.fireCooldown <= 0 && seesPlayer && tp.spawnGrace <= 0 {
                    e.fireCooldown = e.attackCooldown
                    e.state = .attack
                    e.attackAnim = 1.0
                    Sound.play(e.attackSound, position: (e.x, e.y), listener: (p0.x, p0.y, p0.ang),
                               maxDistance: 26)
                    if e.throwsGrenade {
                        throwGrenade(e, at: tp)
                    } else {
                        enemyFire(e, at: tp, damage: Double.random(in: e.minDamage...e.maxDamage))
                    }
                }
            case .idle:
                e.wanderTimer -= dt
                if e.wanderTimer <= 0 {
                    e.wanderTimer = Double.random(in: 0.6...2.4)
                    e.wanderAngle = Double.random(in: 0..<(2 * .pi))
                }
                e.angle = angleLerp(e.angle, e.wanderAngle, min(1, dt * 1.6))
                let sp = e.speed * 0.32
                let ox = e.x, oy = e.y
                moveActor(&e.x, &e.y, cos(e.angle) * sp * dt, sin(e.angle) * sp * dt, radius: e.radius)
                if hypot(ox - e.x, oy - e.y) < 0.001 { e.wanderAngle += 2.2 }
            case .pain, .attack, .dead:
                break
            }
        }
        if enemies.contains(where: { $0.dead && $0.deadTimer > 1.2 }) {
            enemies.removeAll { $0.dead && $0.deadTimer > 1.2 }
        }
    }

    // MARK: enemy ranged attacks

    /// Hitscan shot from an enemy. Traces from the shooter and only hurts the
    /// intended target when the wall is genuinely not in the way, so a soldier
    /// cannot shoot through a pillar. Splash-damage weapons ignore walls, which
    /// is what makes the grenade lob worth the trouble.
    private func enemyFire(_ e: Enemy, at target: Player, damage: Double) {
        let ox = e.x, oy = e.y
        let a = e.angle + Double.random(in: -0.10...0.10)
        let dx = cos(a), dy = sin(a)
        let dist = hypot(target.x - ox, target.y - oy)
        let wallD = wallDistance(ox, oy, dx, dy, dist, doorsPassable: true)
        // a marksman is meant to be scary across a room, so it gets a tighter ray
        let tolerance = e.isMarksman ? 0.5 : 0.1
        if wallD >= dist - tolerance {
            hurt(target, damage, ignoreArmor: false)
            for _ in 0..<3 {
                particles.append(Particle(x: target.x, y: target.y, z: 0.55,
                                          vz: Double.random(in: 0.2...0.8), life: 0.14,
                                          color: (200, 60, 50), size: 0.025))
            }
        } else {
            for _ in 0..<3 {
                particles.append(Particle(x: ox + dx * wallD, y: oy + dy * wallD, z: 0.5,
                                          vz: Double.random(in: 0.2...0.9), life: 0.16,
                                          color: (180, 150, 120), size: 0.02))
            }
        }
    }

    /// Grenadiers lob a projectile. It travels on a fixed heading rather than
    /// homing, so sprinting sideways genuinely dodges it -- and because the
    /// blast uses the same `explode` path as the player's rockets, it also sets
    /// off barrels and hurts every player nearby, the thrower included.
    private func throwGrenade(_ e: Enemy, at target: Player) {
        // aimed at where the target is now, not where it will be: dodging works
        let a = atan2(target.y - e.y, target.x - e.x) + Double.random(in: -0.12...0.12)
        let speed = 8.5
        let pr = Projectile(x: e.x + cos(a) * 0.35, y: e.y + sin(a) * 0.35, z: 0.6,
                            vx: cos(a) * speed, vy: sin(a) * speed,
                            damage: Double.random(in: e.minDamage...e.maxDamage),
                            owner: nil, penetration: 0.1, splashRadius: 2.2)
        // a short fuse so a miss lands and blows rather than sailing past
        pr.life = Double.random(in: 1.4...1.9)
        pr.hostile = true
        projectiles.append(pr)
        // a puff at the thrower's hand so the lob reads
        particles.append(Particle(x: e.x + cos(a) * 0.4, y: e.y + sin(a) * 0.4, z: 0.6,
                                  vz: 0.4, life: 0.2, color: (220, 190, 120), size: 0.03))
    }

    private func angleLerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return a + d * t
    }

    // MARK: barrels & pickups

    private func updateBarrels(_ dt: Double) {
        for b in barrels {
            b.flash = max(0, b.flash - dt)
        }
    }

    private func updatePickups(_ dt: Double) {
        for p in players where !p.down {
            for pk in pickups where !pk.taken {
                if hypot(p.x - pk.x, p.y - pk.y) < 0.55 {
                    if let m = tryPickup(pk, for: p) {
                        setMessage("\(p.name)  \(m)", 1.4)
                        p.pickupFlash = 1.0
                        Sound.play("pickup")
                    }
                }
            }
        }
    }

    @discardableResult
    private func tryPickup(_ p: Pickup, for pl: Player) -> String? {
        switch p.kind {
        case .medikit:
            if pl.health >= 100 { return nil }
            pl.health = min(100, pl.health + 30); p.taken = true; pl.score += 20
            return "PICKED UP MEDIKIT"
        case .stimpack:
            if pl.health >= 100 { return nil }
            pl.health = min(100, pl.health + 12); p.taken = true; pl.score += 10
            return "PICKED UP STIMPACK"
        case .armor:
            if pl.armor >= 50 { return nil }
            pl.armor = min(100, pl.armor + 50); p.taken = true; pl.score += 30
            return "PICKED UP ARMOR"
        case .blueArmor:
            if pl.armor >= 100 { return nil }
            pl.armor = min(100, pl.armor + 100); p.taken = true; pl.score += 60
            return "PICKED UP MEGAARMOR"
        case .bullets:
            if pl.ammo[0] >= maxAmmo[0] { return nil }
            let add = min(12, maxAmmo[0] - pl.ammo[0]); pl.ammo[0] += add; p.taken = true
            return "+\(add) BULLETS"
        case .shells:
            if pl.ammo[1] >= maxAmmo[1] { return nil }
            let add = min(8, maxAmmo[1] - pl.ammo[1]); pl.ammo[1] += add; p.taken = true
            return "+\(add) SHELLS"
        case .cells:
            if pl.ammo[2] >= maxAmmo[2] { return nil }
            let add = min(15, maxAmmo[2] - pl.ammo[2]); pl.ammo[2] += add; p.taken = true
            return "+\(add) CELLS"
        case .rockets:
            if pl.ammo[3] >= maxAmmo[3] { return nil }
            let add = min(5, maxAmmo[3] - pl.ammo[3]); pl.ammo[3] += add; p.taken = true
            return "+\(add) ROCKETS"
        case .shotgun:
            if pl.owned[1] { return nil }
            pl.owned[1] = true; pl.ammo[1] = min(maxAmmo[1], pl.ammo[1] + 12); p.taken = true; pl.score += 50
            return "GOT THE SHOTGUN"
        case .chaingun:
            if pl.owned[2] { return nil }
            pl.owned[2] = true; pl.ammo[2] = min(maxAmmo[2], pl.ammo[2] + 25); p.taken = true; pl.score += 100
            let add = min(50, maxAmmo[0] - pl.ammo[0]); pl.ammo[0] += add
            return "GOT THE CHAINGUN"
        case .rifle:
            if pl.owned[3] { return nil }
            pl.owned[3] = true; let add = min(40, maxAmmo[0] - pl.ammo[0]); pl.ammo[0] += add; p.taken = true; pl.score += 80
            return "GOT THE ASSAULT RIFLE"
        case .launcher:
            if pl.owned[4] { return nil }
            pl.owned[4] = true; pl.ammo[3] = min(maxAmmo[3], pl.ammo[3] + 5); p.taken = true; pl.score += 150
            return "GOT THE ROCKET LAUNCHER"
        case .saw:
            if pl.owned[Game.sawIndex] { return nil }
            pl.owned[Game.sawIndex] = true
            let add = min(80, maxAmmo[0] - pl.ammo[0]); pl.ammo[0] += add
            p.taken = true; pl.score += 200
            return "GOT THE M249 SAW"
        case .dmr:
            if pl.owned[Game.dmrIndex] { return nil }
            pl.owned[Game.dmrIndex] = true
            let add = min(40, maxAmmo[0] - pl.ammo[0]); pl.ammo[0] += add
            p.taken = true; pl.score += 175
            return "GOT THE MK12 DMR"
        case .sniper:
            if pl.owned[Game.sniperIndex] { return nil }
            pl.owned[Game.sniperIndex] = true
            let add = min(30, maxAmmo[0] - pl.ammo[0]); pl.ammo[0] += add
            p.taken = true; pl.score += 300
            return "GOT THE M24 SNIPER"
        case .berserk:
            pl.berserk = 15; p.taken = true; pl.score += 100
            return "BERSERK  -  15 SECONDS"
        case .invulnerability:
            pl.invulnerable = 12; p.taken = true; pl.score += 150
            return "INVULNERABLE  -  12 SECONDS"
        case .megahealth:
            if pl.health >= 200 { return nil }
            pl.health = min(200, pl.health + 100); p.taken = true; pl.score += 120
            return "PICKED UP MEGAHEALTH"
        case .ammoBox:
            var added = 0
            for i in 0..<ammo.count where pl.ammo[i] < maxAmmo[i] {
                let add = min(i == 0 ? 50 : (i == 1 ? 10 : 10), maxAmmo[i] - pl.ammo[i])
                pl.ammo[i] += add
                added += add
            }
            if added == 0 { return nil }
            p.taken = true; pl.score += 40
            return "AMMO CRATE  +\(added)"
        }
    }

    /// A secret is "found" the moment a player walks into the chamber, whether or
    /// not they take the reward -- blowing the wall open is the work.
    private func checkSecrets() {
        guard !level.secrets.isEmpty else { return }
        for (i, s) in level.secrets.enumerated() {
            guard !level.secretFound[i] else { continue }
            for p in players where !p.down && s.contains(Int(p.x), Int(p.y)) {
                level.markSecret(index: i)
                levelSecrets += 1
                secretsFound += 1
                p.score += 250
                totalScore += 250
                setMessage("\(p.name)  FOUND A SECRET  +250", 2.0)
                Sound.play("secret")
                break
            }
        }
    }

    /// In co-op the level ends only once every player still standing is on the
    /// exit; stragglers hold the door open instead of being left behind.
    private     func checkExit() {
        var exitX = -1, exitY = -1
        if let e = level.exitPos {
            exitX = Int(e.x)
            exitY = Int(e.y)
        }
        guard exitX >= 0 else { return }
        let cx = Double(exitX) + 0.5, cy = Double(exitY) + 0.5
        let standing = players.filter { !$0.down }
        guard !standing.isEmpty else { return }
        var waiting = 0
        for p in standing where hypot(p.x - cx, p.y - cy) >= 0.85 { waiting += 1 }
        if waiting > 0 {
            if playerCount > 1 && waiting > 0 {
                setMessage("EXIT  -  WAITING FOR \(waiting) PLAYER\(waiting > 1 ? "S" : "")", 0.5)
            }
            return
        }
        state = .levelDone
        stateTimer = 0
        var bonus = 500
        for p in players { bonus += Int(p.health) * 2 }
        // reward clearing the level and finding everything in it
        var left = 0
        for e in enemies where !e.dead { left += 1 }
        if left == 0 { bonus += 1000 }
        if levelSecrets > 0 { bonus += levelSecrets * 250 }
        // speed bonus: 1 point per second under 60s, capped, so a clean fast run
        // is worth chasing without rushing a hard level being pointless
        if levelTime < 60 { bonus += Int(60 - levelTime) }
        totalScore += bonus
        setMessage(playerCount > 1 ? "SQUAD CLEAR   +\(bonus)" : "EXIT REACHED   +\(bonus)", 99)
        Sound.play("leveldone")
    }

    /// 0...1, or nil when nothing has been fired yet.
    var accuracy: Double? {
        guard levelShots > 0 else { return nil }
        return Double(min(levelHits, levelShots)) / Double(levelShots)
    }

    // MARK: input state
}

final class InputState {
    var forward: Double = 0
    var strafe: Double = 0
    var run = false
    var turn: Double = 0
    var fire = false
    var firePressed = false
    var wantWeapon = -1
    var nextWeapons: [Int] = []
    var strafeLeft = false
    var strafeRight = false
}
