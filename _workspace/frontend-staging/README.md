# 프론트엔드 스테이징 (임시)

`Package.swift`의 프론트 타깃 분리가 반영되기 전까지 여기에 보관한다.
**SPM은 `_workspace/`를 보지 않으므로 빌드에 영향이 없다.**

- `Sources/CodeNavigatorAppKit/` → 반영 후 레포 루트의 `Sources/CodeNavigatorAppKit/`로 이동
- `Tests/CodeNavigatorAppKitTests/` → 반영 후 `Tests/CodeNavigatorAppKitTests/`로 이동
- `Package.swift` → 미러 전용. 옮길 때 버린다.
- 개발 중에는 계약을 실제 소스로 심볼릭 링크해 썼다(복사본 드리프트 방지):
  `ln -s ../../Sources/CodeNavigatorContract Sources/CodeNavigatorContract`

현재 상태: **215 테스트 / 20 스위트 전부 통과** (2026-08-29 17:39 실측)
