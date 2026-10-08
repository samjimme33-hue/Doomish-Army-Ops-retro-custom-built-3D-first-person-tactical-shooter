import Foundation

// MARK: - Army content tables
//
// Doomish's original arsenal was five Doom weapons and four demon types. This
// adds the combined-arms layer: army weapons for infantry, and a vehicle roster
// spanning light tactical, infantry fighting, medium armour and aviation.

// MARK: Vehicle classes

enum VehicleClass: Int {
    case light      // light tactical wheeled
    case ifv        // infantry fighting vehicle
    case mbt        // medium / main battle tank
    case spg        // artillery
    case air        // helicopter

    var display: String {
        switch self {
        case .light: return "LIGHT TACTICAL"
        case .ifv: return "INFANTRY FIGHTING"
        case .mbt: return "MEDIUM ARMORED"
        case .spg: return "ARTILLERY"
        case .air: return "AVIATION"
        }
    }
}

/// The main gun a vehicle carries. `projectile` rounds travel and splash;
/// tracers are hitscan.
struct MountedGun {
    let name: String
    let damage: Double
    let rof: Double            // seconds between shots
    let spread: Double
    let range: Double
    let splash: Double
    let hitscan: Bool
    let automatic: Bool
    let sound: String
    /// 0..1 hull damage reduction. Heavy autocannons chew through light armour
    /// but will not dent a main battle tank.
    let penetration: Double
    let shake: Double

    static func tracer(_ name: String, damage: Double, rof: Double, spread: Double,
                       range: Double, pen: Double, automatic: Bool = true,
                       sound: String = "chain", splash: Double = 0) -> MountedGun {
        MountedGun(name: name, damage: damage, rof: rof, spread: spread, range: range,
                   splash: splash, hitscan: true, automatic: automatic, sound: sound,
                   penetration: pen, shake: 0.25)
    }

    static func shell(_ name: String, damage: Double, rof: Double, splash: Double,
                      pen: Double, sound: String = "launch", shake: Double = 1.4) -> MountedGun {
        MountedGun(name: name, damage: damage, rof: rof, spread: 0, range: 30,
                   splash: splash, hitscan: false, automatic: false, sound: sound,
                   penetration: pen, shake: shake)
    }
}

struct VehicleDef {
    let id: String
    let name: String
    let cls: VehicleClass
    /// metres per second
    let maxSpeed: Double
    let accel: Double
    /// radians per second
    let turnRate: Double
    let hp: Double
    /// 0..1 incoming damage reduction, before per-weapon penetration.
    let armor: Double
    let radius: Double
    /// metres, for drawing the sprite
    let worldHeight: Double
    let gun: MountedGun
    /// Secondary gunner weapon, when the vehicle carries a coax or a missile pod.
    let secondary: MountedGun?
    /// Can a player ride it?
    let seats: Int
    /// A helicopter ignores walls for forward motion but still needs a roof.
    let flying: Bool
    /// AI behaviour when nobody is driving.
    let aiAggression: Double
}

enum Army {

    // MARK: the 54mm autocannon
    //
    // The user asked for a "54 gun" specifically. It sits between the 30mm
    // autocannon (punches light armour) and a tank shell (kills anything), so it
    // kills IFVs and light vehicles but bounces off a main battle tank.

    static let gun54 = MountedGun.tracer("M54 54mm AUTOCANNON", damage: 62, rof: 0.20,
                                         spread: 0.012, range: 26, pen: 0.62,
                                         automatic: true, sound: "chain")

    static let coax50 = MountedGun.tracer("M2 .50 COAX", damage: 22, rof: 0.10,
                                          spread: 0.02, range: 22, pen: 0.35,
                                          automatic: true, sound: "chain")

    static let minigun = MountedGun.tracer("M134 MINIGUN", damage: 9, rof: 0.035,
                                           spread: 0.05, range: 20, pen: 0.2,
                                           automatic: true, sound: "chain")

    static let bushmaster25 = MountedGun.tracer("M242 25mm", damage: 40, rof: 0.16,
                                                spread: 0.016, range: 24, pen: 0.6,
                                                automatic: true, sound: "chain")

    static let atgm = MountedGun.shell("ATGM", damage: 260, rof: 3.2, splash: 2.4,
                                       pen: 0.95, shake: 0.9)

    // MARK: the roster

