/// The Lua the session runs for syntax colour and same-symbol highlighting (REQ-016).
enum NeovimHighlightScript {

    /// 우리가 색을 정해 주는 tree-sitter 캡처. **`@` 는 뺀 이름**이다.
    ///
    /// 위 Lua 의 `treeSitterGroups` 와 같은 목록이어야 한다. 두 벌이라 갈라질 수 있으므로,
    /// 테스트가 쿼리 파일과 이것을 대조해 빠진 것을 잡는다 — 안 칠한 캡처는 사용자의
    /// colorscheme 이 칠하고, 그러면 기계마다 다르게 보인다.
    static let paintedTreeSitterCaptures: Set<String> = [
        "type", "type.definition", "constructor", "module",
        "function", "function.method", "function.call", "method", "function.builtin",
        "attribute",
        "constant", "number", "boolean", "constant.builtin",
        "keyword", "keyword.function", "keyword.return", "keyword.type", "keyword.modifier",
        "keyword.import", "keyword.conditional", "keyword.repeat", "keyword.exception",
        "keyword.operator", "type.builtin", "variable.builtin",
        "string", "character", "string.special", "string.escape",
        "comment", "comment.documentation",
        "variable", "property", "parameter", "variable.parameter", "variable.member",
        "field", "operator", "punctuation", "punctuation.bracket", "punctuation.delimiter",
        "punctuation.special", "label",
    ]


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
          --
          -- **쿼리가 내는 캡처를 하나도 빠뜨리지 않는다.** 안 칠한 캡처는 사용자의
          -- colorscheme 이 칠하고, 그러면 같은 코드가 기계마다 다르게 보인다. 실측으로
          -- 우리 java 쿼리가 내는 것은 9종이었고 셋이 빠져 있었다
          -- (`@type.builtin`·`@variable.builtin`·`@operator`).
          local treeSitterGroups = {
            [colours.type]         = { '@type', '@type.definition', '@constructor', '@module' },
            [colours.functionName] = { '@function', '@function.method', '@function.call', '@method', '@function.builtin' },
            [colours.annotation]   = { '@attribute' },
            [colours.number]       = { '@constant', '@number', '@boolean', '@constant.builtin' },
            -- 기본형(`int`)과 `this`·`super` 는 IntelliJ 에서 키워드 색이다.
            [colours.keyword]      = {
              '@keyword', '@keyword.function', '@keyword.return', '@keyword.type',
              '@keyword.modifier', '@keyword.import', '@keyword.conditional', '@keyword.repeat',
              '@keyword.exception', '@keyword.operator',
              '@type.builtin', '@variable.builtin',
            },
            [colours.string]       = { '@string', '@character', '@string.special', '@string.escape' },
            [colours.comment]      = { '@comment', '@comment.documentation' },
            -- 연산자와 구두점은 본문 색이다. IntelliJ 도 그렇고, 안 칠하면 colorscheme 이
            -- 칠해서 기계마다 달라진다.
            [colours.normalForeground] = {
              '@variable', '@property', '@parameter', '@variable.parameter', '@variable.member',
              '@field', '@operator', '@punctuation', '@punctuation.bracket',
              '@punctuation.delimiter', '@punctuation.special', '@label',
            },
          }
          for colour, groups in pairs(treeSitterGroups) do
            for _, group in ipairs(groups) do
              vim.api.nvim_set_hl(0, group, { fg = colour })
            end
          end
          vim.api.nvim_set_hl(0, '@keyword', { fg = colours.keyword, bold = colours.keywordIsBold })

          vim.api.nvim_set_hl(0, 'LineNr', { fg = colours.lineNumber })
          vim.api.nvim_set_hl(0, 'CursorLineNr', { fg = colours.currentLineNumber, bold = true })

          -- 편집기 주변부. 안 칠하면 nvim 기본값이 나오고, 그건 우리 배경을 모르고 고른
          -- 색이라 대비가 맞을 이유가 없다 — 라이트 모드에서 밝은 화면 아래에 어두운 회색
          -- 막대가 남아 편집기 절반이 다른 앱처럼 보였다.
          --
          -- `StatusLineNC` 는 비활성 창의 상태줄이다. 같이 안 칠하면 창을 나눴을 때 한쪽만
          -- 우리 색이고 다른 쪽은 nvim 색이 된다.
          for _, group in ipairs({ 'StatusLine', 'StatusLineNC' }) do
            vim.api.nvim_set_hl(0, group, {
              fg = colours.statusLineForeground,
              bg = colours.statusLineBackground,
            })
          end
          vim.api.nvim_set_hl(0, 'EndOfBuffer', { fg = colours.endOfBuffer })
          vim.api.nvim_set_hl(0, 'NonText', { fg = colours.nonText })
          -- 사인 열 배경은 편집기 배경과 같다. 다르면 아무것도 없는 줄에도 세로 띠가 생기고,
          -- 사용자는 그것을 무언가 켜져 있는 표시로 읽는다.
          vim.api.nvim_set_hl(0, 'SignColumn', { bg = colours.signColumnBackground })

          vim.api.nvim_set_hl(0, '\(sameSymbolGroup)', { bg = colours.sameSymbolBackground })
          vim.api.nvim_set_hl(0, 'Visual', { bg = colours.selectionBackground })
        end

        _G.code_navigator_apply_palette = applyPalette
        applyPalette()

        -- **colorscheme 이 바뀌면 다시 칠한다.**
        --
        -- 우리는 사용자 설정을 그대로 읽는다(키맵을 지키려고). 그 설정이 나중에
        -- `colorscheme` 을 부르면 우리가 심은 색이 통째로 날아가고, 같은 코드가 기계마다
        -- 다르게 보인다 — 사용자가 신고한 그 증상이다.
        --
        -- 한 번만 만든다. `--embed` 로 띄운 뒤 팔레트가 바뀔 때마다 이 스크립트가 다시
        -- 도는데, 그때마다 autocmd 를 더하면 색 하나 바꿀 때 수십 번 다시 칠하게 된다.
        if not _G.code_navigator_palette_autocmd then
          _G.code_navigator_palette_autocmd = vim.api.nvim_create_autocmd('ColorScheme', {
            callback = function()
              -- 다시 칠하는 것이 또 ColorScheme 을 일으키지는 않는다(`nvim_set_hl` 은
              -- colorscheme 을 바꾸지 않는다). 그래도 재진입을 막아 둔다.
              if _G.code_navigator_repainting then
                return
              end
              _G.code_navigator_repainting = true
              pcall(_G.code_navigator_apply_palette)
              _G.code_navigator_repainting = false
            end,
          })
        end

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
