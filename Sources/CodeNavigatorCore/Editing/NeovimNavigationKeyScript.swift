/// The Lua the session runs to wire `gd` and `gr` (REQ-015).
///
/// Kept apart from the session so the text can be read as text. Lua embedded in Swift string
/// interpolation is hard enough to read without the surrounding actor.
enum NeovimNavigationKeyScript {

    /// Neovim's own `gr`-prefixed defaults, all of which call `vim.lsp.buf.*`.
    ///
    /// They matter because they make plain `gr` **ambiguous**: Neovim must wait a full
    /// `timeoutlen` to learn no second key is coming. Measured, that is 1,032ms before `gr`
    /// does anything — for a key whose whole point is to be quick.
    static let editorDefaultPrefixedKeys = ["grr", "gra", "gri", "grn", "grt", "grx"]

    /// Asks who holds a key. Returns `present|scriptIdentifier|scriptPath`, with the path's
    /// symbolic links resolved.
    ///
    /// The resolution happens here rather than in Swift because the comparison it feeds is a
    /// prefix test against Neovim's runtime path, and the two sides must be spelled the same way.
    /// Measured, they are not by default: `/var/…` from one call and `/private/var/…` from
    /// another, for one file.
    static func mappingReportScript(keys: String) -> String {
        """
        local mapping = vim.fn.maparg('\(keys)', 'n', false, true)
        if vim.tbl_isempty(mapping) then
          return 'false|0|'
        end

        local scriptIdentifier = type(mapping.sid) == 'number' and mapping.sid or 0
        local scriptPath = ''
        if scriptIdentifier > 0 then
          local information = vim.fn.getscriptinfo({ sid = scriptIdentifier })[1]
          if information and information.name ~= '' then
            scriptPath = vim.uv.fs_realpath(information.name) or information.name
          end
        end

        return 'true|' .. scriptIdentifier .. '|' .. scriptPath
        """
    }

    /// Neovim's own runtime directory, with symbolic links resolved. Empty when unknown.
    static let runtimePathScript = """
    local runtime = vim.env.VIMRUNTIME or ''
    if runtime == '' then
      return ''
    end
    return vim.uv.fs_realpath(runtime) or runtime
    """

    /// Removes one of Neovim's own prefixed defaults, for this process only.
    ///
    /// Guarded by the same ownership test as the mapping itself: a `gr*` the *user* defined is
    /// left alone. `pcall` because deleting a mapping that is not there raises, and a missing
    /// default must not take the session down with it.
    static func deleteEditorDefaultScript(keys: String) -> String {
        """
        pcall(vim.keymap.del, 'n', '\(keys)')
        return 'deleted'
        """
    }

    /// Installs one mapping that notifies the application and does nothing else.
    ///
    /// The notification carries only which request it was. Everything else — what the word under
    /// the cursor is, whether it resolves, what to show when it resolves to several places — is
    /// the application's existing ⌘B path, and reusing it is what makes REQ-015 AC-1/AC-2 the
    /// *same* behaviour rather than a parallel one.
    static func installMappingScript(
        keys: String, request: String, notificationName: String
    ) -> String {
        """
        local channelIdentifier = ...
        vim.keymap.set('n', '\(keys)', function()
          vim.rpcnotify(channelIdentifier, '\(notificationName)', { request = '\(request)' })
        end, { desc = 'Code Navigator: \(request)' })
        return 'installed'
        """
    }
}
