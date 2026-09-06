/// The Lua the session runs for syntax colour and same-symbol highlighting (REQ-016).
enum NeovimHighlightScript {

    /// The highlight group the same-symbol match uses. Ours, so nothing else redefines it.
    static let sameSymbolGroup = "CodeNavigatorSameSymbol"

    /// Applies the palette, and keeps applying it.
    ///
    /// Two things here are load-bearing:
    ///
    /// 1. The palette is stored in a Lua global and applied by a function, rather than applied
    ///    once inline. A user's `colorscheme` command re-defines every group it touches, and it
    ///    can run at any time — so the `ColorScheme` autocommand re-runs this and lands *after*
    ///    it. Without that, REQ-016 AC-6 holds only until the user's configuration changes theme.
    /// 2. Groups are set with `link = ''`-breaking explicit attributes. Neovim's standard groups
    ///    are mostly links (`Keyword → Statement`, `String → Constant`); setting a colour on the
    ///    link target alone would leave the linked names pointing elsewhere.
    static func applyPaletteScript(notificationName: String) -> String {
        """
        local palette = ...
        vim.g.code_navigator_palette = palette

        local function applyPalette()
          local colours = vim.g.code_navigator_palette
          if colours == nil then
            return
          end

          -- Standard Vim groups. Measured, the bundled syntax files for Java, Kotlin and
          -- TypeScript all resolve into these, so colouring them colours every supported language.
          local groupsByColour = {
            [colours.keyword]  = { 'Statement', 'Keyword', 'Conditional', 'Repeat', 'StorageClass', 'Operator', 'Exception', 'Label' },
            [colours.type]     = { 'Type', 'Structure', 'Typedef' },
            [colours.functionName] = { 'Function' },
            [colours.string]   = { 'String', 'Character' },
            -- `Constant` 를 숫자와 같은 값으로 바른다. Vim 기본에서 String·Number·Boolean·
            -- Character 가 전부 Constant 에 링크돼 있어서(그래서 Java 측정이 Comment·Constant·
            -- Type 셋만 봤다), String·Number 에 각각 색을 주면 그 링크가 끊긴다. 남는
            -- boolean·문자 리터럴은 "리터럴 값"이라 숫자와 한 가족이다.
            [colours.number]   = { 'Number', 'Boolean', 'Float', 'Constant' },
            [colours.comment]  = { 'Comment' },
          }
          for colour, groups in pairs(groupsByColour) do
            for _, group in ipairs(groups) do
              vim.api.nvim_set_hl(0, group, { fg = colour })
            end
          end

          -- 키워드는 색만으로 부족하다. 실측: nvim 기본에서 키워드 색이 기본 전경색과 같았고
          -- (ΔE 0), 색 하나로만 고치면 색각·저채도 화면에서 다시 같아진다.
          vim.api.nvim_set_hl(0, 'Statement', { fg = colours.keyword, bold = colours.keywordIsBold })
          vim.api.nvim_set_hl(0, 'Keyword', { fg = colours.keyword, bold = colours.keywordIsBold })

          -- 평문은 "색 없음"이 아니라 **평문 색으로 정해진 것**이어야 한다. 비워 두면 사용자
          -- colorscheme 이 그 자리에 우리가 고르지 않은 색을 넣는다 (AC-6).
          vim.api.nvim_set_hl(0, 'Identifier', { fg = colours.normalForeground })
          vim.api.nvim_set_hl(0, 'Normal', {
            fg = colours.normalForeground, bg = colours.normalBackground,
          })

          -- 거터. 안 바르면 nvim 기본 #4F5258 이 남고 우리 배경 위에서 2.19:1 이다 —
          -- §4.5 바닥의 절반이고, 우리가 Normal 배경을 덮으면서 오히려 나빠진 값이다.
          -- tree-sitter 캡처. 정규식 문법은 클래스 이름·메서드 이름·애노테이션을 아예
          -- 분류하지 않아서(실측: Java 는 Comment·Constant·Type 셋뿐) 그 자리가 평문으로
          -- 남았다. 파서가 붙은 언어에서는 이 그룹들이 그 자리를 채운다.
          local treeSitterGroups = {
            [colours.type]         = { '@type', '@type.definition', '@constructor' },
            [colours.functionName] = { '@function', '@function.method', '@function.call', '@method' },
            [colours.annotation]   = { '@attribute' },
            [colours.number]       = { '@constant', '@number', '@boolean' },
            [colours.keyword]      = { '@keyword', '@keyword.function', '@keyword.return' },
            [colours.string]       = { '@string' },
            [colours.comment]      = { '@comment' },
            [colours.normalForeground] = { '@variable', '@property', '@parameter' },
          }
          for colour, groups in pairs(treeSitterGroups) do
            for _, group in ipairs(groups) do
              vim.api.nvim_set_hl(0, group, { fg = colour })
            end
          end
          vim.api.nvim_set_hl(0, '@keyword', { fg = colours.keyword, bold = colours.keywordIsBold })

          vim.api.nvim_set_hl(0, 'LineNr', { fg = colours.lineNumber })
          vim.api.nvim_set_hl(0, 'CursorLineNr', { fg = colours.currentLineNumber, bold = true })

          vim.api.nvim_set_hl(0, '\(sameSymbolGroup)', { bg = colours.sameSymbolBackground })
          vim.api.nvim_set_hl(0, 'Visual', { bg = colours.selectionBackground })
        end

        _G.code_navigator_apply_palette = applyPalette
        applyPalette()

        -- A colourscheme change wipes every group it defines. Re-apply after it, so the
        -- application's theme is what the user ends up looking at (AC-6).
        vim.api.nvim_create_augroup('CodeNavigatorPalette', { clear = true })
        vim.api.nvim_create_autocmd('ColorScheme', {
          group = 'CodeNavigatorPalette',
          callback = applyPalette,
        })

        return '\(notificationName)'
        """
    }

