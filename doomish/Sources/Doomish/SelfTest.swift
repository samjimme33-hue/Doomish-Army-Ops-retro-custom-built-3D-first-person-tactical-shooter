import Foundation
import AppKit

/// `Doomish --selftest` runs the game headless: it builds levels, simulates
/// frames with synthetic input, prints stats and writes PPM screenshots.
enum SelfTest {

    /// Headless gameplay assertions: shooting, death, pickups, doors, barrels,
    /// the exit switch, level progression and collision.
    static var failuresHappened = false

    static func logicTests() {
        var failures = 0
        failuresHappened = false
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1; failuresHappened = true }
            print("   [\(ok ? "PASS" : "FAIL")] \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
        }

        func freshGame() -> Game {
            let g = Game()
            g.startNewGame()
            g.enemies.removeAll()
            g.pickups.removeAll()
            g.barrels.removeAll()
            g.particles.removeAll()
            return g
        }
        func step(_ g: Game, _ n: Int) {
            for _ in 0..<n { g.update(1.0 / 60.0) }
        }

        // 1. shooting an enemy
        do {
            let g = freshGame()
            let e = Enemy(x: g.px + cos(g.pang) * 2.0, y: g.py + sin(g.pang) * 2.0, type: 0, difficulty: 1)
            g.enemies = [e]
            g.input.firePressed = true
            step(g, 1)
            check("pistol shot consumes ammo", g.ammo[0] == 49, "ammo=\(g.ammo[0])")
            check("pistol damages the enemy it hits", e.hp < e.maxHP, "hp=\(e.hp)/\(e.maxHP)")
            var shots = 0
            while !e.dead && shots < 40 {
                g.input.firePressed = true
                step(g, 1)
                shots += 1
            }
            check("enemy dies and is scored", e.dead && g.kills == 1 && g.score > 0,
                  "dead=\(e.dead) kills=\(g.kills) score=\(g.score) shots=\(shots)")
        }

        // 2. enemy damages the player
        do {
            let g = freshGame()
            g.enemies = [Enemy(x: g.px + cos(g.pang) * 1.1, y: g.py + sin(g.pang) * 1.1, type: 0, difficulty: 1)]
            step(g, 180)
            check("enemy attacks hurt the player", g.health < 100, "hp=\(g.health)")
            check("player death switches state", g.health > 0 || g.state == .dead, "hp=\(g.health) state=\(g.state.rawValue)")
        }

        // 3. pickups
        do {
            let g = freshGame()
            g.health = 50
            g.pickups = [Pickup(x: g.px, y: g.py, kind: .medikit)]
            step(g, 2)
            check("medikit heals", g.health > 50 && g.pickups[0].taken, "hp=\(g.health)")
            g.armor = 0
            g.pickups = [Pickup(x: g.px, y: g.py, kind: .blueArmor)]
            step(g, 2)
            check("megaarmor grants armour", g.armor == 100, "armor=\(g.armor)")
            g.pickups = [Pickup(x: g.px, y: g.py, kind: .shotgun)]
            step(g, 2)
            check("shotgun pickup grants the weapon + shells", g.owned[1] && g.ammo[1] > 0,
                  "owned=\(g.owned) shells=\(g.ammo[1])")
            g.pickups = [Pickup(x: g.px, y: g.py, kind: .chaingun)]
            step(g, 2)
            check("chaingun pickup grants the weapon + cells", g.owned[2] && g.ammo[2] > 0,
                  "owned=\(g.owned) cells=\(g.ammo[2])")
            g.pickups = [Pickup(x: g.px, y: g.py, kind: .rifle)]
            step(g, 2)
            check("rifle pickup grants the weapon + bullets", g.owned[3] && g.ammo[0] > 0,
                  "owned=\(g.owned) bullets=\(g.ammo[0])")
            g.pickups = [Pickup(x: g.px, y: g.py, kind: .launcher)]
            step(g, 2)
            check("launcher pickup grants the weapon + rockets", g.owned[4] && g.ammo[3] > 0,
                  "owned=\(g.owned) rockets=\(g.ammo[3])")
        }

        // 4. weapon switching
        do {
            let g = freshGame()
            g.owned = [true, true, true, true, true]
            g.input.wantWeapon = 1
            step(g, 1)
            check("number key switches weapon", g.weapon == 1, "weapon=\(g.weapon)")
            g.ammo = [40, 10, 20, 4]
            g.input.wantWeapon = 2
            step(g, 1)
            var fired = 0
            for i in 0..<40 {
                g.input.fire = true
                g.input.firePressed = (i % 2) == 0
                step(g, 1)
                if g.ammo[0] < 40 { fired += 1 }
            }
            check("chaingun is full auto and uses bullets", fired > 3, "fired=\(fired) ammo=\(g.ammo[0])")
        }

        // 4b. army gear: rifle, rocket launcher, rocket splash, kill feed
        do {
            let g = freshGame()
            g.owned = [true, true, true, true, true]
            g.ammo = [60, 20, 30, 6]
            g.input.wantWeapon = 3
            step(g, 1)
            check("number key 4 selects the rifle", g.weapon == 3, "weapon=\(g.weapon)")
            g.input.fire = true
            var rifleShots = 0
            for _ in 0..<30 {
                g.input.firePressed = true
                step(g, 1)
                if g.ammo[0] < 60 { rifleShots += 1 }
            }
            check("rifle is full auto", rifleShots > 3, "shots=\(rifleShots)")
            g.input.fire = false
            step(g, 20)                                        // let the switch settle
            g.input.wantWeapon = 4
            step(g, 1)
            check("number key 5 selects the rocket launcher", g.weapon == 4, "weapon=\(g.weapon)")
            step(g, 20)
            let before = g.ammo[3]
            g.input.firePressed = true
            step(g, 1)
            check("firing the launcher spends a rocket", g.ammo[3] == before - 1,
                  "rockets=\(g.ammo[3])")
            // park a soldier right in front of the rocket's flight path
            g.enemies.removeAll()
            g.enemies.append(Enemy(x: g.px + cos(g.pang) * 2.0, y: g.py + sin(g.pang) * 2.0,
                                   type: 2, difficulty: 1))
            let e = g.enemies[0]
            g.input.firePressed = true
            step(g, 1)
            step(g, 40)
            check("rocket splash kills a soldier", e.dead, "hp=\(e.hp) dead=\(e.dead)")
            check("kill feed records the kill", g.killFeed.contains { $0.text.contains("SOLDIER") },
                  "feed=\(g.killFeed.map { $0.text })")
        }

        // 5. barrels explode and hurt
        do {
            let g = freshGame()
            let b = Barrel(x: g.px + cos(g.pang) * 1.6, y: g.py + sin(g.pang) * 1.6)
            g.barrels = [b]
            // behind the barrel relative to the player, so the barrel absorbs the shot
            let e = Enemy(x: g.px + cos(g.pang) * 2.6, y: g.py + sin(g.pang) * 2.6, type: 1, difficulty: 1)
            g.enemies = [e]
            g.input.firePressed = true
            step(g, 1)
            check("barrel explodes when shot", b.gone, "gone=\(b.gone)")
            step(g, 2)
            check("barrel blast damages nearby enemies", e.hp < e.maxHP || e.dead, "hp=\(e.hp)")
        }

        // 6. doors open for the player
        do {
            let g = freshGame()
            var doorX = -1, doorY = -1
            for y in 0..<g.level.h {
                for x in 0..<g.level.w where g.level.at(x, y) == Tile.door { doorX = x; doorY = y; break }
                if doorX >= 0 { break }
            }
            if doorX >= 0 {
                g.px = Double(doorX) + 0.5
                g.py = Double(doorY) + 0.5
                g.pang = 0
                step(g, 60)
                check("door opens when the player is near", g.level.doorProgress[doorY * g.level.w + doorX] > 0.9,
                      String(format: "progress=%.2f", g.level.doorProgress[doorY * g.level.w + doorX]))
            } else {
                check("door exists in generated level", false, "no door found")
            }
        }