    static let vehicles: [VehicleDef] = [
        // ---- light tactical ----
        VehicleDef(id: "humvee", name: "HMMWV M1151", cls: .light,
                   maxSpeed: 6.4, accel: 9, turnRate: 2.2, hp: 220, armor: 0.12,
                   radius: 0.52, worldHeight: 0.86,
                   gun: .tracer("M2 .50", damage: 26, rof: 0.14, spread: 0.03,
                                range: 20, pen: 0.3),
                   secondary: nil, seats: 2, flying: false, aiAggression: 0.55),

        VehicleDef(id: "mrap", name: "MRAP M1126", cls: .light,
                   maxSpeed: 5.8, accel: 8, turnRate: 1.9, hp: 340, armor: 0.26,
                   radius: 0.58, worldHeight: 0.94,
                   gun: .tracer("MK19 40mm", damage: 70, rof: 0.9, spread: 0.02,
                                range: 22, pen: 0.45, automatic: false, sound: "launch"),
                   secondary: nil, seats: 2, flying: false, aiAggression: 0.5),

        VehicleDef(id: "jlvt", name: "JLTV M1280", cls: .light,
                   maxSpeed: 6.8, accel: 9.5, turnRate: 2.1, hp: 400, armor: 0.3,
                   radius: 0.6, worldHeight: 0.98,
                   gun: .tracer("M2 .50", damage: 28, rof: 0.13, spread: 0.028,
                                range: 21, pen: 0.32),
                   secondary: nil, seats: 2, flying: false, aiAggression: 0.58),

        // ---- infantry fighting ----
        VehicleDef(id: "bradley", name: "M2A3 BRADLEY", cls: .ifv,
                   maxSpeed: 4.6, accel: 6, turnRate: 1.35, hp: 720, armor: 0.46,
                   radius: 0.78, worldHeight: 1.06,
                   gun: gun54, secondary: coax50,
                   seats: 3, flying: false, aiAggression: 0.7),

        VehicleDef(id: "stryker", name: "M1126 STRYKER", cls: .ifv,
                   maxSpeed: 6.0, accel: 8, turnRate: 1.7, hp: 480, armor: 0.34,
                   radius: 0.68, worldHeight: 1.0,
                   gun: minigun, secondary: nil,
                   seats: 2, flying: false, aiAggression: 0.6),

        VehicleDef(id: "btr", name: "BTR-80", cls: .ifv,
                   maxSpeed: 4.8, accel: 6.5, turnRate: 1.4, hp: 560, armor: 0.4,
                   radius: 0.76, worldHeight: 1.04,
                   gun: .tracer("2A42 30mm", damage: 44, rof: 0.18, spread: 0.018,
                                range: 23, pen: 0.55),
                   secondary: nil, seats: 2, flying: false, aiAggression: 0.68),

        // ---- medium armour ----
        VehicleDef(id: "abrams", name: "M1A2 ABRAMS", cls: .mbt,
                   maxSpeed: 4.2, accel: 5, turnRate: 1.1, hp: 1600, armor: 0.76,
                   radius: 0.92, worldHeight: 1.2,
                   gun: .shell("120mm SMOOTHBORE", damage: 320, rof: 2.4, splash: 2.8,
                               pen: 1.0, shake: 2.2),
                   secondary: coax50,
                   seats: 3, flying: false, aiAggression: 0.75),

        VehicleDef(id: "t90", name: "T-90A", cls: .mbt,
                   maxSpeed: 4.3, accel: 5, turnRate: 1.15, hp: 1400, armor: 0.7,
                   radius: 0.9, worldHeight: 1.18,
                   gun: .shell("125MM", damage: 290, rof: 2.5, splash: 2.7,
                               pen: 1.0, shake: 2.1),
                   secondary: nil, seats: 2, flying: false, aiAggression: 0.72),

        // ---- artillery ----
        VehicleDef(id: "paladin", name: "M109 PALADIN", cls: .spg,
                   maxSpeed: 3.6, accel: 4, turnRate: 0.95, hp: 520, armor: 0.24,
                   radius: 0.86, worldHeight: 1.16,
                   gun: .shell("155MM HOWITZER", damage: 420, rof: 4.0, splash: 4.6,
                               pen: 0.9, shake: 2.6),
                   secondary: nil, seats: 2, flying: false, aiAggression: 0.35),

        // ---- aviation ----
        VehicleDef(id: "blackhawk", name: "UH-60 BLACK HAWK", cls: .air,
                   maxSpeed: 9.5, accel: 7, turnRate: 2.0, hp: 600, armor: 0.2,
                   radius: 0.62, worldHeight: 1.0,
                   gun: minigun, secondary: nil,
                   seats: 2, flying: true, aiAggression: 0.4),

        VehicleDef(id: "lakota", name: "UH-72 LAKOTA", cls: .air,
                   maxSpeed: 8.6, accel: 7, turnRate: 2.2, hp: 460, armor: 0.18,
                   radius: 0.56, worldHeight: 0.92,
                   gun: minigun, secondary: nil,
                   seats: 2, flying: true, aiAggression: 0.38),

        VehicleDef(id: "chinook", name: "CH-47 CHINOOK", cls: .air,
                   maxSpeed: 8.0, accel: 6, turnRate: 1.5, hp: 900, armor: 0.26,
                   radius: 0.72, worldHeight: 1.12,
                   gun: minigun, secondary: nil,
                   seats: 2, flying: true, aiAggression: 0.36),

        VehicleDef(id: "osprey", name: "MV-22 OSPREY", cls: .air,
                   maxSpeed: 9.8, accel: 8, turnRate: 1.8, hp: 700, armor: 0.24,
                   radius: 0.68, worldHeight: 1.05,
                   gun: bushmaster25, secondary: nil,
                   seats: 2, flying: true, aiAggression: 0.42),

        VehicleDef(id: "apache", name: "AH-64 APACHE", cls: .air,
                   maxSpeed: 9.2, accel: 7.5, turnRate: 2.1, hp: 820, armor: 0.3,
                   radius: 0.7, worldHeight: 1.08,
                   gun: gun54, secondary: atgm,
                   seats: 2, flying: true, aiAggression: 0.85),

        VehicleDef(id: "ghost", name: "AH-64E APACHE GUARDIAN", cls: .air,
                   maxSpeed: 9.6, accel: 8, turnRate: 2.2, hp: 900, armor: 0.32,
                   radius: 0.7, worldHeight: 1.1,
                   gun: .tracer("M230 30mm", damage: 48, rof: 0.17, spread: 0.015,
                                range: 25, pen: 0.58),
                   secondary: atgm,
                   seats: 2, flying: true, aiAggression: 0.9),

        VehicleDef(id: "viper", name: "AH-1Z VIPER", cls: .air,
                   maxSpeed: 9.0, accel: 7.5, turnRate: 2.0, hp: 760, armor: 0.27,
                   radius: 0.68, worldHeight: 1.06,
                   gun: .tracer("M197 20mm", damage: 30, rof: 0.09, spread: 0.022,
                                range: 24, pen: 0.5),
                   secondary: nil, seats: 2, flying: true, aiAggression: 0.7),

        VehicleDef(id: "c130", name: "C-130J HERCULES", cls: .air,
                   maxSpeed: 7.4, accel: 5, turnRate: 1.2, hp: 1300, armor: 0.34,
                   radius: 0.84, worldHeight: 1.24,
                   gun: minigun, secondary: nil,
                   seats: 2, flying: true, aiAggression: 0.3),

        VehicleDef(id: "hind", name: "MI-24 HIND", cls: .air,
                   maxSpeed: 8.8, accel: 7, turnRate: 1.9, hp: 840, armor: 0.29,
                   radius: 0.72, worldHeight: 1.1,
                   gun: .tracer("GSh-30 30mm", damage: 46, rof: 0.16, spread: 0.017,
                                range: 24, pen: 0.56),
                   secondary: atgm, seats: 2, flying: true, aiAggression: 0.88),
    ]

