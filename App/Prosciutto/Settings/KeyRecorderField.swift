import SwiftUI
import AppKit

/// A click-to-record shortcut field. Requires at least one modifier (so plain
/// typing can't be captured). Esc cancels; ⌫ clears to ⌘⇧V-less empty (keeps the
/// previous value). Reports the recorded chord via the binding.
struct KeyRecorderField: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderButton {
        let v = RecorderButton()
        v.onRecord = { combo = $0 }
        v.combo = combo
        return v
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.combo = combo
        nsView.onRecord = { combo = $0 }   // keep the binding write-through fresh
    }

    final class RecorderButton: NSButton {
        var onRecord: ((KeyCombo) -> Void)?
        var combo = KeyCombo(keyCode: 9, modifiers: [.command, .shift]) { didSet { refresh() } }
        private var recording = false { didSet { refresh() } }
        private var monitor: Any?

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(toggleRecording)
            refresh()
        }
        required init?(coder: NSCoder) { fatalError() }

        private func refresh() {
            title = recording ? "Type shortcut…  (esc to cancel)" : combo.displayString
        }

        @objc private func toggleRecording() {
            recording ? stop() : start()
        }

        private func start() {
            recording = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event)
                return nil   // swallow while recording
            }
        }

        private func stop() {
            recording = false
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            if event.keyCode == UInt16(53) { stop(); return }   // esc cancels
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains(.command) || mods.contains(.option)
                  || mods.contains(.control) else { return }    // need a modifier
            let new = KeyCombo(keyCode: event.keyCode, modifiers: mods)
            combo = new
            onRecord?(new)
            stop()
        }
    }
}
