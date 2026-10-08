import Foundation

final class Framebuffer {
    let w: Int
    let h: Int
    var px: [UInt8]
    var zbuf: [Double]

    init(w: Int, h: Int) {
        self.w = w
        self.h = h
        self.px = [UInt8](repeating: 0, count: w * h * 4)
        self.zbuf = [Double](repeating: 0, count: w)
    }

    /// Deep copy. Screenshots must snapshot a frame: holding a reference to a
    /// framebuffer would store the *next* frame's contents instead.
    func copy() -> Framebuffer {
        let f = Framebuffer(w: w, h: h)
        f.px = px
        f.zbuf = zbuf
        return f
    }

    @inline(__always) func put(_ x: Int, _ y: Int, _ r: Int, _ g: Int, _ b: Int) {
        if x < 0 || y < 0 || x >= w || y >= h { return }
        let i = (y * w + x) * 4
        px[i] = UInt8(clamping: r); px[i + 1] = UInt8(clamping: g)
        px[i + 2] = UInt8(clamping: b); px[i + 3] = 255
    }

    func clear(_ r: Int, _ g: Int, _ b: Int) {
        var i = 0
        while i < px.count {
            px[i] = UInt8(clamping: r); px[i + 1] = UInt8(clamping: g)
            px[i + 2] = UInt8(clamping: b); px[i + 3] = 255
            i += 4
        }
    }

    func fillRect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ r: Int, _ g: Int, _ b: Int) {
        // Guard the clamped ranges: a caller that computes a size from a width it
        // does not own (split-screen views, for instance) can otherwise produce
        // x0 > x1 and trap on a Swift range, killing the app mid-frame.
        let x0 = max(0, x), x1 = min(w, x + rw)
        let y0 = max(0, y), y1 = min(h, y + rh)
        guard x1 > x0, y1 > y0 else { return }
        for yy in y0..<y1 {
            for xx in x0..<x1 { put(xx, yy, r, g, b) }
        }
    }

    func outlineRect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ r: Int, _ g: Int, _ b: Int) {
        guard rw > 0, rh > 0 else { return }
        fillRect(x, y, rw, 1, r, g, b)
        fillRect(x, y + rh - 1, rw, 1, r, g, b)
        fillRect(x, y, 1, rh, r, g, b)
        fillRect(x + rw - 1, y, 1, rh, r, g, b)
    }

    func tint(_ r: Int, _ g: Int, _ b: Int, _ amount: Double) {
        guard amount > 0.002 else { return }
        let a = amount
        for i in stride(from: 0, to: px.count, by: 4) {
            px[i] = UInt8(clamping: Int(Double(px[i]) * (1 - a) + Double(r) * a))
            px[i + 1] = UInt8(clamping: Int(Double(px[i + 1]) * (1 - a) + Double(g) * a))
            px[i + 2] = UInt8(clamping: Int(Double(px[i + 2]) * (1 - a) + Double(b) * a))
        }
    }

    func brighten(_ amount: Double) {
        guard amount > 0.002 else { return }
        for i in stride(from: 0, to: px.count, by: 4) {
            px[i] = UInt8(clamping: Int(Double(px[i]) * (1 + amount)))
            px[i + 1] = UInt8(clamping: Int(Double(px[i + 1]) * (1 + amount)))
            px[i + 2] = UInt8(clamping: Int(Double(px[i + 2]) * (1 + amount)))
        }
    }

    static let charW = 4, charH = 6

    func text(_ s: String, _ x: Int, _ y: Int, _ r: Int, _ g: Int, _ b: Int, scale: Int = 1, shadow: Bool = true) {
        var cx = x
        for ch in s.uppercased() {
            if ch == " " { cx += Self.charW * scale; continue }
            guard let glyph = Font3x5.glyphs[ch] else { cx += Self.charW * scale; continue }
            let rows = [glyph.0, glyph.1, glyph.2, glyph.3, glyph.4]
            for gy in 0..<5 {
                let bits = Int(rows[gy])
                for gx in 0..<3 {
                    if (bits >> (2 - gx)) & 1 == 1 {
                        for sy in 0..<scale {
                            for sx in 0..<scale {
                                if shadow { put(cx + gx * scale + sx + scale, y + gy * scale + sy + scale, 0, 0, 0) }
                                put(cx + gx * scale + sx, y + gy * scale + sy, r, g, b)
                            }
                        }
                    }
                }
            }
            cx += Self.charW * scale
        }
    }

    func textCentered(_ s: String, _ y: Int, _ r: Int, _ g: Int, _ b: Int, scale: Int = 1, shadow: Bool = true) {
        let width = s.count * Self.charW * scale - scale
        text(s, (w - width) / 2, y, r, g, b, scale: scale, shadow: shadow)
    }
}

