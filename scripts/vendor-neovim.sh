#!/usr/bin/env bash
# Vendors the Neovim the application bundle carries.
#
# The application used to require the user to install Neovim themselves. That made "download the
# DMG and it works" false: on a Mac without Neovim the editor pane simply never appeared, and the
# only clue was a start-up message. Shipping the editor removes the one step a user could not be
# expected to know about.
#
# Upstream publishes a separate tarball per architecture and no universal build, so the two are
# fetched and `lipo`'d here. That matters more than it sounds: `swift build --arch arm64 --arch
# x86_64` makes *our* binary universal, and an arm64-only Neovim inside it would turn every Intel
# Mac into a launch that half-works.
#
# The good news, measured rather than assumed: `otool -L` shows Neovim links only against
# CoreServices, libiconv, libSystem and libutil — all present on every macOS. There is no
# third-party dylib to relocate and no rpath to rewrite.
#
# **What the checksums below do and do not prove.** Upstream publishes no `.sha256sum` for these
# assets, so these are the hashes of what we downloaded on the date in this header. They detect a
# release asset being replaced after the fact; they are not an independent attestation from the
# Neovim project. Re-pinning means downloading, diffing behaviour, and updating both lines.
#
# Unlike `Resources/treesitter` — built here from sources SPM already vendors — this is a
# third-party prebuilt release, so it is fetched rather than committed and `Resources/nvim` is
# git-ignored. A clone stays small; a release build needs the network once.
#
#   vendor-neovim.sh              assemble Resources/nvim
#   vendor-neovim.sh --self-test  prove the assembled Neovim is universal and finds its runtime
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the self-test can be pointed at a deliberately broken copy. Without that the
# only way to prove this checker still catches anything is to break the real tree.
OUTPUT="${NVIM_VENDOR_OUTPUT:-$REPO_ROOT/Resources/nvim}"
CACHE="$REPO_ROOT/.build/vendor-cache"

# Pinned to the version this application was developed and measured against. Vendored 2026-09-06.
NEOVIM_VERSION="v0.12.5"
SHA256_ARM64="65fb000099e47ca1b762584c484cc833f40e30851a0ec450d4174e16317c1f9b"
SHA256_X86_64="81f4518622cb059b450ee2e498c6a1082a222f6bd89589de5bbcf0c6a68aa3fd"

ARCHITECTURES=(arm64 x86_64)

expected_sha256() {  # <arch>
    case "$1" in
        arm64)  printf '%s\n' "$SHA256_ARM64" ;;
        x86_64) printf '%s\n' "$SHA256_X86_64" ;;
        *)      return 1 ;;
    esac
}

fetch() {  # <arch> → path to a verified tarball
    local arch="$1"
    local name="nvim-macos-$arch.tar.gz"
    local archive="$CACHE/$NEOVIM_VERSION-$name"

    mkdir -p "$CACHE"
    if [ ! -f "$archive" ]; then
        curl -sSL --fail -o "$archive.partial" \
            "https://github.com/neovim/neovim/releases/download/$NEOVIM_VERSION/$name" \
            || { echo "FAIL: $name 을 받지 못했다" >&2; rm -f "$archive.partial"; exit 1; }
        mv "$archive.partial" "$archive"
    fi

    # Verified before extraction, not after. A tampered archive that has already been unpacked has
    # already had its chance to write wherever it liked.
    local actual expected
    actual="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
    expected="$(expected_sha256 "$arch")"
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $name 의 해시가 핀과 다르다" >&2
        echo "  기대: $expected" >&2
        echo "  실제: $actual" >&2
        echo "  캐시를 지우고 다시 받아 보고, 그래도 다르면 릴리스가 교체된 것이다: $archive" >&2
        exit 1
    fi
    printf '%s\n' "$archive"
}

