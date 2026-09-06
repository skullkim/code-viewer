import CodeNavigatorContract

/// The Lua that puts the debugger's marks in the editor.
///
/// **`sign` 을 쓴다, `matchadd` 가 아니라.** 같은 심볼 강조는 텍스트 위에 칠하는 것이라
/// `matchadd` 가 맞지만, 브레이크포인트는 거터에 놓이고 줄 번호와 나란히 있어야 한다 —
/// IntelliJ 에서 눈이 찾아가는 그 자리다. `matchadd` 는 거터에 아무것도 못 놓는다.
///
/// 표시는 **매번 통째로 다시 놓는다.** 하나씩 지우고 더하려면 지금 무엇이 놓여 있는지를
/// 우리가 따로 기억해야 하는데, 그 기억과 실제 화면이 어긋나면 사용자는 지웠는데 남아 있는
/// 브레이크포인트를 보게 된다. 그건 "안 지워진다" 가 아니라 "지웠는데 계속 멈춘다" 로 겪힌다.
enum NeovimDebugMarkerScript {

    static let breakpointGroup = "CodeNavigatorBreakpoint"
    static let stoppedLineGroup = "CodeNavigatorStoppedLine"
    static let stoppedSignGroup = "CodeNavigatorStoppedSign"
    /// 우리 표시만 지우기 위한 이름. nvim 의 sign 은 그룹 단위로 지울 수 있고, 그래야
    /// 사용자의 플러그인이 놓은 표시(git 변경 표시 등)를 같이 쓸어 가지 않는다.
    static let signGroup = "CodeNavigatorDebug"

    /// Installs the sign definitions and the function the application calls to refresh them.
    static func installScript(palette: EditorDebugPalette) -> String {
        """
        vim.api.nvim_set_hl(0, '\(breakpointGroup)', { fg = \(packed(palette.breakpointForeground)) })
        vim.api.nvim_set_hl(0, '\(stoppedSignGroup)', { fg = \(packed(palette.stoppedLineForeground)) })
        vim.api.nvim_set_hl(0, '\(stoppedLineGroup)', { bg = \(packed(palette.stoppedLineBackground)) })

        -- `sign_define` 은 같은 이름으로 다시 부르면 덮어쓴다. 외관이 바뀌어 이 스크립트가
        -- 다시 돌 때 중복이 쌓이지 않는다.
        vim.fn.sign_define('\(breakpointGroup)', { text = '●', texthl = '\(breakpointGroup)' })
        vim.fn.sign_define('\(stoppedSignGroup)', {
          text = '▶',
          texthl = '\(stoppedSignGroup)',
          linehl = '\(stoppedLineGroup)',
        })

        -- 사인 열을 항상 켜 둔다. `auto` 로 두면 브레이크포인트를 걸 때마다 편집기 전체가
        -- 한 칸 밀리고, 읽던 자리가 옆으로 움직인다.
        vim.opt.signcolumn = 'yes'

        --- 표시를 통째로 다시 놓는다.
        --- @param path string 프로젝트 상대가 아니라 **절대** 경로 — nvim 은 버퍼를 그렇게 안다
        --- @param breakpointLines table 1-based 줄 번호
        --- @param stoppedLine number|nil
        _G.code_navigator_set_debug_markers = function(path, breakpointLines, stoppedLine)
          -- 우리 그룹만 지운다. 버퍼를 안 넘기면 모든 버퍼에서 지워지는데, 그게 맞다 —
          -- 멈춘 줄 표시는 프로젝트 전체에서 하나뿐이다.
          vim.fn.sign_unplace('\(signGroup)')

          local buffer = vim.fn.bufnr(path)
          -- 그 파일이 안 열려 있으면 놓을 자리가 없다. **그냥 돌아간다** — 억지로 열면
          -- 사용자가 보던 파일이 바뀌고, 그건 표시를 놓는 일이 할 짓이 아니다.
          if buffer == -1 then
            return 'not-open'
          end

          for _, line in ipairs(breakpointLines) do
            vim.fn.sign_place(0, '\(signGroup)', '\(breakpointGroup)', buffer, { lnum = line, priority = 10 })
          end
          if stoppedLine ~= nil then
            -- 멈춘 줄이 더 높은 우선순위다. 브레이크포인트를 건 줄에서 멈추는 것이 보통이고,
            -- 그때 보여야 하는 것은 "여기 멈췄다" 이지 "여기 브레이크포인트가 있다" 가 아니다.
            vim.fn.sign_place(0, '\(signGroup)', '\(stoppedSignGroup)', buffer, { lnum = stoppedLine, priority = 20 })
          end
          return 'placed'
        end

        return 'installed'
        """
    }

    /// The call that refreshes the marks, built for `nvim_exec_lua`.
    static func refreshScript() -> String {
        """
        local arguments = ...
        return _G.code_navigator_set_debug_markers(
          arguments.path, arguments.breakpointLines, arguments.stoppedLine
        )
        """
    }

    private static func packed(_ colour: EditorColor) -> Int {
        Int(colour.red) << 16 | Int(colour.green) << 8 | Int(colour.blue)
    }
}
