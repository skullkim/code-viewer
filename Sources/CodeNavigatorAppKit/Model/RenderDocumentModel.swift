import Foundation
import Observation
import CodeNavigatorContract

/// 렌더 표면이 그릴 문서를 준비한다 (REQ-013).
///
/// `RenderSurface` 는 순전히 표시만 한다 — 읽기와 변환·새니타이즈는 비동기라 `body` 에 둘 수
/// 없다. 그 일이 여기 산다.
///
/// **문서는 탭 id 로 요청한다.** 활성 탭에서 추론하지 않는다: `gt` 로 탭페이지가 옮겨가면
/// 추론은 **맞아 보이는 방식으로 틀린다** — 두 프로젝트가 둘 다 `README.md` 를 갖고 있을 때
/// 특히 그렇다. 엔진의 두 문이 탭 id 를 받는 것과 같은 이유다.
@MainActor
@Observable
public final class RenderDocumentModel {

    public private(set) var phase: RenderPhase = .empty
    public private(set) var html: String = ""
    public private(set) var blocked: [BlockedResource] = []
    public private(set) var unavailable: [UnavailableResource] = []

    /// 지금 화면에 있는 문서의 신원. 늦게 도착한 답이 다른 파일 위에 그려지는 것을 막는다.
    public private(set) var documentRelativePath: String?
    public private(set) var projectRoot: String?

    private let workspace: any ProjectWorkspace
    private var loadTask: Task<Void, Never>?

    public init(workspace: any ProjectWorkspace) {
        self.workspace = workspace
    }

    /// 이미 그리고 있는 문서를 다시 요청하면 아무 일도 하지 않는다.
    ///
    /// 창 본문은 상태가 바뀔 때마다 다시 평가된다. 그때마다 다시 읽으면 **스크롤 위치가
    /// 매번 처음으로 돌아가고**, 사용자는 문서를 읽을 수 없다.
    public func showIfNeeded(path: String, root: String, tab: ProjectTabIdentifier) {
        guard documentRelativePath != path || projectRoot != root else {
            return
        }
        show(path: path, root: root, tab: tab)
    }

    public func show(path: String, root: String, tab: ProjectTabIdentifier) {
        loadTask?.cancel()
        documentRelativePath = path
        projectRoot = root

        // 저장 후 재렌더는 앞 문서를 화면에 둔 채로 한다(AC-5). 첫 렌더만 빈 화면에서 돈다.
        phase = html.isEmpty ? .rendering : .rerendering

        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(path: path, root: root, tab: tab)
        }
    }

    /// 문서가 바뀌지 않았을 때 화면을 비운다 — 소스 보기로 돌아갈 때.
    public func clear() {
        loadTask?.cancel()
        loadTask = nil
        documentRelativePath = nil
        projectRoot = nil
        html = ""
        blocked = []
        unavailable = []
        phase = .empty
    }

    private func load(path: String, root: String, tab: ProjectTabIdentifier) async {
        let source: RenderSource
        do {
            source = try await workspace.renderSource(atRelativePath: path, in: tab)
        } catch let error as NavigatorError {
            apply(failure: error, for: path)
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(reason: "\(error)")
            return
        }

        guard !Task.isCancelled, documentRelativePath == path else {
            // 사용자가 이미 다른 파일로 옮겼다. 늦게 온 답을 그리면 지금 열린 파일 이름
            // 아래에 다른 문서가 놓인다.
            return
        }

        guard !source.text.isEmpty else {
            html = ""
            blocked = []
            unavailable = []
            phase = .empty
            return
        }

        // HTML 만 그대로 통과시키고 나머지 렌더 가능 문서는 마크다운으로 본다.
        // 목록에 `markdown` 이 늘어도 이 분기는 따라온다 — 반대로 적으면(`== "md"` 면 마크다운)
        // 새 확장자가 조용히 HTML 로 취급돼 원문이 그대로 노출된다.
        let isHypertext = (path as NSString).pathExtension.lowercased() == "html"
        let markup = isHypertext ? source.text : MarkdownDocument.html(from: source.text)

        let prepared = await Self.prepare(markup: markup, root: root, tab: tab, workspace: workspace)

        guard !Task.isCancelled, documentRelativePath == path else { return }

        html = prepared.html
        blocked = prepared.blocked
        unavailable = prepared.unavailable
        phase = .rendered(source: source.origin)
    }

    /// 실패는 이유를 잃지 않는다 — "없음"·"너무 큼"·"루트 밖"이 한 사건이 되면 샌드박스
    /// 칩이 무엇이 일어났는지 말할 수 없다.
    /// 준비는 메인 액터 밖에서 돈다.
    ///
    /// `prepare` 의 콜백은 `@Sendable` 이 아니라, 이 모델(`@MainActor`)을 잡은 클로저를
    /// 넘기면 컴파일러가 막는다. 막는 게 맞다 — 문서 하나에 이미지가 수십 개면 그 읽기가
    /// 전부 메인 액터에 줄을 서고, 그동안 창은 멈춘다.
    private nonisolated static func prepare(
        markup: String,
        root: String,
        tab: ProjectTabIdentifier,
        workspace: any ProjectWorkspace
    ) async -> SanitizedDocument {
        await RenderDocumentPipeline.prepare(
            html: markup,
            projectRoot: root,
            loadResource: { resourcePath in
                await loadResource(resourcePath, in: tab, from: workspace)
            }
        )
    }

    private nonisolated static func loadResource(
        _ path: String,
        in tab: ProjectTabIdentifier,
        from workspace: any ProjectWorkspace
    ) async -> Result<Data, RenderResourceFailure> {
        do {
            return .success(try await workspace.renderResource(atRelativePath: path, in: tab))
        } catch let error as NavigatorError {
            return .failure(Self.failure(for: error))
        } catch {
            return .failure(.notReadable("\(error)"))
        }
    }

    /// 이유를 보존한다. 셋을 한 사건으로 뭉개면 샌드박스 칩이 **무엇이 일어났는지** 말할 수
    /// 없고, "차단했다"가 남의 오타까지 자기 공으로 가져간다.
    private nonisolated static func failure(for error: NavigatorError) -> RenderResourceFailure {
        switch error {
        case .fileNotFound:
            return .notFound
        case .fileTooLarge(_, let byteSize, let limit):
            return .tooLarge(byteSize: byteSize, limit: limit)
        case .invalidPath:
            return .invalidPath
        default:
            return .notReadable(error.errorDescription ?? "\(error)")
        }
    }

    private func apply(failure: NavigatorError, for path: String) {
        guard !Task.isCancelled, documentRelativePath == path else { return }
        switch failure {
        case .fileTooLarge(_, let byteSize, _):
            phase = .tooLarge(byteCount: byteSize)
        case .fileNotDecodable:
            phase = .undecodable
        default:
            phase = .failed(reason: failure.errorDescription ?? "\(failure)")
        }
    }
}