        // 7. the exit switch ends the level
        do {
            let g = freshGame()
            var found = false
            for y in 0..<g.level.h {
                for x in 0..<g.level.w where g.level.at(x, y) == Tile.exit {
                    g.px = Double(x) + 0.5
                    g.py = Double(y) + 1.2
                    found = true
                    break
                }
                if found { break }
            }
            step(g, 2)
            check("touching the exit completes the level", g.state == .levelDone, "state=\(g.state.rawValue)")
            step(g, 120)
            check("next level loads after the exit", g.levelIndex == 2 && g.state == .playing,
                  "level=\(g.levelIndex) state=\(g.state.rawValue)")
        }

        // 8. walls stop the player
        do {
            let g = freshGame()
            // walk hard into the nearest wall for two seconds
            var best = (d: 1e9, ang: 0.0)
            for a in stride(from: 0.0, to: 2 * .pi, by: 0.05) {
                let d = g.wallDistance(g.px, g.py, cos(a), sin(a), 6.0)
                if d < best.d { best = (d, a) }
            }
            g.pang = best.ang
            let before = (g.px, g.py)
            g.input.forward = 1
            step(g, 120)
            let moved = hypot(g.px - before.0, g.py - before.1)
            check("player cannot walk through walls", moved < best.d,
                  String(format: "moved %.2f, wall at %.2f", moved, best.d))
        }

        // 9. running out of ammo is survivable
        do {
            let g = freshGame()
            g.ammo = [0, 0, 0, 0]
            for i in 0..<200 {
                g.input.firePressed = (i % 5) == 0
                g.input.fire = true
                step(g, 1)
            }
            check("firing with no ammo is handled", g.health == 100 && g.state == .playing, "hp=\(g.health)")
        }

