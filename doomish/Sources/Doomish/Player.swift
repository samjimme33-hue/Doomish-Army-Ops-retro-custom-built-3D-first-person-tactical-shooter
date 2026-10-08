import Foundation

/// One local player. The world (level, enemies, pickups, barrels, projectiles)
/// belongs to `Game` and is shared; everything a player owns -- position, aim,
/// health, ammo, score -- lives here.
final class Player {
    /// Stable 0-based index; also the split-screen slot.
    let index: Int
    /// Short tag drawn on the HUD and in the kill feed.
    let name: String
    /// HUD accent so a glance tells the views apart.
    let color: (Int, Int, Int)

    // ---- transform ----
    var x = 2.5, y = 2.5, ang = 0.0
    /// Collision radius; players body-block each other.
    let radius = 0.24

    // ---- vitals ----
    var health = 100.0
    var armor = 0.0

    // ---- inventory ----
    var ammo = [50, 0, 0, 0]
    /// One slot per `Game.weapons` entry. Grown by the level builder, so a new
    /// weapon does not silently read past the end of the array.
    var owned = [true, false, false, false, false, false, false, false, false]
    var weapon = 0

    // ---- feel / view state ----
    var bobPhase = 0.0
    var weaponBob = 0.0
    var recoil = 0.0
    var muzzleFlash = 0.0
    var kick = 0.0
    var fireCooldown = 0.0
    var painTimer = 0.0
    var spawnGrace = 0.0
    /// Brief lockout while swapping weapons, so you cannot skip-shot.
    var weaponSwitching = 0.0
    var shake = 0.0
    var damageFlash = 0.0
    var pickupFlash = 0.0
    var hitMarker = 0.0

    // ---- input plumbing ----
    /// Accumulated mouse delta for this frame (player 0 only).
    var mouseDx = 0.0
    var mouseDy = 0.0
    /// A real click edge, distinct from mouse movement.
    var clicked = false
    /// Fire edge mirrored out of InputState for the state-machine screens.
    var firePressed = false

    // ---- scoring ----
    var score = 0
    var kills = 0
    /// Kills made without dying or letting the streak lapse. Drives the score
    /// multiplier and the HUD combo counter.
    var streak = 0
    /// Longest streak this player has ever held, for the victory summary.
    var bestStreak = 0
    /// Seconds left before the streak lapses.
    var streakTimer = 0.0
    /// Shots fired and shots that connected, for the accuracy readout.
    var shotsFired = 0
    var shotsHit = 0
    /// Seconds of berserk rage remaining; 0 when inactive. Doubles fire rate and
    /// damage, tints the view, and is what the berserk powerup grants.
    var berserk = 0.0
    /// Invulnerability window from the invulnerability powerup.
    var invulnerable = 0.0

    /// 0...1 hit rate, or nil when nothing has been fired yet.
    var accuracy: Double? {
        guard shotsFired > 0 else { return nil }
        return Double(min(shotsHit, shotsFired)) / Double(shotsFired)
    }

    /// Score multiplier from the current streak: 1.0 up to 5 kills, then +0.2
    /// per extra kill up to 3.0x at 15.
    var streakMultiplier: Double {
        guard streak > 0 else { return 1.0 }
        return min(3.0, 1.0 + Double(streak - 1) * 0.2)
    }

    /// The vehicle this player is riding, if any. The game owns the driving.
    var rides: Vehicle?

    // ---- life cycle ----
    /// A downed player waits `respawnTimer` then returns at the level start.
    var down = false
    var respawnTimer = 0.0
    static let respawnDelay = 4.0

    var input = InputState()

    init(index: Int) {
        self.index = index
        switch index {
        case 1:
            name = "P2"
            color = (255, 170, 70)
        case 2:
            name = "P3"
            color = (150, 220, 255)
        default:
            name = "P1"
            color = (126, 240, 150)
        }
    }

    /// Put this player back on their feet at a spot, with a fresh loadout.
    func reset(at pos: (x: Double, y: Double, ang: Double), keepScore: Bool) {
        x = pos.x
        y = pos.y
        ang = pos.ang
        health = 100
        armor = 0
        ammo = [50, 0, 0, 0]
        owned = [true, false, false, false, false, false, false, false, false]
        weapon = 0
        bobPhase = 0
        weaponBob = 0
        recoil = 0
        muzzleFlash = 0
        kick = 0
        fireCooldown = 0
        painTimer = 0
        hitMarker = 0
        weaponSwitching = 0
        damageFlash = 0
        pickupFlash = 0
        shake = 0
        mouseDx = 0
        mouseDy = 0
        clicked = false
        firePressed = false
        spawnGrace = 1.4
        down = false
        respawnTimer = 0
        berserk = 0
        invulnerable = 0
        input = InputState()
        if !keepScore {
            score = 0
            kills = 0
            streak = 0
            streakTimer = 0
            shotsFired = 0
            shotsHit = 0
        }
    }

    /// Camera shake every player feels, not just the one who fired.
    func addShake(_ amount: Double) { shake = min(1.0, max(shake, amount)) }
}