    static func def(_ id: String) -> VehicleDef? { vehicles.first { $0.id == id } }

    /// Vehicles that show up in a fresh level, keyed by tier so the level builder
    /// can bias toward the classes the player is likely to meet.
    static let groundRoster = ["humvee", "mrap", "jlvt", "bradley", "stryker",
                               "abrams", "btr", "t90", "paladin"]
    static let airRoster = ["blackhawk", "lakota", "chinook", "osprey", "apache",
                            "ghost", "viper", "c130", "hind"]

    // MARK: army weapons for infantry

    /// Army rifles that replace the stock Doom arsenal for soldiers. Indexed the
    /// same way as `Game.weapons`, so the existing fire/switch code is untouched.
    struct ArmyWeapon {
        let name: String
        let damage: Double
        let delay: Double
        let automatic: Bool
        let sound: String
        let recoil: Double
        let spread: Double
        /// Anti-armour: these bite tanks. 0 for normal rifles.
        let penetration: Double
    }

    static let m4 = ArmyWeapon(name: "M4A1", damage: 11, delay: 0.09, automatic: true,
                               sound: "rifle", recoil: 0.4, spread: 0.012, penetration: 0.1)
    static let saw = ArmyWeapon(name: "M249 SAW", damage: 10, delay: 0.075, automatic: true,
                                sound: "chain", recoil: 0.42, spread: 0.024, penetration: 0.18)
    static let m240 = ArmyWeapon(name: "M240B", damage: 14, delay: 0.1, automatic: true,
                                 sound: "chain", recoil: 0.7, spread: 0.028, penetration: 0.3)
    static let mk12 = ArmyWeapon(name: "MK12 DMR", damage: 20, delay: 0.2, automatic: false,
                                 sound: "rifle", recoil: 0.9, spread: 0.006, penetration: 0.35)
    static let m24 = ArmyWeapon(name: "M24 SNIPER", damage: 46, delay: 1.1, automatic: false,
                                sound: "rifle", recoil: 1.4, spread: 0.002, penetration: 0.4)
    static let m1014 = ArmyWeapon(name: "M1014", damage: 9, delay: 0.7, automatic: false,
                                  sound: "shotgun", recoil: 1.4, spread: 0.07, penetration: 0.08)
    static let at4 = ArmyWeapon(name: "AT4", damage: 140, delay: 1.4, automatic: false,
                                sound: "launch", recoil: 1.9, spread: 0, penetration: 0.95)
    static let m320 = ArmyWeapon(name: "M320 GL", damage: 95, delay: 1.0, automatic: false,
                                 sound: "launch", recoil: 1.5, spread: 0, penetration: 0.5)
}

