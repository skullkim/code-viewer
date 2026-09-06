/// What the debugger wants drawn in the editor's gutter and on its lines.
///
/// 구문 팔레트와 **따로 둔다.** 섞으면 테마가 바뀔 때마다 브레이크포인트 목록까지 같이
/// 흘러다니고, 팔레트에 항목을 하나 더할 때마다 구문 색만 보려고 만든 테스트 픽스처
/// 다섯 곳을 함께 고쳐야 한다. 두 관심사는 바뀌는 시점도 이유도 다르다.
public struct EditorDebugMarkers: Sendable, Hashable {
    /// 프로젝트 상대 경로. 지금 편집기에 열려 있는 파일과 다르면 아무것도 그리지 않는다 —
    /// 다른 파일의 브레이크포인트를 이 파일 줄 번호에 찍으면 없는 표시를 만드는 것이다.
    public let path: String
    /// 1-based. 사용자가 건 줄들.
    public let breakpointLines: [Int]
    /// 1-based, 멈춰 있지 않으면 nil.
    public let stoppedLine: Int?

    public init(path: String, breakpointLines: [Int], stoppedLine: Int?) {
        self.path = path
        self.breakpointLines = breakpointLines
        self.stoppedLine = stoppedLine
    }

    /// 아무것도 그리지 않는 상태. 디버거를 떼거나 파일을 옮길 때 쓴다.
    public static func cleared(path: String) -> EditorDebugMarkers {
        EditorDebugMarkers(path: path, breakpointLines: [], stoppedLine: nil)
    }
}

/// The colours those marks are drawn in.
///
/// 외관을 따라 바뀌므로 팔레트처럼 앱이 정해서 내려보낸다 — nvim 기본값에 맡기면 우리
/// 배경을 모르는 색이 나온다.
public struct EditorDebugPalette: Sendable, Hashable {
    /// 브레이크포인트 점. 빨강 계열이지만 **오류 빨강과 같으면 안 된다** — 브레이크포인트는
    /// 사용자가 의도해서 놓은 것이고, 고장이 아니다.
    public let breakpointForeground: EditorColor
    /// 멈춘 줄의 배경. 코드 글자가 그 위에서 계속 읽혀야 하므로 진하면 안 된다.
    public let stoppedLineBackground: EditorColor
    /// 멈춘 줄을 가리키는 거터 화살표.
    public let stoppedLineForeground: EditorColor

    public init(
        breakpointForeground: EditorColor,
        stoppedLineBackground: EditorColor,
        stoppedLineForeground: EditorColor
    ) {
        self.breakpointForeground = breakpointForeground
        self.stoppedLineBackground = stoppedLineBackground
        self.stoppedLineForeground = stoppedLineForeground
    }
}
