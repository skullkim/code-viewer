// 접근성 트리에서 이름으로 요소를 찾아 누른다.
//
// AppleScript 의 `entire contents` 는 큰 창에서 조용히 0건을 돌려주고, 손으로 몇 단계씩
// 내려가는 코드는 매번 다시 쓰게 된다. 여기서는 깊이 우선으로 전부 훑되 상한을 둔다.
//
// 사용법: swift scripts/click-ax.swift <프로세스 이름> <찾을 문구> [--list]
import AppKit
import ApplicationServices

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("사용법: click-ax.swift <프로세스> <문구> [--list]\n".utf8))
    exit(2)
}
let processName = arguments[1]
let needle = arguments[2]
let listOnly = arguments.contains("--list")
/// SwiftUI 의 `onTapGesture` 는 접근성 `AXPress` 로 발동되지 않는다. 그럴 때는 요소의
/// **자기 좌표**를 받아 그 자리를 누른다 — 화면 좌표를 손으로 찍는 것이 아니라, 이름으로
/// 찾은 요소가 알려 준 자리다.
let useMouse = arguments.contains("--mouse")

guard AXIsProcessTrusted() else {
    print("FAIL: 이 도구에 손쉬운 사용 권한이 없다 — 시스템 설정에서 허용하라")
    exit(3)
}

guard let application = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName == processName || $0.bundleURL?.deletingPathExtension().lastPathComponent == processName
}) else {
    print("FAIL: \(processName) 프로세스를 못 찾았다")
    exit(4)
}

let root = AXUIElementCreateApplication(application.processIdentifier)

func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
    else { return [] }
    return (value as? [AXUIElement]) ?? []
}

func label(_ element: AXUIElement) -> String {
    [
        string(element, kAXTitleAttribute as String),
        string(element, kAXDescriptionAttribute as String),
        string(element, kAXValueAttribute as String),
    ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " | ")
}

/// 깊이 상한. 무한 재귀는 없지만 아주 깊은 트리에서 시간을 다 쓰지 않게 막는다.
let maximumDepth = 25
var visited = 0
var matches: [(element: AXUIElement, role: String, label: String)] = []

func walk(_ element: AXUIElement, depth: Int) {
    guard depth <= maximumDepth, visited < 20_000 else { return }
    visited += 1
    let role = string(element, kAXRoleAttribute as String) ?? "?"
    let text = label(element)
    if listOnly {
        if !text.isEmpty { print("\(String(repeating: "  ", count: depth))\(role): \(text)") }
    } else if text.contains(needle) {
        matches.append((element, role, text))
    }
    for child in children(element) { walk(child, depth: depth + 1) }
}

walk(root, depth: 0)

if listOnly {
    print("훑은 요소 \(visited)개")
    exit(0)
}

// 누를 수 있는 것을 고른다. 정적 텍스트가 먼저 걸리면 그 부모를 눌러야 한다.
guard let match = matches.first(where: { $0.role == "AXButton" || $0.role == "AXRow" || $0.role == "AXCell" })
    ?? matches.first
else {
    print("FAIL: \"\(needle)\" 을 못 찾았다 (훑은 요소 \(visited)개)")
    exit(1)
}

if useMouse {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard
        AXUIElementCopyAttributeValue(match.element, kAXPositionAttribute as CFString, &positionValue) == .success,
        AXUIElementCopyAttributeValue(match.element, kAXSizeAttribute as CFString, &sizeValue) == .success
    else {
        print("FAIL: \(match.label) 의 자리를 못 읽었다")
        exit(6)
    }
    var origin = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    let centre = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)

    application.activate()
    usleep(300_000)
    for (down, up) in [(CGEventType.leftMouseDown, CGEventType.leftMouseUp)] {
        for type in [down, up] {
            guard let event = CGEvent(
                mouseEventSource: nil, mouseType: type, mouseCursorPosition: centre,
                mouseButton: .left
            ) else {
                print("FAIL: 이벤트를 만들지 못했다")
                exit(7)
            }
            event.post(tap: .cghidEventTap)
            usleep(60_000)
        }
    }
    print("눌렀다(마우스): \(match.role) [\(match.label)] @\(Int(centre.x)),\(Int(centre.y))")
    exit(0)
}

let result = AXUIElementPerformAction(match.element, kAXPressAction as CFString)
if result == .success {
    print("눌렀다: \(match.role) [\(match.label)]")
    exit(0)
}
print("FAIL: \(match.role) [\(match.label)] 을 누르지 못했다 (\(result.rawValue))")
exit(5)