// MARK: - Vehicle entity

/// A drivable, shootable vehicle. One entity covers every class: `def` carries
/// the class-specific numbers, and the same update path drives a Humvee and an
/// Apache.
final class Vehicle {
    let def: VehicleDef
    /// Which side it belongs to. Doomish is co-op-vs-demons, so `hostile` marks
    /// vehicles the players should shoot and not board.
    let hostile: Bool

    var x: Double, y: Double
    var ang: Double           // hull heading
    var turretAng: Double     // relative to the hull
    var speed: Double = 0
    var hp: Double
    var maxHP: Double
    var dead = false
    var deadTimer: Double = 0
    var flash: Double = 0
    var fireCooldown: Double = 0
    var secondaryCooldown: Double = 0
    /// Track marks / dust phase, purely cosmetic.
    var animPhase: Double
    /// Index of the player driving (-1 when empty).
    var driver: Int = -1
    /// Index of the player on the gun, -1 when unmanned.
    var gunner: Int = -1
    /// Rotor spin for helicopters.
    var rotorPhase: Double = 0
    /// AI state
    var aiTimer: Double = 0
    var aiWander: Double = 0
    var aiTarget: Int = -1
    var alertTimer: Double = 0

    init(def: VehicleDef, x: Double, y: Double, ang: Double, hostile: Bool) {
        self.def = def
        self.x = x
        self.y = y
        self.ang = ang
        self.turretAng = 0
        self.hostile = hostile
        self.hp = def.hp
        self.maxHP = def.hp
        self.animPhase = Double.random(in: 0..<(2 * .pi))
        self.aiWander = Double.random(in: 0..<(2 * .pi))
    }

    var occupied: Bool { driver >= 0 }
    var freeSeat: Int {
        if driver < 0 { return 0 }
        if def.seats > 1 && gunner < 0 { return 1 }
        return -1
    }

    var hpFraction: Double { max(0, min(1, hp / maxHP)) }

    /// Display name with a damage suffix, so the HUD can flag a dying vehicle.
    var statusName: String {
        guard hpFraction < 0.34 else { return def.name }
        return hpFraction < 0.15 ? "\(def.name) [CRITICAL]" : "\(def.name) [DAMAGED]"
    }

    /// Damage actually taken after armour and the attacker's penetration.
    /// `penetration` 0..1: 1 is a tank shell, 0.2 is a pistol.
    func absorbed(_ raw: Double, penetration: Double) -> Double {
        // Effective armour is reduced by penetration: a high-penetration round
        // shrugs off the plating, a low-penetration round is mostly stopped.
        let eff = max(0, def.armor * (1 - penetration))
        return max(1, raw * (1 - eff))
    }

    func damage(_ amount: Double) {
        if dead { return }
        hp -= amount
        flash = 1
        if hp <= 0 {
            hp = 0
            dead = true
            deadTimer = 0
        }
    }

    /// Facing the gun actually points in, world space.
    var muzzleAngle: Double { ang + turretAng }

    func seatOffset(_ seat: Int) -> (x: Double, y: Double) {
        switch seat {
        case 0: return (x - cos(ang) * def.radius * 0.2, y - sin(ang) * def.radius * 0.2)
        default: return (x + cos(ang) * def.radius * 0.1, y + sin(ang) * def.radius * 0.1)
        }
    }
}
