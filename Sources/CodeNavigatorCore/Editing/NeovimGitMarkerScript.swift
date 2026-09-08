import CodeNavigatorContract

/// 거터에 git 변경 막대를 놓는 Lua.
///
/// **줄 번호 왼쪽**이 목표다. Neovim 은 사인 열을 줄 번호 앞에 그리므로, 브레이크포인트와
/// 같은 방식으로 놓으면 IntelliJ 에서 눈이 찾아가는 그 자리가 된다.
///
/// 브레이크포인트와 **다른 그룹**을 쓴다. 그래야 한쪽을 지울 때 다른 쪽이 같이 사라지지
/// 않는다 — 파일을 저장할 때마다 변경 표시를 다시 놓는데, 그때 브레이크포인트가 지워지면
/// 사용자는 걸어 둔 것이 없어진 채로 디버깅한다.
enum NeovimGitMarkerScript {

    static let addedGroup = "CodeNavigatorGitAdded"
    static let modifiedGroup = "CodeNavigatorGitModified"
    static let deletedGroup = "CodeNavigatorGitDeleted"
    /// 우리 git 표시만 지우기 위한 이름.
    static let signGroup = "CodeNavigatorGit"

    /// 막대 글자. `▏` 는 칸의 왼쪽 끝에 붙는 얇은 세로선이라 IntelliJ 의 막대와 가장 닮았다.
    static let barText = "▏"
    /// 삭제는 막대로 못 그린다 — 그 줄이 화면에 없기 때문이다. 사라진 자리를 가리키는
    /// 작은 삼각형을 쓴다. IntelliJ 도 같은 모양이다.
    static let deletedText = "▁"

    static func installScript(palette: GitMarkerPalette) -> String {
        """
        vim.api.nvim_set_hl(0, '\(addedGroup)', { fg = \(packed(palette.added)) })
        vim.api.nvim_set_hl(0, '\(modifiedGroup)', { fg = \(packed(palette.modified)) })
        vim.api.nvim_set_hl(0, '\(deletedGroup)', { fg = \(packed(palette.deleted)) })

        vim.fn.sign_define('\(addedGroup)', { text = '\(barText)', texthl = '\(addedGroup)' })
        vim.fn.sign_define('\(modifiedGroup)', { text = '\(barText)', texthl = '\(modifiedGroup)' })
        vim.fn.sign_define('\(deletedGroup)', { text = '\(deletedText)', texthl = '\(deletedGroup)' })

        -- 사인 열을 **두 칸**으로 둔다. 한 칸이면 브레이크포인트와 변경 막대가 같은 자리를
        -- 다투고, 우선순위가 낮은 쪽이 소리 없이 안 보인다. 두 칸이면 둘 다 보인다.
        vim.opt.signcolumn = 'yes:2'

        --- 한 파일의 git 표시를 통째로 다시 놓는다.
        --- @param path string 절대 경로
        --- @param added table 1-based 줄 번호
        --- @param modified table
        --- @param deleted table
        _G.code_navigator_set_git_markers = function(path, added, modified, deleted)
          local buffer = vim.fn.bufnr(path)
          if buffer == -1 then
            return 'not-open'
          end

          -- **이 버퍼의 우리 표시만** 지운다. 버퍼를 안 넘기면 다른 탭의 표시까지 사라지고,
          -- 그 파일로 돌아갔을 때 변경 표시가 없는 것을 보게 된다.
          vim.fn.sign_unplace('\(signGroup)', { buffer = buffer })

          local function place(group, lines)
            for _, line in ipairs(lines) do
              -- 우선순위를 브레이크포인트보다 낮게 둔다. 같은 칸을 다투게 되면 사용자가
              -- 직접 건 것이 이겨야 한다.
              vim.fn.sign_place(0, '\(signGroup)', group, buffer, { lnum = line, priority = 5 })
            end
          end

          place('\(addedGroup)', added)
          place('\(modifiedGroup)', modified)
          place('\(deletedGroup)', deleted)
          return 'ok'
        end
        """
    }

    /// 표시를 다시 놓는 호출. 설치는 한 번, 갱신은 파일을 저장할 때마다다.
    static func refreshScript() -> String {
        """
        local arguments = ...
        return _G.code_navigator_set_git_markers(
          arguments.path, arguments.added, arguments.modified, arguments.deleted
        )
        """
    }

    /// nvim 은 색을 24비트 정수로 받는다.
    private static func packed(_ colour: EditorColor) -> Int {
        (Int(colour.red) << 16) | (Int(colour.green) << 8) | Int(colour.blue)
    }
}
