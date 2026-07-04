# HwpKitCore

Platform-neutral 렌더 코어. **AppKit / UIKit / SwiftUI / CoreAnimation import 금지.** CoreGraphics / CoreText / Foundation / CoreHwp 만 허용.

## 파이프라인 (canonical)

```
CoreHwp.HwpFile
  → HwpDocumentActor.buildDocument (HwpKitNative)
     → HwpIndex             # docInfo.idMappings 인덱싱 (charShape/paraShape/…)
     → HwpPaginator (actor) # 페이지 lazy 생성
        ├─ per paragraph
        │   HwpTextRunBuilder → NSAttributedString
        │   HwpParagraphLayout (CTFramesetter)
        ├─ appendEmbeddedBlocks
        │   ctrls walk: header/footer/footnote/endnote/table/textbox
        │   재귀 (nested paragraph 안의 ctrls 도 계속)
        └─ per page
            HwpPaintListBuilder → HwpPaintList
  → HwpDocument { pages: [HwpPage(blocks, paintList)] }
```

## 블록 모델 gotchas

- `AnyHwpBlock.attributedString` — CT 페이로드. **immutable copy 필수** (`NSAttributedString(attributedString:)`)
- `AnyHwpBlock.hyperlinkURL` — block-level. `HwpPaginator.hyperlinkURL(in:)` 이 top-level 및 nested paragraph 양쪽에서 추출
- **랜덤 UUID identifier 금지.** equality/hash 는 `frame + kind + attributedString + url` 기반. 같은 문서 두 번 로드 시 동일 블록으로 인식되어야 함
- `HwpBlockKind`: `text` / `image` / `shape` / `table` / `textbox` / `footnote` / `placeholder`

## Paint list

- `HwpPaintCommand` = `@unchecked Sendable` enum. CF/NS 참조 타입 (`CGColor`/`CGPath`/`CGImage`/`NSAttributedString`) 을 담기 때문에 자동 Sendable 불가
- 케이스: `fillRect` / `strokeRect` / `drawText` / `drawPath` / `drawImage` / `drawPlaceholder` / `hyperlink`
- **`HwpPage.==` / `hash` 는 `paintList.commands.count` 만 비교** (structural fingerprint). 같은 count + 다른 내용 = `==`. 렌더 결과 비교용으로 쓰지 말 것

## 컨벤션

- **HWPUNIT canonical**: 변환은 `Utils/HwpUnits.swift` 에서만. `pt` / `px` / `HWPUNIT` 혼용 금지
- **번들 폰트 금지**. `Fonts/HwpFontMap.default` = script-aware fallback 매핑. `HwpFontResolver.resolve` 는 `CTFontDescriptorCreateMatchingFontDescriptor` 로 family/PS-name 후보를 매칭하고 결과를 (faceName, script, size) 키로 캐시
- Sendable actor: `HwpPaginator`, `HwpImageCache` (HwpKitNative)
- `HwpFontResolver.testDeterministic` — 스냅샷 테스트용 (system font 만 사용하는 결정론적 resolver)

## 새 블록 종류 추가

1. `Model/HwpBlock.swift` 의 `HwpBlockKind` 에 case 추가
2. `Layout/HwpPaginator.swift` 의 `childParagraphs(of:)` 에서 emit (unsupported walk 와 embedded 블록이 이 한 곳을 공유)
3. `Paint/HwpPaintListBuilder.swift` 의 `paintCommands(for:)` 에 케이스 추가
4. `Layout/HwpHitTester.swift` 의 `hit(page:point:)` 에 케이스 추가

## 안티 패턴

- `HwpPage` 렌더 결과가 다른지 `==` 로 확인 — 안 됨 (count 만 비교). blocks 배열이나 paintList.commands 를 직접 순회할 것
- `HwpBlockKind.image/.shape` block 은 현재 어떤 경로에서도 emit 되지 않음 (embedded shape/image geometry 미연결). 좌표 연결 전에 시각 fidelity 를 주장하지 말 것
- generated/semantic 텍스트 컨트롤 (`.pageNumberPosition`, `.autoNumber`, `.newNumber`, equation edit body) 을 조용히 무시 — 현재 미연결. 추가하려면 `HwpPaginator.childParagraphs(of:)` 확장
