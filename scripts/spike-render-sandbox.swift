// INV-6 선행 스파이크: 렌더 표면이 원격 요청을 정말 0으로 만들 수 있는가.
//
// 문서를 믿지 않고 실제 리스너를 띄워 "연결이 오는가"로 판정한다. 틀리면 REQ-013의
// 렌더 표면 설계가 통째로 바뀌는 가정이라 구현 전에 실측한다.
import AppKit
import WebKit
import Network

let port: NWEndpoint.Port = 8975
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

let html = """
<html><head>
<link rel="stylesheet" href="http://127.0.0.1:\(port)/style.css">
<style>@font-face { font-family: X; src: url("http://127.0.0.1:\(port)/font.woff"); }</style>
<script src="http://127.0.0.1:\(port)/script.js"></script>
</head><body>
<h1 style="font-family:X">제목</h1>
<img src="http://127.0.0.1:\(port)/image.png">
<script>
  var probe = new Image(); probe.src = "http://127.0.0.1:\(port)/from-inline-script.png";
  fetch("http://127.0.0.1:\(port)/from-fetch");
  document.body.innerHTML += "<p id=js>스크립트가 실행됐다</p>";
</script>
</body></html>
"""

// 차단을 끈 대조군(control)이 요청을 실제로 받아야, 차단군의 0이 "막았다"를 뜻한다.
// 그 확인 없이는 0이 "리스너가 고장났다"와 구별되지 않는다.
let isControl = CommandLine.arguments.contains("--control")
// 세 번째 변종: JS 만 끄고 규칙 목록은 안 붙인다. 무엇이 실제로 막고 있는지 가른다.
let isJavaScriptOnly = CommandLine.arguments.contains("--js-off-only")

@MainActor func report(_ webView: WKWebView) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        let hits = counter.all
        let variant = isControl ? "대조군(차단 꺼짐)" : (isJavaScriptOnly ? "JS만 끔(규칙 없음)" : "차단군(규칙+JS끔)")
        print("=== INV-6 스파이크 — \(variant)")
        print("원격 요청 수: \(hits.count)")
        for hit in hits { print("  받은 요청: \(hit)") }
        // 인라인 스크립트가 돌았는지는 evaluateJavaScript 가 아니라 그 스크립트가 낸
        // 요청으로 판정한다 — JS 를 끄면 판정용 스크립트도 못 돌기 때문이다.
        let scriptTraces = hits.filter { $0.contains("from-inline-script") || $0.contains("from-fetch") }
        print("인라인 스크립트가 실행됐나: \(scriptTraces.isEmpty ? "아니오" : "예 (\(scriptTraces.count)건)")")
        if isControl || isJavaScriptOnly {
            exit(0)
        }
        exit(hits.isEmpty ? 0 : 2)
    }
}

@MainActor func run() {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = isControl

    guard !isControl, !isJavaScriptOnly else {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        webView.loadHTMLString(html, baseURL: nil)
        report(webView)
        return
    }

    let blockEverything = """
    [{"trigger": {"url-filter": "^(https?|wss?|ftp|file)://"}, "action": {"type": "block"}}]
    """
    WKContentRuleListStore.default().compileContentRuleList(
        forIdentifier: "spike-remote-only", encodedContentRuleList: blockEverything
    ) { list, error in
        if let error { print("규칙 컴파일 실패: \(error)"); exit(1) }
        if let list { configuration.userContentController.add(list) }

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        webView.loadHTMLString(html, baseURL: nil)
        report(webView)
    }
}
MainActor.assumeIsolated { run() }
RunLoop.main.run(until: Date().addingTimeInterval(12))
print("시간 초과")
exit(3)
