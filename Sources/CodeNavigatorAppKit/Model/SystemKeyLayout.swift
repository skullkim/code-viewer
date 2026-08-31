import Carbon
import Foundation

/// Translates a physical key into the letter it carries on a Latin layout (REQ-014).
///
/// Asks the system for its **ASCII-capable** layout rather than naming one: hardcoding
/// `com.apple.keylayout.ABC` fails on a machine whose Latin layout is Dvorak or a national
/// variant, and failing there means Vim's command keys stay broken with no sign of why.
///
/// This reads the input source; it never selects one. That is the whole difference between
/// this approach and the one it replaced — no global state is changed, so none can be left
/// behind when the process dies.
public enum SystemKeyLayout {

    /// The Latin character for a key code, or nil when the layout has no answer.
    public static func latinCharacter(forKeyCode keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return errSecParam
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDown),
                // Modifiers are deliberately zero: the notation layer applies Shift and the
                // chord prefixes itself, so this asks only "which key is this".
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else {
            return nil
        }
        return String(utf16CodeUnits: characters, count: length)
    }
}