    /// Turns syntax off for files in languages this application does not support (AC-4).
    ///
    /// Runs on `FileType` for files opened later, and over the already-open buffers once, because
    /// the session may have opened files before this was installed.
    static func installAllowListScript(allowedFileTypes: [String]) -> String {
        let allowedList = allowedFileTypes.map { "['\($0)'] = true" }.joined(separator: ", ")
        return """
        local allowed = { \(allowedList) }

        local function applyAllowList(buffer)
          local fileType = vim.bo[buffer].filetype
          if allowed[fileType] then
            return
          end
          -- Not "colour it differently" — no colour at all. A supported-looking file whose
          -- `gd` does nothing is worse than a plain one (AC-4, SC-13).
          vim.bo[buffer].syntax = 'OFF'
        end

        vim.api.nvim_create_augroup('CodeNavigatorAllowList', { clear = true })
        vim.api.nvim_create_autocmd({ 'FileType' }, {
          group = 'CodeNavigatorAllowList',
          callback = function(arguments) applyAllowList(arguments.buf) end,
        })

        for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buffer) then
            applyAllowList(buffer)
          end
        end

        return 'installed'
        """
    }

    /// Highlights every other occurrence of the symbol under the cursor, within the file (AC-2).
    ///
    /// `matchadd` is window-local, which suits this exactly: the highlight belongs to what is on
    /// screen, not to the buffer, and it survives no longer than the window does.
    ///
    /// The previous match is deleted before a new one is added. Without that the highlights
    /// accumulate and every symbol the cursor has ever rested on stays lit — which reads as
    /// "everything is highlighted", i.e. as a broken feature rather than a missing one.
    static func installSameSymbolHighlightScript(allowedFileTypes: [String]) -> String {
        let allowedList = allowedFileTypes.map { "['\($0)'] = true" }.joined(separator: ", ")
        return """
        local allowed = { \(allowedList) }

        local function clearExistingMatch()
          local existing = vim.w.code_navigator_same_symbol_match
          if existing ~= nil then
            pcall(vim.fn.matchdelete, existing)
            vim.w.code_navigator_same_symbol_match = nil
          end
        end

        local function highlightSymbolUnderCursor()
          clearExistingMatch()

          if not allowed[vim.bo.filetype] then
            return
          end

          -- Only where the cursor actually sits on code. `<cword>` happily reports a word
          -- inside a comment or a string literal, and AC-2 is about **symbols** — lighting up
          -- every occurrence of an ordinary English word because the cursor rested in a comment
          -- reads as a broken highlight, not a helpful one.
          local position = vim.api.nvim_win_get_cursor(0)
          local syntaxGroup = vim.fn.synIDattr(
            vim.fn.synIDtrans(vim.fn.synID(position[1], position[2] + 1, 1)), 'name'
          )
          -- 심볼이 아닌 것들. 실측(2026-09-01, TypeScript·Java)으로 갈랐다:
          --   class·const·function → Statement · string → Type   (전부 키워드)
          --   UserService → typescriptClassName · beta → Function · gamma → PreProc  (전부 심볼)
          -- 리터럴·주석만 막았을 때는 커서를 `const` 에 두면 파일의 모든 `const` 에 불이 켜졌다.
          -- AC-2 의 낱말은 **심볼**이고 키워드는 심볼이 아니다.
          local nonSymbolGroups = {
            -- 리터럴과 주석
            Comment = true, String = true, Character = true,
            Number = true, Float = true, Boolean = true, Constant = true,
            -- 언어 키워드. Java 는 public·private·class 가, TypeScript 는 string 이 Type 으로
            -- 떨어진다 — 사용자가 지은 이름은 언어별 그룹(typescriptClassName 등)이나 무그룹이라
            -- Type 을 막아도 클래스 이름을 잃지 않는다.
            Statement = true, Keyword = true, Conditional = true, Repeat = true,
            Label = true, Exception = true, Operator = true,
            StorageClass = true, Structure = true, Typedef = true, Type = true,
          }
          if nonSymbolGroups[syntaxGroup] then
            return
          end

          local word = vim.fn.expand('<cword>')
          -- Only identifiers. Punctuation under the cursor would otherwise light up every
          -- bracket in the file.
          if word == '' or word:match('^[%a_][%w_]*$') == nil then
            return
          end

          local pattern = [[\\<]] .. vim.fn.escape(word, [[\\]]) .. [[\\>]]
          vim.w.code_navigator_same_symbol_match =
            vim.fn.matchadd('\(sameSymbolGroup)', pattern, -1)
        end

        vim.api.nvim_create_augroup('CodeNavigatorSameSymbol', { clear = true })
        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufEnter', 'WinEnter' }, {
          group = 'CodeNavigatorSameSymbol',
          callback = highlightSymbolUnderCursor,
        })

        highlightSymbolUnderCursor()
        return 'installed'
        """
    }

