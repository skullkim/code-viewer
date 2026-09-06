import SwiftUI

/// A draggable divider between two areas stacked vertically — the debug panel and the editor.
///
/// `ShellSplitter` 의 세로판이 아니라 별도 타입이다. 하나로 합치면 방향 인자가 축과 성장
/// 방향 두 가지를 동시에 뜻하게 되고, 그러면 `.leading` 이 가로에서는 왼쪽, 세로에서는
/// 위쪽을 뜻하는 이름이 된다. 커서 모양도 축마다 다르다.
///
/// 드래그는 **위로 끌면 커진다**. 패널이 편집기 아래에 있으므로 위쪽 경계를 올리는 것이
/// 패널을 키우는 것이다.
struct ShellHorizontalSplitter: View {

    let height: CGFloat
    let onChange: (CGFloat) -> Void

    @State private var heightAtDragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(DesignTokens.border.dynamicColor)
            .frame(height: Metrics.lineHeight)
            .frame(height: Metrics.hitHeight)
            .contentShape(Rectangle())
            .onHover { isInside in
                if isInside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // 드래그 시작 시점의 높이를 쓴다. 매 프레임 현재 높이를 읽으면
                        // 이동량이 누적돼 경계가 포인터에서 달아난다 — 가로 스플리터에서
                        // 이미 겪은 것과 같은 실수다.
                        let start = heightAtDragStart ?? height
                        heightAtDragStart = start
                        onChange(start - value.translation.height)
                    }
                    .onEnded { _ in heightAtDragStart = nil }
            )
            .accessibilityLabel("디버그 패널 높이 조절")
    }

    private enum Metrics {
        static let lineHeight: CGFloat = 1
        static let hitHeight: CGFloat = 7
    }
}
