# 라이브 E2E 대상 프로젝트 (리더 소유 — 빌드 산출물 아님)

인증(`_workspace/CERTIFICATION.md` §3)에서 앱으로 열 대상이다. 지원 언어가
Kotlin·Java·TypeScript·JavaScript 라 이 레포(Swift)로는 E2E 를 할 수 없어 따로 둔다.

- **SC-1**: `SymbolIndex` 클래스 정의가 `src/core/SymbolIndex.ts` 한 곳. 옆에 `SymbolIndexHolder`
  가 있어 단어 경계가 지켜지는지도 같이 드러난다.
- **SC-2**: `resolveTarget` 함수가 **세 곳**에 정의돼 있다(`core`·`search`·`tree`).
- **SC-3**: 아무 파일에 함수를 추가하고 저장하면 심볼 검색에 떠야 한다.
- **한글**: `src/core/text.ts` 에 한글 주석·문자열이 있어 셀 폭·커서 정렬을 눈으로 본다.
- **제외**: `node_modules/` 가 있어 스캔에서 빠지는지 확인한다.
