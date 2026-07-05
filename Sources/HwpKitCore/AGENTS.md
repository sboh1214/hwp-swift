# HwpKitCore

Platform-neutral 렌더 코어. **AppKit / UIKit / SwiftUI / CoreAnimation import 금지.** CoreGraphics / CoreText / Foundation / CoreHwp 만 허용.

## 파이프라인 (canonical)

```
CoreHwp.HwpFile
  → HwpDocumentActor.buildDocument (HwpKitNative)
     → HwpIndex             # docInfo.idMappings 인덱싱 (charShape/paraShape/…)
     → HwpImageStore        # binItemId(1-based) → BinData 바이트 조인
     → HwpPaginator (actor) # 페이지 lazy 생성
        ├─ per paragraph
        │   HwpTextRunBuilder → NSAttributedString
        │   HwpParagraphLayout (CTFramesetter)
        ├─ appendControlBlocks     # 컨트롤 → 실제 레이아웃 엔진
        │   .table  → HwpTableLayout (row 단위 페이지 분할)
        │   gso/도형 → HwpTextboxLayout / HwpShapeGeometry / 이미지 블록
        │   .header/.footer → 머리말/꼬리말 밴드 텍스트 블록
        │   .footnote/.endnote → 페이지 하단 HwpFootnoteLayout
        └─ per page (cacheCurrentPage)
            HwpPaintListBuilder → HwpPaintList
  → HwpDocument { pages: [HwpPage(blocks, paintList)], imageStore }
```

## 블록 모델 gotchas

- `AnyHwpBlock.attributedString` — CT 페이로드. **immutable copy 필수** (`NSAttributedString(attributedString:)`)
- `AnyHwpBlock.payload` — 종류별 상세 결과: `.table(HwpTableFrame)` / `.textbox` / `.footnote` / `.shape(HwpShapeGeometry)` / `.image(HwpImageBlockInfo)`. payload 내부 좌표는 **블록-로컬** (footnote 의 separator 만 페이지 좌표)
- `AnyHwpBlock.source` — `HwpBlockSource(controlInstanceId/paragraphId)`: 편집 기능이 렌더 결과에서 CoreHwp 모델로 돌아가는 참조
- `AnyHwpBlock.hyperlinkURL` — block-level. `HwpPaginator.hyperlinkURL(in:)` 이 top-level 및 nested paragraph 양쪽에서 추출
- **랜덤 UUID identifier 금지.** equality/hash 는 `frame + kind + text + url + payload + source` 기반. 같은 문서 두 번 로드 시 동일 블록으로 인식되어야 함
- `HwpBlockKind`: `text` / `image` / `shape` / `table` / `textbox` / `footnote` / `placeholder`

## 앵커 규칙 (표 70)

- treatAsChar 또는 textWrap ∈ {square, tight, through, topAndBottom}: 흐름 위치에 배치 + 높이 소비
- textWrap ∈ {behindText, inFrontOfText}: 기준(쪽/문단) + 오프셋 위치에 배치, 흐름 소비 없음 — **text 블록과 겹칠 수 있음** (overlap 검사는 text-text 쌍만)
- 오프셋은 `Int32(bitPattern:)` 으로 읽는다 (음수 허용; `points(fromHwpUnitU:)` 금지)

## Paint list

- `HwpPaintCommand` = `@unchecked Sendable` enum. CF/NS 참조 타입을 담기 때문에 자동 Sendable 불가
- 케이스: `fillRect` / `strokeRect` / `drawText` / `drawPath` / `drawImage` / `drawImageReference(binItemId:rect:)` / `drawPlaceholder` / `hyperlink`
- `drawImageReference` 는 비트맵을 운반하지 않는다 — HwpKitNative 의 `HwpPageImageProvider` 가 `HwpImageStore` + `HwpImageCache` + `HwpImageAdapter` 로 지연 디코딩
- **`HwpPage.==` / `hash` 는 `paintList.commands.count` 만 비교** (structural fingerprint). 렌더 결과 비교용으로 쓰지 말 것

## 컨벤션

- **HWPUNIT canonical**: 변환은 `Utils/HwpUnits.swift` 에서만 (1 pt = 100 HWPUNIT). `pt` / `px` / `HWPUNIT` 혼용 금지
- **번들 폰트 금지**. `HwpFontResolver.resolve` 는 매칭 결과를 (faceName, script, size) 키로 캐시
- borderFill 참조는 **1-based (0 = 없음)**: `resolvedBorderFill` 은 id-1 을 먼저, 원래 id 를 다음에 시도
- Sendable actor: `HwpPaginator`, `HwpImageCache` (HwpKitNative)
- `HwpFontResolver.testDeterministic` — 스냅샷 테스트용 결정론적 resolver

## 새 블록 종류 추가

1. `Model/HwpBlock.swift` 의 `HwpBlockKind` + `Model/HwpBlockPayload.swift` 에 payload case 추가
2. `Layout/HwpPaginator.swift`: `childParagraphs(of:)` (unsupported walk) 와 `appendControlBlocks(from:depth:)` (렌더) 양쪽에 추가
3. `Paint/HwpPaintListBuilder.swift` 의 `paintCommands(for:)` 에 payload 렌더 추가
4. `Layout/HwpHitTester.swift` 의 `hit(page:point:)` 에 케이스 추가

## 안티 패턴 / 남은 한계

- `HwpPage` 렌더 결과가 다른지 `==` 로 확인 — 안 됨 (count 만 비교). blocks 배열이나 paintList.commands 를 직접 순회할 것
- 다단 (`cold` 컨트롤) 미연결 — `HwpPageGeometry.columnFrames` 는 항상 `[contentFrame]`
- treatAsChar 개체는 문단 뒤 흐름 위치에 배치된다 (줄 안 FFFC 위치 아님) — 줄 중간 앵커는 미구현
- 미주(endnote)는 호스트 페이지 하단에 각주와 동일하게 배치된다 (문서/구역 끝 배치는 미구현)
- 수식 (`eqed`) 은 EQEDIT 스크립트 렌더 없이 placeholder + textbox 폴백 텍스트
- 그림 crop/밝기/명암/효과 (표 107) 는 디코딩만 되고 렌더에는 미적용
- 페이지보다 큰 표 row는 통째로 방출된다 (셀 내부 분할 미구현 — 하단 여백 침범 가능)
- 중첩 표는 바깥 표가 placeholder가 되고 안쪽 표는 재귀 경로로 렌더된다
- 페이지 분할 직후 수집된 각주는 다음 cacheCurrentPage의 페이지에 실린다 (참조 위치와 한 페이지 어긋날 수 있음); 반 페이지를 넘는 각주는 잘린다
- 머리말/꼬리말은 컨트롤이 붙은 문단의 페이지에만 렌더된다 (페이지마다 반복 미구현)
