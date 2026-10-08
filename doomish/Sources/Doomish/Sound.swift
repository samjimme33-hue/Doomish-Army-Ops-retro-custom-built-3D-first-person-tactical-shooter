import AVFoundation
import Foundation
import QuartzCore

/// Tiny procedural sound engine: every effect is synthesised into an
/// in-memory PCM buffer the first time it is played. No audio assets needed.
final class SoundEngine {
    static let shared = SoundEngine()

    /// A pool of voices. One shared player node made every new sound cut the
    /// previous one off mid-bang, and a single `volume` for the node meant the
    /// next shot retroactively changed how loud the last one still was -- which
    /// is what made the gunfire sound like a broken speaker.
    private let engine = AVAudioEngine()
    private var voices: [AVAudioPlayerNode] = []
    private var voiceVolume: [Float] = []
    private var nextVoice = 0
    private static let voiceCount = 8

    /// Throttle per sound name. A dozen enemies screaming at once summed into a
    /// clipped mess; dropping the repeats inside this window keeps it readable.
    private var lastPlayed: [String: Double] = [:]
    private static let minInterval = 0.045

    private let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var started = false
    private var failed = false
    var enabled = true

    private init() {
        for _ in 0..<Self.voiceCount {
            let v = AVAudioPlayerNode()
            engine.attach(v)
            engine.connect(v, to: engine.mainMixerNode, format: format)
            voices.append(v)
            voiceVolume.append(1.0)
        }
    }

    private func ensureStarted() {
        if started || failed { return }
        do {
            try engine.start()
            started = true
        } catch {
            failed = true
        }
    }

    private func makeBuffer(_ dur: Double, _ gen: (Double, Double) -> Double) -> AVAudioPCMBuffer? {
        let frames = Int(dur * format.sampleRate)
        guard frames > 8,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buf.floatChannelData
        else { return nil }
        buf.frameLength = AVAudioFrameCount(frames)
        let n = Double(frames)
        let data = channels[0]
        // ~2 ms fades: a buffer that starts and ends at full scale plays a click
        let fade = max(2, Int(format.sampleRate * 0.002))
        for i in 0..<frames {
            let t = Double(i) / format.sampleRate
            var v = gen(t, Double(i) / n)
            var env = 1.0
            if i < fade { env = Double(i) / Double(fade) }
            else if i >= frames - fade { env = Double(frames - 1 - i) / Double(fade) }
            v *= env
            // soft clip rather than hard clamp: summing voices stays musical
            v = v / (1.0 + abs(v) * 0.6)
            data[i] = Float(max(-1.0, min(1.0, v)))
        }
        return buf
    }

    private func build() {
        var rng = RNG(seed: 12345)
        func noise() -> Double { rng.f() * 2.0 - 1.0 }

        buffers["pistol"] = makeBuffer(0.22) { t, _ in
            let f = 220.0 * exp(-t * 9.0)
            return exp(-t * 26.0) * (noise() * 0.55 + sin(2 * .pi * f * t) * 0.75)
        }
        buffers["shotgun"] = makeBuffer(0.45) { t, _ in
            let f = 150.0 * exp(-t * 5.0)
            return exp(-t * 11.0) * (noise() * 0.85 + sin(2 * .pi * f * t) * 0.55)
        }
        buffers["chain"] = makeBuffer(0.14) { t, _ in
            let f = 320.0 * exp(-t * 12.0)
            return exp(-t * 34.0) * (noise() * 0.45 + sin(2 * .pi * f * t) * 0.6)
        }
        // crisp full-auto crack for the assault rifle
        buffers["rifle"] = makeBuffer(0.11) { t, _ in
            let f = 520.0 * exp(-t * 14.0)
            return exp(-t * 40.0) * (noise() * 0.5 + sin(2 * .pi * f * t) * 0.55)
        }
        // deep whoosh + thump for the rocket launcher
        buffers["launch"] = makeBuffer(0.6) { t, _ in
            let sweep = 90.0 + 320.0 * exp(-t * 4.0)
            let hiss = exp(-t * 2.4) * noise() * 0.7
            let thump = exp(-t * 7.0) * sin(2 * .pi * sweep * t) * 0.6
            return hiss + thump
        }
        buffers["click"] = makeBuffer(0.07) { t, _ in
            exp(-t * 90.0) * noise() * 0.5
        }
        buffers["switch"] = makeBuffer(0.10) { t, _ in
            exp(-t * 22.0) * (sin(2 * .pi * 320 * t) * 0.35 + noise() * 0.2)
        }
        buffers["imp"] = makeBuffer(0.34) { t, _ in
            let f = 420.0 - 260.0 * min(1.0, t * 3.0)
            return exp(-t * 7.0) * (sin(2 * .pi * f * t) * 0.55 + noise() * 0.25)
        }
        buffers["impshot"] = makeBuffer(0.20) { t, _ in
            let f = 190.0 * exp(-t * 8.0)
            return exp(-t * 18.0) * (noise() * 0.45 + sin(2 * .pi * f * t) * 0.6)
        }
        buffers["bruteshot"] = makeBuffer(0.30) { t, _ in
            let f = 120.0 * exp(-t * 6.0)
            return exp(-t * 13.0) * (noise() * 0.5 + sin(2 * .pi * f * t) * 0.7)
        }
        buffers["death"] = makeBuffer(0.45) { t, _ in
            let f = 190.0 - 130.0 * min(1.0, t * 2.4)
            return exp(-t * 5.0) * (sin(2 * .pi * f * t) * 0.6 + noise() * 0.3)
        }
        buffers["hurt"] = makeBuffer(0.28) { t, _ in
            exp(-t * 10.0) * (noise() * 0.5 + sin(2 * .pi * 120 * t) * 0.6)
        }
        buffers["pickup"] = makeBuffer(0.20) { t, _ in
            let f = t < 0.08 ? 520.0 : 780.0
            return exp(-t * 12.0) * sin(2 * .pi * f * t) * 0.45
        }
        buffers["explode"] = makeBuffer(0.7) { t, _ in
            exp(-t * 5.0) * noise() * 0.9 + exp(-t * 2.2) * sin(2 * .pi * 42 * t) * 0.6
        }
        // long, thin crack for a .308 marksman round
        buffers["snipershot"] = makeBuffer(0.5) { t, _ in
            let f = 900.0 * exp(-t * 22.0) + 60.0
            return exp(-t * 20.0) * (noise() * 0.5 + sin(2 * .pi * f * t) * 0.6)
        }
        // a guttural cry as a marksman goes down
        buffers["marksmandeath"] = makeBuffer(0.4) { t, _ in
            let f = 700.0 - 520.0 * min(1.0, t * 4.0)
            return exp(-t * 9.0) * (sin(2 * .pi * f * t) * 0.5 + noise() * 0.2)
        }
        // pin popping out of a hand, then the arc of a lobbed grenade
        buffers["thrownoise"] = makeBuffer(0.35) { t, _ in
            let click = exp(-t * 70.0) * noise() * 0.4
            let whoosh = exp(-abs(t - 0.2) * 6.0) * noise() * 0.35
            return click + whoosh
        }
        // a soft, rewarding two-note sting for finding a secret
        buffers["secret"] = makeBuffer(0.6) { t, _ in
            let notes = [523.0, 784.0, 1046.0]
            let i = min(2, Int(t / 0.16))
            let lt = t - Double(i) * 0.16
            return exp(-lt * 6.0) * sin(2 * .pi * notes[i] * t) * 0.4
        }
        buffers["leveldone"] = makeBuffer(0.8) { t, _ in
            let notes = [392.0, 523.0, 659.0, 784.0]
            let i = min(3, Int(t / 0.16))
            let lt = t - Double(i) * 0.16
            return exp(-lt * 7.0) * sin(2 * .pi * notes[i] * t) * 0.4
        }
    }

