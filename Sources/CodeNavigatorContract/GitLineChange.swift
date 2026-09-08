/// 한 줄이 저장소의 것과 어떻게 다른지.
///
/// IntelliJ 가 줄 번호 왼쪽에 그리는 그 막대다. 사용처를 읽다가 "이 줄은 내가 방금 고친
/// 것인가" 를 묻는 일이 잦은데, 그 답이 편집기 안에 없으면 매번 `git diff` 로 나가야 한다.
public struct GitLineChange: Sendable, Hashable {

    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// 저장소에 없던 줄.
        case added
        /// 저장소에 있지만 내용이 다른 줄.
        case modified
        /// 저장소에는 있었는데 지금은 없는 줄. **그 줄은 화면에 없으므로** 사라진 자리를
        /// 가리킨다 — 어디서 없어졌는지 알려면 그 수밖에 없다.
        case deleted
    }

    /// 지금 파일 기준 줄 번호. 1부터.
    public let line: Int
    public let kind: Kind

    public init(line: Int, kind: Kind) {
        self.line = line
        self.kind = kind
    }
}
