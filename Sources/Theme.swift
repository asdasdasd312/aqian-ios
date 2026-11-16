import SwiftUI
import Foundation

/// 一间屋子的光。夜是屋子自己的暖灯，昼是窗边的纸感，中间过一档黄昏。
/// 跨明暗不要在 RGB 直线插值——会插出一片灰；所以走 夜 → 黄昏 → 昼 两段。

struct RGB {
    var r: Double, g: Double, b: Double
    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
    }
    var color: Color { Color(red: r, green: g, blue: b) }
    func mix(_ o: RGB, _ u: Double) -> RGB {
        RGB.raw(r + (o.r - r) * u, g + (o.g - g) * u, b + (o.b - b) * u)
    }
    static func raw(_ r: Double, _ g: Double, _ b: Double) -> RGB {
        var v = RGB(0); v.r = r; v.g = g; v.b = b; return v
    }
}

struct Tok {
    var bg: RGB, her: RGB, me: RGB, accent: RGB, txt: RGB, dim: RGB, line: RGB, card: RGB, glow: RGB
    var gx: Double, gy: Double, ga: Double
}

enum Palettes {
    static let night = Tok(
        bg: RGB(0x0b0f14), her: RGB(0x131b26), me: RGB(0x1b2836),
        accent: RGB(0xffb877), txt: RGB(0xdbe6f2), dim: RGB(0x8fa2b8),
        line: RGB(0x1e2a38), card: RGB(0x111823), glow: RGB(0xffb877),
        gx: 76, gy: 14, ga: 0.16)

    static let dusk = Tok(
        bg: RGB(0x2a1d17), her: RGB(0x2c211a), me: RGB(0x33261d),
        accent: RGB(0xff9a5c), txt: RGB(0xf0e2d0), dim: RGB(0xb09a86),
        line: RGB(0x3a2b22), card: RGB(0x241a15), glow: RGB(0xff9a5c),
        gx: 66, gy: 4, ga: 0.42)

    static let day = Tok(
        bg: RGB(0xf4efe6), her: RGB(0xfffaf0), me: RGB(0xefe3cd),
        accent: RGB(0x8a6a46), txt: RGB(0x332e27), dim: RGB(0x7d7263),
        line: RGB(0xe2d5c2), card: RGB(0xefe7d8), glow: RGB(0xffd6a0),
        gx: 50, gy: 0, ga: 0.30)

    /// t: 0 = 夜, 1 = 昼
    static func at(_ t: Double) -> Tok {
        let u = min(max(t, 0), 1)
        let a: Tok, b: Tok, k: Double
        if u < 0.5 { a = night; b = dusk; k = u * 2 } else { a = dusk; b = day; k = (u - 0.5) * 2 }
        return Tok(
            bg: a.bg.mix(b.bg, k), her: a.her.mix(b.her, k), me: a.me.mix(b.me, k),
            accent: a.accent.mix(b.accent, k), txt: a.txt.mix(b.txt, k), dim: a.dim.mix(b.dim, k),
            line: a.line.mix(b.line, k), card: a.card.mix(b.card, k), glow: a.glow.mix(b.glow, k),
            gx: a.gx + (b.gx - a.gx) * k, gy: a.gy + (b.gy - a.gy) * k, ga: a.ga + (b.ga - a.ga) * k)
    }
}

/// 主题档位：自动（跟屋子的钟）/ 白天 / 夜里
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var t: Double = 0          // 0 夜 → 1 昼
    @Published var mode: String = "auto" { didSet { save() } }
    @Published private(set) var roomHour: Int = -1     // 屋子里现在几点（-1 表示还没问到）

    private var timer: Timer?
    private var target: Double = 0
    private let duration: Double = 1.2

    var palette: Tok { Palettes.at(t) }
    var isDay: Bool { t > 0.5 }

    init() {
        mode = UserDefaults.standard.string(forKey: "theme_mode") ?? "auto"
    }

    private func save() { UserDefaults.standard.set(mode, forKey: "theme_mode") }

    /// 屋子里几点：昼 = 06:30–18:30
    static func dayBy(hour: Int, minute: Int = 0) -> Bool {
        let m = hour * 60 + minute
        return m >= 6 * 60 + 30 && m < 18 * 60 + 30
    }

    func setRoomHour(_ h: Int) {
        roomHour = h
        if mode == "auto" { retarget(Self.dayBy(hour: h) ? 1 : 0) }
    }

    func setMode(_ m: String) {
        mode = m
        switch m {
        case "day": retarget(1)
        case "night": retarget(0)
        default:
            let h = roomHour >= 0 ? roomHour : Calendar.current.component(.hour, from: Date())
            retarget(Self.dayBy(hour: h) ? 1 : 0)
        }
    }

    /// 只在真的换档时走一遍；减弱动态效果时直接跳。
    func retarget(_ v: Double) {
        guard abs(v - target) > 0.001 || timer == nil else { return }
        target = v
        guard !UIAccessibility.isReduceMotionEnabled else {
            timer?.invalidate(); timer = nil; t = v; return
        }
        timer?.invalidate()
        let start = t, delta = v - start
        let steps = max(1, Int(duration * 60))
        var i = 0
        timer = Timer.scheduledTimer(withTimeInterval: duration / Double(steps), repeats: true) { [weak self] tm in
            guard let self else { tm.invalidate(); return }
            i += 1
            let k = Double(i) / Double(steps)
            // 稍微 ease-in-out 一点，起落不生硬
            let e = k < 0.5 ? 2 * k * k : 1 - pow(-2 * k + 2, 2) / 2
            self.t = min(max(start + delta * e, 0), 1)
            if i >= steps { tm.invalidate(); self.timer = nil; self.t = v }
        }
    }
}
