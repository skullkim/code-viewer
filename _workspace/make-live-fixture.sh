#!/usr/bin/env bash
# 인증 라이브 검증용 픽스처 프로젝트를 만든다 (REQ-015·016·017).
#
# 왜 픽스처가 필요한가: 수용 시나리오가 구체적인 수를 요구한다 — SC-10 은 "UserService 를
# 쓰는 파일 3개", SC-11 은 "한 파일 안에 같은 이름 5곳". 아무 레포나 열어서 재면 그 수가
# 맞는지부터 세야 하고, 세는 순간 판정이 흐려진다. 여기서는 수를 미리 정해 둔다.
#
# 사용법:
#   make-live-fixture.sh              /tmp/cn-live-fixture 에 생성
#   make-live-fixture.sh --self-test  픽스처가 시나리오의 수를 실제로 만족하는지 검사
set -uo pipefail

FIXTURE="${FIXTURE:-/tmp/cn-live-fixture}"

# SC-10 이 요구하는 수. 픽스처와 검사가 같은 상수를 읽어야 한 쪽만 바뀌지 않는다.
EXPECTED_USER_SERVICE_FILES=3
EXPECTED_USER_OCCURRENCES=5

write_fixture() {
    rm -rf "$FIXTURE"
    mkdir -p "$FIXTURE/src"

    # ── SC-11: 한 파일 안에 `user` 가 정확히 5곳 (같은 심볼 강조 대상) ──
    # 구문 그룹도 한 화면에 다 나오게 짰다 — 키워드·타입·문자열·숫자·주석·함수명.
    # 하나라도 빠지면 AC-1 을 "색이 여러 개다"로 재는 자리에서 축이 하나 비게 된다.
    cat > "$FIXTURE/src/UserService.java" <<'JAVA'
package app;

// UserService owns the user lookup path.
public class UserService {
    private static final int MAX_RETRIES = 3;
    private final String realm = "primary";

    public String describe(String user) {
        if (user == null) {
            return "anonymous";
        }
        String normalised = user.trim();
        return realm + ":" + normalised + "/" + user.length();
    }

    public int retries() {
        return MAX_RETRIES;
    }
}
JAVA

    # ── SC-10: UserService 를 쓰는 파일이 정확히 3개 ──
    cat > "$FIXTURE/src/AccountController.java" <<'JAVA'
package app;

// First of three call sites for UserService.
public class AccountController {
    private final UserService service = new UserService();

    public String show(String name) {
        return service.describe(name);
    }
}
JAVA

    cat > "$FIXTURE/src/ReportJob.java" <<'JAVA'
package app;

// Second of three call sites for UserService.
public class ReportJob {
    public String run(UserService service) {
        return service.describe("nightly") + service.retries();
    }
}
JAVA

    cat > "$FIXTURE/src/Bootstrap.kt" <<'KOTLIN'
package app

// Third call site, in Kotlin — proves the grammar is not Java-only.
class Bootstrap {
    private val service = UserService()

    fun greet(who: String): String {
        val count = 42
        return service.describe(who) + " " + count
    }
}
KOTLIN

    cat > "$FIXTURE/src/client.ts" <<'TYPESCRIPT'
// TypeScript file — third bundled grammar.
export interface Account {
    id: number;
    label: string;
}

export function formatAccount(account: Account): string {
    const prefix = "acct";
    return `${prefix}-${account.id}-${account.label}`;
}
TYPESCRIPT

    # ── SC-13: 문법이 번들되지 않은 언어. 평문으로 보여야 하고 깨지면 안 된다 ──
    # 일부러 키워드·문자열·주석·숫자를 다 넣었다. 강조가 새면 여기서 색이 늘어난다.
    cat > "$FIXTURE/src/tool.py" <<'PYTHON'
# Python has no bundled grammar - this file must render as plain text.
import sys

MAX_ITEMS = 128


class Collector:
    def __init__(self, label):
        self.label = label
        self.items = []

    def add(self, value):
        if len(self.items) < MAX_ITEMS:
            self.items.append(value)
        return len(self.items)


def main():
    collector = Collector("default")
    collector.add(sys.argv)
    print(collector.label)
PYTHON

    cat > "$FIXTURE/README.md" <<'MARKDOWN'
# Live fixture

Built by `make-live-fixture.sh` for certification. Not part of the product.
MARKDOWN
}

# ── 자기 검사 ────────────────────────────────────────────────────────────────
# 픽스처가 시나리오의 수를 실제로 만족하는지 센다. 이걸 안 세면 인증 때
# "참조가 3개 안 나온다"를 결함으로 올리게 되는데, 원인이 픽스처일 수 있다.
# 재는 대상이 틀렸는지부터 가른다.
self_test() {
    printf '=== make-live-fixture 자체 검사 ===\n'
    write_fixture
    local failures=0

    check() {
        if [ "$2" = "$3" ]; then
            printf '  ok: %s (%s)\n' "$1" "$2"
        else
            printf '  FAIL: %s — 기대 %s, 실제 %s\n' "$1" "$3" "$2"
            failures=$((failures + 1))
        fi
    }

    # 정의 파일 자신은 "사용처"가 아니므로 뺀다 — SC-10 의 3은 호출하는 쪽의 수다.
    local using
    using=$(grep -rl 'UserService' "$FIXTURE/src" | grep -v 'UserService.java' | wc -l | tr -d ' ')
    check "UserService 를 쓰는 파일 수" "$using" "$EXPECTED_USER_SERVICE_FILES"

    local occurrences
    occurrences=$(grep -o '\buser\b' "$FIXTURE/src/UserService.java" | wc -l | tr -d ' ')
    check "UserService.java 안의 user 출현 수" "$occurrences" "$EXPECTED_USER_OCCURRENCES"

    # 지원 언어 3종 + 미지원 1종이 다 있어야 AC-1 과 AC-4 를 같은 창에서 가른다.
    for f in UserService.java Bootstrap.kt client.ts tool.py; do
        if [ -f "$FIXTURE/src/$f" ]; then
            printf '  ok: %s 존재\n' "$f"
        else
            printf '  FAIL: %s 없음\n' "$f"; failures=$((failures + 1))
        fi
    done

    # 반대 방향: 검사가 아무 파일에서나 참을 돌려주지 않는지 (positive control 의 짝)
    local absent
    absent=$(grep -rl 'PaymentService' "$FIXTURE/src" | wc -l | tr -d ' ')
    check "없는 심볼은 0개로 센다" "$absent" "0"

    if [ "$failures" -eq 0 ]; then
        printf '  → 자체 검사 통과. 인증에서 수가 안 맞으면 원인은 픽스처가 아니라 앱이다.\n'
        return 0
    fi
    printf '  → 자체 검사 실패 %s건 — 이 픽스처로 잰 결과를 근거로 쓰지 마라.\n' "$failures"
    return 1
}

[ "${1:-}" = "--self-test" ] && { self_test; exit $?; }

write_fixture
printf '%s\n' "$FIXTURE"
printf 'SC-10  UserService 사용 파일 %s개 (AccountController · ReportJob · Bootstrap.kt)\n' "$EXPECTED_USER_SERVICE_FILES"
printf 'SC-11  UserService.java 안 user %s곳\n' "$EXPECTED_USER_OCCURRENCES"
printf 'SC-13  tool.py — 평문이어야 한다\n'
