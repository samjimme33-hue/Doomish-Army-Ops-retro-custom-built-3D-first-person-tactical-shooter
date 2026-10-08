import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// All 2D interface drawing: weapon view, HUD panels, overlays, automap.
/// Everything is laid out from `fb.w` / `fb.h` so the same code works at any
/// internal resolution.
enum Hud {

    // MARK: palette

    static let ink = (232, 236, 244)
    static let gold = (255, 208, 96)
    static let violet = (196, 150, 255)
    static let dim = (150, 158, 172)
    static let accent = (120, 226, 255)
    static let danger = (255, 88, 72)
    static let good = (126, 240, 150)
    static let ammo = (255, 214, 92)
    static let army = (196, 214, 130)
    static let panelBG = (20, 22, 30)
    static let panelEdge = (62, 70, 88)

    // MARK: first person weapon + muzzle flash

    /// Draw the whole in-game HUD for one player's view. Every panel is scoped to
    /// `p`, so split-screen just calls this once per viewport.
    static func drawForPlayer(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        fb.brighten(0.16 * p.muzzleFlash)
        drawWeapon(g, p, fb)
        drawPlayerTag(g, p, fb)
        if g.showAutomap {
            drawAutomap(g, fb)
        } else {
            drawTopInfo(g, p, fb)
            drawProgress(g, p, fb)
            drawExitCompass(g, p, fb)
            drawCrosshair(g, p, fb)
            drawMessage(g, fb)
            drawStatusBar(g, p, fb)
            drawPowerups(g, p, fb)
            drawCombo(g, p, fb)
            drawKillFeed(g, fb)
        }
        drawVignette(g, p, fb)
    }

    /// A strip under the top bar that always points at the exit, and shows how far
    /// off-screen it is. Without it the player has no way to know which way to
    /// hunt once the map is out of sight.
    static func drawExitCompass(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        guard let exit = g.exitPoint, !exit.x.isNaN else { return }
        let y = 22
        let cx = fb.w / 2
        let dx = exit.x - p.x, dy = exit.y - p.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist > 0.2 else { return }
        // bearing relative to where this player is looking
        var rel = atan2(dy, dx) - p.ang
        while rel > .pi { rel -= 2 * .pi }
        while rel < -.pi { rel -= 2 * .pi }

        let w = 74
        fb.fillRect(cx - w / 2, y, w, 10, 16, 18, 26)
        fb.outlineRect(cx - w / 2, y, w, 10, 58, 64, 82)
        fb.text("EXIT", cx - w / 2 + 3, y + 3, 150, 158, 172, scale: 1, shadow: false)
        let distStr = "\(Int(dist))M"
        fb.text(distStr, cx + w / 2 - 3 - distStr.count * 4, y + 3, 150, 158, 172, scale: 1, shadow: false)

        // an arrow that slides left/right with the bearing and clamps at the ends
        let norm = max(-1.0, min(1.0, rel / .pi))
        let arrowX = cx + Int(Double(w / 2 - 18) * norm)
        let a = max(0, p.color.0 + 40), b = max(0, p.color.1 + 40), c = max(0, p.color.2 + 40)
        for i in 0..<4 {
            fb.put(arrowX + i, y + 8 - i, a, b, c)
            fb.put(arrowX - i, y + 8 - i, a, b, c)
        }
        fb.put(arrowX, y + 5, 255, 255, 255)
        fb.put(arrowX, y + 4, a, b, c)
    }

    /// Timers for the two timed powerups, drawn above the status bar so they are
    /// always visible but never in the way of the weapon.
    static func drawPowerups(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        var y = fb.h - 66
        if p.berserk > 0 {
            powerChip(fb, x: 5, y: y, w: 58, label: "RAGE", frac: p.berserk / 15.0,
                      col: (255, 110, 60))
            y += 12
        }
        if p.invulnerable > 0 {
            powerChip(fb, x: 5, y: y, w: 58, label: "SHIELD", frac: p.invulnerable / 12.0,
                      col: (150, 200, 255))
        }
        // a combo counter, only once the streak is worth showing
        if p.streak >= 3 {
            let mult = String(format: "%.1fX", p.streakMultiplier)
            let txt = "\(p.streak) KILL STREAK"
            let w = txt.count * 4 + 8
            fb.fillRect(fb.w - w - 5, fb.h - 78, w, 11, 46, 30, 16)
            fb.outlineRect(fb.w - w - 5, fb.h - 78, w, 11, gold.0, gold.1, gold.2)
            fb.text(txt, fb.w - w - 1, fb.h - 75, gold.0, gold.1, gold.2, scale: 1, shadow: false)
            let mw = mult.count * 4 * 2 - 2
            fb.text(mult, fb.w - mw - 5, fb.h - 95, 255, 240, 190, scale: 2)
        }
    }

    private static func powerChip(_ fb: Framebuffer, x: Int, y: Int, w: Int,
                                   label: String, frac: Double, col: (Int, Int, Int)) {
        fb.fillRect(x, y, w, 11, 16, 18, 26)
        fb.outlineRect(x, y, w, 11, col.0, col.1, col.2)
        fb.text(label, x + 3, y + 3, col.0, col.1, col.2, scale: 1, shadow: false)
        meter(fb, x + 2, y + 8, w - 4, 2, frac, col)
    }

