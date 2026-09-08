/// 열린 파일에서 저장소와 다른 줄들. 편집기에 그대로 넘긴다.
public struct EditorGitMarkers: Sendable, Hashable {
    /// nvim 이 버퍼를 아는 이름 — **절대** 경로다.
    public let absolutePath: String
    public let added: [Int]
    public let modified: [Int]
    public let deleted: [Int]

    public init(absolutePath: String, added: [Int], modified: [Int], deleted: [Int]) {
        self.absolutePath = absolutePath
        self.added = added
        self.modified = modified
        self.deleted = deleted
    }

    /// 줄 변경 목록을 종류별로 갈라 담는다. 같은 줄이 두 번 들어가지 않게 정리한다 —
    /// nvim 에 같은 자리를 두 번 놓으면 표시가 겹쳐 진해 보인다.
    public init(absolutePath: String, changes: [GitLineChange]) {
        func lines(_ kind: GitLineChange.Kind) -> [Int] {
            Array(Set(changes.filter { $0.kind == kind }.map(\.line))).sorted()
        }
        self.init(
            absolutePath: absolutePath,
            added: lines(.added),
            modified: lines(.modified),
            deleted: lines(.deleted)
        )
    }

    public var isEmpty: Bool { added.isEmpty && modified.isEmpty && deleted.isEmpty }
}

/// 변경 막대의 색.
public struct GitMarkerPalette: Sendable, Hashable {
    /// 새로 생긴 줄.
    public let added: EditorColor
    /// 내용이 달라진 줄. 사용자가 "노란 줄" 이라 부른 그것이다.
    public let modified: EditorColor
    /// 사라진 자리.
    public let deleted: EditorColor

    public init(added: EditorColor, modified: EditorColor, deleted: EditorColor) {
        self.added = added
        self.modified = modified
        self.deleted = deleted
    }
}
