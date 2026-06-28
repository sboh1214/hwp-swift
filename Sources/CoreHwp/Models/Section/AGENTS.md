# Section 모델

HWP 본문 payload. 한 `.hwp`의 한 구역(section)당 `HwpSection` 하나이며,
각각이 `HwpParagraph` 배열을 가진다. 단락은 텍스트, 글자 모양 run, 라인
세그먼트, 영역 태그, 그리고 박혀 있는 컨트롤(표·다단·도형)을 보관한다.

## 구조

```
Section/
├── HwpParagraph.swift              # 단락 컨테이너 - HwpSectionTag로 하위 record를 dispatch
├── HwpParaHeader.swift             # 단락 헤더 (run 개수, 컨트롤 마스크)
├── HwpParaText.swift               # 텍스트 run - [HwpChar]로 디코딩
├── HwpChar.swift                   # 글자 하나: normal | control(UInt16) | extended (16 byte)
├── HwpParaCharShape.swift          # (위치, charShapeId) 튜플
├── HwpParaLineSeg.swift            # 라인 세그먼트 배열
├── HwpParaLineSegInternal.swift    # 세그먼트별 내부 레이아웃
├── HwpParaRangeTag.swift           # inline 영역 태그
├── HwpCtrlHeader.swift             # 일반 컨트롤 헤더 (아직 모델링되지 않은 컨트롤의 fallback)
├── HwpListHeader.swift             # 리스트 헤더 (표 셀 등)
└── CtrlHeader/                     # HwpCtrlId로 dispatch되는 컨트롤 payload
    ├── SectionDef/                 # 구역 정의, 페이지/각주/테두리 모양
    ├── Column/                     # 다단 레이아웃
    ├── Table/                      # 표 + 셀 + 영역 속성
    ├── HwpGenShapeObject.swift     # 도형
    ├── HwpCommonCtrlProperty.swift # 공통 컨트롤 속성
    └── HwpPageNumberPosition.swift
```

## 컨트롤 Dispatch

`HwpParaHeader.ctrlMask`가 어떤 단락에 컨트롤이 붙는지 표시한다. 각 컨트롤
record는 4-byte 컨트롤 ID로 시작하며,
[`Enums/CtrlId/Hwp{Common,Other,Field}CtrlId.swift`](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Enums/CtrlId/)와 매칭되어
`HwpCtrlId` enum case로 들어간다. ID 자체를 모르는 컨트롤은
`HwpCtrlId.unknown(HwpCtrlHeader)`, ID는 알지만 세부 모델링이 없거나 typed
모델 승격에 실패해 raw 보존이 더 맞는 컨트롤은
`HwpCtrlId.notImplemented(HwpCtrlHeader)` 또는 raw-preserving wrapper로
떨어진다 — **throw 금지, assert 금지**. 그대로 보존해야 라운드트립이
깨지지 않는다. 잘린 payload처럼 구조 자체가 malformed인 경우에는 crash가
아니라 typed `HwpError`를 반환한다.

새 컨트롤 추가 절차:

1. 4-byte ID를 `Enums/CtrlId/`의 알맞은 파일에 추가.
2. `CtrlHeader/` 하위에 payload struct 추가 (하위 record가 있으면 전용
   subdirectory).
3. `HwpCtrlId`에 case 추가, manual `Codable` 구현 갱신.
4. 단락 dispatch에서 `.notImplemented(HwpCtrlHeader)`로부터 분리.

## 컨벤션

- 폴더명과 파일명은 PascalCase에 공백을 넣지 않는다 — `CtrlHeader/`,
  `SectionDef/`, `Table/`, `Column/`.
- 글자 코드는 UTF-16LE. `HwpChar.extended`는 선두 control 코드를 포함해
  16 byte를 소비 — 텍스트 디코딩 시 offset 주의.
- 단락 하위 record는 고정된 순서로 디코딩된다 (header → text → charShape →
  rangeTag → lineSeg → ctrls). 순서를 바꾸지 말 것.

## 안티 패턴

- 모르는 컨트롤에 대해 `invalidCtrlId`를 throw — `.unknown` 또는
  `.notImplemented`로 떨어뜨릴 것. throw 하면 미모델 컨트롤이 포함된 모든
  픽스처가 깨진다.
- 단락 개수 하드코딩 — 구역(section)의 단락 배열은 가변. index 대신 iterate.
- `CtrlHeader/` 밖에 컨트롤 로직 추가 — dispatch는 `HwpParagraph`에,
  payload는 여기에.