extension Framebuffer {
    /// Centre a string on an arbitrary x (used to line up HUD columns).
    func textCenteredX(_ s: String, aroundX cx: Int, _ y: Int,
                       _ r: Int, _ g: Int, _ b: Int, scale: Int = 1, shadow: Bool = true) {
        let width = s.count * Framebuffer.charW * scale - scale
        text(s, cx - width / 2, y, r, g, b, scale: scale, shadow: shadow)
    }
}

// MARK: - World renderer

private struct Drawable {
    var x: Double, y: Double
    var lift: Double
    var worldH: Double
    var tex: Tex
    var tintFlash: Double = 0
    var scaleX: Double = 1
}

enum Renderer {

    static let fovPlane = 0.72      // tan(fov/2) ~ 72 deg
    static let eyeHeight = 0.5

    /// Per-type sprite tables, so adding an enemy is a one-line change here.
    /// Indexed by `Enemy.type` (see `EnemyType`).
    static let enemyIdleSprites: [Sprite] = [
        .imp, .brute, .soldier, .heavy, .grenadier, .marksman, .rioter,
    ]
    static let enemyAttackSprites: [Sprite] = [
        .impAttack, .bruteAttack, .soldierAttack, .heavyAttack,
        .grenadierAttack, .marksmanAttack, .rioterAttack,
    ]
    static let enemyCorpseSprites: [Sprite] = [
        .impDie, .bruteDie, .soldierDie, .heavyDie,
        .grenadierDie, .marksmanDie, .rioterDie,
    ]
    static let enemyWorldHeights: [Double] = [1.02, 1.24, 1.16, 1.34, 1.18, 1.14, 1.28]

    static func enemySprite(type: Int, attacking: Bool, dead: Bool) -> Sprite {
        let t = min(max(type, 0), enemyIdleSprites.count - 1)
        if dead { return enemyCorpseSprites[t] }
        if attacking { return enemyAttackSprites[t] }
        return enemyIdleSprites[t]
    }

    static func enemyHeight(type: Int) -> Double {
        enemyWorldHeights[min(max(type, 0), enemyWorldHeights.count - 1)]
    }

    /// Sprite for a type, falling back to the imp if a table ever runs short.
    static func enemySpriteOrImp(type: Int, attacking: Bool, dead: Bool) -> Sprite {
        let s = enemySprite(type: type, attacking: attacking, dead: dead)
        return TexLib.sprites[s] != nil ? s : .imp
    }

    /// Camera a single view is rendered from. Split-screen renders one of these
    /// per player, so the world renderer never has to know about player indices.
    struct Camera {
        var x: Double
        var y: Double
        var ang: Double
        var shake: Double
    }

    static func camera(for p: Player) -> Camera {
        Camera(x: p.x, y: p.y, ang: p.ang, shake: p.shake)
    }

