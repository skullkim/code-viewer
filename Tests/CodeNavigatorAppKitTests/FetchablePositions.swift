import Foundation

/// 전처리 결과를 **페치 가능한 자리**로만 검사하는 공용 헬퍼.
///
/// 두 스위트가 같은 성질을 재므로 구현도 하나다 — 두 벌이면 한쪽만 고쳐지고,
/// 안 고쳐진 쪽이 곧 아무도 안 보는 검사가 된다.
/// 페치를 일으킬 수 있는 자리에 담긴 값들 — 참조 속성과 CSS `url()`.
///
/// 예전엔 `!html.contains("evil.com")` 으로 쟀다. 그 단언은 **W-15 박스가 생기면서
/// 성립하지 않는다** — 박스는 일부러 출처를 보여 준다("이 자리에 뭐가 있었나"가 W-15의
/// 목적이다). 그렇다고 단언을 지우면 진짜 유출까지 통과한다.
///
/// 그래서 **프록시를 버리고 원래 성질을 직접 잰다.** 지키려던 것은 "문자열이 문서에
/// 없다"가 아니라 **"브라우저가 그것을 가지러 가지 않는다"** 였고, 그 성질은 참조 속성과
/// `url()` 밖에서는 성립한다. 본문 텍스트에 적힌 호스트는 아무것도 가져오지 않는다.
func fetchableValues(in html: String) -> [String] {
    var values: [String] = []

    // 경계를 느슨하게 잡아 `data-src=` 같은 것까지 걸리게 둔다 — 이 방향의 과검출은
    // 안전하다. 놓치는 쪽이 위험하다.
    for attribute in ["src", "href", "poster", "data", "srcset"] {
        var rest = Substring(html)
        while let marker = rest.range(of: attribute + "=", options: [.caseInsensitive]) {
            var value = rest[marker.upperBound...]
            if let quote = value.first, quote == "\"" || quote == "'" {
                value = value.dropFirst()
                if let end = value.firstIndex(of: quote) {
                    values.append(String(value[..<end]))
                }
            } else if let end = value.firstIndex(where: { $0 == " " || $0 == ">" }) {
                values.append(String(value[..<end]))
            }
            rest = rest[marker.upperBound...]
        }
    }

    var rest = Substring(html)
    while let open = rest.range(of: "url(") {
        let after = rest[open.upperBound...]
        if let close = after.firstIndex(of: ")") {
            values.append(String(after[..<close]))
        }
        rest = rest[open.upperBound...]
    }

    return values
}

func fetchableValues(in html: String, containing needle: String) -> [String] {
    fetchableValues(in: html).filter { $0.contains(needle) }
}
