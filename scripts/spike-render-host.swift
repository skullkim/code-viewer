// 렌더 웹뷰 호스트 실측. `RenderWebView` 가 하는 것을 같은 순서로 재현해 **재고**, 앱을
// 건드리지 않는다(QA 가 앱을 잡고 있다).
//
// 재는 것 셋:
//  1. 콘텐츠 룰이 실제로 원격 요청을 막는가 — **대조군을 먼저 통과시킨 뒤에** 0 을 읽는다
//  2. **두 개의 0 을 구별한다** — "규칙이 막았다"와 "문서가 아예 안 떴다"는 둘 다 0 건이다.
//     규칙 목록이 실제로 컴파일됐는지 + 문서가 실제로 그려졌는지를 같이 봐야 0 이 증거가 된다
//  3. `baseURL` 에 따라 상대 링크가 **어떤 URL 로** 해석되는가 — 내비게이션 판정기의 입력
//
// 실행:
//   swift scripts/spike-render-host.swift --control   규칙 없음 (요청이 나와야 정상)
//   swift scripts/spike-render-host.swift             규칙 있음 (0 + 문서는 떠야 정상)
//   swift scripts/spike-render-host.swift --links     상대 링크 해석만
import AppKit
import WebKit
import Network

let port: NWEndpoint.Port = 8977

// ⚠ 앱이 쓰는 것과 **같은 문자열**이어야 이 측정이 앱에 대한 근거가 된다.
// `RenderLoadGateTests` 가 이 문자열이 `RenderContentRules.blockEverything` 과 같은지 단언한다.
let ruleJSON = #"[{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}}]"#

final class Hits: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func record(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
let hits = Hits()

let listener = try! NWListener(using: .tcp, on: port)
listener.newConnectionHandler = { connection in
    connection.start(queue: .global())
    connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { data, _, _, _ in
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        hits.record(text.split(separator: "\r\n").first.map(String.init) ?? "(빈 요청)")
        connection.cancel()
    }
}
listener.start(queue: .global())

let isControl = CommandLine.arguments.contains("--control")
let measuresLinks = CommandLine.arguments.contains("--links")
// baseURL 을 바꾸면 규칙 동작이 달라질 수 있다 — 그게 이 플래그의 이유다. 상대 링크가
// 풀리게 하려고 파일 base 를 쓰면, **그 상태에서도 차단이 유지되는지**를 다시 재야 한다.
let usesFileBase = CommandLine.arguments.contains("--file-base")

@MainActor func load(_ webView: WKWebView, _ html: String) {
    guard usesFileBase else {
        webView.loadHTMLString(html, baseURL: nil)
        return
    }
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("render-spike-base-\(UUID().uuidString)/docs")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    webView.loadHTMLString(html, baseURL: directory)
}

// 1x1 투명 PNG — 전처리가 만들어 낼 `data:` 래스터를 대신한다. 이게 떠야 "문서가 그려졌다".
let raster = "data:image/png;base64,"
    + "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

let document = """
<html><head>
<link rel="stylesheet" href="http://127.0.0.1:\(port)/style.css">
</head><body>
<h1>문서</h1>
<img id="remote" src="http://127.0.0.1:\(port)/image.png">
<img id="raster" src="\(raster)">
<a id="rel" href="./OTHER.md">상대</a>
<a id="up" href="../outside/x.md">상위</a>
<a id="frag" href="#anchor">앵커</a>
<a id="abs" href="https://example.com/x">원격</a>
</body></html>
"""

@MainActor func finish(_ webView: WKWebView, mode: String, compileMillis: Double?) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        print("=== \(mode) ===")
        if let compileMillis {
            print("규칙 컴파일 \(String(format: "%.0f", compileMillis))ms")
        }
        print("원격 요청 \(hits.all.count)건")
        for hit in hits.all { print("  · \(hit)") }

        // **두 개의 0 을 가르는 질문**: 문서가 실제로 떴는가.
        webView.evaluateJavaScript(
            "[document.getElementById('raster')?.naturalWidth ?? -1, document.querySelectorAll('a').length]"
        ) { value, _ in
            let pair = value as? [Int] ?? [-1, -1]
            print("문서 렌더 확인 → data: 래스터 naturalWidth=\(pair[0]) · 링크 \(pair[1])개")
            print(pair[0] > 0
                ? "  ⇒ 문서는 떴다. 따라서 0 은 '막았다'이지 '안 떴다'가 아니다"
                : "  ⇒ ⚠ 문서가 안 떴다 — 이 0 은 차단의 증거가 아니다")
            print(isControl ? "기대: 원격 요청 여러 건" : "기대: 원격 0건 + 래스터 표시")
            exit(0)
        }
    }
}

@MainActor func measureLinks() {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)

    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("render-spike-\(UUID().uuidString)/docs")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("guide.html")
    try? document.write(to: file, atomically: true, encoding: .utf8)

    // 두 로드 방식에서 같은 href 가 어떻게 풀리는지 나란히 본다.
    webView.loadHTMLString(document, baseURL: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        webView.evaluateJavaScript("['rel','up','frag','abs'].map(i => document.getElementById(i).href).join(' | ')") { value, _ in
            print("=== baseURL: nil ===")
            print("  \(value as? String ?? "(없음)")")

            webView.loadFileURL(file, allowingReadAccessTo: directory.deletingLastPathComponent())
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                webView.evaluateJavaScript("['rel','up','frag','abs'].map(i => document.getElementById(i).href).join(' | ')") { value, _ in
                    print("=== baseURL: 파일 (docs/guide.html) ===")
                    print("  \(value as? String ?? "(없음)")")
                    exit(0)
                }
            }
        }
    }
}

@MainActor func run() {
    if measuresLinks {
        measureLinks()
        return
    }

    let configuration = WKWebViewConfiguration()
    // 앱과 같다. 이 플래그는 네트워크를 막지 않는다 — 그것이 ADR-0109 의 핵심 실측이다.
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)

    guard !isControl else {
        // 대조군: 규칙 없이. 요청이 나와야 리스너가 살아 있다는 뜻이고, 그래야 아래의 0 이
        // 의미를 갖는다.
        load(webView, document)
        finish(webView, mode: "대조군 · 규칙 없음" + (usesFileBase ? " · 파일 base" : ""), compileMillis: nil)
        return
    }

    guard let store = WKContentRuleListStore.default() else {
        print("규칙 저장소 없음 — 앱이라면 렌더를 거부한다")
        exit(1)
    }
    let started = Date()
    store.compileContentRuleList(forIdentifier: "spike-block-all", encodedContentRuleList: ruleJSON) { list, error in
        MainActor.assumeIsolated {
            guard let list else {
                print("규칙 컴파일 실패: \(error?.localizedDescription ?? "?") — 앱이라면 렌더 거부")
                exit(1)
            }
            let millis = Date().timeIntervalSince(started) * 1000
            // 규칙이 **붙은 뒤에** 로드한다. 이 순서가 로드 게이트가 강제하는 그 순서다.
            webView.configuration.userContentController.add(list)
            load(webView, document)
            finish(webView, mode: "규칙 적용" + (usesFileBase ? " · 파일 base" : ""), compileMillis: millis)
        }
    }
}

MainActor.assumeIsolated { run() }
RunLoop.main.run(until: Date().addingTimeInterval(15))
print("시간 초과")
exit(1)