        // 10. level generation invariants across a whole campaign
        do {
            var ok = true
            var detail = ""
            for i in 1...Game().maxLevels {
                let lv = LevelBuilder.build(level: i)
                let flow = lv.flowField(from: (Int(lv.startPos.x), Int(lv.startPos.y)))
                if lv.solidAtPoint(lv.startPos.x, lv.startPos.y, radius: 0.24, doorsPassable: false) {
                    ok = false; detail = "L\(i) starts inside a wall"
                }
                if !lv.enemySpecs.isEmpty && lv.pickupSpecs.isEmpty { ok = false; detail = "L\(i) has no pickups" }
                var exitOK = false
                for y in 0..<lv.h {
                    for x in 0..<lv.w where lv.at(x, y) == Tile.exit {
                        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                            let nx = x + dx, ny = y + dy
                            if lv.inBounds(nx, ny) && lv.at(nx, ny) == Tile.floor && flow[ny * lv.w + nx] > 0 { exitOK = true }
                        }
                    }
                }
                if !exitOK { ok = false; detail = "L\(i) exit unreachable" }
            }
            check("all \(Game().maxLevels) levels: start clear, exit reachable, stocked", ok, detail)
        }

        // 11. texture invariants: sprites must keep transparent backgrounds and
        //     every enemy type must resolve to its own art
        do {
            var transparentOK = true
            var detail = ""
            let keys: [Sprite] = [.imp, .impAttack, .brute, .soldier, .soldierAttack,
                                  .heavy, .medikit, .bullets, .rockets, .riflePickup,
                                  .launcherPickup, .rocketBall]
            for k in keys {
                guard let tex = TexLib.sprites[k] else {
                    transparentOK = false; detail = "\(k) missing"; continue
                }
                // corners and the top row must stay see-through, otherwise
                // noise/glow painting over transparent pixels boxes the sprite in
                let corners = [(0, 0), (tex.w - 1, 0), (0, tex.h - 1), (tex.w - 1, tex.h - 1)]
                for (cx, cy) in corners where tex.alphaAt(cx, cy) != 0 {
                    transparentOK = false
                    detail = "\(k) corner opaque"
                }
                if tex.alphaAt(tex.w / 2, 0) != 0 {
                    transparentOK = false; detail = "\(k) top row opaque"
                }
            }
            check("sprite textures keep transparent backgrounds", transparentOK, detail)

            var seen = Set<Sprite>()
            for t in 0..<EnemyType.count {
                seen.insert(Renderer.enemySprite(type: t, attacking: false, dead: false))
                seen.insert(Renderer.enemySprite(type: t, attacking: true, dead: false))
                seen.insert(Renderer.enemySprite(type: t, attacking: false, dead: true))
            }
            check("all \(EnemyType.count) enemy types have idle/attack/corpse art",
                  seen.count == EnemyType.count * 3, "sprites=\(seen.count)")
            check("enemy sprite tables are non-empty", Renderer.enemyWorldHeights.allSatisfy { $0 > 0 })
            let wc = Game().weapons.count
            check("weapon views cover all \(wc) weapons", TexLib.weaponViews.count == wc,
                  "views=\(TexLib.weaponViews.count)")
            // every weapon's own tags exist, or the hotbar prints "???"
            check("weapon tags cover the arms rack", Game.weaponTags.count >= wc,
                  "tags=\(Game.weaponTags.count)")
            // and every pickup the level builder can emit must have art
            let newKinds: [PickupKind] = [.saw, .dmr, .sniper, .berserk, .invulnerability,
                                          .megahealth, .ammoBox]
            var missingSprite = ""
            for k in newKinds where TexLib.sprites[k.sprite] == nil { missingSprite = "\(k) " }
            check("new army pickups all have sprites", missingSprite.isEmpty, missingSprite)
            // new enemy art must exist too, or they render as the imp
            var missingEnemy = ""
            for t in [EnemyType.grenadier, EnemyType.marksman, EnemyType.rioter] {
                for a in [false, true] where TexLib.sprites[
                    Renderer.enemySprite(type: t, attacking: a, dead: false)] == nil {
                    missingEnemy += "\(t)/\(a) "
                }
            }
            check("new enemy types all have idle and attack art", missingEnemy.isEmpty, missingEnemy)
            // a player must be able to own and switch to every weapon
            let g9 = Game()
            g9.startNewGame()
            g9.owned = [Bool](repeating: true, count: g9.weapons.count)
            var switchOK = true
            for i in 0..<g9.weapons.count {
                g9.p0.input.wantWeapon = i
                g9.update(1.0 / 60.0)
                if g9.weapon != i { switchOK = false }
            }
            check("all \(wc) weapons are selectable once owned", switchOK, "weapon=\(g9.weapon)")
        }

        // 12. spawn must not be wedged: the player has to be able to walk
        //     FORWARD off the spawn tile, otherwise W/S look "dead" while A/D
        //     still work (strafing slides along the wall).
        do {
            var wedged: [String] = []
            for i in 1...Game().maxLevels {
                let g = Game()
                g.levelIndex = i
                g.loadLevel()
                // the generated spawn faces the next room; check it has room
                let a = g.pang
                let d = g.wallDistance(g.px, g.py, cos(a), sin(a), 4.0)
                if d < 1.0 {
                    wedged.append("L\(i) wall at \(String(format: "%.2f", d))")
                    continue
                }
                // and the tile straight ahead must be walkable
                let ax = g.px + cos(a) * 0.5, ay = g.py + sin(a) * 0.5
                if g.level.solidAtPoint(ax, ay, radius: 0.24, doorsPassable: false) {
                    wedged.append("L\(i) tile ahead solid")
                    continue
                }
                // finally: hold "forward" and confirm the position really changes
                let x0 = g.px, y0 = g.py
                g.input.forward = 1
                for _ in 0..<30 { g.update(1.0 / 60.0) }
                let moved = hypot(g.px - x0, g.py - y0)
                if moved < 0.5 { wedged.append("L\(i) moved only \(String(format: "%.2f", moved))") }
            }
            check("spawn has open floor ahead (W/S work on level 1)", wedged.isEmpty,
                  wedged.joined(separator: "; "))
            if CommandLine.arguments.contains("--spawndebug") && !wedged.isEmpty {
                for i in 1...Game().maxLevels {
                    let g = Game()
                    g.levelIndex = i
                    g.loadLevel()
                    print(String(format: "   L%d start=(%.2f,%.2f) ang=%.2f wallD=%.2f tileAt=(%d,%d)",
                                 i, g.px, g.py, g.pang,
                                 g.wallDistance(g.px, g.py, cos(g.pang), sin(g.pang), 4.0),
                                 Int((g.px + cos(g.pang) * 0.5).rounded(.down)),
                                 Int((g.py + sin(g.pang) * 0.5).rounded(.down))))
                    let sx = Int(g.px.rounded(.down)), sy = Int(g.py.rounded(.down))
                    var rows = ""
                    for dy in -2...2 {
                        var line = "     "
                        for dx in -2...2 { line += g.level.at(sx + dx, sy + dy) == Tile.floor ? "." : "#" }
                        rows += line + "\n"
                    }
                    print("   L\(i) room=\(g.level.rooms[0]) cells:\(rows)")
                    print("     openAhead(+x)=\(g.level.wallDistance(g.px, g.py, 1, 0, 3.5)) "
                        + "openAhead(+y)=\(g.level.wallDistance(g.px, g.py, 0, 1, 3.5)) "
                        + "solidAt(start)=\(g.level.solidAtPoint(g.px, g.py, radius: 0.24, doorsPassable: false))")
                }
            }
        }

        // 13. co-op: three local players, independent state, shared world
        do {
            let g = Game()
            g.setPlayerCount(3)
            g.startNewGame()
            check("three local players are created", g.players.count == 3 && g.playerCount == 3,
                  "count=\(g.players.count)")
            check("co-op players are distinct", g.players[0] !== g.players[1] && g.players[1] !== g.players[2])
            check("co-op players are named", g.players.map { $0.name } == ["P1", "P2", "P3"],
                  "\(g.players.map { $0.name })")

            // nobody may start inside a wall, or stuck on each other
            var stuck: [String] = []
            for p in g.players {
                if g.level.solidAtPoint(p.x, p.y, radius: 0.24, doorsPassable: false) {
                    stuck.append("\(p.name) in wall")
                }
                if g.level.wallDistance(p.x, p.y, cos(p.ang), sin(p.ang), 1.0, doorsPassable: false) < 0.5 {
                    stuck.append("\(p.name) facing wall")
                }
            }
            check("all three co-op spawns are clear", stuck.isEmpty, stuck.joined(separator: "; "))

            // spawn points must not overlap
            var minSep = Double.infinity
            for i in 0..<3 {
                for j in (i + 1)..<3 {
                    minSep = min(minSep, hypot(g.players[i].x - g.players[j].x,
                                               g.players[i].y - g.players[j].y))
                }
            }
            check("co-op spawns are spread out", minSep > 0.4, String(format: "min sep %.2f", minSep))
        }

        // 14. co-op: each player moves, fires and owns its own ammo/score
        do {
            let g = Game()
            g.setPlayerCount(3)
            g.startNewGame()
            g.enemies.removeAll()
            g.pickups.removeAll()

            // put the squad in clear space, facing the same way
            for (i, p) in g.players.enumerated() {
                p.x = g.level.startPos.x + Double(i) * 0.7
                p.y = g.level.startPos.y
                p.ang = g.level.startPos.ang
                p.spawnGrace = 99
            }
            let x0 = g.players.map { $0.x }
            for p in g.players { p.input.forward = 1 }
            for _ in 0..<20 { g.update(1.0 / 60.0) }
            let movedAll = g.players.enumerated().allSatisfy { i, p in
                // each player advanced, and none of them ran into anyone else
                hypot(p.x - x0[i], p.y - g.level.startPos.y) > 0.3
            }
            check("all three co-op players can move", movedAll,
                  "d=" + g.players.map { String(format: "%.2f", $0.x - x0[$0.index]) }.joined(separator: ","))

            // no two players may occupy the same tile
            var overlap = false
            for i in 0..<3 {
                for j in (i + 1)..<3 {
                    if hypot(g.players[i].x - g.players[j].x, g.players[i].y - g.players[j].y) < 0.2 {
                        overlap = true
                    }
                }
            }
            check("co-op players do not stack on one spot", !overlap)

            // independent ammo: only P2 fires
            for p in g.players { p.ammo = [50, 0, 0, 0] }
            g.players[1].input.firePressed = true
            g.update(1.0 / 60.0)
            check("only the firing player spends ammo",
                  g.players[0].ammo[0] == 50 && g.players[1].ammo[0] == 49 && g.players[2].ammo[0] == 50,
                  "ammo=\(g.players.map { $0.ammo[0] })")

            // a kill is credited to whoever fired it
            g.enemies.append(Enemy(x: g.players[2].x + cos(g.players[2].ang) * 2.0,
                                   y: g.players[2].y + sin(g.players[2].ang) * 2.0,
                                   type: 0, difficulty: 1))
            let e = g.enemies[0]
            var shots = 0
            while !e.dead && shots < 60 {
                g.players[2].input.firePressed = true
                g.update(1.0 / 60.0)
                shots += 1
            }
            check("a kill is credited to the shooter, not the whole squad",
                  e.dead && g.players[2].kills == 1 && g.players[0].kills == 0 && g.players[1].kills == 0,
                  "kills=\(g.players.map { $0.kills })")
        }

        // 15. co-op: a downed player respawns and the round does not end
        do {
            let g = Game()
            g.setPlayerCount(3)
            g.startNewGame()
            g.enemies.removeAll()
            g.hurt(g.players[1], 500, ignoreArmor: true)
            check("a downed co-op player is marked, not game-over",
                  g.players[1].down && g.state == .playing, "state=\(g.state.rawValue)")
            check("a downed player stops being hurt", {
                let hp = g.players[1].health
                g.hurt(g.players[1], 100, ignoreArmor: true)
                return g.players[1].health == hp
            }())
            for _ in 0..<Int(Player.respawnDelay * 60) + 30 { g.update(1.0 / 60.0) }
            check("a downed player redeploys at full health",
                  !g.players[1].down && g.players[1].health == 100,
                  "down=\(g.players[1].down) hp=\(g.players[1].health)")
        }

        // 16. co-op: the exit waits for everyone
        do {
            let g = Game()
            g.setPlayerCount(3)
            g.startNewGame()
            var exitTile = (-1, -1)
            outer: for y in 0..<g.level.h {
                for x in 0..<g.level.w where g.level.at(x, y) == Tile.exit {
                    exitTile = (x, y)
                    break outer
                }
            }
            if exitTile.0 >= 0 {
                let cx = Double(exitTile.0) + 0.5, cy = Double(exitTile.1) + 0.5
                // park P1 and P2 on the exit, leave P3 across the map
                g.players[0].x = cx; g.players[0].y = cy
                g.players[1].x = cx; g.players[1].y = cy
                g.players[2].x = g.level.startPos.x; g.players[2].y = g.level.startPos.y
                g.update(1.0 / 60.0)
                check("co-op exit waits for the straggler", g.state == .playing, "state=\(g.state.rawValue)")
                g.players[2].x = cx; g.players[2].y = cy
                g.update(1.0 / 60.0)
                check("co-op exit opens once everyone arrives", g.state == .levelDone,
                      "state=\(g.state.rawValue)")
            } else {
                check("co-op exit test found the exit", false)
            }
        }

        // 17. splash damage reaches every player in range, not just the shooter
        do {
            let g = Game()
            g.setPlayerCount(3)
            g.startNewGame()
            g.enemies.removeAll()
            let cx = g.level.startPos.x, cy = g.level.startPos.y
            for (i, p) in g.players.enumerated() {
                p.x = cx + Double(i) * 0.6     // all well inside the blast
                p.y = cy
                p.spawnGrace = 0
            }
            g.barrels = [Barrel(x: cx, y: cy)]
            let before = g.players.map { $0.health }
            g.explodeBarrelForTest(g.barrels[0], damage: 30)
            let after = g.players.map { $0.health }
            check("a barrel blast damages all three players",
                  after.indices.allSatisfy { after[$0] < before[$0] },
                  "before=\(before) after=\(after)")
        }

        // 17b. spawn grace is a real shield, not just an enemy-fire one: a level
        //      that rolls a barrel or a tank next to the start must not open with
        //      an unavoidable hit.
        do {
            let g = Game()
            g.startNewGame()
            g.enemies.removeAll()
            g.p0.spawnGrace = 1.0
            let hp = g.health
            g.explodeBarrelForTest(Barrel(x: g.px, y: g.py), damage: 30)
            check("spawn grace blocks a point-blank blast", g.health == hp,
                  "hp=\(g.health) was \(hp)")
            // ... and it expires
            g.p0.spawnGrace = 0
            g.explodeBarrelForTest(Barrel(x: g.px, y: g.py), damage: 30)
            check("the blast lands once spawn grace expires", g.health < hp, "hp=\(g.health)")
        }

        // 18. split-screen geometry: the views tile the frame with no gap/overlap
        do {
            let w = 480, h = 300
            var ok = true
            var detail = ""
            for n in 1...maxLocalPlayers {
                let rects = GameView.viewRects(count: n, w: w, h: h)
                if rects.count != n { ok = false; detail = "count=\(rects.count) for \(n)"; break }
                var covered = 0
                for r in rects {
                    if r.width < 100 { ok = false; detail = "view too narrow: \(Int(r.width))"; }
                    if r.origin.x < 0 || r.origin.x + r.width > Double(w) + 0.5 {
                        ok = false; detail = "out of bounds"
                    }
                    covered += Int(r.width) * Int(r.height)
                }
                // columns must be contiguous: no seam and no overlap
                var x = 0
                for r in rects {
                    if Int(r.origin.x) != x { ok = false; detail = "gap/overlap at \(Int(r.origin.x)) != \(x)"; break }
                    x += Int(r.width)
                }
                if covered > w * h { ok = false; detail = "views overlap" }
            }
            check("split-screen views tile the frame exactly", ok, detail)
        }

        // 19. difficulty actually changes the fight, and is settable
        do {
            func soldierHP(_ d: Difficulty) -> Double {
                Difficulty.current = d
                defer { Difficulty.current = .veteran }
                return Enemy(x: 0, y: 0, type: EnemyType.soldier, difficulty: 4).maxHP
            }
            let rookie = soldierHP(.rookie)
            let veteran = soldierHP(.veteran)
            let elite = soldierHP(.elite)
            check("difficulty scales enemy health", rookie < veteran && veteran < elite,
                  "\(String(format: "%.0f", rookie))/\(String(format: "%.0f", veteran))/\(String(format: "%.0f", elite))")
            // damage taken scales too, so elite is not just a bullet sponge
            func taken(_ d: Difficulty) -> Double {
                Difficulty.current = d
                defer { Difficulty.current = .veteran }
                let g = freshGame()
                g.spawnGrace = 0
                g.hurt(g.p0, 50, ignoreArmor: true)
                return 100 - g.health
            }
            check("difficulty scales damage taken", taken(.rookie) < taken(.elite),
                  "\(String(format: "%.1f", taken(.rookie))) vs \(String(format: "%.1f", taken(.elite)))")
            // the menu/title path writes the same global
            let g = Game()
            g.difficulty = .elite
            check("difficulty round-trips through Game", g.difficulty == .elite && Game.difficultySetting == 2)
            g.difficulty = .veteran
        }

        // 20. powerups: berserk, invulnerability, megahealth, ammo crate
        do {
            let g = freshGame()
            g.health = 50
            g.pickups = [Pickup(x: g.px, y: g.py, kind: .megahealth)]
            step(g, 2)
            check("megahealth heals past the 100 cap", g.health > 100, "hp=\(g.health)")

            let g2 = freshGame()
            g2.pickups = [Pickup(x: g2.px, y: g2.py, kind: .berserk)]
            step(g2, 2)
            check("berserk sets a timer", g2.p0.berserk > 10, "rage=\(String(format: "%.1f", g2.p0.berserk))")

            // invulnerability must actually eat a hit
            let g3 = freshGame()
            g3.p0.invulnerable = 5
            g3.hurt(g3.p0, 40, ignoreArmor: true)
            check("invulnerability blocks damage", g3.health == 100, "hp=\(g3.health)")
            g3.p0.invulnerable = 0
            g3.hurt(g3.p0, 40, ignoreArmor: true)
            check("damage lands once the shield expires", g3.health < 100, "hp=\(g3.health)")

            let g4 = freshGame()
            g4.ammo = [0, 0, 0, 0]
            g4.pickups = [Pickup(x: g4.px, y: g4.py, kind: .ammoBox)]
            step(g4, 2)
            check("ammo crate fills every ammo type", g4.ammo.allSatisfy { $0 > 0 }, "ammo=\(g4.ammo)")
        }

        // 21. berserk really does speed up the weapon, and the streak really does
        //     pay more than a cold kill
        do {
            let g = freshGame()
            g.owned[2] = true
            g.ammo[0] = 200
            g.input.wantWeapon = 2
            step(g, 2)
            // count shots in a fixed window, normal then berserk
            func shots(_ berserk: Bool) -> Int {
                g.p0.fireCooldown = 0
                g.p0.berserk = berserk ? 10 : 0
                let before = g.ammo[0]
                for _ in 0..<60 {
                    g.input.fire = true
                    g.input.firePressed = true
                    step(g, 1)
                }
                return before - g.ammo[0]
            }
            let normal = shots(false)
            let raged = shots(true)
            check("berserk raises the rate of fire", raged > normal, "normal=\(normal) rage=\(raged)")

            let g2 = freshGame()
            g2.enemies = []
            g2.score = 0
            // one kill cold, then a second immediately after to build the streak
            g2.damageEnemy(Enemy(x: g2.px + 1, y: g2.py, type: 0, difficulty: 1), damage: 999, by: g2.p0)
            let cold = g2.score
            g2.damageEnemy(Enemy(x: g2.px + 1, y: g2.py, type: 0, difficulty: 1), damage: 999, by: g2.p0)
            let warm = g2.score - cold
            check("a kill streak raises the score awarded", warm > cold,
                  "cold=\(cold) warm=\(warm) streak=\(g2.p0.streak)")
            // and the streak lapses if you stop killing
            g2.p0.streakTimer = 0.001
            step(g2, 5)
            check("the streak lapses after its window", g2.p0.streak == 0, "streak=\(g2.p0.streak)")
        }

        // 22. secrets: generated, sealed, and found on entry
        do {
            var foundLevel = 0
            var totalSecrets = 0
            for i in 1...Game().maxLevels {
                let lv = LevelBuilder.build(level: i)
                totalSecrets += lv.secrets.count
                if foundLevel == 0 && !lv.secrets.isEmpty { foundLevel = i }
            }
            check("later levels generate secret chambers", foundLevel >= 2 && totalSecrets > 0,
                  "first at L\(foundLevel), \(totalSecrets) total")

            // the front wall must actually be solid, or the "secret" is not sealed
            var unsealed: [String] = []
            for i in 1...Game().maxLevels {
                for s in LevelBuilder.build(level: i).secrets {
                    let wx = s.x0, wy = (s.y0 + s.y1) / 2
                    if !Tile.isSolidCell(LevelBuilder.build(level: i).at(wx, wy)) {
                        unsealed.append("L\(i)")
                    }
                }
            }
            check("every secret chamber is walled shut", unsealed.isEmpty,
                  unsealed.joined(separator: ","))

            // walking in scores it and records the find
            let g = Game()
            g.levelIndex = Game().maxLevels
            g.loadLevel()
            guard let s = g.level.secrets.first else {
                check("secret find test found a secret", false)
                return
            }
            g.p0.x = s.cx
            g.p0.y = s.cy
            let before = g.totalScore
            g.update(1.0 / 60.0)
            check("entering a secret is detected and scored",
                  g.levelSecrets == 1 && g.totalScore > before,
                  "found=\(g.levelSecrets) score \(before)->\(g.totalScore)")
        }

        // 23. the new enemy specialists behave
        do {
            // marksman: long reach, hits hard
            let m = Enemy(x: 0, y: 0, type: EnemyType.marksman, difficulty: 3)
            check("marksman out-ranges a soldier",
                  m.attackRange > Enemy(x: 0, y: 0, type: EnemyType.soldier, difficulty: 3).attackRange
                  && m.maxDamage > Enemy(x: 0, y: 0, type: EnemyType.soldier, difficulty: 3).maxDamage,
                  "range=\(m.attackRange) dmg=\(m.maxDamage)")

            // grenadier: lobs a projectile that goes hostile
            let g = freshGame()
            g.p0.spawnGrace = 0
            let e = Enemy(x: g.px + 4, y: g.py, type: EnemyType.grenadier, difficulty: 1)
            g.enemies = [e]
            var sawGrenade = false
            for _ in 0..<400 {
                g.update(1.0 / 60.0)
                if g.projectiles.contains(where: { $0.hostile }) { sawGrenade = true; break }
            }
            check("a grenadier lobs a projectile", sawGrenade)
            check("enemy projectiles are flagged hostile",
                  g.projectiles.allSatisfy { !$0.hostile } || g.projectiles.contains { $0.hostile })

            // riot trooper: a shield blunts frontal fire
            let g2 = freshGame()
            let r1 = Enemy(x: g2.px + cos(g2.pang) * 2, y: g2.py + sin(g2.pang) * 2,
                           type: EnemyType.rioter, difficulty: 1)
            g2.enemies = [r1]
            g2.damageEnemy(r1, damage: 100, by: g2.p0, frontal: true)
            let frontalLoss = r1.maxHP - r1.hp
            g2.damageEnemy(r1, damage: 100, by: g2.p0, frontal: false)
            let flankLoss = r1.maxHP - r1.hp - frontalLoss
            check("a riot shield blunts frontal fire", flankLoss > frontalLoss,
                  "frontal=\(String(format: "%.0f", frontalLoss)) flank=\(String(format: "%.0f", flankLoss))")
        }

        // 24. accuracy tracking, and the exit bonus for a clean level
        do {
            let g = freshGame()
            g.enemies = [Enemy(x: g.px + cos(g.pang) * 2, y: g.py + sin(g.pang) * 2,
                               type: 0, difficulty: 1)]
            for _ in 0..<10 {
                g.input.firePressed = true
                g.input.fire = true
                step(g, 1)
            }
            check("shots fired and hits are counted", g.levelShots > 0 && g.levelHits > 0,
                  "\(g.levelHits)/\(g.levelShots) acc=\(g.accuracy.map { String(format: "%.2f", $0) } ?? "nil")")
            check("accuracy is a sane fraction", (g.accuracy ?? 0) > 0 && (g.accuracy ?? 1) <= 1)
        }

        // 25. the level count actually goes up, and the campaign ends cleanly
        do {
            let g = Game()
            g.startNewGame()
            var ok = g.maxLevels >= 12
            // jump to the last level and take the exit: the run must end, not wrap
            g.levelIndex = g.maxLevels
            g.loadLevel()
            guard let t = g.level.exitTile else {
                check("campaign-final level has an exit", false)
                return
            }
            g.p0.x = Double(t.0) + 0.5
            g.p0.y = Double(t.1) + 0.5
            step(g, 2)
            ok = ok && g.state == .levelDone
            step(g, 120)
            ok = ok && g.state == .victory
            check("the \(g.maxLevels)-level campaign ends in victory", ok,
                  "state=\(g.state.rawValue)")
        }

        print(failures == 0 ? "   == all logic tests passed ==" : "   == \(failures) FAILURES ==")
    }

    static func run() {
        setvbuf(stdout, nil, _IONBF, 0)
        if CommandLine.arguments.contains("--logic") {
            logicTests()
            exit(failuresHappened ? 1 : 0)
        }
        var t0 = Date()
        print("== texture build ==")
        _ = TexLib.walls
        _ = TexLib.sprites
        _ = TexLib.weaponViews
        _ = Font3x5.glyphs
        print(String(format: "   %.1f ms", -t0.timeIntervalSinceNow * 1000))

        t0 = Date()
        print("== level generation ==")
        var levels: [Level] = []
        for i in 1...Game().maxLevels {
            let lv = LevelBuilder.build(level: i)
            levels.append(lv)
            let flow = lv.flowField(from: (Int(lv.startPos.x), Int(lv.startPos.y)))
            var exitReachable = false
            var exitTile = (0, 0)
            for y in 0..<lv.h {
                for x in 0..<lv.w where lv.at(x, y) == Tile.exit {
                    exitReachable = true
                    exitTile = (x, y)
                }
            }
            // is the exit reachable: does any floor cell next to it have flow > 0?
            var exitAdjacent = false
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = exitTile.0 + dx, ny = exitTile.1 + dy
                if lv.inBounds(nx, ny) && lv.at(nx, ny) == Tile.floor && flow[ny * lv.w + nx] > 0 { exitAdjacent = true }
            }
            let startSolid = lv.solidAtPoint(lv.startPos.x, lv.startPos.y, radius: 0.24, doorsPassable: false)
            var badSpawns = 0
            for e in lv.enemySpecs where lv.solidAtPoint(e.x, e.y, radius: 0.3, doorsPassable: true) { badSpawns += 1 }
            // a pickup inside a secret chamber is deliberately *not* reachable by
            // the normal flow field, so only judge orphans outside the secrets
            var orphanPickups = 0
            for p in lv.pickupSpecs {
                let fx = Int(p.x), fy = Int(p.y)
                let inSecret = lv.secrets.contains { $0.contains(fx, fy) }
                if inSecret { continue }
                if !lv.inBounds(fx, fy) || lv.at(fx, fy) != Tile.floor || flow[fy * lv.w + fx] <= 0 { orphanPickups += 1 }
            }
            var doors = 0
            for c in lv.cells where c == Tile.door { doors += 1 }
            var typeCounts = [Int](repeating: 0, count: EnemyType.count)
            for e in lv.enemySpecs where e.type >= 0 && e.type < EnemyType.count { typeCounts[e.type] += 1 }
            let mix = typeCounts.enumerated().compactMap { c, n in n > 0 ? "\(Enemy(x: 0, y: 0, type: c, difficulty: 1).name) \(n)" : nil }
            .joined(separator: " ")
            print(String(format: "   L%d rooms:%2d enemies:%3d pickups:%3d barrels:%2d doors:%2d secret:%d exit:%@ adj:%@ startInWall:%@ badSpawn:%d orphan:%d",
                         i, lv.rooms.count, lv.enemySpecs.count, lv.pickupSpecs.count, lv.barrelSpecs.count,
                         doors, lv.secrets.count,
                         exitReachable ? "ok" : "MISSING", exitAdjacent ? "ok" : "BLOCKED",
                         startSolid ? "YES" : "no", badSpawns, orphanPickups))
            print("        mix: \(mix.isEmpty ? "(none)" : mix)")
        }
        print(String(format: "   %.1f ms total", -t0.timeIntervalSinceNow * 1000))

        // ---- simulate play ----
        print("== simulation (600 frames x 3 runs) ==")
        var g = Game()
        g.startNewGame()
        var shots: [(String, Framebuffer)] = []
        let fb = Framebuffer(w: 480, h: 300)
        if CommandLine.arguments.contains("--probe") {
            let lvl = CommandLine.arguments.firstIndex(of: "--probe").map { i in Int(CommandLine.arguments[i + 1]) ?? 1 } ?? 1
            let g = Game()
            g.startNewGame()
            g.levelIndex = lvl
            g.loadLevel()
            for frame in 0..<600 {
                g.input.forward = (frame / 60) % 2 == 0 ? 1.0 : -1.0
                g.input.strafe = ((frame / 40) % 2 == 0) ? 1.0 : -1.0
                g.input.turn = ((frame / 30) % 2 == 0) ? 1.0 : -1.0
                g.input.run = true
                g.input.fire = (frame % 3) == 0
                g.input.firePressed = (frame % 7) == 0
                let su = Date()
                g.update(1.0 / 60.0)
                let ums = -su.timeIntervalSinceNow * 1000
                let s = Date()
                Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
                Hud.drawWeapon(g, g.players[0], fb)
                let ms = -s.timeIntervalSinceNow * 1000
                _ = (ums, ms)
                if g.health <= 0 { g.startNewGame(); g.levelIndex = lvl; g.loadLevel() }
            }
            print("probe done")
            exit(0)
        }


        for run in 0..<3 {
            g = Game()
            g.startNewGame()
            if run > 0 { g.levelIndex = run * 2 + 1; g.loadLevel() }
            var renderTime = 0.0
            var worst = 0.0
            for frame in 0..<600 {
                g.input.forward = (frame / 60) % 2 == 0 ? 1.0 : -1.0
                g.input.strafe = ((frame / 40) % 2 == 0) ? 1.0 : -1.0
                g.input.turn = ((frame / 30) % 2 == 0) ? 1.0 : -1.0
                g.input.run = true
                g.input.wantWeapon = (frame / 150) % g.weapons.count
                g.input.firePressed = true
                g.input.fire = (frame % 3) == 0
                g.update(1.0 / 60.0)
                let s = Date()
                Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
                Hud.drawWeapon(g, g.players[0], fb)
                Hud.drawTopInfo(g, g.players[0], fb)
                Hud.drawProgress(g, g.players[0], fb)
                Hud.drawCrosshair(g, g.players[0], fb)
                Hud.drawStatusBar(g, g.players[0], fb)
                Hud.drawVignette(g, g.players[0], fb)
                let dtms = -s.timeIntervalSinceNow * 1000
                renderTime += dtms
                worst = max(worst, dtms)
                if frame == 20 || frame == 120 {
                    shots.append((String(format: "/tmp/doomish_shot_%d_%03d.ppm", run, frame), fb.copy()))
                }
                if g.health <= 0 { g.startNewGame() }
            }
            print(String(format: "   run %d: state %d hp %.0f armor %.0f ammo %@ kills %d score %d  avg render %.2f ms  worst %.2f ms  (budget 16.7)",
                         run, g.state.rawValue, g.health, g.armor, "\(g.ammo)", g.kills, g.score,
                         renderTime / 600.0, worst))
        }

        // final beauty shots at several levels
        g = Game()
        g.startNewGame()
        for (idx, label) in [(1, "e1m1"), (3, "e1m3"), (6, "e1m6")] {
            g.levelIndex = idx
            g.loadLevel()
            for frame in 0..<40 {
                g.input.forward = frame < 20 ? 1.0 : 0.0
                g.input.firePressed = (frame == 30)
                g.update(1.0 / 60.0)
            }
            Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
            fb.brighten(0.16 * g.muzzleFlash)
            Hud.drawWeapon(g, g.players[0], fb)
            Hud.drawTopInfo(g, g.players[0], fb)
            Hud.drawProgress(g, g.players[0], fb)
            Hud.drawCrosshair(g, g.players[0], fb)
            Hud.drawStatusBar(g, g.players[0], fb)
            Hud.drawVignette(g, g.players[0], fb)
            shots.append(("/tmp/doomish_level_\(label).ppm", fb.copy()))
        }
        // automap shot
        g.showAutomap = true
        Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
        Hud.drawAutomap(g, fb)
        shots.append(("/tmp/doomish_automap.ppm", fb.copy()))
        g.showAutomap = false
        // title shot (time 0 so the blinking prompt is captured lit)
        g.state = .start
        g.time = 0
        Hud.drawTitle(g, fb)
        shots.append(("/tmp/doomish_title.ppm", fb.copy()))

        // army showcase: every enemy type and the new pickups on one frame
        g.state = .playing
        g.enemies.removeAll()
        g.pickups.removeAll()
        g.barrels.removeAll()
        g.owned = [Bool](repeating: true, count: g.weapons.count)
        g.ammo = [140, 40, 90, 12]
        g.health = 78
        g.armor = 55
        g.weapon = 4
        g.kills = 7
        g.totalEnemies = 26
        g.difficulty = .elite
        g.levelSecrets = 1
        g.secretsTotal = 2
        g.p0.streak = 6
        g.p0.streakTimer = 6
        g.p0.berserk = 11
        g.killFeed = [("P1  SOLDIER  +150", 2.5), ("P2  HEAVY  +400", 2.0), ("P3  MARKSMAN  +175", 1.0)]
        for (d, a, type) in [(1.9, 0.0, 2), (2.6, 0.30, 0), (3.3, -0.30, 3), (4.1, 0.55, 1),
                             (3.0, -0.62, EnemyType.grenadier), (4.6, -0.75, EnemyType.marksman),
                             (5.4, 0.68, EnemyType.rioter)] {
            g.enemies.append(Enemy(x: g.px + cos(g.pang + a) * d, y: g.py + sin(g.pang + a) * d,
                                   type: type, difficulty: 2))
        }
        for (d, a, k) in [(1.3, -0.55, PickupKind.rifle), (1.6, -0.72, PickupKind.launcher),
                          (1.9, -0.88, PickupKind.rockets), (2.2, 0.85, PickupKind.chaingun),
                          (2.5, 0.98, PickupKind.medikit), (2.8, 1.06, PickupKind.saw),
                          (3.1, 1.12, PickupKind.dmr), (3.4, 1.18, PickupKind.sniper),
                          (3.7, 1.24, PickupKind.berserk), (4.0, 1.30, PickupKind.ammoBox),
                          (4.3, 1.36, PickupKind.invulnerability), (4.6, 1.42, PickupKind.megahealth)] {
            g.pickups.append(Pickup(x: g.px + cos(g.pang + a) * d, y: g.py + sin(g.pang + a) * d, kind: k))
        }
        g.barrels.append(Barrel(x: g.px + cos(g.pang - 0.4) * 2.0, y: g.py + sin(g.pang - 0.4) * 2.0))
        g.projectiles.append(Projectile(x: g.px + cos(g.pang) * 2.2, y: g.py + sin(g.pang) * 2.2,
                                        z: Renderer.eyeHeight, vx: cos(g.pang) * 15, vy: sin(g.pang) * 15,
                                        damage: 96))
        g.muzzleFlash = 0.8
        g.hitMarker = 0.9
        Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
        fb.brighten(0.16 * g.muzzleFlash)
        Hud.drawWeapon(g, g.players[0], fb)
        Hud.drawTopInfo(g, g.players[0], fb)
        Hud.drawProgress(g, g.players[0], fb)
        Hud.drawCrosshair(g, g.players[0], fb)
        Hud.drawStatusBar(g, g.players[0], fb)
        Hud.drawExitCompass(g, g.players[0], fb)
        Hud.drawPowerups(g, g.players[0], fb)
        Hud.drawCombo(g, g.players[0], fb)
        Hud.drawKillFeed(g, fb)
        Hud.drawVignette(g, g.players[0], fb)
        shots.append(("/tmp/doomish_showcase.ppm", fb.copy()))

        // one screenshot per weapon view
        for w in 0..<g.weapons.count {
            g.weapon = w
            g.muzzleFlash = (w == 1 || w == 4) ? 1.0 : 0.0
            g.recoil = 0.5
            g.kick = 0.5
            Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
            fb.brighten(0.16 * g.muzzleFlash)
            Hud.drawWeapon(g, g.players[0], fb)
            Hud.drawTopInfo(g, g.players[0], fb)
            Hud.drawProgress(g, g.players[0], fb)
            Hud.drawCrosshair(g, g.players[0], fb)
            Hud.drawStatusBar(g, g.players[0], fb)
            Hud.drawVignette(g, g.players[0], fb)
            shots.append((String(format: "/tmp/doomish_weapon_%d.ppm", w), fb.copy()))
        }

        // pause screen, so the stat block is eyeballed too
        g.weapon = 3
        g.paused = true
        g.levelShots = 184
        g.levelHits = 121
        Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
        Hud.drawForPlayer(g, g.players[0], fb)
        Hud.drawOverlays(g, fb)
        shots.append(("/tmp/doomish_pause.ppm", fb.copy()))
        g.paused = false

        // victory summary
        g.state = .victory
        g.totalKills = 512
        g.totalScore = 148920
        g.secretsFound = 17
        Hud.drawOverlays(g, fb)
        shots.append(("/tmp/doomish_victory.ppm", fb.copy()))
        g.state = .playing
        g.difficulty = .veteran

        for (path, buf) in shots {
            writePPM(path, buf)
            print("   wrote \(path)")
        }
        if CommandLine.arguments.contains("--stress") {
            // worst case: three full split-screen views plus a horde on the camera
            let g = Game()
            g.setPlayerCount(3)
            g.startNewGame()
            g.levelIndex = 5
            g.loadLevel()
            for i in 0..<40 {
                let a = Double(i) / 40.0 * 2 * .pi
                g.enemies.append(Enemy(x: g.px + cos(a) * 0.8, y: g.py + sin(a) * 0.8, type: i % 4, difficulty: 5))
            }
            for i in 0..<24 {
                let a = Double(i) / 24.0 * 2 * .pi
                g.particles.append(Particle(x: g.px + cos(a) * 1.2, y: g.py + sin(a) * 1.2, z: 0.5,
                                            vz: 1.0, life: 99, color: (200, 100, 40), size: 0.05))
            }
            let rects = GameView.viewRects(count: 3, w: fb.w, h: fb.h)
            let vfbs = rects.map { Framebuffer(w: max(1, Int($0.width)), h: max(1, Int($0.height))) }
            var total = 0.0, worst = 0.0
            var worldMs = 0.0, hudMs = 0.0, blendMs = 0.0
            for _ in 0..<120 {
                g.update(1.0 / 60.0)
                let s = Date()
                for (i, p) in g.players.enumerated() {
                    Renderer.renderWorld(g, vfbs[i], Renderer.camera(for: p))
                }
                let mid = Date()
                for (i, p) in g.players.enumerated() {
                    Hud.drawForPlayer(g, p, vfbs[i])
                }
                let m2 = Date()
                for i in 0..<g.players.count {
                    blend(vfbs[i], into: fb, atX: Int(rects[i].origin.x))
                }
                let ms = -s.timeIntervalSinceNow * 1000
                worldMs += -mid.timeIntervalSinceNow * 1000
                hudMs += -m2.timeIntervalSinceNow * 1000
                blendMs += -Date().timeIntervalSinceNow * 1000
                total += ms
                worst = max(worst, ms)
            }
            print(String(format: "   breakdown: world %.2f ms  hud %.2f ms  blend %.2f ms",
                         worldMs / 120.0, hudMs / 120.0, blendMs / 120.0))
            print(String(format: "STRESS 3 split views + 40 enemies + 24 particles: avg %.2f ms  worst %.2f ms  (60fps budget 16.7 ms)",
                         total / 120.0, worst))
            exit(0)
        }

        if CommandLine.arguments.contains("--ascii") {
            let g = Game()
            g.startNewGame()
            g.levelIndex = 1
            g.loadLevel()
            for _ in 0..<30 { g.input.forward = 1.0; g.update(1.0 / 60.0) }
            Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
            Hud.drawWeapon(g, g.players[0], fb); Hud.drawStatusBar(g, g.players[0], fb); Hud.drawCrosshair(g, g.players[0], fb)
            asciiDump(fb, cols: 120, rows: 40, title: "level 1 in-game")
            // showcase: every enemy type, army pickups, a barrel and a rocket
            g.enemies.removeAll()
            g.enemies.append(Enemy(x: g.px + cos(g.pang) * 2.2, y: g.py + sin(g.pang) * 2.2, type: 0, difficulty: 1))
            g.enemies.append(Enemy(x: g.px + cos(g.pang + 0.4) * 3.4, y: g.py + sin(g.pang + 0.4) * 3.4, type: 1, difficulty: 1))
            g.enemies.append(Enemy(x: g.px + cos(g.pang - 0.4) * 3.4, y: g.py + sin(g.pang - 0.4) * 3.4, type: 2, difficulty: 1))
            g.enemies.append(Enemy(x: g.px + cos(g.pang + 0.75) * 4.6, y: g.py + sin(g.pang + 0.75) * 4.6, type: 3, difficulty: 1))
            g.pickups.removeAll()
            for (d, k) in [(1.4, PickupKind.medikit), (2.0, PickupKind.rifle), (2.6, PickupKind.launcher),
                           (3.2, PickupKind.rockets), (3.8, PickupKind.chaingun)] {
                g.pickups.append(Pickup(x: g.px + cos(g.pang - 0.9) * d, y: g.py + sin(g.pang - 0.9) * d, kind: k))
            }
            g.barrels.removeAll()
            g.barrels.append(Barrel(x: g.px + cos(g.pang - 0.35) * 1.8, y: g.py + sin(g.pang - 0.35) * 1.8))
            g.projectiles.removeAll()
            g.projectiles.append(Projectile(x: g.px + cos(g.pang) * 2.2, y: g.py + sin(g.pang) * 2.2,
                                            z: Renderer.eyeHeight, vx: 0, vy: 0, damage: 96))
            g.owned = [true, true, true, true, true]
            g.ammo = [140, 40, 90, 12]
            g.update(1.0 / 60.0)
            Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
            Hud.drawWeapon(g, g.players[0], fb)
            asciiDump(fb, cols: 120, rows: 40, title: "sprites: imp, brute, soldier, heavy, army pickups, barrel, rocket")
            for w in 0..<g.weapons.count {
                g.weapon = w
                g.ammo = [140, 40, 90, 12]
                g.muzzleFlash = (w == 1 || w == 4) ? 1.0 : 0.0
                g.recoil = 0.5
                Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
                Hud.drawWeapon(g, g.players[0], fb)
                asciiDump(fb, cols: 120, rows: 40, title: "weapon \(w): \(g.weapons[w].name)")
            }
            g.showAutomap = true
            Renderer.renderWorld(g, fb, Renderer.camera(for: g.players[0]))
            Hud.drawAutomap(g, fb)
            asciiDump(fb, cols: 120, rows: 40, title: "automap")
            g.state = .start
            Hud.drawTitle(g, fb)
            asciiDump(fb, cols: 120, rows: 40, title: "title screen")
        }
        print("== done ==")
    }

    /// Terminal-friendly visualisation of a framebuffer so the rendering can be
    /// eyeballed without a display: luminance ramp plus dominant-hue letters.
    static func asciiDump(_ fb: Framebuffer, cols: Int = 120, rows: Int = 40, title: String = "") {
        print("--- \(title) [\(fb.w)x\(fb.h)] ---")
        let ramp: [Character] = Array(" .:-=+*#%@")
        var out = ""
        for ry in 0..<rows {
            var line = ""
            for rx in 0..<cols {
                let x0 = rx * fb.w / cols, x1 = max(x0 + 1, (rx + 1) * fb.w / cols)
                let y0 = ry * fb.h / rows, y1 = max(y0 + 1, (ry + 1) * fb.h / rows)
                var r = 0, g = 0, b = 0, n = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let i = (y * fb.w + x) * 4
                        r += Int(fb.px[i]); g += Int(fb.px[i + 1]); b += Int(fb.px[i + 2]); n += 1
                    }
                }
                r /= n; g /= n; b /= n
                let lum = Double(r + g + b) / 3.0
                var ch = ramp[min(ramp.count - 1, Int(lum / 255.0 * Double(ramp.count)))]
                if ch == " " {
                    if g > r + 40 && g > b + 40 { ch = "G" }
                    else if r > g + 50 && r > b + 20 { ch = "R" }
                    else if b > r + 40 { ch = "B" }
                    else if r > 120 && g > 100 && b < 90 { ch = "Y" }
                } else if lum > 150 && r > b + 60 { ch = "W" }
                line += String(ch)
            }
            out += line + "\n"
        }
        print(out, terminator: "")
    }

    /// Copy a view framebuffer into the composed screen framebuffer (mirrors what
    /// GameView does each frame, so the stress test can time the real pipeline).
    static func blend(_ src: Framebuffer, into dst: Framebuffer, atX ox: Int) {
        let w = min(src.w, dst.w - ox)
        let h = min(src.h, dst.h)
        guard w > 0, h > 0 else { return }
        for y in 0..<h {
            let srcRow = y * src.w * 4
            let dstRow = (y * dst.w + ox) * 4
            for x in 0..<w {
                let si = srcRow + x * 4, di = dstRow + x * 4
                dst.px[di] = src.px[si]
                dst.px[di + 1] = src.px[si + 1]
                dst.px[di + 2] = src.px[si + 2]
                dst.px[di + 3] = 255
            }
        }
    }

    static func writePPM(_ path: String, _ fb: Framebuffer) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(fb.w * fb.h * 3 + 64)
        func put(_ s: String) { bytes.append(contentsOf: Array(s.utf8)) }
        put("P6\n\(fb.w) \(fb.h)\n255\n")
        for i in stride(from: 0, to: fb.px.count, by: 4) {
            bytes.append(fb.px[i]); bytes.append(fb.px[i + 1]); bytes.append(fb.px[i + 2])
        }
        try? Data(bytes).write(to: URL(fileURLWithPath: path))
    }

    // MARK: - input / responder chain

    /// Sends real NSEvents through a real window so the whole chain is exercised:
    /// menu key equivalents first, then the first responder. This is what catches a
    /// bare-letter menu shortcut eating a movement key (a plain `q` on "Quit" used
    /// to kill the process instead of turning left) and a view that is not actually
    /// the first responder.
    static func runInputTest() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        GameView.cursorLockDisabled = true

        let view = GameView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        let win = NSWindow(contentRect: view.bounds,
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.contentView = view
        view.timer?.invalidate()          // the test drives updates itself
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
        AppDelegate.installMainMenu()

        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("   [\(ok ? "PASS" : "FAIL")] \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
            if !ok { failures += 1 }
        }

        check("view is the window's first responder", win.firstResponder === view,
              "responder=\(win.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")

        var terminatedEarly = false
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { _ in
            terminatedEarly = true
            print("   [FAIL] a bare key press terminated the app (menu shortcut)")
        }

        let game = view.game
        game.startNewGame()
        game.update(1.0 / 60.0)

        func event(_ type: NSEvent.EventType, _ kc: UInt16, _ chars: String) -> NSEvent? {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                             timestamp: 0, windowNumber: win.windowNumber, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars,
                             isARepeat: false, keyCode: kc)
        }
        // route through NSApplication, not NSWindow: only the app performs main-menu
        // key-equivalent matching, which is exactly the layer that swallowed keys
        func post(_ e: NSEvent?) { if let e { app.sendEvent(e) } }
        func tap(_ kc: UInt16, _ chars: String) {
            post(event(.keyDown, kc, chars))
            post(event(.keyUp, kc, chars))
        }

        // held keys, released immediately: the held value must be non-zero and the
        // release must clear it, proving keyDown/keyUp both arrive
        let held: [(UInt16, String, String, () -> Double)] = [
            (13, "w", "W", { game.input.forward }),
            (1, "s", "S", { game.input.forward }),
            (0, "a", "A", { game.input.strafe }),
            (2, "d", "D", { game.input.strafe }),
            (12, "q", "Q", { game.input.turn }),
            (14, "e", "E", { game.input.turn })
        ]
        for (kc, lower, upper, read) in held {
            game.input.forward = 0; game.input.strafe = 0; game.input.turn = 0
            post(event(.keyDown, kc, lower))
            let peak = read()
            post(event(.keyUp, kc, upper))
            let after = read()
            check("\(upper) reaches the game (no menu shortcut steals it)", peak != 0,
                  "held=\(Int(peak)) afterRelease=\(Int(after))")
            check("\(upper) releases cleanly", after == 0, "after=\(Int(after))")
        }

        do {
            let x0 = game.px, y0 = game.py
            game.input.forward = 1
            for _ in 0..<12 { game.update(1.0 / 60.0) }
            game.input.forward = 0
            let moved = hypot(game.px - x0, game.py - y0)
            check("W moves the player", moved > 0.3, "moved \(Int(moved * 100)) cm")
        }
        do {
            let x0 = game.px, y0 = game.py
            game.input.strafe = 1
            for _ in 0..<12 { game.update(1.0 / 60.0) }
            game.input.strafe = 0
            check("D strafes the player", hypot(game.px - x0, game.py - y0) > 0.3)
        }
        do {
            let a0 = game.pang
            game.input.turn = -1
            for _ in 0..<12 { game.update(1.0 / 60.0) }
            game.input.turn = 0
            check("Q turns left", game.pang < a0 - 0.1,
                  "dPang=\(String(format: "%.2f", game.pang - a0))")
        }
        do {
            game.input.fire = false; game.input.firePressed = false
            post(event(.keyDown, 49, " "))
            let fired = game.input.firePressed || game.input.fire
            post(event(.keyUp, 49, " "))
            check("SPACE fires", fired)
        }
        do {
            game.owned[4] = true
            tap(23, "5")
            game.update(1.0 / 60.0)
            check("key 5 selects the rocket launcher", game.weapon == 4, "weapon=\(game.weapon)")
        }
        do {
            let was = Sound.enabled
            tap(46, "m")
            check("M toggles mute in-game", Sound.enabled != was, "\(was) -> \(Sound.enabled)")
            tap(46, "m")
        }
        do {
            let was = game.showAutomap
            tap(48, "\t")
            check("TAB toggles the automap", game.showAutomap != was)
            tap(48, "\t")
        }
        do {
            game.paused = false
            tap(53, "\u{1b}")
            check("ESC pauses", game.paused)
            game.paused = false
        }
        do {
            let st = game.state, lvl = game.levelIndex
            tap(78, "n")
            game.update(1.0 / 60.0)
            check("bare `n` does not trigger the New Game item", game.state == st && game.levelIndex == lvl,
                  "state=\(game.state) level=\(game.levelIndex)")
        }
        // the menu layer, checked directly: NSApp only performs main-menu key
        // equivalents for a frontmost app, so the test asserts the rule itself
        do {
            var offenders: [String] = []
            func walk(_ menu: NSMenu?) {
                guard let menu else { return }
                for item in menu.items {
                    if !item.keyEquivalent.isEmpty, item.keyEquivalentModifierMask.isEmpty {
                        offenders.append("\(item.title) on bare '\(item.keyEquivalent)'")
                    }
                    if let sub = item.submenu { walk(sub) }
                }
            }
            walk(NSApp.mainMenu)
            check("no bare-letter menu shortcuts", offenders.isEmpty,
                  offenders.joined(separator: ", "))
        }
        do {
            let keys: [(UInt16, String)] = [(13, "w"), (1, "s"), (0, "a"), (2, "d"),
                                            (12, "q"), (14, "e"), (49, " "), (48, "\t"),
                                            (53, "\u{1b}"), (23, "5"), (46, "m")]
            let eaten = keys.compactMap { kc, chars -> String? in
                guard let d = event(.keyDown, kc, chars) else { return nil }
                return NSApp.mainMenu?.performKeyEquivalent(with: d) == true ? chars : nil
            }
            check("no gameplay key is claimed by the main menu", eaten.isEmpty,
                  "eaten=\(eaten)")
        }
        do {
            // structural, not performKeyEquivalent: actually firing \u{2318}Q would
            // quit the test process
            var quit: NSMenuItem?
            func find(_ menu: NSMenu?) {
                guard let menu else { return }
                for item in menu.items {
                    if item.title == "Quit Doomish" { quit = item }
                    find(item.submenu)
                }
            }
            find(NSApp.mainMenu)
            let item = quit
            check("Quit is bound to \u{2318}Q only (bare Q is turn-left)",
                  item?.keyEquivalent == "q" && item?.keyEquivalentModifierMask.contains(.command) == true,
                  "mask=\(String(describing: item?.keyEquivalentModifierMask.rawValue))")
        }
        do {
            GameView.cursorLockDisabled = false
            GameView.CursorLock.set(true)
            let locked = GameView.CursorLock.locked
            GameView.CursorLock.release()
            check("cursor lock has a working release path", locked && !GameView.CursorLock.locked)
            GameView.cursorLockDisabled = true
        }

        if terminatedEarly { failures += 1 }
        GameView.cursorLockDisabled = false
        print(failures == 0 ? "   == all input tests passed ==" : "   == \(failures) INPUT FAILURES ==")
        exit(failures == 0 ? 0 : 1)
    }
}