    static func renderWorld(_ g: Game, _ fb: Framebuffer, _ cam: Camera) {
        let w = fb.w, h = fb.h
        let level = g.level

        // camera with screen shake
        var camX = cam.x, camY = cam.y, ang = cam.ang
        if cam.shake > 0.01 {
            let s = cam.shake
            camX += Double.random(in: -0.05...0.05) * s
            camY += Double.random(in: -0.05...0.05) * s
            ang += Double.random(in: -0.012...0.012) * s
        }
        let dirX = cos(ang), dirY = sin(ang)
        let planeX = -dirY * fovPlane, planeY = dirX * fovPlane
        let halfH = Double(h) / 2.0
        let posZ = eyeHeight

        let wallTex = TexLib.walls
        let nWall = TexLib.wallCount
        let floorTex = TexLib.floor
        let ceilTex = TexLib.ceiling
        let doorTex = TexLib.door
        let exitTex = TexLib.exit
        let secretTex = TexLib.sprites[.secretWall] ?? TexLib.walls[0]

        let cells = level.cells
        let doors = level.doorProgress
        let mw = level.w, mh = level.h
        let texSize = TexLib.wallSize
        let fpx = floorTex.px, cpx = ceilTex.px
        let texMask = texSize - 1

        fb.px.withUnsafeMutableBufferPointer { pbuf in
            fb.zbuf.withUnsafeMutableBufferPointer { zbuf in
                guard let P = pbuf.baseAddress, let Z = zbuf.baseAddress else { return }

                for x in 0..<w { Z[x] = 1e9 }

                @inline(__always) func sample(_ arr: [UInt8], _ tx: Int, _ ty: Int) -> (Double, Double, Double) {
                    let i = ((ty & texMask) * texSize + (tx & texMask)) * 4
                    return (Double(arr[i]), Double(arr[i + 1]), Double(arr[i + 2]))
                }

                for x in 0..<w {
                    let cam = 2.0 * Double(x) / Double(w) - 1.0
                    let rayX = dirX + planeX * cam
                    let rayY = dirY + planeY * cam

                    // --- DDA ---
                    var mapX = Int(camX.rounded(.down)), mapY = Int(camY.rounded(.down))
                    let deltaX = abs(1.0 / (rayX == 0 ? 1e-9 : rayX))
                    let deltaY = abs(1.0 / (rayY == 0 ? 1e-9 : rayY))
                    var stepX: Int, stepY: Int
                    var sideDistX: Double, sideDistY: Double
                    if rayX < 0 {
                        stepX = -1; sideDistX = (camX - Double(mapX)) * deltaX
                    } else {
                        stepX = 1; sideDistX = (Double(mapX + 1) - camX) * deltaX
                    }
                    if rayY < 0 {
                        stepY = -1; sideDistY = (camY - Double(mapY)) * deltaY
                    } else {
                        stepY = 1; sideDistY = (Double(mapY + 1) - camY) * deltaY
                    }
                    var side = 0
                    var hit = false
                    var dist = 0.0
                    var guardCount = 0
                    while guardCount < 160 {
                        guardCount += 1
                        if sideDistX < sideDistY {
                            sideDistX += deltaX; mapX += stepX; side = 0
                            dist = sideDistX - deltaX
                        } else {
                            sideDistY += deltaY; mapY += stepY; side = 1
                            dist = sideDistY - deltaY
                        }
                        if mapX < 0 || mapY < 0 || mapX >= mw || mapY >= mh { break }
                        if cells[mapY * mw + mapX] != 0 { hit = true; break }
                    }

                    let lineH = max(1.0, Double(h) / max(dist, 0.0001))
                    var drawStart = Int((Double(h) - lineH) / 2.0)
                    var drawEnd = drawStart + Int(lineH)
                    if drawStart < 0 { drawStart = 0 }
                    if drawEnd > h { drawEnd = h }

                    // door: rises out of the frame
                    var doorP = 0.0
                    if hit, mapX >= 0, mapY >= 0, mapX < mw, mapY < mh {
                        let c = cells[mapY * mw + mapX]
                        if c == Tile.door { doorP = doors[mapY * mw + mapX] }
                    }
                    if doorP > 0 { drawEnd = drawStart + Int(Double(drawEnd - drawStart) * (1.0 - doorP)) }

                    // --- ceiling & floor ---
                    if drawStart > 0 {
                        var y = 0
                        while y < drawStart {
                            let p = max(0.5, halfH - Double(y))
                            let rowDist = posZ * halfH / p
                            let step = rowDist < 0.8 ? 1 : 2
                            let fx = camX + rowDist * rayX
                            let fy = camY + rowDist * rayY
                            let tx = Int(fx * Double(texSize)), ty = Int(fy * Double(texSize))
                            var sh = max(0.14, 1.0 - (rowDist - 0.4) * 0.085)
                            if ((tx >> 5) + (ty >> 5)) & 1 == 0 { sh *= 0.86 }
                            let c = sample(cpx, tx, ty)
                            let rr = Int(c.0 * sh), gg = Int(c.1 * sh), bb = Int(c.2 * sh)
                            let y2 = min(drawStart, y + step)
                            if y2 <= y { break }
                            for yy in y..<y2 {
                                let idx = (yy * w + x) * 4
                                P[idx] = UInt8(clamping: rr); P[idx + 1] = UInt8(clamping: gg)
                                P[idx + 2] = UInt8(clamping: bb); P[idx + 3] = 255
                            }
                            y = y2
                        }
                    }
                    if drawEnd < h {
                        var y = max(drawEnd, Int(halfH))
                        while y < h {
                            let p = max(0.5, Double(y) - halfH + 1.0)
                            let rowDist = posZ * halfH / p
                            let step = rowDist < 0.8 ? 1 : 2
                            let fx = camX + rowDist * rayX
                            let fy = camY + rowDist * rayY
                            let tx = Int(fx * Double(texSize)), ty = Int(fy * Double(texSize))
                            var sh = max(0.13, 1.0 - (rowDist - 0.4) * 0.085)
                            if ((tx >> 5) + (ty >> 5)) & 1 == 0 { sh *= 0.88 }
                            let c = sample(fpx, tx, ty)
                            let rr = Int(c.0 * sh), gg = Int(c.1 * sh), bb = Int(c.2 * sh)
                            let y2 = min(h, y + step)
                            if y2 <= y { break }
                            for yy in y..<y2 {
                                let idx = (yy * w + x) * 4
                                P[idx] = UInt8(clamping: rr); P[idx + 1] = UInt8(clamping: gg)
                                P[idx + 2] = UInt8(clamping: bb); P[idx + 3] = 255
                            }
                            y = y2
                        }
                    }

                    Z[x] = dist

                    if !hit { continue }

                    // --- wall column ---
                    let cell = cells[mapY * mw + mapX]
                    let wallH: Double = side == 0 ? dist * deltaX : dist * deltaY
                    var wallX = side == 0 ? camY + wallH : camX + wallH
                    wallX -= wallH.rounded(.down)
                    var texX = Int(wallX * Double(texSize))
                    texX &= texMask
                    if (side == 0 && rayX > 0) || (side == 1 && rayY < 0) { texX = texMask - texX }

                    let src: [UInt8]
                    if cell == Tile.door { src = doorTex.px }
                    else if cell == Tile.exit { src = exitTex.px }
                    else if cell == Tile.secret { src = secretTex.px }
                    else { src = wallTex[min(nWall - 1, max(0, Int(cell) - 1))].px }

                    var sh = max(0.11, 1.0 - (dist - 0.35) * 0.082)
                    if side == 1 { sh *= 0.68 }
                    if cell == Tile.exit { sh *= 1.0 + 0.35 * abs(sin(g.time * 4)) }

                    let texStep = Double(texSize) / lineH
                    var texPos = (Double(drawStart) - (Double(h) - lineH) / 2.0) * texStep
                    for y in drawStart..<drawEnd {
                        if texPos >= 0 && texPos < Double(texSize) {
                            let ty = Int(texPos)
                            let i = (ty * texSize + texX) * 4
                            let rr = Int(Double(src[i]) * sh)
                            let gg = Int(Double(src[i + 1]) * sh)
                            let bb = Int(Double(src[i + 2]) * sh)
                            let idx = (y * w + x) * 4
                            P[idx] = UInt8(clamping: rr); P[idx + 1] = UInt8(clamping: gg)
                            P[idx + 2] = UInt8(clamping: bb); P[idx + 3] = 255
                        }
                        texPos += texStep
                    }
                }

                // ---------------- sprites ----------------
                var drawables: [Drawable] = []
                drawables.reserveCapacity(64)

                for p in g.pickups where !p.taken {
                    let bob = 0.03 + 0.02 * sin(g.time * 2.6 + p.phase)
                    drawables.append(Drawable(x: p.x, y: p.y, lift: bob, worldH: 0.42,
                                              tex: TexLib.sprites[p.kind.sprite] ?? TexLib.sprites[.medikit]!))
                }
                for b in g.barrels where !b.gone {
                    let tex: Tex
                    if b.flash > 0.01 && Int(g.time * 30) % 2 == 0 { tex = TexLib.sprites[.barrelFlash]! }
                    else { tex = TexLib.sprites[.barrel]! }
                    drawables.append(Drawable(x: b.x, y: b.y, lift: 0, worldH: 0.78, tex: tex))
                }
                for e in g.enemies {
                    let texKey = Renderer.enemySpriteOrImp(type: e.type,
                                                          attacking: e.attackAnim > 0.35,
                                                          dead: e.state == .dead)
                    var d = Drawable(x: e.x, y: e.y, lift: 0,
                                     worldH: Renderer.enemyHeight(type: e.type),
                                     tex: TexLib.sprites[texKey] ?? TexLib.sprites[.imp]!)
                    if e.state == .dead {
                        let t = min(1, e.deadTimer / 1.2)
                        d.lift = t * 0.45
                        d.worldH *= 1.0 - t * 0.35
                    }
                    d.tintFlash = e.flash > 0 ? 0.7 : (e.gore * 0.3)
                    drawables.append(d)
                }

                for v in g.vehicles {
                    let table = v.dead ? TexLib.vehicleWreckTex : TexLib.vehicleTex
                    let tex = table[v.def.id]
                    if let tex {
                        var lift = 0.0
                        var h = v.def.worldHeight
                        if v.dead {
                            lift = min(0.18, v.deadTimer * 0.05)
                            h *= 0.72
                        } else if v.def.flying {
                            // helicopters hover, bobbing gently
                            lift = 0.42 + 0.04 * sin(g.time * 1.6 + v.animPhase)
                        }
                        var d = Drawable(x: v.x, y: v.y, lift: lift, worldH: h, tex: tex)
                        d.tintFlash = v.flash
                        drawables.append(d)
                    }
                }

                let invDet = 1.0 / (planeX * dirY - dirX * planeY)

                // far to near
                drawables.sort { a, b in
                    let da = (a.x - camX) * (a.x - camX) + (a.y - camY) * (a.y - camY)
                    let db = (b.x - camX) * (b.x - camX) + (b.y - camY) * (b.y - camY)
                    return da > db
                }

                // only the nearest few dozen sprites matter: culling them keeps the
                // worst-case frame time sane when a horde crowds the camera.
                // Vehicles always draw -- a tank you are driving must never pop.
                var drawCount = min(drawables.count, 28)
                var forced = 0
                if let camPlayer = g.players.first(where: { $0.x == camX && $0.y == camY }),
                   let rv = g.vehicles.first(where: { $0 === camPlayer.rides }) {
                    if let i = drawables.firstIndex(where: { $0.x == rv.x && $0.y == rv.y }) {
                        // move it to the near end so the cull cannot drop it
                        let d = drawables.remove(at: i)
                        drawables.insert(d, at: min(drawables.count, forced))
                        forced = 1
                    }
                    drawCount = drawables.count
                }
                for d in drawables.suffix(drawCount) {
                    let sx = d.x - camX, sy = d.y - camY
                    if sx * sx + sy * sy > 676.0 { continue }   // beyond 26 units
                    let tX = invDet * (dirY * sx - dirX * sy)
                    let tY = invDet * (-planeY * sx + planeX * sy)
                    if tY < 0.12 { continue }
                    let tex = d.tex
                    let worldW = d.worldH * Double(tex.w) / Double(tex.h)
                    let screenH = d.worldH * Double(h) / tY
                    let screenW = worldW * Double(h) / tY
                    if screenH < 1 || screenW < 1 { continue }
                    let centerX = Double(w) / 2.0 * (1.0 + tX / tY)
                    // anchor the sprite on the floor: the floor line at this depth
                    // sits at halfH + eyeHeight*h/tY, and `lift` raises it
                    let floorY = halfH + posZ * Double(h) / tY - d.lift * Double(h) / tY
                    let centerY = floorY - screenH / 2.0
                    let left = Int(centerX - screenW / 2.0)
                    let top = Int(centerY - screenH / 2.0)
                    var fog = max(0.18, 1.0 - (tY - 0.4) * 0.075)
                    fog *= (d.tintFlash > 0 ? 1.25 : 1.0)
                    let x0 = max(0, left), x1 = min(w - 1, left + Int(screenW))
                    let y0 = max(0, top), y1 = min(h - 1, top + Int(screenH))
                    if x1 < x0 || y1 < y0 { continue }
                    // a sprite right in your face can cover the whole screen: sample it
                    // more coarsely instead of paying for every pixel
                    let step = tY < 0.85 ? 2 : 1
                    let invScreenW = 1.0 / max(1.0, screenW)
                    let invScreenH = 1.0 / max(1.0, screenH)
                    let yEnd = min(h, y1 + 1)
                    var xc = x0
                    while xc <= x1 {
                        if tY < Z[xc] {
                            let u = Double(xc - left) * invScreenW * Double(tex.w)
                            let uPix = min(tex.w - 1, max(0, Int(u)))
                            let xEnd = min(x1 + 1, xc + step)
                            var y = y0
                            while y < yEnd {
                                let v = Double(y - top) * invScreenH * Double(tex.h)
                                if v >= 0 && v < Double(tex.h) {
                                    let ti = (Int(v) * tex.w + uPix) * 4
                                    if Int(tex.px[ti + 3]) > 24 {
                                        let rr = UInt8(clamping: Int(Double(tex.px[ti]) * fog))
                                        let gg = UInt8(clamping: Int(Double(tex.px[ti + 1]) * fog))
                                        let bb = UInt8(clamping: Int(Double(tex.px[ti + 2]) * fog))
                                        for fy in y..<min(yEnd, y + step) {
                                            let row = (fy * w) * 4
                                            for fx in xc..<xEnd {
                                                let idx = row + fx * 4
                                                P[idx] = rr; P[idx + 1] = gg; P[idx + 2] = bb; P[idx + 3] = 255
                                            }
                                        }
                                    }
                                }
                                y += step
                            }
                        }
                        xc += step
                    }
                }

                // ---------------- particles ----------------
                for pt in g.particles {
                    let sx = pt.x - camX, sy = pt.y - camY
                    let tX = invDet * (dirY * sx - dirX * sy)
                    let tY = invDet * (-planeY * sx + planeX * sy)
                    if tY < 0.15 { continue }
                    let sxp = Double(w) / 2.0 * (1.0 + tX / tY)
                    let syp = halfH + (posZ - pt.z) * Double(h) / tY
                    var rad = Int(pt.size * Double(h) / tY)
                    if rad < 1 { rad = 1 }
                    if rad > 24 { rad = 24 }
                    let pstep = rad > 8 ? 2 : 1
                    let fade = max(0.1, min(1, pt.life / pt.maxLife))
                    let rr = Int(Double(pt.r) * fade), gg = Int(Double(pt.g) * fade), bb = Int(Double(pt.b) * fade)
                    let yA = Int(syp) - rad, yB = Int(syp) + rad
                    let xA = Int(sxp) - rad, xB = Int(sxp) + rad
                    var yy = yA
                    while yy <= yB {
                        var xx = xA
                        while xx <= xB {
                            guard xx >= 0, xx < w, yy >= 0, yy < h else { xx += pstep; continue }
                            if tY >= Z[xx] { xx += pstep; continue }
                            let idx = (yy * w + xx) * 4
                            P[idx] = UInt8(clamping: rr); P[idx + 1] = UInt8(clamping: gg)
                            P[idx + 2] = UInt8(clamping: bb); P[idx + 3] = 255
                            xx += pstep
                        }
                        yy += pstep
                    }
                }

                // ---------------- rockets in flight ----------------
                if !g.projectiles.isEmpty, let rocket = TexLib.sprites[.rocketBall] {
                    for pr in g.projectiles {
                        let sx = pr.x - camX, sy = pr.y - camY
                        let tX = invDet * (dirY * sx - dirX * sy)
                        let tY = invDet * (-planeY * sx + planeX * sy)
                        if tY < 0.15 { continue }
                        let sxp = Double(w) / 2.0 * (1.0 + tX / tY)
                        let syp = halfH + (posZ - pr.z) * Double(h) / tY
                        let rad = max(2, Int(0.30 * Double(h) / tY))
                        let xA = Int(sxp) - rad, xB = Int(sxp) + rad
                        let yA = Int(syp) - rad, yB = Int(syp) + rad
                        for yy in yA...yB {
                            for xx in xA...xB {
                                guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
                                if tY >= Z[xx] { continue }
                                let u = Int(Double(xx - xA) * Double(rocket.w) / Double(max(1, xB - xA + 1)))
                                let v = Int(Double(yy - yA) * Double(rocket.h) / Double(max(1, yB - yA + 1)))
                                if u < 0 || v < 0 || u >= rocket.w || v >= rocket.h { continue }
                                let ti = (v * rocket.w + u) * 4
                                if Int(rocket.px[ti + 3]) < 24 { continue }
                                let idx = (yy * w + xx) * 4
                                P[idx] = rocket.px[ti]; P[idx + 1] = rocket.px[ti + 1]
                                P[idx + 2] = rocket.px[ti + 2]; P[idx + 3] = 255
                            }
                        }
                    }
                }
            }
        }
    }
}
