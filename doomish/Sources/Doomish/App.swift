import AppKit

final class GameView: NSView {
    let game = Game()
    let fb = Framebuffer(w: 480, h: 300)
    /// One framebuffer per split-screen view. Sized to the viewport, not the
    /// window: each view is rendered at its own resolution and then blitted, so
    /// the world/HUD code is identical for one player and for three.
    private var viewFBs: [Framebuffer] = []
    private(set) var timer: Timer?
    private var lastTime = Date()
    private var relativeMouse = false
    private var frames = 0
    private var demoMode = CommandLine.arguments.contains("--demo")

    static let baseWidth = 480
    static let baseHeight = 300

    /// Screen rect of each split-screen view. One player gets the whole frame;
    /// two and three get equal vertical columns (the classic Doom co-op layout).
    static func viewRects(count: Int, w: Int, h: Int) -> [CGRect] {
        switch count {
        case 2:
            let half = w / 2
            return [CGRect(x: 0, y: 0, width: half, height: h),
                    CGRect(x: half, y: 0, width: w - half, height: h)]
        case 3:
            let third = w / 3
            return [CGRect(x: 0, y: 0, width: third, height: h),
                    CGRect(x: third, y: 0, width: third, height: h),
                    CGRect(x: 2 * third, y: 0, width: w - 2 * third, height: h)]
        default:
            return [CGRect(x: 0, y: 0, width: w, height: h)]
        }
    }