    /// Points Neovim at the parsers the application ships, and turns tree-sitter on for the
    /// languages that have one (REQ-016 AC-1).
    ///
    /// Neovim installs six parsers and none of them are languages this application indexes, so
    /// without this the editor falls back to regex syntax files. Those cannot tell a class name
    /// from a variable — measured, Java resolves into `Comment`, `Constant` and `Type` and
    /// nothing else, which is why class and method names rendered as plain text.
    ///
    /// The runtime path is *prepended* so a user who has their own parser for the same language
    /// keeps it: the application supplies what is missing rather than replacing what is there
    /// (INV-7).
    ///
    /// Starting is per-buffer and guarded. `vim.treesitter.start` throws for a language with no
    /// parser, and a throw here would leave the buffer with no highlighting at all — worse than
    /// the regex fallback it was meant to improve on. So a failure quietly leaves the regex path
    /// in place, which is exactly what Kotlin does today.
    static func installTreeSitterScript(runtimePath: String, languages: [String]) -> String {
        let languageList = languages.map { "['\($0)'] = true" }.joined(separator: ", ")
        return """
        local bundled = { \(languageList) }
        -- `vim.opt` 가 목록 항목의 이스케이프를 처리한다. 직접 escape 를 부르면 Swift 문자열
        -- 리터럴을 한 겹 더 지나며 역슬래시가 어긋나고, 그 결과는 **조용히 실패하는 Lua** 다.
        vim.opt.runtimepath:prepend([[\(runtimePath)]])

        local function startTreeSitter(buffer)
          local language = vim.bo[buffer].filetype
          if not bundled[language] then
            return
          end
          -- 실패해도 조용히 정규식 경로를 남긴다. 여기서 예외가 나면 그 버퍼는 강조가
          -- 아예 없어지는데, 그건 고치려던 것보다 나쁘다.
          pcall(vim.treesitter.start, buffer, language)
        end

        vim.api.nvim_create_augroup('CodeNavigatorTreeSitter', { clear = true })
        vim.api.nvim_create_autocmd('FileType', {
          group = 'CodeNavigatorTreeSitter',
          callback = function(arguments) startTreeSitter(arguments.buf) end,
        })

        for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buffer) then
            startTreeSitter(buffer)
          end
        end

        return 'installed'
        """
    }

}
