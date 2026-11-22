import AppKit
import SwiftUI

// Explicitly select the DynamicProperty wrapper on SDKs that also expose a State macro.
typealias LocalState<Value> = SwiftUI.State<Value>

enum AppTheme {
    // CubeBit's exact palette. Rust is reserved for primary actions; sky carries highlights & metrics.
    static let navyHex = "132A45"
    static let deepNavyHex = "0D1F35"
    static let rustHex = "B0552E"
    static let skyHex = "7FB3DA"
    static let navy = Color(hex: 0x132A45)
    static let deepNavy = Color(hex: 0x0D1F35)
    static let rust = Color(hex: 0xB0552E)
    static let sky = Color(hex: 0x7FB3DA)
    static let accentText = sky
    static let text = Color(red: 0.95, green: 0.95, blue: 0.93)
    static let secondary = Color(red: 0.68, green: 0.74, blue: 0.79)
    static let muted = Color(red: 0.58, green: 0.65, blue: 0.71)
    static let hairline = Color.white.opacity(0.08)
    static let surface = Color.white.opacity(0.04)
    static let surfaceHover = Color.white.opacity(0.065)
    static let positive = Color(red: 0.45, green: 0.80, blue: 0.62)
    static let warning = Color(red: 0.90, green: 0.65, blue: 0.35)
    static let browserHeight: CGFloat = 440
    static let stackHeight: CGFloat = 496

    @MainActor static func prepare(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard [6, 8].contains(clean.count), let n = UInt64(clean, radix: 16) else { return nil }
        let value = clean.count == 8 ? n >> 8 : n
        self.init(
            srgbRed: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255,
            alpha: clean.count == 8 ? Double(n & 255) / 255 : 1
        )
    }
}

private struct NativeGlass: NSViewRepresentable {
    var radius: CGFloat
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.layer?.cornerRadius = radius
        view.layer?.masksToBounds = true
    }
}

struct GlassBackground: View {
    var radius: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if !reduceTransparency { NativeGlass(radius: radius) }
            AppTheme.navy.opacity(reduceTransparency ? 1 : 0.72)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FlatButtonStyle: ButtonStyle {
    var primary = false
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11.5 : 12, weight: primary ? .semibold : .medium))
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 6.5 : 9)
            .foregroundStyle(primary ? Color.white : AppTheme.text)
            .background(
                primary
                    ? AppTheme.rust
                    : Color.white.opacity(configuration.isPressed ? 0.11 : 0.06),
                in: Capsule()
            )
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.82 : 1)
    }
}

struct ChromeButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @LocalState private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovered ? AppTheme.text : AppTheme.secondary)
                .frame(width: 28, height: 28)
                .background(.white.opacity(hovered ? 0.08 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovered = $0 }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(AppTheme.hairline).frame(height: 1).accessibilityHidden(true)
    }
}

struct ChoiceMenu<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(String, Value)]
    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                Button { selection = options[index].1 } label: {
                    if selection == options[index].1 { Label(options[index].0, systemImage: "checkmark") }
                    else { Text(options[index].0) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first(where: { $0.1 == selection })?.0 ?? "Custom")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(AppTheme.muted)
            }
            .font(.system(size: 13))
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
    }
}

struct ShortcutHint: View {
    let keys: String
    let label: String
    var body: some View {
        HStack(spacing: 5) {
            Text(keys).font(.system(size: 11, weight: .medium, design: .monospaced))
            Text(label).font(.system(size: 11))
        }.foregroundStyle(AppTheme.muted)
    }
}

struct StepRow<V: Strideable & Comparable>: View where V.Stride: SignedNumeric {
    let title: String
    let value: String
    @Binding var number: V
    let range: ClosedRange<V>
    let step: V.Stride
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13)).foregroundStyle(AppTheme.text)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 13)).monospacedDigit().foregroundStyle(AppTheme.sky)
            HStack(spacing: 0) {
                stepButton("minus", enabled: isEnabled && number > range.lowerBound) {
                    number = max(range.lowerBound, number.advanced(by: -step))
                }
                Rectangle().fill(AppTheme.hairline).frame(width: 1, height: 14)
                stepButton("plus", enabled: isEnabled && number < range.upperBound) {
                    number = min(range.upperBound, number.advanced(by: step))
                }
            }
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .opacity(isEnabled ? 1 : 0.45)
        .padding(.vertical, 6)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? AppTheme.text : AppTheme.muted.opacity(0.5))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct ToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(AppTheme.text)
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(AppTheme.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(AppTheme.rust)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .padding(.vertical, 5)
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(AppTheme.text)
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(AppTheme.secondary).lineSpacing(3)
            }
        }
        .padding(.bottom, 10)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(AppTheme.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.white.opacity(0.055), in: Capsule())
    }
}

/// CubeBit geometric monogram mark for Gary Tools (matches the app icon).
struct GaryBrandMark: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(AppTheme.deepNavy)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(AppTheme.sky.opacity(0.35), lineWidth: max(0.75, size * 0.035))
                )
            // Architectural "G" mark: 3 sky geometric segments + 1 rust action node
            Canvas { ctx, sz in
                let s = sz.width / 32
                let sky = GraphicsContext.Shading.color(AppTheme.sky)
                let rust = GraphicsContext.Shading.color(AppTheme.rust)
                // Top bar
                ctx.fill(Path(roundedRect: CGRect(x: 7 * s, y: 7 * s, width: 18 * s, height: 4.5 * s), cornerRadius: 2.2 * s), with: sky)
                // Left pillar
                ctx.fill(Path(roundedRect: CGRect(x: 7 * s, y: 7 * s, width: 4.5 * s, height: 18 * s), cornerRadius: 2.2 * s), with: sky)
                // Bottom bar
                ctx.fill(Path(roundedRect: CGRect(x: 7 * s, y: 20.5 * s, width: 18 * s, height: 4.5 * s), cornerRadius: 2.2 * s), with: sky)
                // Right lower leg
                ctx.fill(Path(roundedRect: CGRect(x: 20.5 * s, y: 14.5 * s, width: 4.5 * s, height: 10.5 * s), cornerRadius: 2.2 * s), with: sky)
                // Rust crossbar / precision node
                ctx.fill(Path(roundedRect: CGRect(x: 15 * s, y: 14.5 * s, width: 10 * s, height: 4.5 * s), cornerRadius: 2.2 * s), with: rust)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Notification.Name {
    static let focusPasteSearch = Notification.Name("local.nicegary.garytools.focusSearch")
    static let settingsChanged = Notification.Name("local.nicegary.garytools.settingsChanged")
}
