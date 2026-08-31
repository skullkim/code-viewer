import Foundation

/// 한 파일을 소스로 볼 것인가 렌더로 볼 것인가 (REQ-013 AC-3, 02b F-14).
public enum DocumentViewMode: Sendable, Hashable {
    case source
    case rendered
}

/// **세 표시가 읽는 하나의 값.**
///
/// 02b F-14 1 은 렌더 보기를 세 곳에 동시에 그린다 — 툴바 `렌더` 버튼 눌림 · 렌더 헤더 바 ·
/// 상태바 `[읽기 전용] 렌더 보기`. 셋이 각자 판단하면 어긋나고, **어긋나면 사용자는 어느
/// 것이 진짜인지 알 방법이 없다** — 화면 셋이 서로를 반증하지만 어느 쪽도 자기가 틀렸다고
/// 말하지 않는다.
///
/// 인덱스 상태를 탭 바 스피너와 상태바 칩이 한 출처에서 읽게 한 것과 같은 이유다.
public struct RenderViewState: Sendable, Hashable {

    /// `.md`·`.html` 인가. 이 판정의 소유자는 `RenderNavigationPolicy` 이고 여기서는 받는다 —
    /// 확장자 목록을 두 곳이 들면 하나만 늘어나는 날이 온다.
    public let isRenderable: Bool

    public let mode: DocumentViewMode

    /// 지금 렌더를 보고 있는가. **세 표시가 전부 이 하나를 읽는다.**
    public var isShowingRender: Bool {
        isRenderable && mode == .rendered
    }

    public init(isRenderable: Bool, mode: DocumentViewMode) {
        self.isRenderable = isRenderable
        self.mode = mode
    }

    /// 파일이 없을 때. 렌더할 것이 없으면 렌더 보기도 없다.
    public static let noDocument = RenderViewState(isRenderable: false, mode: .source)
}

/// 파일마다의 선택을 세션 동안 기억한다 (02b F-14 2, §1.1 "탭별 × 파일별").
///
/// 탭별인 이유는 이 값이 `ProjectTabState` 안에 살기 때문이고, 파일별인 이유는 문서를
/// 고치려는 사람이 **한 번만** 전환하게 하기 위해서다 — 파일을 옮길 때마다 다시 누르게
/// 하면 그 전환은 기억이 아니라 반복 노동이 된다.
public struct RenderViewSelection: Sendable, Hashable {

    private var chosen: [String: DocumentViewMode] = [:]

    public init() {}

    /// 렌더 가능한 파일은 **렌더로 열린다**(02b D-C). 사용자가 고른 적이 있으면 그것이 이긴다.
    public func mode(forPath path: String, isRenderable: Bool) -> DocumentViewMode {
        guard isRenderable else {
            return .source
        }
        return chosen[path] ?? .rendered
    }

    public func state(forPath path: String?, isRenderable: Bool) -> RenderViewState {
        guard let path else {
            return .noDocument
        }
        return RenderViewState(
            isRenderable: isRenderable,
            mode: mode(forPath: path, isRenderable: isRenderable)
        )
    }

    /// 렌더할 수 없는 파일에는 아무 일도 일어나지 않는다 — 02b F-14 4 는 그 경우를 상태바
    /// 메시지로 처리하고, 기억할 선택 자체가 없다.
    public mutating func toggle(path: String, isRenderable: Bool) {
        guard isRenderable else {
            return
        }
        let next: DocumentViewMode = mode(forPath: path, isRenderable: true) == .rendered ? .source : .rendered
        chosen[path] = next
    }
}
