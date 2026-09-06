#!/usr/bin/env bash
# Builds the tree-sitter parsers the embedded Neovim loads, plus their highlight queries.
#
# Why the application ships these at all: Neovim installs six parsers (c, lua, markdown, query,
# vim, vimdoc) and none of the languages this application indexes. Without a parser Neovim falls
# back to its regex syntax files, and those cannot tell a class name from a variable — measured,
# Java resolves into `Comment`, `Constant` and `Type` and nothing else, so class and method names
# render as plain text. Handing Neovim a parser is what makes the editor colour code the way an
# IDE does; the split from ADR-0010 is unchanged, Neovim still classifies and the application
# still chooses the colours.
#
# The grammars are already vendored for symbol extraction (`Package.swift`), but as Swift packages
# linked into the binary — a form Neovim cannot load. This builds the same sources again as
# loadable objects.
#
#   build-treesitter-parsers.sh              build into Resources/treesitter
#   build-treesitter-parsers.sh --self-test  prove Neovim actually loads what was built
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKOUTS="$REPO_ROOT/.build/checkouts"
OUTPUT="$REPO_ROOT/Resources/treesitter"

# Only Java, and both omissions were measured rather than assumed.
#
# Kotlin's grammar ships no `highlights.scm` at all. TypeScript ships one, but it is 35 lines of
# type rules — asked for the captures in `const alpha = "a string";` it returns **none**. Starting
# tree-sitter for either turns the regex syntax off and puts nothing in its place, so the editor
# would go from imperfect colour to no colour. Both keep the regex path they have today.
#
# The test that caught this is worth keeping in mind: TypeScript highlighting went plain and the
# build was green, because nothing asked whether the new classifier actually classified anything.
LANGUAGES=(java)

parser_sources() {  # <language> → the .c files to compile, first one decides the directory
    case "$1" in
        java)       echo "$CHECKOUTS/tree-sitter-java/src/parser.c" ;;
        typescript) echo "$CHECKOUTS/tree-sitter-typescript/typescript/src/parser.c" \
                         "$CHECKOUTS/tree-sitter-typescript/typescript/src/scanner.c" ;;
        *)          return 1 ;;
    esac
}

query_source() {  # <language> → the highlights.scm to bundle
    case "$1" in
        java)       echo "$CHECKOUTS/tree-sitter-java/queries/highlights.scm" ;;
        typescript) echo "$CHECKOUTS/tree-sitter-typescript/queries/highlights.scm" ;;
        *)          return 1 ;;
    esac
}

build() {
    # The checkouts only exist after a resolve, and a clean clone has none.
    swift package --package-path "$REPO_ROOT" resolve >&2

    rm -rf "$OUTPUT"
    mkdir -p "$OUTPUT/parser"

    for language in "${LANGUAGES[@]}"; do
        local sources; read -r -a sources <<< "$(parser_sources "$language")"
        local includeDirectory; includeDirectory="$(dirname "${sources[0]}")"

        # Universal for the same reason the application is: a parser that is arm64-only makes the
        # editor silently fall back to regex highlighting on an Intel Mac, which looks like a
        # missing feature rather than a missing file.
        cc -O2 -fPIC -shared \
            -arch arm64 -arch x86_64 \
            -I "$includeDirectory" \
            "${sources[@]}" \
            -o "$OUTPUT/parser/$language.so"

        mkdir -p "$OUTPUT/queries/$language"
        cp "$(query_source "$language")" "$OUTPUT/queries/$language/highlights.scm"

        printf '  %-12s %s · %s\n' \
            "$language" \
            "$(lipo -archs "$OUTPUT/parser/$language.so")" \
            "$(du -h "$OUTPUT/parser/$language.so" | cut -f1)" >&2
    done
}

# ── 자기 검사 ────────────────────────────────────────────────────────────────
# 빌드가 성공했다는 것과 Neovim 이 읽는다는 것은 다르다. `.so` 는 아키텍처가 하나여도,
# 심볼 이름이 어긋나도 조용히 만들어지고, 그 실패는 **강조가 안 붙는 화면**으로만 드러난다.
# 그래서 실제 Neovim 에 물려 파스 트리와 캡처가 나오는지까지 본다.
self_test() {
    printf '=== build-treesitter-parsers 자체 검사 ===\n'
    local failures=0

    for language in "${LANGUAGES[@]}"; do
        local object="$OUTPUT/parser/$language.so"
        if [ ! -f "$object" ]; then
            printf '  FAIL: %s.so 가 없다 — 먼저 빌드하라\n' "$language"
            failures=$((failures + 1)); continue
        fi

        local architectures; architectures="$(lipo -archs "$object")"
        for wanted in arm64 x86_64; do
            case " $architectures " in
                *" $wanted "*) ;;
                *) printf '  FAIL: %s.so 에 %s 가 없다 (%s)\n' "$language" "$wanted" "$architectures"
                   failures=$((failures + 1)) ;;
            esac
        done

        [ -f "$OUTPUT/queries/$language/highlights.scm" ] || {
            printf '  FAIL: %s 하이라이트 쿼리가 없다 — 파서만으로는 아무 색도 안 붙는다\n' "$language"
            failures=$((failures + 1))
        }
    done

    # 실제로 Neovim 에 물려 본다. 여기가 이 검사의 본체다.
    #
    # 표본 목록은 `LANGUAGES` 에서 만든다. 따로 적어 두었더니 언어를 뺀 뒤에도 검사만 옛
    # 목록을 들고 "typescript 파서를 못 만든다"고 실패했다 — 목록이 두 벌이면 한쪽만 고쳐진다.
    local samples=""
    for language in "${LANGUAGES[@]}"; do
        samples="$samples $language = { filetype = \"$language\", code = sampleFor(\"$language\") },"
    done

    local report
    report="$(nvim --headless -i NONE --clean --cmd "set runtimepath^=$OUTPUT" -c 'lua
      local function sampleFor(language)
        local byLanguage = {
          java = "class Sample { void run() {} }",
          typescript = "export class Sample { run(): void {} }",
        }
        return byLanguage[language] or "class Sample {}"
      end
      local samples = { '"$samples"' }
      for language, sample in pairs(samples) do
        local buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { sample.code })
        vim.bo[buffer].filetype = sample.filetype
        local parsed, parser = pcall(vim.treesitter.get_parser, buffer, language)
        if not parsed or parser == nil then
          print(("FAIL %s 파서를 못 만든다"):format(language))
        else
          local query = vim.treesitter.query.get(language, "highlights")
          if query == nil then
            print(("FAIL %s 쿼리를 못 읽는다"):format(language))
          else
            local captures = 0
            for _ in query:iter_captures(parser:parse()[1]:root(), buffer, 0, -1) do
              captures = captures + 1
            end
            print(("%s %s 캡처 %d개"):format(captures > 0 and "ok" or "FAIL", language, captures))
          end
        end
      end' -c q 2>&1 | grep -vE '^$')"

    printf '%s\n' "$report" | sed 's/^/  /'
    case "$report" in
        *FAIL*) failures=$((failures + 1)) ;;
    esac

    if [ "$failures" -eq 0 ]; then
        printf '  → 자체 검사 통과. Neovim 이 실제로 파스하고 캡처를 낸다.\n'
        return 0
    fi
    printf '  → 자체 검사 실패 %s건 — 이 파서를 근거로 강조를 주장하지 마라.\n' "$failures"
    return 1
}

case "${1:-}" in
    --self-test) self_test ;;
    *) build; printf '%s\n' "$OUTPUT" ;;
esac