    func play(_ name: String, volume: Float = 1.0) {
        guard enabled else { return }
        ensureStarted()
        guard !failed, !voices.isEmpty else { return }
        if buffers.isEmpty { build() }
        guard let buf = buffers[name] else { return }

        let now = CACurrentMediaTime()
        if let last = lastPlayed[name], now - last < Self.minInterval { return }
        lastPlayed[name] = now

        // round-robin so a burst never stacks on one voice and clips
        let i = nextVoice % voices.count
        nextVoice = (nextVoice + 1) % voices.count
        let v = voices[i]
        // if this voice is still busy with something long, drop it rather than
        // cutting it off -- that abrupt stop is what read as "broken audio"
        if v.isPlaying { v.stop() }
        v.volume = min(1.0, max(0.0, volume))
        v.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        if !v.isPlaying { v.play() }
    }

    /// Play positioned relative to the listener. Distance attenuates and pans,
    /// so a tank shell going off across the level reads as far away instead of
    /// as loud as one going off in your face.
    func play(_ name: String, at x: Double, y: Double, listener: (Double, Double, Double),
              maxDistance: Double = 30, volume: Float = 1.0) {
        let dx = x - listener.0
        let dy = y - listener.1
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist < maxDistance else { return }
        let falloff = pow(max(0, 1 - dist / maxDistance), 1.6)
        guard falloff > 0.02 else { return }
        // right vector is the listener heading rotated 90 degrees
        let rx = -sin(listener.2)
        let ry = cos(listener.2)
        // break the expression up: chained arithmetic in one line pushed the
        // type-checker past its budget and this file failed to compile at all
        let lateral: Double = dx * rx + dy * ry
        var pan = 0.0
        if dist > 0.01 {
            pan = lateral / dist
            pan = max(-1.0, min(1.0, pan))
        }
        let atten: Float = Float(falloff)
        let panGain: Float = 1.0 - 0.35 * Float(abs(pan))
        play(name, volume: volume * atten * panGain)
    }
}

enum Sound {
    static func play(_ name: String, volume: Float = 1.0) {
        SoundEngine.shared.play(name, volume: volume)
    }

    /// Positioned play. `listener` is (x, y, heading).
    static func play(_ name: String, position: (x: Double, y: Double),
                     listener: (x: Double, y: Double, ang: Double) = (0, 0, 0),
                     volume: Float = 1.0, maxDistance: Double = 30) {
        SoundEngine.shared.play(name, at: position.x, y: position.y,
                                listener: listener, maxDistance: maxDistance, volume: volume)
    }

    static var enabled: Bool {
        get { SoundEngine.shared.enabled }
        set { SoundEngine.shared.enabled = newValue }
    }
}