build() {
    local work; work="$(mktemp -d)"
    trap 'rm -rf "$work"' RETURN

    for arch in "${ARCHITECTURES[@]}"; do
        local archive; archive="$(fetch "$arch")"
        mkdir -p "$work/$arch"
        tar xzf "$archive" -C "$work/$arch" --strip-components 1
    done

    rm -rf "$OUTPUT"
    mkdir -p "$OUTPUT/bin" "$OUTPUT/lib/nvim/parser"

    # Neovim finds its runtime relative to the executable — `<prefix>/bin/nvim` looks for
    # `<prefix>/share/nvim/runtime`. The layout is load-bearing, not cosmetic: flatten it and the
    # editor starts with no syntax files, no filetype detection and no help, reporting none of it
    # as an error.
    lipo -create -output "$OUTPUT/bin/nvim" \
        "$work/arm64/bin/nvim" "$work/x86_64/bin/nvim"

    # The parsers Neovim ships (c, lua, markdown, query, vim, vimdoc) are per-architecture objects
    # and need the same treatment as the executable.
    for parser in "$work/arm64/lib/nvim/parser"/*.so; do
        local name; name="$(basename "$parser")"
        lipo -create -output "$OUTPUT/lib/nvim/parser/$name" \
            "$parser" "$work/x86_64/lib/nvim/parser/$name"
    done

    # Architecture-independent, so one copy serves both. `share/man` and `share/icons` are dropped:
    # nothing inside an application bundle reads them.
    mkdir -p "$OUTPUT/share/nvim"
    cp -R "$work/arm64/share/nvim/runtime" "$OUTPUT/share/nvim/runtime"

    # macOS refuses to execute an unsigned Mach-O that arrived with a quarantine attribute, and a
    # `--deep` signature over the app bundle does not reliably reach a nested executable. Signing
    # here means the DMG carries a Neovim the system will actually start.
    codesign --force --sign - "$OUTPUT/bin/nvim" 2>/dev/null
    for parser in "$OUTPUT/lib/nvim/parser"/*.so; do
        codesign --force --sign - "$parser" 2>/dev/null
    done

    printf '  neovim %s · %s · %s\n' \
        "$NEOVIM_VERSION" "$(lipo -archs "$OUTPUT/bin/nvim")" "$(du -sh "$OUTPUT" | cut -f1)" >&2
}

# ── 자기 검사 ────────────────────────────────────────────────────────────────
# 번들된 Neovim 이 틀어지는 방식은 전부 조용하다. 한쪽 아키텍처만 들어가면 이 맥에서는
# 멀쩡하고 남의 맥에서만 안 뜨고, 런타임 디렉터리가 어긋나면 구문 강조와 파일타입 감지가
# 통째로 빠진 채 그냥 실행된다. 셋 다 "빌드 성공"과 구별되지 않으므로 실제로 띄워서 잰다.
self_test() {
    printf '=== vendor-neovim 자체 검사 ===\n'
    local failures=0
    local binary="$OUTPUT/bin/nvim"

    if [ ! -x "$binary" ]; then
        printf '  FAIL: %s 가 없다 — 먼저 빌드하라\n' "$binary"
        printf '  → 자체 검사 실패 1건.\n'
        return 1
    fi

    # 1. 두 아키텍처가 다 들어갔나 — 실행 파일과 파서 전부.
    local architectures; architectures="$(lipo -archs "$binary")"
    local missingArchitectures=0
    for wanted in "${ARCHITECTURES[@]}"; do
        case " $architectures " in
            *" $wanted "*) ;;
            *) printf '  FAIL: 실행 파일에 %s 가 없다 (%s)\n' "$wanted" "$architectures"
               missingArchitectures=$((missingArchitectures + 1)) ;;
        esac
    done
    failures=$((failures + missingArchitectures))
    # 실패한 항목을 다시 ok 로 적지 않는다 — 같은 줄에 FAIL 과 ok 가 나란히 찍히면
    # 읽는 사람이 어느 쪽이 판정인지 모른다.
    [ "$missingArchitectures" -eq 0 ] && printf '  ok: 실행 파일 아키텍처 (%s)\n' "$architectures"

    local thinParsers=0 parserCount=0
    for parser in "$OUTPUT/lib/nvim/parser"/*.so; do
        [ -e "$parser" ] || continue
        parserCount=$((parserCount + 1))
        case "$(lipo -archs "$parser")" in
            *arm64*x86_64*|*x86_64*arm64*) ;;
            *) printf '  FAIL: %s 가 유니버설이 아니다 (%s)\n' "$(basename "$parser")" "$(lipo -archs "$parser")"
               thinParsers=$((thinParsers + 1)) ;;
        esac
    done
    if [ "$parserCount" -eq 0 ]; then
        printf '  FAIL: 파서가 한 개도 없다\n'; failures=$((failures + 1))
    elif [ "$thinParsers" -eq 0 ]; then
        printf '  ok: 파서 %d개가 모두 유니버설이다\n' "$parserCount"
    else
        failures=$((failures + thinParsers))
    fi

    # 2. 실제로 실행되고, 핀으로 박은 그 버전인가.
    #
    # 사용자 설정을 읽지 않게 격리해서 잰다(`-u NONE -i NONE`). 여기서 재려는 것은 우리가
    # 조립한 트리이지 이 맥의 nvim 설정이 아니고, 설정이 섞이면 남의 맥에서 다른 답이 나온다.
    local reportedVersion
    reportedVersion="$("$binary" --version 2>/dev/null | head -1 | awk '{print $2}')"
    if [ "$reportedVersion" = "$NEOVIM_VERSION" ]; then
        printf '  ok: 실행되고 핀과 같은 버전을 보고한다 (%s)\n' "$reportedVersion"
    else
        printf '  FAIL: 버전이 다르다 — 기대 %s, 실제 %s\n' "$NEOVIM_VERSION" "${reportedVersion:-실행 실패}"
        failures=$((failures + 1))
    fi

    # 3. 런타임을 자기 트리 안에서 찾는가.
    #
    # 이게 이 검사의 본체다. 실행만 되는 것과 편집기로 쓸 수 있는 것은 다르다 — 런타임을
    # 못 찾으면 구문 파일도 파일타입 감지도 없이 그냥 뜬다.
    local runtimePath
    runtimePath="$("$binary" --headless -u NONE -i NONE -c 'echo $VIMRUNTIME' -c q 2>&1 | tr -d '\r' | tail -1)"
    case "$runtimePath" in
        "$OUTPUT"/*) printf '  ok: 런타임을 번들 안에서 찾는다\n' ;;
        *) printf '  FAIL: 런타임이 번들 밖을 가리킨다 — %s\n' "${runtimePath:-빈 응답}"
           printf '        (bin/nvim 옆의 share/nvim/runtime 배치가 깨졌다는 뜻이다)\n'
           failures=$((failures + 1)) ;;
    esac

    # 4. 런타임 파일이 실제로 읽히는가. 경로가 맞아도 내용이 안 왔을 수 있다.
    local filetypeAnswer
    filetypeAnswer="$("$binary" --headless -u NONE -i NONE \
        -c 'filetype on' -c 'edit /tmp/vendor-neovim-selftest.java' \
        -c 'echo &filetype' -c 'q!' 2>&1 | tr -d '\r' | tail -1)"
    if [ "$filetypeAnswer" = "java" ]; then
        printf '  ok: 런타임이 읽힌다 (.java 를 java 로 인식)\n'
    else
        printf '  FAIL: 파일타입 감지가 안 된다 — 기대 java, 실제 "%s"\n' "$filetypeAnswer"
        printf '        런타임 디렉터리는 있는데 내용이 안 왔다.\n'
        failures=$((failures + 1))
    fi

    [ "$failures" -eq 0 ] && { printf '  → 자체 검사 통과. 번들된 Neovim 이 두 아키텍처로 실행되고 런타임을 읽는다.\n'; return 0; }
    printf '  → 자체 검사 실패 %s건 — 이 트리를 근거로 "Neovim 을 싣었다"고 하지 마라.\n' "$failures"
    return 1
}

case "${1:-}" in
    --self-test) self_test ;;
    *) build; printf '%s\n' "$OUTPUT" ;;
esac
