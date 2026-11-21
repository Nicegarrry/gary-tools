import AppKit
import SwiftUI

enum Theme {
    // CubeBit's exact palette. Rust is reserved for actions; sky carries small text highlights.
    static let navyHex = "132A45"
    static let rustHex = "B0552E"
    static let skyHex = "7FB3DA"
    static let navy = Color(hex: 0x132A45)
    static let rust = Color(hex: 0xB0552E)
    static let sky = Color(hex: 0x7FB3DA)
    static let accentText = sky
    static let text = Color(red: 0.95, green: 0.95, blue: 0.93)
    static let secondary = Color(red: 0.68, green: 0.74, blue: 0.79)
    static let muted = Color(red: 0.58, green: 0.65, blue: 0.71)
    static let hairline = Color.white.opacity(0.08)

    static func prepare(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
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
    var radius: CGFloat = 24
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if !reduceTransparency { NativeGlass(radius: radius) }
            Theme.navy.opacity(reduceTransparency ? 1 : 0.68)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FlatButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: primary ? .semibold : .medium))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundStyle(primary ? Color.white : Theme.text)
            .background(primary ? Theme.rust : Color.white.opacity(configuration.isPressed ? 0.10 : 0.055), in: Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.8 : 1)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1).accessibilityHidden(true) }
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
            HStack(spacing: 9) {
                Text(options.first(where: { $0.1 == selection })?.0 ?? "Custom")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.muted)
            }.font(.system(size: 13)).foregroundStyle(Theme.text)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(label)
    }
}

// Select the property wrapper explicitly on SDKs that also expose a State macro.
typealias LocalState<Value> = SwiftUI.State<Value>

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}
