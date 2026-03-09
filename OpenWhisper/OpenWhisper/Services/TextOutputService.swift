import Cocoa
import Carbon.HIToolbox

final class TextOutputService {

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Append text at the current cursor position (no deletion).
    func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        usleep(50_000)
        simulatePaste()
    }

    /// Replace previously streamed text with the final transcription result.
    /// Deletes all old characters and pastes the final text.
    func replaceText(old: String, with new: String) {
        guard !old.isEmpty || !new.isEmpty else { return }
        if old == new { return } // Already correct

        // Delete all streamed text
        if !old.isEmpty {
            sendBackspaces(count: old.count)
            usleep(UInt32(max(20_000, old.count * 1_000)))
        }

        // Paste final result
        if !new.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(new, forType: .string)
            usleep(50_000)
            simulatePaste()
        }
    }

    /// Delete `count` characters by sending backspace events.
    func deleteCharacters(_ count: Int) {
        guard count > 0 else { return }
        sendBackspaces(count: count)
    }

    func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.simulatePaste()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: UInt16(kVK_ANSI_V),
            keyDown: true
        ) else { return }
        keyDown.flags = .maskCommand

        guard let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: UInt16(kVK_ANSI_V),
            keyDown: false
        ) else { return }
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(10_000)
        keyUp.post(tap: .cghidEventTap)
    }

    private func sendBackspaces(count: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)

        for _ in 0..<count {
            guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: UInt16(kVK_Delete),
                keyDown: true
            ) else { continue }

            guard let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: UInt16(kVK_Delete),
                keyDown: false
            ) else { continue }

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            usleep(1_000) // 1ms between backspaces
        }
    }
}