    // MARK: lifecycle

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // compositing the frame through a layer keeps the per-frame cost on the
        // GPU instead of stretching 320x200 into a backing store on the CPU
        wantsLayer = true
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        layer?.isOpaque = true
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
        if timer == nil {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            lastTime = Date()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { setRelativeMouse(false) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        DispatchQueue.main.async { self.needsDisplay = true }
    }

    override func resignFirstResponder() -> Bool {
        setRelativeMouse(false)
        return true
    }

    override func becomeFirstResponder() -> Bool {
        DispatchQueue.main.async { [weak self] in self?.setRelativeMouse(true) }
        return true
    }

    /// Set by the headless input test so running tests never steals the real cursor.
    static var cursorLockDisabled = false
    private static var signalSources: [DispatchSourceSignal] = []

    private func setRelativeMouse(_ on: Bool) {
        guard !GameView.cursorLockDisabled else { return }
        guard on != relativeMouse else { return }
        relativeMouse = on
        CursorLock.set(on)
        if on { pinPointerToWindow() }
    }

    /// The window centre in Quartz (top-left origin) coordinates, which is what
    /// CGWarpMouseCursorPosition expects.
    private var pointerHome: CGPoint? {
        guard let win = window, let view = win.contentView,
              let scr = win.screen ?? NSScreen.main else { return nil }
        let mid = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        return CGPoint(x: mid.x, y: scr.frame.minY + scr.frame.height - mid.y)
    }

    /// True pointer lock: the cursor is hidden, its deltas accumulate, and it is
    /// warped back to the middle of the window after every move. Without the warp
    /// the cursor walks to the window edge and then *out* of it, and AppKit stops
    /// delivering mouseMoved — the player literally cannot look around any more.
    /// ESC (pause) releases it.
    private func pinPointerToWindow() {
        guard let home = pointerHome else { return }
        if let cur = CGEvent(source: nil)?.location,
           hypot(cur.x - home.x, cur.y - home.y) < 12 { return }
        CGWarpMouseCursorPosition(home)
    }

    /// The cursor lock is the one thing in this app that can wedge the whole desktop
    /// if the process dies without unwinding (force quit, crash, `kill -9`). Every
    /// path out of here goes through the same two calls.
    enum CursorLock {
        static var locked = false

        static func set(_ on: Bool) {
            guard on != locked else { return }
            locked = on
            if on {
                CGAssociateMouseAndMouseCursorPosition(1)
                CGDisplayHideCursor(CGMainDisplayID())
            } else {
                release()
            }
        }

        static func release() {
            guard locked else { return }
            locked = false
            CGDisplayShowCursor(CGMainDisplayID())
            CGAssociateMouseAndMouseCursorPosition(0)
        }
    }

    /// backstops for exits that skip `applicationWillTerminate`
    static func installCursorSafety() {
        atexit { CursorLock.release() }
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }
        for name in [NSApplication.didResignActiveNotification,
                     NSWindow.didResignKeyNotification,
                     NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                CursorLock.release()
            }
        }
    }

    // MARK: game loop

    private func tick() {
        let now = Date()
        var dt = now.timeIntervalSince(lastTime)
        lastTime = now
        if dt > 0.1 { dt = 0.1 }
        if dt < 0 { dt = 0 }

        if demoMode && game.state == .start && frames > 3 { game.startNewGame() }
        if demoMode { driveDemo() }
        game.update(dt)
        render()
        layer?.contents = makeImage()

        // only hold the cursor while actually playing and focused; any other
        // state (title, pause, death, unfocused, menu open) hands it back
        setRelativeMouse(!demoMode && !game.paused && game.state == .playing && NSApp.isActive)

        // debug hook: `touch /tmp/doomish_capture` to dump what the window shows
        frames += 1
        if frames % 60 == 0, FileManager.default.fileExists(atPath: "/tmp/doomish_capture") {
            SelfTest.writePPM("/tmp/doomish_gui.ppm", fb)
            let s = game.state
            let line = "locked=\(CursorLock.locked ? 1 : 0) state=\(s.rawValue) "
                + "paused=\(game.paused ? 1 : 0) active=\(NSApp.isActive ? 1 : 0) "
                + "demo=\(demoMode ? 1 : 0) px=\(Int(game.px * 100)) py=\(Int(game.py * 100)) "
                + "hp=\(Int(game.health)) weapon=\(game.weapon) fps=\(Int(1.0 / max(dt, 0.0001))) "
                + "fwd=\(Int(game.input.forward * 100)) strafe=\(Int(game.input.strafe * 100)) "
                + "turn=\(Int(game.input.turn * 100)) fire=\(game.input.fire ? 1 : 0) "
                + "resp=\(window?.firstResponder === self ? 1 : 0)\n"
            try? line.write(toFile: "/tmp/doomish_gui.state", atomically: true, encoding: .utf8)
        }
    }

    /// Attract-mode bot: picks the nearest visible enemy, faces it, keeps its
    /// preferred range and squeezes the trigger. Also doubles as a headless
    /// smoke test for the combat code paths.
    private func driveDemo() {
        let g = game
        guard g.state == .playing else {
            g.input.forward = 0; g.input.strafe = 0; g.input.turn = 0
            g.input.fire = false; g.input.firePressed = false
            return
        }
        let t = g.time

        var target: Enemy?
        var targetDist = 1e9
        for e in g.enemies where !e.dead {
            let d = hypot(e.x - g.px, e.y - g.py)
            guard d < 22 else { continue }
            guard g.lineOfSight(g.px, g.py, e.x, e.y) else { continue }
            if d < targetDist { target = e; targetDist = d }
        }

        if let e = target {
            let want = atan2(e.y - g.py, e.x - g.px)
            var diff = want - g.pang
            while diff > .pi { diff -= 2 * .pi }
            while diff < -.pi { diff += 2 * .pi }
            g.input.turn = max(-1, min(1, diff * 3.0))
            let aimed = abs(diff) < 0.14
            g.input.fire = aimed
            g.input.firePressed = aimed && (frames % 5) == 0
            let preferred = g.weapons[g.weapon].projectile ? 7.0 : 3.6
            g.input.forward = targetDist > preferred + 1.0 ? 1.0 : (targetDist < preferred - 1.2 ? -1.0 : 0.0)
            g.input.strafe = sin(t * 0.9)
        } else {
            g.input.forward = sin(t * 0.37) > -0.85 ? 1.0 : 0.0
            g.input.strafe = sin(t * 0.23) > 0.55 ? 1.0 : (sin(t * 0.23) < -0.55 ? -1.0 : 0.0)
            g.input.turn = cos(t * 0.31) * 0.9
            g.input.fire = false
            g.input.firePressed = false
        }
        g.input.run = false

        // use whatever hits hardest
        if g.owned[4] && g.ammo[3] > 0 && targetDist > 5 && (frames % 170) == 0 { g.input.nextWeapons = [4] }
        else if g.owned[2] && g.ammo[0] > 30 { g.input.nextWeapons = [2] }
        else if g.owned[3] && g.ammo[0] > 20 { g.input.nextWeapons = [3] }
        else if g.owned[1] && g.ammo[1] > 6 && (frames % 260) == 0 { g.input.nextWeapons = [1] }
        if (g.weapon == 2 || g.weapon == 3) && g.ammo[0] < 12 { g.input.nextWeapons = [0] }
        if g.weapon == 4 && g.ammo[3] == 0 { g.input.nextWeapons = [0] }
    }

    private func render() {
        let g = game
        if g.state == .start {
            fb.clear(8, 8, 14)
            Hud.drawTitle(g, fb)
            return
        }
        let n = min(max(g.players.count, 1), maxLocalPlayers)
        let rects = Self.viewRects(count: n, w: fb.w, h: fb.h)

        // (re)allocate the per-view framebuffers when the split changes
        if viewFBs.count != n {
            viewFBs = rects.map { Framebuffer(w: max(1, Int($0.width)), h: max(1, Int($0.height))) }
        }

        for i in 0..<n {
            let p = g.players[i]
            let vfb = viewFBs[i]
            Renderer.renderWorld(g, vfb, Renderer.camera(for: p))
            Hud.drawForPlayer(g, p, vfb)
            blitView(vfb, into: fb, atX: Int(rects[i].origin.x))
        }
        // hairline dividers so the columns read as separate views
        for i in 1..<n {
            let x = Int(rects[i].origin.x)
            for y in 0..<fb.h { fb.put(x, y, 60, 66, 84) }
        }
        Hud.drawOverlays(g, fb)
    }

    /// Copy a view framebuffer into the composed screen framebuffer.
    private func blitView(_ src: Framebuffer, into dst: Framebuffer, atX ox: Int) {
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

    // MARK: menu actions

    @objc func newGame() {
        game.startNewGame()
    }

    /// Start a co-op session with `n` local players.
    @objc func startCoop(_ sender: NSMenuItem) {
        game.setPlayerCount(sender.tag)
        game.startNewGame()
    }

    @objc func changePlayerCount(_ sender: NSMenuItem) {
        let n = sender.tag
        game.setPlayerCount(n)
        // the state menu items must be rebuilt to show the checkmark
        AppDelegate.installMainMenu()
        Sound.play("switch")
    }

    @objc func togglePause() {
        switch game.state {
        case .start, .victory: break
        case .dead: game.restartLevel()
        case .levelDone: break
        case .playing: game.paused.toggle()
        }
    }

    @objc func toggleMap() {
        guard game.state == .playing else { return }
        game.showAutomap.toggle()
        Sound.play("switch")
    }

    @objc func toggleSound() {
        Sound.enabled.toggle()
        if Sound.enabled { Sound.play("switch") }
    }

    @objc func changeDifficulty(_ sender: NSMenuItem) {
        guard let d = Difficulty(rawValue: sender.tag) else { return }
        guard game.difficulty != d else { return }
        game.difficulty = d
        AppDelegate.installMainMenu()
        Sound.play("switch")
        // changing mid-campaign applies immediately: enemy health is already
        // baked into the live enemies, so reload to make the new numbers real
        if game.state == .playing { game.restartLevel() }
    }

    /// Debug/demo affordance: jump straight to the next level, or to the end.
    @objc func skipLevel() {
        guard game.state == .playing || game.state == .levelDone else { return }
        game.nextLevel()
    }

    @objc func giveUp() {
        guard game.state == .playing else { return }
        game.state = .victory
        game.stateTimer = 0
    }

    // MARK: drawing

    private func makeImage() -> CGImage? {
        let data = Data(fb.px) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: fb.w, height: fb.h,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: fb.w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    override func draw(_ dirtyRect: NSRect) {
        // only used if the view is ever not layer-backed
        guard let ctx = NSGraphicsContext.current?.cgContext, let img = makeImage() else { return }
        ctx.interpolationQuality = .none
        ctx.draw(img, in: bounds)
    }

    // MARK: input
    //
    // Player 1 keeps mouse aim. Players 2 and 3 get a disjoint keyboard block,
    // because one mouse cannot serve three first-person views:
    //
    //   P1  mouse aim,  WASD move,  Q/E turn,  SPACE fire,   1-5 arms
    //   P2  arrow keys (move + turn),  . fire,  , arm-cycle,  RIGHT-SHIFT run
    //   P3  IJKL (move + turn),        P fire,  / arm-cycle,  RIGHT-CONTROL run

    private func input(forPlayer i: Int) -> InputState? {
        guard i < game.players.count else { return nil }
        return game.players[i].input
    }

    override func keyDown(with event: NSEvent) {
        let kc = Int(event.keyCode)
        let inp = game.input

        // ---- player 2 / 3 private keys ----
        if game.players.count > 1 {
            switch kc {
            case 125: bump(kc, forward: +1, player: 1)                    // up
            case 126: bump(kc, forward: -1, player: 1)                    // down
            case 123: turn(kc, by: -1, player: 1)                          // left
            case 124: turn(kc, by: +1, player: 1)                          // right
            case 41: fire(kc, player: 1)                                   // .
            case 43: cycleWeapon(kc, dir: -1, player: 1)                   // ,
            case 31: bump(kc, forward: +1, player: 2)                     // I
            case 32: bump(kc, forward: -1, player: 2)                     // K
            case 38: strafe(kc, by: +1, player: 2)                         // J
            case 37: strafe(kc, by: -1, player: 2)                         // L
            case 33: turn(kc, by: -1, player: 2)                           // U
            case 35: turn(kc, by: +1, player: 2)                           // O
            case 34: fire(kc, player: 2)                                   // P
            case 47: cycleWeapon(kc, dir: 1, player: 2)                    // /
            case 48 where game.players.count < 2: break
            default: break
            }
            if handledByCoopKey(kc) { return }
        }

        switch kc {
        case 13: inp.forward = min(1, inp.forward + 1)                    // W
        case 1: inp.forward = max(-1, inp.forward - 1)                    // S
        case 2: inp.strafe = min(1, inp.strafe + 1)                      // D
        case 0: inp.strafe = max(-1, inp.strafe - 1)                     // A
        case 12: inp.turn = max(-1, inp.turn - 1)                        // Q
        case 14: inp.turn = min(1, inp.turn + 1)                         // E
        case 15:                                                          // R
            if game.state == .dead { game.restartLevel() }
            else if game.state == .victory { game.startNewGame() }
            inp.fire = true
        case 18: inp.wantWeapon = 0
        case 19: inp.wantWeapon = 1
        case 20: inp.wantWeapon = 2
        case 21: inp.wantWeapon = 3
        case 23: inp.wantWeapon = 4
        // the SAW, DMR and sniper occupy slots 6, 7 and 8
        case 22: inp.wantWeapon = 5
        case 24: inp.wantWeapon = 6
        case 25: inp.wantWeapon = 7
        case 26: inp.wantWeapon = 8
        case 48:                                                          // TAB -> automap
            game.showAutomap.toggle()
            Sound.play("switch")
        case 46:                                                          // M -> mute
            Sound.enabled.toggle()
        case 50, 36:                                                       // [ and ]
            if game.state == .start {
                let d = Difficulty(rawValue: Game.difficultySetting) ?? .veteran
                let all = Difficulty.allCases
                let i = all.firstIndex(of: d) ?? 1
                let next = all[(i + (kc == 50 ? -1 : 1) + all.count) % all.count]
                game.difficulty = next
                Sound.play("switch")
            }
        case 49:                                                          // SPACE
            inp.fire = true
            inp.firePressed = true
        case 3:                                                           // F -> enter/exit vehicle
            game.toggleVehicle(for: game.p0)
        case 53:                                                          // ESC
            togglePause()
        default:
            break
        }
    }

    /// True when the key belongs to the P2/P3 block and must not fall through to
    /// player 1's bindings.
    private func handledByCoopKey(_ kc: Int) -> Bool {
        switch kc {
        case 125, 126, 123, 124, 41, 43, 31, 32, 38, 37, 33, 35, 34, 47:
            return true
        default:
            return false
        }
    }

    private func bump(_ kc: Int, forward d: Int, player: Int) {
        guard let inp = input(forPlayer: player) else { return }
        if d > 0 { inp.forward = min(1, inp.forward + 1) } else { inp.forward = max(-1, inp.forward - 1) }
    }

    private func strafe(_ kc: Int, by d: Int, player: Int) {
        guard let inp = input(forPlayer: player) else { return }
        if d > 0 { inp.strafe = min(1, inp.strafe + 1) } else { inp.strafe = max(-1, inp.strafe - 1) }
    }

    private func turn(_ kc: Int, by d: Int, player: Int) {
        guard let inp = input(forPlayer: player) else { return }
        if d > 0 { inp.turn = min(1, inp.turn + 1) } else { inp.turn = max(-1, inp.turn - 1) }
    }

    private func fire(_ kc: Int, player: Int) {
        guard let inp = input(forPlayer: player) else { return }
        inp.fire = true
        inp.firePressed = true
    }

    /// Cycle that player's own weapons (their slots, not the global set).
    private func cycleWeapon(_ kc: Int, dir: Int, player: Int) {
        guard player < game.players.count else { return }
        let owned = game.players[player].owned
        let ownedList = (0..<owned.count).filter { owned[$0] }
        guard let cur = ownedList.firstIndex(of: game.players[player].weapon) else { return }
        let next = ownedList[(cur + dir + ownedList.count) % ownedList.count]
        if next != game.players[player].weapon { game.players[player].input.nextWeapons.append(next) }
    }

    override func keyUp(with event: NSEvent) {
        let kc = Int(event.keyCode)
        let inp = game.input
        let p2 = input(forPlayer: 1)
        let p3 = input(forPlayer: 2)
        switch kc {
        case 13: if inp.forward > 0 { inp.forward -= 1 }
        case 1: if inp.forward < 0 { inp.forward += 1 }
        case 2: if inp.strafe > 0 { inp.strafe -= 1 }
        case 0: if inp.strafe < 0 { inp.strafe += 1 }
        case 12: if inp.turn < 0 { inp.turn += 1 }
        case 14: if inp.turn > 0 { inp.turn -= 1 }
        case 125, 31: if let p2, p2.forward > 0 { p2.forward -= 1 }
        case 126, 32: if let p2, p2.forward < 0 { p2.forward += 1 }
        case 123, 33: if let p2, p2.turn < 0 { p2.turn += 1 }
        case 124, 35: if let p2, p2.turn > 0 { p2.turn -= 1 }
        case 38: if let p2, p2.strafe > 0 { p2.strafe -= 1 }
        case 37: if let p2, p2.strafe < 0 { p2.strafe += 1 }
        case 41: if let p2 { p2.fire = false }
        case 34: if let p3 { p3.fire = false }
        case 49: inp.fire = false
        case 15: inp.fire = false
        default: break
        }
    }

    override func flagsChanged(with event: NSEvent) {
        let f = event.modifierFlags
        // AppKit exposes left/right shift only as raw device bits, so the two are
        // matched numerically: left shift runs player 1, right shift runs player 2,
        // right control runs player 3. That is the only way three players can
        // share one keyboard.
        let leftShift = f.rawValue & 0x0002_0000 != 0
        let rightShift = f.rawValue & 0x0006_0000 != 0
        let rightControl = f.rawValue & 0x0004_0000 != 0
        game.players[0].input.run = leftShift
        if game.players.count > 1 { game.players[1].input.run = rightShift }
        if game.players.count > 2 { game.players[2].input.run = rightControl }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // On the title screen a click is also a UI click: the difficulty row and
        // the player-count row are hit-tested before the click is treated as
        // "deploy". Without this, changing difficulty would start the game.
        if game.state == .start {
            let p = convert(event.locationInWindow, from: nil)
            if let d = Hud.difficultyAt(x: Int(p.x), y: Int(p.y), fbW: fb.w, fbH: fb.h) {
                if game.difficulty != d {
                    game.difficulty = d
                    Sound.play("switch")
                }
                return
            }
            if let n = playerCountAt(x: Int(p.x), y: Int(p.y)) {
                game.setPlayerCount(n)
                Sound.play("switch")
                return
            }
        }
        game.input.fire = true
        game.input.firePressed = true
        game.clicked = true
    }

    /// Which of the title screen's player-count buttons a point lands on.
    private func playerCountAt(x: Int, y: Int) -> Int? {
        let bw = 78, gap = 8
        let totalW = bw * maxLocalPlayers + gap * (maxLocalPlayers - 1)
        var bx = (fb.w - totalW) / 2
        let by = fb.h - 66
        for n in 1...maxLocalPlayers {
            if x >= bx && x < bx + bw && y >= by && y < by + 16 { return n }
            bx += bw + gap
        }
        return nil
    }

    override func mouseUp(with event: NSEvent) {
        game.input.fire = false
    }

    override func rightMouseDown(with event: NSEvent) {
        cycleWeapon(1)
    }

    override func rightMouseUp(with event: NSEvent) { }

    override func mouseMoved(with event: NSEvent) {
        game.mouseDx += event.deltaX
        if relativeMouse { pinPointerToWindow() }
    }

    override func mouseDragged(with event: NSEvent) {
        game.mouseDx += event.deltaX
        if relativeMouse { pinPointerToWindow() }
    }

    override func scrollWheel(with event: NSEvent) {
        cycleWheel(event.scrollingDeltaY)
    }

    private func cycleWheel(_ delta: Double) {
        let dir = delta > 0 ? 1 : -1
        let owned = game.owned
        let ownedList = (0..<owned.count).filter { owned[$0] }
        guard let cur = ownedList.firstIndex(of: game.weapon) else { return }
        let next = ownedList[(cur + dir + ownedList.count) % ownedList.count]
        if next != game.weapon { game.input.nextWeapons.append(next) }
    }

    private func cycleWeapon(_ dir: Int) {
        let owned = game.owned
        let ownedList = (0..<owned.count).filter { owned[$0] }
        guard let cur = ownedList.firstIndex(of: game.weapon) else { return }
        let next = ownedList[(cur + dir + ownedList.count) % ownedList.count]
        if next != game.weapon { game.input.nextWeapons.append(next) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let view = GameView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let rect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered,
                          defer: false)
        window.title = "Doomish — Army Ops"
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.center()
        window.makeFirstResponder(view)

        GameView.installCursorSafety()
        AppDelegate.installMainMenu()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    /// Static (and not private) so the headless input test can install the real
    /// menu and prove it does not swallow gameplay keys. Every shortcut is ⌘-based:
    /// plain letters belong to the game, and "Quit" on a bare `q` used to swallow
    /// the turn-left key and kill the process instead of turning the player.
    static func installMainMenu() {
        let main = NSMenu()
        func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
            let i = NSMenuItem()
            i.title = title
            i.action = action
            i.keyEquivalent = key
            i.keyEquivalentModifierMask = .command
            return i
        }

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Doomish", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide Doomish", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item("Quit Doomish", #selector(NSApplication.terminate(_:)), "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let gameMenu = NSMenu(title: "Game")
        gameMenu.addItem(item("New Game", #selector(GameView.newGame), "n"))
        for n in 2...maxLocalPlayers {
            let ci = item("Co-op: \(n) Players", #selector(GameView.startCoop(_:)), "")
            ci.tag = n
            gameMenu.addItem(ci)
        }
        gameMenu.addItem(item("Pause / Resume", #selector(GameView.togglePause), "p"))
        gameMenu.addItem(.separator())
        gameMenu.addItem(item("Toggle Map", #selector(GameView.toggleMap), "t"))
        gameMenu.addItem(item("Toggle Sound", #selector(GameView.toggleSound), "m"))
        gameMenu.addItem(.separator())
        // difficulty submenu, radio-checked against the live setting
        let diffMenu = NSMenu(title: "Difficulty")
        let v = NSApp.windows.compactMap { $0.contentView as? GameView }.first?.game
        for d in Difficulty.allCases {
            let i = item(d.name, #selector(GameView.changeDifficulty(_:)), "")
            i.tag = d.rawValue
            i.state = (v?.difficulty == d) ? .on : .off
            diffMenu.addItem(i)
        }
        let dItem = NSMenuItem()
        dItem.title = "Difficulty"
        dItem.submenu = diffMenu
        gameMenu.addItem(dItem)
        gameMenu.addItem(.separator())
        gameMenu.addItem(item("Skip to Next Level", #selector(GameView.skipLevel), ""))
        gameMenu.addItem(item("End Campaign", #selector(GameView.giveUp), ""))
        let gameItem = NSMenuItem()
        gameItem.submenu = gameMenu
        main.addItem(gameItem)

        // live player-count switcher
        let view = NSApp.windows.compactMap { $0.contentView as? GameView }.first
        if let v = view {
            let playersMenu = NSMenu(title: "Players")
            for n in 1...maxLocalPlayers {
                let it = item("\(n) Player\(n > 1 ? "s" : "")",
                              #selector(GameView.changePlayerCount(_:)), "")
                it.tag = n
                it.state = (v.game.playerCount == n) ? .on : .off
                playersMenu.addItem(it)
            }
            let pItem = NSMenuItem()
            pItem.submenu = playersMenu
            main.addItem(pItem)
        }

        NSApp.mainMenu = main
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        GameView.CursorLock.release()
    }
}