    /// Big centred combo flash when the streak crosses a threshold.
    static func drawCombo(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        guard p.streak >= 3, p.streakTimer > 5.4 else { return }
        if Int(g.time * 3) % 2 == 0 {
            fb.textCentered("\(p.streak) STREAK", fb.h / 2 - 52, 255, 220, 120, scale: 2)
        }
    }

    /// Names the split-screen slot in the corner of each view.
    static func drawPlayerTag(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        if g.playerCount < 2 { return }
        let w = p.name.count * 4 + 8
        fb.fillRect(4, 20, w, 11, 16, 18, 24)
        fb.outlineRect(4, 20, w, 11, p.color.0, p.color.1, p.color.2)
        fb.text(p.name, 8, 23, p.color.0, p.color.1, p.color.2, scale: 1, shadow: false)
        if p.down {
            let dw = 74
            fb.fillRect(fb.w - dw - 4, 20, dw, 11, 40, 14, 14)
            fb.outlineRect(fb.w - dw - 4, 20, dw, 11, 220, 80, 70)
            let secs = max(0, Int(p.respawnTimer.rounded(.up)))
            fb.text("REDEPLOY \(secs)", fb.w - dw, 23, 255, 150, 140, scale: 1, shadow: false)
        }
    }

    static func drawWeapon(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        guard p.weapon >= 0 && p.weapon < TexLib.weaponViews.count else { return }
        let def = g.weapons[p.weapon]
        let tex = TexLib.weaponViews[p.weapon]
        let destW = Int(Double(fb.w) * (0.24 + 0.035 * Double(p.weapon)))
        let destH = max(1, destW * tex.h / tex.w)
        let bobX = Int(sin(p.bobPhase) * 5.0 * def.bobAmount)
        let bobY = Int(abs(sin(p.bobPhase * 0.5)) * 5.0 * def.bobAmount)
        let kickX = Int(p.kick * 9.0), kickY = Int(p.kick * 12.0)
        let ox = (fb.w - destW) / 2 + bobX + kickX
        let oy = fb.h - destH - 54 + bobY + kickY
        var bright = 1.0 + 0.22 * p.muzzleFlash
        if p.painTimer > 0 { bright *= 0.8 }
        blit(tex, to: fb, x: ox, y: oy, destW: destW, destH: destH, brightness: bright, alphaCut: 24)

        // muzzle flash
        if p.muzzleFlash > 0.02 {
            let a = p.muzzleFlash
            let anchor: (Double, Double)
            switch p.weapon {
            case 0: anchor = (0.34, 0.14)
            case 1: anchor = (0.10, 0.18)
            case 2: anchor = (0.68, 0.14)
            case 3: anchor = (0.06, 0.16)
            default: anchor = (0.05, 0.20)
            }
            let fxd = Double(ox) + Double(destW) * anchor.0
            let fyd = Double(oy) + Double(destH) * anchor.1
            let rad = (6.0 + 18.0 * a) * (0.8 + 0.4 * sin(g.time * 90.0))
            let hot = a > 0.5
            let r0 = 255
            let g0 = hot ? 255 : 190
            let b0 = hot ? 210 : 60
            for i in 0..<7 {
                let ang = Double(i) / 7.0 * 2 * .pi + g.time * 20.0
                let len = rad * (0.5 + 0.5 * abs(sin(ang * 3.0 + g.time * 40.0)))
                line(fb, Int(fxd), Int(fyd),
                     Int(fxd + cos(ang) * len), Int(fyd + sin(ang) * len),
                     r0, g0, b0, hot)
            }
            let rMin = Int(fxd - rad / 2.0), rMax = Int(fxd + rad / 2.0)
            let yMin = Int(fyd - rad / 2.0), yMax = Int(fyd + rad / 2.0)
            let limit = rad * rad * 0.4
            for yy in yMin...yMax {
                for xx in rMin...rMax {
                    let dx = Double(xx) - fxd
                    let dy = Double(yy) - fyd
                    if dx * dx + dy * dy < limit {
                        if hot { fb.put(xx, yy, 255, 250, 220) } else { fb.put(xx, yy, 255, 200, 90) }
                    }
                }
            }
        }
    }

    static func blit(_ tex: Tex, to fb: Framebuffer, x: Int, y: Int, destW: Int, destH: Int,
                     brightness: Double, alphaCut: Int) {
        guard destW > 0, destH > 0 else { return }
        for dy in 0..<destH {
            let sy = dy * tex.h / destH
            for dx in 0..<destW {
                let sx = dx * tex.w / destW
                let i = (sy * tex.w + sx) * 4
                if Int(tex.px[i + 3]) < alphaCut { continue }
                fb.put(x + dx, y + dy,
                       Int(Double(tex.px[i]) * brightness),
                       Int(Double(tex.px[i + 1]) * brightness),
                       Int(Double(tex.px[i + 2]) * brightness))
            }
        }
    }

