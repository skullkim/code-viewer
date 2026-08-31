// INV-6 2층 스파이크: WebKit 이 우리가 주입하는 `<meta>` CSP 를 **실제로 강제하는가**.
//
// ADR-0109 는 "전면 차단 + 인라인"의 근거를 실측했지만, 그 위에 얹은 **CSP 백스톱은 한 번도
// 재지 않았다.** 지금 우리가 아는 것은 "메타 태그를 문서에 넣었다"까지이고 그 뒤는 가정이다.
// 겹의 수는 그 자체로 안심의 근거가 아니다 — 각 겹이 막는지 재야 근거가 된다.
//
// 판정은 문서가 아니라 **연결이 오는가**로 한다. 그리고 대조군을 **먼저** 통과시킨다:
// 대조군이 요청을 못 받으면 차단군의 0 은 "막았다"가 아니라 "리스너가 고장났다"이다.
//
// 실행:
//   swift scripts/spike-csp-enforcement.swift --control        CSP 없음 (요청이 나와야 정상)
//   swift scripts/spike-csp-enforcement.swift                  CSP 있음 (0 이어야 정상)
//   swift scripts/spike-csp-enforcement.swift --file-url       loadFileURL 경로로 같은 측정
import AppKit
import WebKit
import Network

let port: NWEndpoint.Port = 8976

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var hits: [String] = []
    func record(_ what: String) { lock.lock(); hits.append(what); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return hits }
}
let counter = Counter()

let listener = try! NWListener(using: .tcp, on: port)
listener.newConnectionHandler = { connection in
    connection.start(queue: .global())
    connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { data, _, _, _ in
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let firstLine = text.split(separator: "\r\n").first.map(String.init) ?? "(빈 요청)"
        counter.record(firstLine)
        connection.cancel()
    }
}
listener.start(queue: .global())

let isControl = CommandLine.arguments.contains("--control")
// 우리 로드 방식이 무엇이냐에 따라 CSP 적용이 달라질 수 있다 — 그게 이 질문의 전부다.
let usesFileURL = CommandLine.arguments.contains("--file-url")
// 그리고 **문서의 모양**에 따라서도 달라질 수 있다. 이 스파이크의 첫 판은 `<head>` 가 있는
// 완전한 페이지만 쟀는데, 마크다운은 그 모양을 만들지 않는다 — `injectingPolicy` 의 head 없는
// 분기가 정책 메타를 문서 **맨 앞**에 놓은 조각을 낸다. 파서가 그 메타를 head 로 끌어올린다는
// 것은 그럴듯한 이야기이고, 이 빌드에서 그럴듯한 이야기는 근거가 아니다.
let usesFragment = CommandLine.arguments.contains("--fragment")

// 앱이 실제로 주입하는 정책과 같은 문자열이어야 측정이 의미가 있다.
let policy = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src 'none'; "
    + "script-src 'none'; frame-src 'none'; connect-src 'none'"
let policyTag = isControl
    ? ""
    : "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"

// 1x1 투명 PNG. 전처리가 만들어 낼 `data:` 래스터를 대신한다 — CSP 가 이것까지 막으면
// **과차단**이고, 정당한 문서 이미지가 안 보인다.
let rasterDataURI = "data:image/png;base64,"
    + "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

// 참조와 본문을 따로 두고, 완전한 페이지와 머리 없는 조각 두 형태로 조립한다. 두 형태가
// 같은 참조를 걸어야 비교가 성립한다.
let references = """
<link rel="stylesheet" href="http://127.0.0.1:\(port)/style.css">
<style>@font-face { font-family: X; src: url("http://127.0.0.1:\(port)/font.woff"); }</style>
"""

let body = """
<h1 style="font-family:X">제목</h1>
<img id="remote" src="http://127.0.0.1:\(port)/image.png">
<img id="raster" src="\(rasterDataURI)">
<iframe src="http://127.0.0.1:\(port)/frame.html"></iframe>
<!-- 인라인 **이벤트 핸들러**. 위의 `<script>` 와 다른 구문이고 CSP 에서도 다른 검사를 탄다.
     신뢰하지 않는 레포의 README 가 원시 HTML 로 이걸 품는 것이 INV-6 의 그 시나리오다.
     깨진 `data:` 라 `onerror` 가 뜬다. 요청이 오면 핸들러가 실행된 것이다. -->
<img id="handler" src="data:image/png;base64,QQ==" onerror="fetch('http://127.0.0.1:\(port)/from-onerror')">
<script>
  var probe = new Image(); probe.src = "http://127.0.0.1:\(port)/from-inline-script.png";
  fetch("http://127.0.0.1:\(port)/from-fetch");
</script>
"""

let html = usesFragment
    ? policyTag + references + body
    : "<html><head>\(policyTag)\(references)</head><body>\(body)</body></html>"

@MainActor func report(_ webView: WKWebView, mode: String) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        let hits = counter.all
        print("=== \(mode) ===")
        print("원격 요청 \(hits.count)건")
        for hit in hits { print("  · \(hit)") }

        // 과차단 확인: 우리가 만든 래스터 `data:` 는 여전히 떠야 한다. 0 이 "전부 막힘"인지
        // "원격만 막힘"인지를 이 한 줄이 가른다.
        webView.evaluateJavaScript(
            "document.getElementById('raster')?.naturalWidth ?? -1"
        ) { value, _ in
            let width = (value as? Int) ?? -1
            let verdict = width > 0 ? "표시됨 ✅" : (width == 0 ? "차단됨 ⚠️(과차단)" : "확인 불가")
            print("data: 래스터 이미지 → \(verdict) (naturalWidth=\(width))")
            print(isControl
                ? "기대: 원격 요청이 여러 건 — 0 이면 리스너나 환경 문제이지 CSP 효과가 아니다"
                : "기대: 원격 요청 0 + 래스터 표시됨")
            exit(0)
        }
    }
}

@MainActor func run() {
    let configuration = WKWebViewConfiguration()
    // 스크립트는 앱에서도 끈다. 여기서 켜 두는 이유는 `fetch`·`new Image()` 경로가 CSP 에
    // 막히는지 보기 위해서다 — 앱의 1층은 스크립트를 아예 제거하므로 이 변종은 **CSP 단독의
    // 힘**을 재는 것이다.
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true

    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)

    let mode: String
    if usesFileURL {
        // 앱이 파일에서 로드한다면 그 경로로 재야 한다. baseURL 이 있는 로드와 없는 로드에서
        // 정책 적용이 다를 수 있고, 그 차이가 이 스파이크의 이유다.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("csp-spike-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("index.html")
        try? html.write(to: file, atomically: true, encoding: .utf8)
        webView.loadFileURL(file, allowingReadAccessTo: directory)
        mode = (isControl ? "대조군" : "CSP") + " · loadFileURL" + (usesFragment ? " · 조각" : " · 완전한 페이지")
    } else {
        webView.loadHTMLString(html, baseURL: nil)
        mode = (isControl ? "대조군" : "CSP") + " · loadHTMLString" + (usesFragment ? " · 조각" : " · 완전한 페이지")
    }

    report(webView, mode: mode)
}

MainActor.assumeIsolated { run() }
RunLoop.main.run(until: Date().addingTimeInterval(12))
print("시간 초과 — 렌더가 끝나지 않았다")
exit(1)
