import Foundation

/// The Lua that turns Neovim into a standard macOS-style editor, and back (REQ-010).
///
/// Standard mode is expressed as Neovim options and mappings rather than as an app-side
/// translation table. That choice is what keeps REQ-010 AC-4 true for free: the buffer, the undo
/// history and the dirty flag never move, because nothing but the interpretation of keys changes.
///
/// It is also the only way AC-5 holds honestly. For `i`, `:` and `hjkl` to be *typed characters*,
/// Neovim has to actually be in insert mode — an app-side table would have to track and mirror
/// editor mode to fake it, which is the state fork REQ-010 exists to forbid.
enum NeovimStandardMode {

    /// Command-key shortcuts, mapped to what they mean in insert mode.
    ///
    /// `<C-o>` runs one normal-mode command and returns to insert, so each mapping is a single
    /// undo-able action that leaves the user back where they were typing.
    static let commandShortcuts: [(key: String, action: String)] = [
        ("<D-s>", "<C-o>:write<CR>"),
        ("<D-z>", "<C-o>u"),
        ("<D-S-z>", "<C-o><C-r>"),
        ("<D-a>", "<C-o>ggVG"),
        ("<D-c>", "<C-o>\"+y"),
        ("<D-x>", "<C-o>\"+d"),
        ("<D-v>", "<C-o>\"+P"),
        ("<D-Left>", "<Home>"),
        ("<D-Right>", "<End>"),
        ("<D-Up>", "<C-o>gg"),
        ("<D-Down>", "<C-o>G"),
        ("<M-Left>", "<C-Left>"),
        ("<M-Right>", "<C-Right>"),
    ]

    /// Enters standard mode.
    ///
    /// `keymodel=startsel,stopsel` with `selectmode=key` is Neovim's own shift-to-select
    /// behaviour — the same machinery `:behave mswin` uses — so selection stays Neovim's model
    /// rather than a second one we would have to keep in sync.
    static var enterScript: String {
        var lines = [
            "vim.o.keymodel = 'startsel,stopsel'",
            "vim.o.selectmode = 'key'",
            "vim.o.selection = 'exclusive'",
            "vim.o.virtualedit = 'onemore'",
        ]
        for shortcut in commandShortcuts {
            lines.append(mappingStatement(mode: "i", key: shortcut.key, action: shortcut.action))
            lines.append(mappingStatement(mode: "s", key: shortcut.key, action: "<Esc>" + shortcut.action))
        }
        // Typing must insert, so the session ends up in insert mode and stays there.
        lines.append("if vim.fn.mode() ~= 'i' then vim.cmd('startinsert') end")
        return lines.joined(separator: "\n")
    }

    /// Returns to Vim mode, removing everything `enterScript` added.
    static var exitScript: String {
        var lines = [
            "vim.o.keymodel = ''",
            "vim.o.selectmode = ''",
            "vim.o.selection = 'inclusive'",
            "vim.o.virtualedit = ''",
        ]
        for shortcut in commandShortcuts {
            lines.append("pcall(vim.keymap.del, 'i', '\(shortcut.key)')")
            lines.append("pcall(vim.keymap.del, 's', '\(shortcut.key)')")
        }
        lines.append("if vim.fn.mode() == 'i' then vim.cmd('stopinsert') end")
        return lines.joined(separator: "\n")
    }

    private static func mappingStatement(mode: String, key: String, action: String) -> String {
        let escapedAction = action.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "vim.keymap.set('\(mode)', '\(key)', '\(escapedAction)', { noremap = true, silent = true })"
    }
}
