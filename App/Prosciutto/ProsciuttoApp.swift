import SwiftUI

@main
struct ProsciuttoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var env = AppEnvironment.shared

    init() { FontRegistrar.registerBundledFonts() }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(env: env)
        } label: {
            HamBarLabel(env: env)
        }

        Settings {
            SettingsView()
                .environmentObject(env.theme)
        }
    }
}

/// Menu-bar ham. Eases through a pink pulse on each capture.
private struct HamBarLabel: View {
    // Observed (not a value) so the label re-renders as `pulseLevel` ticks —
    // MenuBarExtra doesn't reliably re-evaluate the enclosing scene.
    @ObservedObject var env: AppEnvironment
    var body: some View {
        // MenuBarExtra re-rasterizes the status image on content change but ignores
        // live opacity/transform, so we feed a fresh pre-composited frame each tick.
        if env.pulseLevel <= 0 {
            Image("HamBar").renderingMode(.template)   // idle: native template tinting
        } else {
            Image(nsImage: HamBarRenderer.frame(level: env.pulseLevel))
        }
    }
}

/// One crossfade frame: template silhouette recoloured to the menu-bar tint, with the
/// pink ham drawn over at `level` opacity (0 = white/black ham, 1 = full pink).
private enum HamBarRenderer {
    static let base = NSImage(named: "HamBar")!
    static let pink = NSImage(named: "HamBarPink")!

    static func frame(level: CGFloat) -> NSImage {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let out = NSImage(size: base.size)
        out.lockFocus()
        let rect = NSRect(origin: .zero, size: base.size)
        base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        (dark ? NSColor.white : .black).set()
        rect.fill(using: .sourceAtop)                  // recolour silhouette to tint
        pink.draw(in: rect, from: .zero, operation: .sourceOver, fraction: level)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }
}

private struct MenuContent: View {
    @ObservedObject var env: AppEnvironment
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Prosciutto") { env.openGallery() }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        Divider()
        if env.pasteIsInstalled {
            Button("Import from Paste…") { env.importFromPaste() }
            Divider()
        }
        Button(env.isPaused ? "Resume Capture" : "Pause Capture") { env.togglePause() }
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit Prosciutto") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
