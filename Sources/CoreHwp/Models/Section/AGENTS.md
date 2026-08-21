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
5. `Models/HwpParseDiagnostic.swift`의 `collect(ctrl:)`에 진단 순회 case 추가
   (`default:` 없는 exhaustive switch라 컴파일러가 강제한다 — 근거는 상위
   `CoreHwp/AGENTS.md` 같은 절).

## 컨벤션

- 폴더명과 파일명은 PascalCase에 공백을 넣지 않는다 — `CtrlHeader/`,
  `SectionDef/`, `Table/`, `Column/`.
- 글자 코드는 UTF-16LE. `HwpChar.extended`는 선두 control 코드를 포함해
  16 byte를 소비 — 텍스트 디코딩 시 offset 주의.
- 단락 하위 record는 고정된 순서로 디코딩된다 (header → text → charShape →
  rangeTag → lineSeg → ctrls). 순서를 바꾸지 말 것.

## 부분 복구 placeholder (#65)

`HwpLoadOptions.recoverPartialContent`가 켜지면 손상 문단·구역이 fail-fast
대신 placeholder로 대체된다 (설계·게이트는 루트 `AGENTS.md` "부분 복구").
placeholder 생성이 이 폴더에 있으므로 그 형태 계약을 여기 남긴다.

- `HwpParagraph.parseFailurePlaceholder(record:error:)`는 `paraText = nil` +
  원본 레코드를 `unknownChildren`에 보존 + `parseFailure`에 원인. `paraText`가
  nil인 이유: 기본 문단은 extended char 2개를 갖는데 ctrlHeader 없이 두면
  컨트롤 매칭이 어긋나고, nil은 하류 run builder가 이미 빈 문단으로 처리한다.
- `HwpSection.parseFailurePlaceholder(error:rawPayload:)`는 빈 문서 템플릿 문단
  (sectionDef+column)을 채워 조판 전제를 지키고 구역 수를 보존한다.
- **`parseFailure`는 Equatable/Hashable에 참여한다** — placeholder와 진짜 빈
  문단/구역이 같다고 판정되면 복구 흔적이 비교에서 지워진다. 새 저장 필드지만
  raw payload 파생이 아니라 로드 사건의 기록이라 legacy 아카이브에서
  재수화하지 않는다 (`decodeIfPresent ?? nil` — 루트 "Codable 아카이브 호환").
- 손상 **메모 문단**도 `HwpParagraph.load`의 메모 수집 루프에서 개별
  placeholder로 대체한다 — 전파시키면 호스트 문단 전체가 placeholder가 되어
  본문·메모 그룹 경계까지 잃는다.
- **구역의 첫 문단은 복구 대상이 아니다** (#110). sectionDef가 첫 문단에만
  붙으므로 이를 문단 placeholder로 삼키면 paginator가 구역 경계를 놓쳐 그
  구역이 앞 구역 지오메트리로 조판된다. `HwpSection.load`가 `paragraphs.isEmpty`
  일 때 전파해 `HwpFile`이 구역 단위 placeholder로 승격시킨다 — 그 가드를
  지우면 경계 유실이 재발한다 (루트 "부분 복구").

## 메모 계열 child 소비 (#66)

`unconsumedRecords`는 메모 계열(MEMO_LIST 93·메모 문단 66)을 태그가 아니라
**그룹 빌더가 실제 소비한 child 인덱스**로 제외한다. 태그 blanket 제외는 양쪽으로
틀렸다 — 첫 MEMO_LIST **앞**의 stray 문단(66)은 그룹 빌더가 소비하지 않는데
(`current == nil`) 함께 삼켜져 typed 소비도 raw 보존도 없이 모델에서 사라졌고,
문단 없는 MEMO_LIST는 빈 그룹으로 typed 소비됐는데도 `unknownChildren`에 중복
보존됐다. 전자는 미해석 요소 집계(`parseDiagnostics`)가 **구조적으로 볼 수 없는**
유실이라 #66에서 고쳤다 — 이 폴더가 그 유실의 발생 지점이었다. 가드는
`ParagraphMemoRecursionTests`의 stray/빈 그룹 테스트이고, 집계 쪽 계약은 루트
`AGENTS.md` "미해석 요소 집계"에 있다.

## `HwpParaText.wcharCount` (#67)

파스 루프가 실제로 소비한 wchar의 **누적 저장값**이다 (컨트롤 문자 = 8 wchar).
문단당 `reduce` 재계산에서 바뀌었지만 값·공개 API는 동일하다 — `charArray`
변경 시 `didSet`이 재동기화한다. 파생값이라 **Equatable/Hashable·인코딩 모두에서
제외**: payload **유무** 파생이라 `HwpChar` 동등성(type/value만)과 어긋날 수
있고, 빈 템플릿 vs 파싱본의 round-trip 동등성이 이 제외에 기댄다. custom
Codable은 `rawPayload`/`charArray` 두 키만 인코딩하고 디코더가 재계산한다.
"파생 필드는 저장보다 재계산" 컨벤션의 예외이므로 되돌리지 말 것 — `HwpChar`가
문서 전체 문자 수만큼 존재해 문단당 reduce가 반복 비용이라 저장으로 옮겼다.

`HwpTableCellHeader`의 음수 `paragraphCount` 가드도 이때 제거됐다 — 표 셀은
`UInt16`을 `Int32`로 승격해 읽어 항상 비음수라 도달 불가였다 (리스트/글상자와
달리 bytes 6-7이 셀 확장 속성이라 읽기 폭을 넓힐 수 없다는 근거가
`HwpTable.swift` 주석). 되살리지 말 것.

## 안티 패턴

- 모르는 컨트롤에 대해 `invalidCtrlId`를 throw — `.unknown` 또는
  `.notImplemented`로 떨어뜨릴 것. throw 하면 미모델 컨트롤이 포함된 모든
  픽스처가 깨진다.
- 단락 개수 하드코딩 — 구역(section)의 단락 배열은 가변. index 대신 iterate.
- `CtrlHeader/` 밖에 컨트롤 로직 추가 — dispatch는 `HwpParagraph`에,
  payload는 여기에.
- `parseFailure` placeholder 로직을 다른 모델·다른 error로 넓히기 — 복구는
  문단·구역·메모 문단 한정이고 게이트는 `error.isRecoveryExempt`다 (루트
  "부분 복구").
- 메모 계열 child를 **태그로** blanket 제외 — 소비 인덱스 기반이어야 한다
  (위 "메모 계열 child 소비"). 되돌리면 stray 문단(66)이 typed 소비도 raw
  보존도 없이 모델에서 사라진다.
