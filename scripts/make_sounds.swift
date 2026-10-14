// Synthesises AINCRAD's original UI sounds (no samples from the anime or SAO Utils).
// Usage: swift scripts/make_sounds.swift AINCRAD/Resources/Sounds
import Foundation

let rate = 44_100.0

struct Tone {
    var freq: Double, start: Double, length: Double, gain: Double
    var glideTo: Double? = nil
}

/// Sine partials with a soft 4 ms attack and exponential decay, plus a quiet octave for shimmer.
func render(_ tones: [Tone], length: Double, decay: Double) -> [Int16] {
    let n = Int(length * rate)
    var out = [Double](repeating: 0, count: n)
    for t in tones {
        var phase = 0.0, phase2 = 0.0
        let s0 = Int(t.start * rate), count = Int(t.length * rate)
        for i in 0..<count where s0 + i < n {
            let x = Double(i) / rate
            let f = t.glideTo.map { t.freq + ($0 - t.freq) * x / t.length } ?? t.freq
            phase += 2 * .pi * f / rate
            phase2 += 2 * .pi * f * 2 / rate
            let env = min(x / 0.004, 1) * exp(-x * decay)
            out[s0 + i] += t.gain * env * (sin(phase) + 0.18 * sin(phase2))
        }
    }
    let peak = max(out.map(abs).max() ?? 1, 1e-9)
    return out.map { Int16(($0 / peak) * 0.8 * 32_767) }
}

func wav(_ samples: [Int16]) -> Data {
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: "RIFF".utf8); u32(UInt32(36 + samples.count * 2)); d.append(contentsOf: "WAVE".utf8)
    d.append(contentsOf: "fmt ".utf8); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
    d.append(contentsOf: "data".utf8); u32(UInt32(samples.count * 2))
    samples.forEach { u16(UInt16(bitPattern: $0)) }
    return d
}

let sounds: [String: [Int16]] = [
    "open": render([Tone(freq: 1318.5, start: 0, length: 0.35, gain: 1),
                    Tone(freq: 1975.5, start: 0.075, length: 0.35, gain: 0.8),
                    Tone(freq: 2637.0, start: 0.15, length: 0.3, gain: 0.45)], length: 0.5, decay: 11),
    "select": render([Tone(freq: 1760, start: 0, length: 0.12, gain: 1),
                      Tone(freq: 2637, start: 0.025, length: 0.1, gain: 0.5)], length: 0.16, decay: 30),
    "back": render([Tone(freq: 1480, start: 0, length: 0.12, gain: 1, glideTo: 1046)], length: 0.15, decay: 26),
    "close": render([Tone(freq: 1975.5, start: 0, length: 0.25, gain: 0.8),
                     Tone(freq: 1318.5, start: 0.06, length: 0.25, gain: 0.7)], length: 0.33, decay: 16),
    "hover": render([Tone(freq: 2900, start: 0, length: 0.03, gain: 1)], length: 0.035, decay: 120),
    "error": render([Tone(freq: 311, start: 0, length: 0.16, gain: 1),
                     Tone(freq: 233, start: 0.09, length: 0.18, gain: 1)], length: 0.3, decay: 14),
]

let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for (name, s) in sounds {
    try wav(s).write(to: dir.appendingPathComponent(name + ".wav"))
    print("wrote \(name).wav (\(s.count * 2 / 1024) KB)")
}