    static func line(_ fb: Framebuffer, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int,
                     _ r: Int, _ g: Int, _ b: Int, _ bright: Bool) {
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        var x = x0, y = y0
        var guard_ = 0
        while true {
            if bright { fb.put(x, y, min(255, r + 40), min(255, g + 40), min(255, b + 30)) }
            else { fb.put(x, y, r, g, b) }
            if (x == x1 && y == y1) || guard_ > 4096 { break }
            guard_ += 1
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    // MARK: primitives

    static func panel(_ fb: Framebuffer, _ x: Int, _ y: Int, _ w: Int, _ h: Int,
                      edge: (Int, Int, Int) = panelEdge) {
        fb.fillRect(x, y, w, h, panelBG.0, panelBG.1, panelBG.2)
        fb.outlineRect(x, y, w, h, edge.0, edge.1, edge.2)
    }

    /// Horizontal meter used for health / armor.
    static func meter(_ fb: Framebuffer, _ x: Int, _ y: Int, _ w: Int, _ h: Int,
                      _ frac: Double, _ col: (Int, Int, Int)) {
        fb.fillRect(x, y, w, h, 34, 36, 46)
        let fill = max(0, min(1, frac))
        let fw = Int(Double(w - 2) * fill)
        if fw > 0 { fb.fillRect(x + 1, y + 1, fw, h - 2, col.0, col.1, col.2) }
    }

    // MARK: crosshair + hit marker

    static func drawCrosshair(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        let cx = fb.w / 2, cy = fb.h / 2
        let w = g.weapons[p.weapon]
        let gap = 3 + Int(p.recoil * 5.0) + Int(w.spread * 40.0)
        let len = 4
        let col: (Int, Int, Int) = p.ammo[w.ammoType] > 0 ? (170, 255, 190) : (255, 120, 90)
        for i in 0..<len {
            fb.put(cx + gap + i, cy, col.0, col.1, col.2)
            fb.put(cx - gap - i, cy, col.0, col.1, col.2)
            fb.put(cx, cy + gap + i, col.0, col.1, col.2)
            fb.put(cx, cy - gap - i, col.0, col.1, col.2)
        }
        fb.put(cx, cy, 230, 255, 240)

        // hit marker: brief red ticks when a shot connects
        if p.hitMarker > 0.05 {
            let a = Int(255 * min(1, p.hitMarker * 2))
            for i in 0..<5 {
                let o = 4 + i
                fb.put(cx + o, cy + o, a, 60, 50)
                fb.put(cx - o, cy - o, a, 60, 50)
                fb.put(cx + o, cy - o, a, 60, 50)
                fb.put(cx - o, cy + o, a, 60, 50)
            }
        }
    }

    // MARK: top strip

    static func drawTopInfo(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        let h = 16
        fb.fillRect(0, 0, fb.w, h, 14, 16, 22)
        fb.fillRect(0, h - 1, fb.w, 1, 54, 62, 78)
        let mm = Int(g.time) / 60, ss = Int(g.time) % 60
        let timeStr = String(format: "%d:%02d", mm, ss)
        let timeX = fb.w - 5 - timeStr.count * 4

        fb.text("\(g.level.name)", 5, 4, accent.0, accent.1, accent.2, scale: 1)
        // difficulty and secrets, immediately after the level name
        var x = 5 + g.level.name.count * 4 + 6
        let diff = g.difficulty.name
        fb.text(diff, x, 4, dim.0, dim.1, dim.2, scale: 1)
        x += diff.count * 4 + 6
        if g.secretsTotal > 0 {
            let s = "SEC \(g.levelSecrets)/\(g.secretsTotal)"
            let found = g.levelSecrets > 0
            fb.text(s, x, 4, found ? gold.0 : dim.0, found ? gold.1 : dim.1,
                    found ? gold.2 : dim.2, scale: 1)
            x += s.count * 4 + 6
        }
        // kill count lives here rather than in a status-bar panel: with nine
        // weapons the arms rack needs every pixel it can get
        fb.text("KILLS \(p.kills)", x, 4, 200, 150, 140, scale: 1)
        // each view shows that player's own score, not the squad total
        fb.textCenteredX("SCORE \(p.score)", aroundX: fb.w / 2, 4, ink.0, ink.1, ink.2, scale: 1)
        // how many are still standing: the "is it clear yet" question
        let standing = g.enemies.reduce(0) { $0 + ($1.dead ? 0 : 1) }
        if standing > 0 {
            let s = "HOSTILES \(standing)"
            fb.text(s, timeX - s.count * 4 - 8, 4, 200, 120, 110, scale: 1)
        }
        fb.text(timeStr, timeX, 4, dim.0, dim.1, dim.2, scale: 1)
        drawProgress(g, p, fb)
        drawVehiclePanel(g, p, fb)
    }

    /// Vehicle read-out. Only drawn while this player is mounted, so the normal
    /// on-foot HUD is never cluttered.
    static func drawVehiclePanel(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        guard let v = p.rides, !v.dead else { return }
        let y = 20
        let pw = min(fb.w - 8, 190)
        let ph = 34
        fb.fillRect(4, y, pw, ph, 12, 16, 14)
        fb.outlineRect(4, y, pw, ph, 70, 90, 60)

        fb.text(v.statusName, 8, y + 3, army.0, army.1, army.2, scale: 1)
        let cls = v.def.cls.display
        fb.text(cls, 8, y + 12, dim.0, dim.1, dim.2, scale: 1)

        // hull integrity bar
        let bw = pw - 12
        fb.fillRect(8, y + 22, bw, 5, 40, 24, 20)
        let frac = v.hpFraction
        let fw = Int(Double(bw) * frac)
        let (hr, hg, hb): (Int, Int, Int) = frac > 0.6 ? (126, 200, 110) : (frac > 0.3 ? (230, 190, 80) : (230, 80, 60))
        if fw > 0 { fb.fillRect(8, y + 22, fw, 5, hr, hg, hb) }
        fb.text("\(Int(v.hp))", 8, y + 22, 12, 14, 12, scale: 1)

        // speed and the mounted gun
        let kmh = Int(abs(v.speed) * 3.6)
        let speedStr = "\(kmh) KM/H"
        fb.text(speedStr, pw + 8 - speedStr.count * 4, y + 3, ink.0, ink.1, ink.2, scale: 1)
        // the gunner seat wields the secondary weapon, the driver's the main gun
        let gun = (p.rides?.gunner == p.index ? v.def.secondary?.name : v.def.gun.name) ?? v.def.gun.name
        fb.text(gun, 8, y + 28, 190, 200, 140, scale: 1)
    }

    /// Thin level-progress bar under the top strip.
    static func drawProgress(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        let y = 16
        fb.fillRect(0, y, fb.w, 3, 26, 28, 36)
        let total = max(1, g.totalEnemies)
        let frac = Double(p.kills) / Double(total)
        let fw = Int(Double(fb.w) * min(1, frac))
        if fw > 0 { fb.fillRect(0, y, fw, 3, 220, 90, 70) }
        if g.totalEnemies > 0 {
            fb.text("\(p.kills)/\(g.totalEnemies)", 5, y + 5, 200, 130, 110, scale: 1)
        }
    }

    // MARK: bottom status bar

    static func drawStatusBar(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        let barH = 52
        let y0 = fb.h - barH
        fb.fillRect(0, y0, fb.w, barH, 14, 15, 21)
        // the player's accent colour ties each panel to its view
        fb.fillRect(0, y0, fb.w, 1, p.color.0, p.color.1, p.color.2)

        let pad = 5
        // split-screen views are a third of the width, so the panels shrink to
        // fit rather than overflowing the view
        let compact = fb.w < 300
        // The arms rack needs a legible slot per weapon. With nine weapons in the
        // rack the stat panels give up width (and the kill counter moves to the
        // top strip) so every slot can still hold its name and a number.
        let wideRack = g.weapons.count >= 8 && !compact
        let hpW = compact ? 52 : (wideRack ? 66 : 88)
        let arW = compact ? 52 : (wideRack ? 66 : 88)
        let amW = compact ? 44 : (wideRack ? 62 : 80)
        let panelH = compact ? 34 : 40
        let valScale = compact ? 1 : 2
        let hpX = pad
        let arX = hpX + hpW + 5
        let amX = arX + arW + 5
        let barX = amX + amW + 6
        let killsW = compact ? 0 : (wideRack ? 0 : 44)
        let barW = max(40, fb.w - barX - killsW - 8)

        // health can exceed 100 with a megahealth pickup, so the meter is scaled
        // against 200 and the panel turns gold once the player is over-healed
        let overHealed = p.health > 100
        let hpCol: (Int, Int, Int) = p.health < 30 ? danger : (overHealed ? gold : good)
        statPanel(fb, x: hpX, y: y0 + 8, w: hpW, h: panelH, label: "HEALTH",
                  value: "\(Int(p.health))",
                  col: hpCol, frac: p.health / 200.0, scale: valScale)
        statPanel(fb, x: arX, y: y0 + 8, w: arW, h: panelH, label: "ARMOR",
                  value: "\(Int(p.armor))",
                  col: p.armor > 0 ? (120, 180, 255) : dim, frac: p.armor / 100.0, scale: valScale)

        // ammo
        let at = g.weapons[p.weapon].ammoType
        let have = p.ammo[at]
        statPanel(fb, x: amX, y: y0 + 8, w: amW, h: panelH, label: compact ? "" : g.ammoLabel(for: at),
                  value: "\(have)",
                  col: have > 0 ? ammo : danger,
                  frac: Double(have) / Double(max(1, g.maxAmmo[at])), scale: valScale)

        drawHotbar(g, p, fb, x: barX, y: y0 + 8, w: barW, h: panelH)

        // kills
        if killsW > 0 {
            let kx = fb.w - killsW - 4
            panel(fb, kx, y0 + 6, killsW, barH - 12, edge: (86, 52, 52))
            fb.text("KILLS", kx + 4, y0 + 10, 200, 140, 130, scale: 1, shadow: false)
            fb.textCenteredX("\(p.kills)", aroundX: kx + killsW / 2, y0 + 20,
                             255, 170, 150, scale: 2)
        }
    }

    /// Colour used to key a weapon to its ammo type (status panel, hotbar pips).
    static func ammoTint(_ ammoType: Int) -> (Int, Int, Int) {
        switch ammoType {
        case 1: return (230, 140, 90)     // shells
        case 2: return (120, 170, 255)    // cells
        case 3: return (255, 130, 70)     // rockets
        default: return (220, 200, 110)   // bullets
        }
    }

    private static func statPanel(_ fb: Framebuffer, x: Int, y: Int, w: Int, h: Int,
                                  label: String, value: String, col: (Int, Int, Int),
                                  frac: Double, scale: Int) {
        panel(fb, x, y, w, h)
        if !label.isEmpty {
            fb.text(label, x + 4, y + 4, dim.0, dim.1, dim.2, scale: 1, shadow: false)
        }
        let vw = value.count * 4 * scale - scale
        fb.text(value, x + w - 4 - vw, y + (h - 5 * scale) / 2 + 1, col.0, col.1, col.2, scale: scale)
        meter(fb, x + 4, y + h - 7, w - 8, 5, frac, col)
    }

    /// Five-slot arms rack; the equipped weapon is highlighted.
    private static func drawHotbar(_ g: Game, _ p: Player, _ fb: Framebuffer,
                                   x: Int, y: Int, w: Int, h: Int) {
        let count = g.weapons.count
        guard count > 0, w > 12 else { return }
        let gap = 3
        let slotW = max(8, (w - gap * (count - 1)) / count)
        let slotH = h
        // below ~20px a slot cannot hold a label and a number legibly
        let labelled = slotW >= 20
        let letters = Game.weaponTags
        // nine slots in a 480-wide bar is tight; below this the labels no longer
        // fit, so drop to numbers + a colour-coded pip instead of overlapping text
        let cramped = slotW < 22
        for i in 0..<count {
            let sx = x + i * (slotW + gap)
            let has = i < p.owned.count && p.owned[i]
            let active = i == p.weapon
            if active {
                fb.fillRect(sx, y, slotW, slotH, 46, 60, 44)
                fb.outlineRect(sx, y, slotW, slotH, p.color.0, p.color.1, p.color.2)
            } else if has {
                fb.fillRect(sx, y, slotW, slotH, 26, 28, 38)
                fb.outlineRect(sx, y, slotW, slotH, 78, 86, 104)
            } else {
                fb.fillRect(sx, y, slotW, slotH, 18, 19, 25)
                fb.outlineRect(sx, y, slotW, slotH, 44, 48, 60)
            }
            if labelled {
                // slot number
                fb.text("\(i + 1)", sx + 2, y + 3, dim.0, dim.1, dim.2, scale: 1, shadow: false)
            }
            if has {
                if labelled && !cramped {
                    let name: String = i < letters.count ? letters[i] : "???"
                    fb.text(name, sx + 2, y + 14, active ? ink.0 : dim.0,
                            active ? ink.1 : dim.1, active ? ink.2 : dim.2, scale: 1, shadow: false)
                } else if cramped {
                    // a coloured pip band keyed to the ammo type
                    let tint = Hud.ammoTint(g.weapons[i].ammoType)
                    fb.fillRect(sx + 2, y + 13, slotW - 4, 3, tint.0, tint.1, tint.2)
                }
                let wdef = g.weapons[i]
                if wdef.ammoType != 0 {
                    if labelled {
                        let n = "\(p.ammo[wdef.ammoType])"
                        fb.text(n, sx + 2, y + 26, ammo.0, ammo.1, ammo.2, scale: 1, shadow: false)
                    }
                } else if labelled {
                    meter(fb, sx + 3, y + 30, slotW - 6, 4,
                          Double(p.ammo[0]) / Double(max(1, g.maxAmmo[0])), (200, 180, 90))
                } else {
                    // tiny slot: a filled pip bar is all that fits
                    meter(fb, sx + 1, y + slotH - 5, slotW - 2, 4,
                          Double(p.ammo[0]) / Double(max(1, g.maxAmmo[0])), (200, 180, 90))
                }
            } else if labelled {
                fb.text("LOCK", sx + 2, y + 14, 60, 64, 78, scale: 1, shadow: false)
            }
        }
    }

    // MARK: messages, kill feed, combo

    static func drawMessage(_ g: Game, _ fb: Framebuffer) {
        guard g.messageTimer > 0, !g.message.isEmpty else { return }
        let blink = g.messageTimer < 1.0 && Int(g.messageTimer * 8) % 2 == 0
        if blink { return }
        let w = g.message.count * 4 + 8
        fb.fillRect((fb.w - w) / 2, fb.h - 78, w, 12, 20, 20, 26)
        fb.textCentered(g.message, fb.h - 75, 255, 214, 96, scale: 1)
    }

    static func drawKillFeed(_ g: Game, _ fb: Framebuffer) {
        var y = 24
        if g.playerCount > 1 { y += 13 }   // clear the player tag
        for entry in g.killFeed.reversed() {
            let fade = min(1.0, entry.timer)
            let col = entry.text.contains("HEAVY") || entry.text.contains("SOLDIER")
                ? army : (200, 200, 210)
            let c = Int(Double(col.0) * fade), cc = Int(Double(col.1) * fade), d = Int(Double(col.2) * fade)
            // clip to the view: in a three-way split a long entry would run into
            // the next viewport
            let maxChars = max(4, (fb.w - 8) / 4)
            let text = entry.text.count > maxChars ? String(entry.text.prefix(maxChars)) : entry.text
            fb.text(text, fb.w - 6 - text.count * 4, y, c, cc, d, scale: 1)
            y += 9
        }
    }

    // MARK: vignette + screen effects

    static func drawVignette(_ g: Game, _ p: Player, _ fb: Framebuffer) {
        // corner darkening: only the border strips are touched
        let band = max(12, fb.h / 7)
        let w = fb.w, h = fb.h
        func shade(_ x: Int, _ y: Int) {
            let i = (y * w + x) * 4
            let edge = min(min(x, w - 1 - x), min(y, h - 1 - y))
            let f = 1.0 - 0.42 * (1.0 - Double(edge) / Double(band))
            fb.px[i] = UInt8(clamping: Int(Double(fb.px[i]) * f))
            fb.px[i + 1] = UInt8(clamping: Int(Double(fb.px[i + 1]) * f))
            fb.px[i + 2] = UInt8(clamping: Int(Double(fb.px[i + 2]) * f))
        }
        for y in 0..<min(band, h) {
            for x in 0..<min(band, w) { shade(x, y) }                       // top-left
            for x in max(0, w - band)..<w { shade(x, y) }                    // top-right
        }
        for y in max(0, h - band)..<h {
            for x in 0..<min(band, w) { shade(x, y) }                       // bottom-left
            for x in max(0, w - band)..<w { shade(x, y) }                    // bottom-right
        }
        // low-health pulse
        if p.health < 35 {
            let pulse = (1.0 - p.health / 35.0) * (0.10 + 0.08 * sin(g.time * 5.0))
            fb.tint(150, 10, 6, max(0, pulse))
        }
        fb.tint(120, 255, 150, 0.14 * p.pickupFlash)
        fb.tint(255, 20, 10, 0.40 * p.damageFlash)
        // a downed view dims so it is obvious which slot is waiting to redeploy
        if p.down { fb.tint(0, 0, 0, 0.5) }
    }

    // MARK: automap

    static func drawAutomap(_ g: Game, _ fb: Framebuffer) {
        let lv = g.level
        let cell = max(2, min((fb.w - 24) / lv.w, (fb.h - 56) / lv.h))
        let mapW = lv.w * cell, mapH = lv.h * cell
        let ox = (fb.w - mapW) / 2, oy = (fb.h - mapH) / 2

        fb.tint(0, 0, 0, 0.55)
        for y in 0..<lv.h {
            for x in 0..<lv.w {
                let c = lv.at(x, y)
                let px0 = ox + x * cell, py0 = oy + y * cell
                if c == Tile.floor {
                    fb.fillRect(px0, py0, cell, cell, 40, 44, 58)
                } else if c == Tile.door {
                    let p = lv.doorProgress[y * lv.w + x]
                    fb.fillRect(px0, py0, cell, cell, Int(200 - 120 * p), Int(180 - 100 * p), 40)
                } else if c == Tile.exit {
                    let blink = Int(g.time * 5) % 2 == 0
                    fb.fillRect(px0, py0, cell, cell, blink ? 255 : 120, blink ? 60 : 20, blink ? 30 : 12)
                } else if c == Tile.secret {
                    // an unopened secret reads as a wall, but with a faint seam
                    fb.fillRect(px0, py0, cell, cell, 104, 100, 94)
                } else {
                    fb.fillRect(px0, py0, cell, cell, 118, 118, 128)
                }
            }
        }
        for p in g.pickups where !p.taken {
            fb.fillRect(ox + Int(p.x * Double(cell)) - 1, oy + Int(p.y * Double(cell)) - 1, 2, 2, 120, 220, 255)
        }
        for b in g.barrels where !b.gone {
            fb.fillRect(ox + Int(b.x * Double(cell)) - 1, oy + Int(b.y * Double(cell)) - 1, 3, 3, 255, 140, 40)
        }
        for e in g.enemies where !e.dead {
            let ex = ox + Int(e.x * Double(cell)), ey = oy + Int(e.y * Double(cell))
            // demons red, infantry olive, and the two specialists the player most
            // needs to notice get their own colours
            let col: (Int, Int, Int)
            switch e.type {
            case EnemyType.marksman: col = (255, 200, 90)
            case EnemyType.grenadier: col = (200, 150, 255)
            case EnemyType.rioter: col = (120, 190, 235)
            default: col = e.isArmy ? army : (230, 40, 40)
            }
            fb.fillRect(ex - 1, ey - 1, 3, 3, col.0, col.1, col.2)
        }
        // secrets that have been opened show on the map
        for (i, s) in lv.secrets.enumerated() {
            guard lv.secretFound.indices.contains(i), lv.secretFound[i] else { continue }
            let px0 = ox + s.x0 * cell, py0 = oy + s.y0 * cell
            fb.outlineRect(px0, py0, s.w * cell, s.h * cell, gold.0, gold.1, gold.2)
        }
        for p in g.pickups where !p.taken && p.kind.isPowerup {
            fb.fillRect(ox + Int(p.x * Double(cell)) - 1, oy + Int(p.y * Double(cell)) - 1,
                        3, 3, gold.0, gold.1, gold.2)
        }
        fb.text("TACTICAL MAP", ox + 2, oy - 10, 190, 200, 215, scale: 1)
        fb.textCentered("MAP - TAB TO CLOSE", fb.h - 12, 200, 200, 210, scale: 1)

        // one arrow per squad member, each in their own colour
        for p in g.players {
            let pxx = ox + Int(p.x * Double(cell)), pyy = oy + Int(p.y * Double(cell))
            if p.down {
                fb.outlineRect(pxx - 2, pyy - 2, 5, 5, 220, 80, 70)
                continue
            }
            let rr = g.playerCount > 1 ? 7.0 : 6.0
            for i in 0..<12 {
                let t = Double(i) / 12.0
                let ang = p.ang - 0.55 + t * 1.1
                let r = rr * sin(Double(i) / 12.0 * .pi)
                fb.put(pxx + Int(cos(ang) * r), pyy + Int(sin(ang) * r), p.color.0, p.color.1, p.color.2)
            }
            fb.fillRect(pxx - 1, pyy - 1, 3, 3, min(255, p.color.0 + 60),
                        min(255, p.color.1 + 15), min(255, p.color.2 + 60))
        }
    }

    // MARK: title / end screens

    static func drawTitle(_ g: Game, _ fb: Framebuffer) {
        fb.clear(8, 8, 14)
        for y in 0..<fb.h {
            let t = Double(y) / Double(fb.h)
            let c = Int(10 + 66 * (1 - t))
            fb.fillRect(0, y, fb.w, 1, c, Int(Double(c) * 0.35), Int(Double(c) * 0.3))
        }
        for i in 0..<6 {
            fb.fillRect(0, Int(Double(i) * Double(fb.h) / 6), fb.w, 2, 120, 20, 20)
        }
        let scale = max(4, fb.h / 30)
        // Explicit vertical budget rather than stacked offsets: the title, the two
        // selector rows and the deploy prompt all have to fit a 300px frame
        // without colliding, so each block gets a fixed band.
        let titleY = 14
        let subY = titleY + scale * 6
        let taglineY = subY + 14
        let controlsY = taglineY + 14
        let coOpY = controlsY + 5 * 12
        let playersLabelY = coOpY + 26
        let playersY = playersLabelY + 10
        let diffY = difficultyRowTop(fbH: fb.h)
        let deployY = diffY + 22

        fb.textCentered("DOOMISH", titleY, 214, 34, 26, scale: scale)
        fb.textCentered("ARMY OPS", subY, 120, 226, 255, scale: 2)
        fb.textCentered("FAST DEMONS. BIG GUNS. NO MERCY.", taglineY, 150, 150, 165, scale: 1)
        // controls in two columns: a single column of ten lines pushed the
        // selectors off the bottom of the frame
        let leftCol = [
            "MOVE   W A S D  /  ARROWS",
            "TURN   Q E  OR DRAG MOUSE",
            "FIRE   LEFT MOUSE BUTTON",
            "ARMS   1-9  OR SCROLL",
            "RUN    SHIFT",
        ]
        let rightCol = [
            "MAP    TAB",
            "MUTE   M",
            "PAUSE  ESC",
            "RESTART  R",
            "DRIVE  F   (NEAR A WRECK)",
        ]
        let colW = (fb.w - 24) / 2
        for (i, l) in leftCol.enumerated() {
            fb.text(l, 12, controlsY + i * 12, 200, 205, 215, scale: 1)
        }
        for (i, l) in rightCol.enumerated() {
            fb.text(l, 12 + colW, controlsY + i * 12, 200, 205, 215, scale: 1)
        }
        fb.textCentered("CO-OP: USE THE PLAYERS MENU, OR CLICK BELOW", coOpY, 170, 176, 190, scale: 1)
        fb.textCentered("P2  ARROWS MOVE  . FIRE  , ARMS  R-SHIFT RUN   P3  IJKL MOVE  P FIRE  / ARMS",
                        coOpY + 12, 150, 156, 170, scale: 1)

        // difficulty selector, same click model as the player-count row below
        // player-count selector on the title screen
        let bw = 78, gap = 8
        let totalW = bw * maxLocalPlayers + gap * (maxLocalPlayers - 1)
        var bx = (fb.w - totalW) / 2
        let by = playersY
        fb.textCenteredX("PLAYERS", aroundX: (fb.w - totalW) / 2, playersLabelY,
                         150, 156, 170, scale: 1)
        for n in 1...maxLocalPlayers {
            let active = g.playerCount == n
            if active {
                fb.fillRect(bx, by, bw, 16, 40, 58, 40)
                fb.outlineRect(bx, by, bw, 16, good.0, good.1, good.2)
            } else {
                fb.fillRect(bx, by, bw, 16, 20, 22, 30)
                fb.outlineRect(bx, by, bw, 16, 60, 68, 84)
            }
            let label = "\(n)P"
            let col = active ? good.0 : dim.0
            let cc = active ? good.1 : dim.1
            let d = active ? good.2 : dim.2
            fb.textCenteredX(label, aroundX: bx + bw / 2, by + 5, col, cc, d, scale: 1)
            if active {
                // a small pip row showing the current squad size
                for i in 0..<n {
                    let p = g.players[min(i, g.players.count - 1)]
                    fb.fillRect(bx + bw - 6 - i * 5, by + 2, 3, 3, p.color.0, p.color.1, p.color.2)
                }
            }
            bx += bw + gap
        }
        if Int(g.time * 2) % 2 == 0 {
            fb.textCentered("CLICK OR PRESS SPACE TO DEPLOY", deployY, 255, 220, 90, scale: 2)
        }
    }

    /// Three difficulty buttons. The highlighted one is what the next run uses;
    /// `Game.difficulty` is a global so this reads the same on every view.
    /// `y` is the button row's top edge, and the blurb is drawn 10px above it.
    static func drawDifficultyPicker(_ g: Game, _ fb: Framebuffer, y: Int) {
        let cases = Difficulty.allCases
        let bw = 92, gap = 8
        let totalW = bw * cases.count + gap * (cases.count - 1)
        var bx = (fb.w - totalW) / 2
        for d in cases {
            let active = g.difficulty == d
            if active {
                fb.fillRect(bx, y, bw, 15, 40, 58, 40)
                fb.outlineRect(bx, y, bw, 15, good.0, good.1, good.2)
            } else {
                fb.fillRect(bx, y, bw, 15, 20, 22, 30)
                fb.outlineRect(bx, y, bw, 15, 60, 68, 84)
            }
            let col = active ? good.0 : dim.0
            let cc = active ? good.1 : dim.1
            let b = active ? good.2 : dim.2
            fb.textCenteredX(d.name, aroundX: bx + bw / 2, y + 5, col, cc, b, scale: 1)
            bx += bw + gap
        }
        fb.textCenteredX("DIFFICULTY", aroundX: (fb.w - totalW) / 2, y - 20, 150, 156, 170, scale: 1)
        fb.textCentered(g.difficulty.blurb, y - 10, 255, 200, 110, scale: 1)
    }

    /// Which difficulty button contains a point, if any. The row sits directly
    /// under the blurb, at the same offsets `drawTitle` lays out.
    static func difficultyAt(x: Int, y: Int, fbW: Int, fbH: Int) -> Difficulty? {
        let cases = Difficulty.allCases
        let bw = 92, gap = 8
        let totalW = bw * cases.count + gap * (cases.count - 1)
        var bx = (fbW - totalW) / 2
        let by = difficultyRowTop(fbH: fbH)
        for d in cases {
            if x >= bx && x < bx + bw && y >= by && y < by + 15 { return d }
            bx += bw + gap
        }
        return nil
    }

    /// Top edge of the difficulty button row for a frame of this height. Shared
    /// by the drawing code and the click hit-test so the two cannot drift apart.
    static func difficultyRowTop(fbH: Int) -> Int {
        let scale = max(4, fbH / 30)
        let taglineY = 14 + scale * 6 + 14
        let controlsY = taglineY + 14
        let coOpY = controlsY + 5 * 12
        let playersY = coOpY + 36
        return playersY + 20 + 10
    }

    static func drawOverlays(_ g: Game, _ fb: Framebuffer) {
        switch g.state {
        case .start:
            drawTitle(g, fb)
        case .dead:
            fb.tint(150, 0, 0, 0.45)
            fb.textCentered("YOU DIED", fb.h / 2 - 24, 255, 60, 50, scale: 5)
            if Int(g.time * 2) % 2 == 0 {
                fb.textCentered("PRESS FIRE OR R TO TRY AGAIN", fb.h / 2 + 20, 240, 220, 200, scale: 1)
            }
        case .levelDone:
            fb.textCentered("EXIT REACHED", fb.h / 2 - 30, 120, 255, 140, scale: 4)
            fb.textCentered("ENTERING LEVEL \(g.levelIndex + 1)", fb.h / 2 + 8, 240, 240, 240, scale: 1)
        case .victory:
            fb.tint(0, 0, 0, 0.5)
            fb.textCentered("CAMPAIGN COMPLETE", fb.h / 2 - 48, 255, 210, 70, scale: 4)
            drawVictoryStats(g, fb)
            if Int(g.time * 2) % 2 == 0 {
                fb.textCentered("PRESS FIRE TO PLAY AGAIN", fb.h / 2 + 58, 255, 200, 100, scale: 1)
            }
        case .playing:
            if g.paused { drawPause(g, fb) }
        }
    }

    private static func drawPause(_ g: Game, _ fb: Framebuffer) {
        fb.tint(0, 0, 0, 0.55)
        fb.textCentered("PAUSED", fb.h / 2 - 40, 230, 235, 245, scale: 5)
        // live run stats, so pausing is also where you check the numbers
        var stats: [String] = []
        stats.append("DIFFICULTY  \(g.difficulty.name)")
        if let acc = g.accuracy {
            stats.append(String(format: "ACCURACY  %d%%  (%d/%d SHOTS)",
                                Int(acc * 100), g.levelHits, g.levelShots))
        } else {
            stats.append("ACCURACY  NO SHOTS FIRED")
        }
        if g.secretsTotal > 0 {
            stats.append("SECRETS  \(g.secretsFound) OF \(g.secretsTotal) THIS RUN")
        }
        var y = fb.h / 2 - 6
        for s in stats {
            fb.textCentered(s, y, gold.0, gold.1, gold.2, scale: 1)
            y += 11
        }
        y += 6
        let lines = [
            "ESC  RESUME",
            "TAB  TACTICAL MAP",
            "M    \(Sound.enabled ? "SOUND ON" : "SOUND OFF")",
            "R    RESTART LEVEL",
            "CMD-Q  QUIT"
        ]
        for l in lines {
            fb.textCentered(l, y, 190, 196, 210, scale: 1)
            y += 13
        }
    }

    /// Campaign summary, shown on the victory screen.
    static func drawVictoryStats(_ g: Game, _ fb: Framebuffer) {
        let lines: [String] = [
            "TOTAL KILLS \(g.totalKills)",
            "TOTAL SCORE \(g.totalScore)",
            "DIFFICULTY \(g.difficulty.name)",
            "SECRETS \(g.secretsFound)",
        ]
        var y = fb.h / 2 + 6
        for l in lines {
            fb.textCentered(l, y, 240, 240, 240, scale: 1)
            y += 11
        }
    }
}
