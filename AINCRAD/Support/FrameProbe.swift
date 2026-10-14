import AppKit
import QuartzCore

/// Samples the display link briefly after an animation starts and logs frame pacing.
/// It sees main-thread vsync callbacks, so it is a proxy: hitches inside WindowServer are not visible here.
final class FrameProbe: NSObject {
    private var link: CADisplayLink?
    private var stamps: [CFTimeInterval] = []
    private var started: CFTimeInterval = 0
    private var label = ""
    private var expected: Double = 1.0 / 60

    func run(on screen: NSScreen, label: String, seconds: Double = 0.6) {
        stop()
        self.label = label
        stamps = []
        started = CACurrentMediaTime()
        expected = 1.0 / Double(max(screen.maximumFramesPerSecond, 1))
        let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.finish() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        stamps.append(CACurrentMediaTime())
    }

    private func finish() {
        defer { stop() }
        guard stamps.count > 2, let first = stamps.first else { return }
        let intervals = zip(stamps.dropFirst(), stamps).map { $0 - $1 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let worst = intervals.max() ?? 0
        let late = intervals.filter { $0 > expected * 1.5 }.count
        Log.info(String(format: "frames[%@]: first callback +%.1f ms, %d frames, mean %.1f ms, worst %.1f ms, %d late (target %.1f ms)",
                        label, (first - started) * 1000, intervals.count, mean * 1000, worst * 1000, late, expected * 1000))
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }
}
