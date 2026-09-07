# Hwpx 지식 베이스

HWPX(OCF ZIP + OWPML XML, KS X 6101)를 **기존 `Hwp*` 모델로 변환 파싱**하는
서브트리다. 목표는 새 모델이 아니라 `HwpFile` 합성이다 — 그래야 뷰어 스택
(HwpKitCore/Native/Kit)이 무변경으로 HWPX를 렌더한다.

## 파이프라인

```
.hwpx 바이트
  → HwpxFormatDetection            # HwpFile init 3종의 매직 스니핑 (PK → 이 경로)
  → HwpxArchive                    # 자체 ZIP 리더 (central directory 신뢰, method 0/8)
  → HwpxContainer                  # mimetype 게이트 + encryption.xml 거부 + 예산
  → HwpxXMLTreeParser              # SAX → HwpxXMLNode mini-DOM (hp:switch 해소 포함)
  → Hwpx*Mapper (Owpml/)           # OWPML → Hwp* 모델 (id 리맵·WCHAR 합성)
  → HwpxDocumentAssembler          # extension HwpFile.init(hwpxData:options:)
```

## 지켜야 하는 불변식

- **extended 문자 ↔ ctrl 슬롯 1:1** — `HwpTextRunBuilder.extendedOrdinal`이
  모든 extended 문자를 세며 `ctrlHeaderArray`를 서수로 인덱싱한다. 필드 끝
  (inline 4)은 슬롯이 없다. 앵커를 추측으로 만들거나 빼면 정렬이 무너진다.
- **`startingIndex`는 WCHAR 좌표** — 텍스트 1 code unit = 1, 컨트롤 = 8.
  합성 컨트롤 문자에는 반드시 14바이트 payload를 실어야 `wcharCount`(payload
  유무 기반)와 위치 산술(type 기반)이 일치한다. payload 선두 4바이트는 LE
  ctrl id다 (`HwpInlineControl.rawControlId` 계약).
- **id 리맵은 gap-fill이 아니다** — HWPX id는 dense가 아니라서
  (`HwpxIdTables`) 가족별 문서 등장 순서 오프셋을 부여하고 모든 `*IDRef`를
  재작성한다. borderFill과 번호/글머리표 참조는 1-based(0 = 없음) —
  조판이 `> 0` 게이트 뒤에서 -1로 되돌린다. 댕글링은 0 폴백. 구역 정의의
  개요 번호 참조(`hp:secPr@outlineShapeIDRef` → `numberParaShapeId`)도 같은
  1-based다 (#152, 아래 "구역의 개요 번호 참조").
- **lineseg 안전밸브** — `<hp:linesegarray>`는 절대 캐시 조판의 입력이다.
  미지 요소로 위치가 불확실하거나 sanity(첫 textpos 0·단조·범위)를 어기면
  **빈 배열로 강등**한다. 틀린 캐시로 오렌더하는 것보다 reflow가 낫다.
- **미지 요소는 `hwpxSyntheticTagId`(0) + 요소명 payload**로
  `HwpUnknownRecord`에 남긴다 — `parseDiagnostics()`가 무변경으로 HWPX
  미해석 요소를 보고하는 규약이다. HWPX 문서의 진단에서 tagId 0의 payload는
  UTF-8 OWPML local name으로 읽되, **속성 수준 강등**은 `요소@속성=값` 꼴이다
  (현재 `secPr@outlineShapeIDRef=` 하나 — "구역의 개요 번호 참조" 참조).
- **요소 매칭은 (namespace URI, local name)** — 접두사(hp/hh/hs)는 문서마다
  다를 수 있다. 낯선 namespace의 동명 요소는 OWPML로 오인하지 않는다.
- **복구 규약은 바이너리와 동일** — 손상 문단은 placeholder, 구역 첫 문단은
  전파해 구역 단위 승격(#110), recovery-exempt(자원 한도·미지원)는 항상
  전파. 재귀 깊이는 `HwpxMappingContext.descending()`이 `maxNestingDepth`로
  가드한다 (`parseTreeRecord` level 가드의 XML 대응).

## 컨테이너 결정

- ZIP 크기는 항상 central directory 선언값 (data descriptor 무력화). 중복
  이름 첫 등장 우선. Zip64·멀티 디스크·미지 압축 method는 typed 거부.
  압축 해제는 `HwpInflate`(raw DEFLATE = method 8) 재사용 — 해제 도중 한도.
- `mimetype != application/hwp+zip`은 `invalidArchive` — .docx 등 임의
  ZIP이 하류 XML 오류로 표류하지 않게 하는 포맷 게이트다.
- `META-INF/encryption.xml` 존재 = `unsupportedFeature(.encryptedDocument)`.
- 집계 예산은 `HwpxByteBudget` — `StreamReader`의 aggregate와 같은 역할.

## 1차 범위 밖 (미해석 강등 — 진단으로 보고됨)

도형(line/rect/…)·수식·글상자(`.notImplemented`; `hp:default` fallback 없이
`hp:chart`만 오는 문서도 여기 — OLE 개체 `hp:ole`은 #134에서 승격됐다),
홀/짝수 조정(`hp:pageNumCtrl` → `pgct`), 형광펜·변경 추적 표식(zero-width 진단),
그러데이션/이미지 채우기, 명시 탭 정지, 쪽 테두리.
승격 시 대응 요소를 `HwpxControlMapper` 분류표에서 옮긴다.

**구역 부속 컨트롤 중 남은 강등은 `hp:pageNumCtrl` 하나다** (#163의 세 단계가
#167 머리말·꼬리말, #168 각주·미주·자동 번호, #169 새 번호·쪽 감추기·책갈피·
찾아보기 표식으로 끝났다). `pgct`는 바이너리 쪽에 표 146의 typed 모델이 없고
저장소 실물 36종에 사례가 0건이라 payload를 지어내야 하며, 승격해도
`HwpUnsupportedDetector`가 여전히 "알 수 없음: pageCT"를 낸다 — 실물 표본이
생길 때 함께 다룬다. `HwpxFileTests`의 강등 진단 핀이 이 요소를 쓴다.

**머리말·꼬리말은 #167에서 승격됐다** (`HwpxHeaderFooterMapper`). `hp:header`·
`hp:footer` → `.header`/`.footer(HwpListControl)`이고 조판(`HwpPageChromeBuilder`)이
읽는 값은 적용 범위와 리스트 문단 둘뿐이다. 적용 범위는 컨트롤 헤더 payload를
**되읽어** 얻으므로(`headerFooterApplyScope`가 오프셋 4의 UINT32 하위 2비트,
표 141) payload 합성이 렌더 필수이고, 바이너리 `HwpListControl.load`와 같이
`decoupledPayload`로 **양 모드 보존**한다 — `preservedPayload` 게이트를 쓰면
`.viewer`에서 홀·짝수 머리말이 전부 양쪽으로 그려진다. `applyPageType`은
`BOTH`·`EVEN`·`ODD`이고 생략·미지 이름은 양쪽으로 접는다(범위를 추측해 쪽을
건너뛰면 머리말이 통째로 사라진다). 실물 구조는 `header-footer` 변환 쌍이
정본이다 — `hp:subList@vertAlign`이 머리말 `TOP`·꼬리말 `BOTTOM`이고, 문단 안
`hp:linesegarray`도 본문과 같은 경로로 모델에 실린다 — 다만 쪽 크롬은 그 캐시를
쓰지 않고 CT로 다시 조판한다(`HwpPageChromeBuilder.layoutBandBlocks`, 바이너리
경로도 같다).

`hp:visibility`의 `hideFirstHeader`·`hideFirstFooter`·`hideFirstMasterPage`·
`hideFirstPageNum`을 구역 정의 속성(표 132 bits 0·1·2·5)으로 함께 옮긴다 — 승격
뒤에는 이 플래그가 없으면 감춰야 할 구역 첫 쪽에도 머리말이 그려진다. `border`·
`fill` 열거와 `showLineNumber`는 대응 소비자가 없어 옮기지 않는다.

**미실측**: `applyPageType`의 `EVEN`·`ODD`와 속성 생략 경로는 실물이 없다
(저장소의 유일한 실물은 `BOTH`). 표 141 나열 순서를 따랐고 합성 입력으로만 잠갔다.

가드: `HwpxHeaderFooterMapperTests`(매핑·payload 모양·보존 게이트·진단),
`HwpPageChromeApplyScopeTests`(홀·짝수 범위가 실제로 쪽을 가르는지),
`HwpxFixtureRenderTests.testHwpxPageChromeMatchesHwpPairs`(HWP 쌍 등식 + 직접 핀).

2026-09-02 한글.app 12.30.0 나란히 육안 대조(변환 쌍 10종 13쪽, 한컴 폰트
모드): 쪽수 10종 전부 일치, 표·그림·다단·글자 장식·쪽나눔 일치. HWPX
렌더에만 보이던 격차는 범위 밖 3건(글머리표 "-" #133·차트 OLE #134·쪽 번호
#135)이었고, HWP 쌍 렌더와 HWPX 렌더는 그 3건을 빼면 동일했다. 쪽 번호는
#135, 차트 OLE는 #134, 글머리표는 #133에서 승격돼 남은 격차는 없다. 한글.app
자체가 포맷에 따라 다르게 그리는 것이 하나 있다 — CharShape 취소선 견본(HWP는
취소선 비트에 더해 스펙 미정의 밑줄 종류 raw 2(`HwpUnderlineType.undefined2`)를
갖고, HWPX 재저장본은 밑줄 없음 + `<hh:strikeout>`만 적는다)을 .hwp는 글자 아래
단선으로, .hwpx는 글자 가운데 취소선으로 그린다. 우리는 두 포맷 모두 HWP 쪽(아래
단선)으로 그린다 (#136). 그래서 등가 투영은 밑줄 종류를 비교하되 raw 2만
없음으로 접는다 — 진짜 '글자 위'는 raw 3 ↔ `type="TOP"`으로 같은 `.above`에
모인다 (#149, `underline-above` 쌍).

## 구역 부속 표식 (`hp:newNum`·`hp:pageHiding`·`hp:bookmark`·`hp:indexmark`, #169)

`HwpxSectionMarkMapper`가 넷을 `.newNumber`/`.pageHide`/`.bookmark`/`.indexmark
(HwpOtherControl)`로 옮긴다. 강등 상태에서는 조판이 **쪽 번호를 되돌리지도
감추지도 못했다** — `HwpPaginator.applyNewNumbers`와
`HwpPageChromeBuilder.pageHideMask`가 typed 컨트롤만 보기 때문이다
(`section-marks` 쌍 실측: 강등 HWPX가 `1·2·3`, HWP 쌍이 `(감춤)·9·10`).

**제어 문자 코드는 새 번호·쪽 감추기 21, 책갈피·찾아보기 표식 22다.** 코드 18은
자동 번호(`atno`) 전용이고, 승격 전 강등 표는 `newNum`을 18로 적고 있었다 —
저장소 실물 36종 전수 집계가 `atno` 3,436건 전부 18 · `nwno` 41건 전부 21로
갈린다. 기존 텍스트 축은 제어 문자를 전부 걸러내고 `controlMask`에는 소비자가
없어 이 오기를 잡을 축이 없었다 —
`HwpxHwpEquivalenceSectionMarkProjection`의 `sectionMarks`가 그 자리를 메운다.

payload는 전부 **합성해서 바이너리 로더에 태운다**(`HwpOtherControl.init`) —
typed 뷰와 로드 옵션 게이트를 한 번에 얻는 #167·#168과 같은 규약이다.

| 요소 | payload | 비고 |
|---|---|---|
| `hp:newNum` | 4CC + 속성 UINT32 + 번호 UINT16 = **10바이트** | 12바이트를 넘기면 레거시 `numberingInfo` 오버레이가 실물에 없는 뷰를 만든다 |
| `hp:pageHiding` | 4CC + 마스크 UINT32 = **8바이트** | 여섯 불리언 → 표 145 bits 0-5 |
| `hp:bookmark` | 4CC **4바이트** + `CTRL_DATA` 자식 | 이름은 ParameterSet `0x021B`(item id `0x4000_0000`, type 1) |
| `hp:indexmark` | 4CC + (길이 WORD + WCHAR)×2 + UINT32 | 마지막 UINT32는 한글 12.30이 -1, 레거시가 0 |

**쪽 감추기 비트는 실측으로 확정됐다** — `section-marks`의 두 표본이 서로의
여집합이라(`0x29` = 머리말·쪽 테두리·쪽 번호, `0x16` = 꼬리말·바탕쪽·쪽 배경)
여섯 비트가 한 가지로 정해진다. 이름·순서는 한컴 공개 모델
`OWPML/Class/Para/pageHiding.cpp`의 나열과 같고, 표 132를 옮긴
`HwpSectionDefProperty`의 bits 0-5와도 같다. 그 전에는 저장소 실물이 전부
`0x20`뿐이라 bit 5 말고는 추론이었다.

**`TOTAL_PAGE`는 승격하지 않는다.** `HwpAutoNumberKind`가 0-5뿐이라 `.page`로
접히는데, 새 번호의 `.page`는 `pendingPageNumber`를 갈아 **그 뒤 모든 쪽**의
번호를 바꾼다 — 강등 상태에는 없던 오작동이다. `autoNumberKinds`에 없는 이름은
자리(코드·4CC)만 지키는 강등 앵커로 되돌린다 (#168 `hp:autoNum`과 같은 규약).
길이 WORD를 넘는 책갈피·찾아보기 이름도 같은 방식으로 강등한다 — `WORD(count)`가
트랩하고(P1), 던지면 구역 첫 문단(복구 대상이 아닌 자리)에서 문서 전체가 파싱
실패가 되기 때문이다.

**미실측**: `hp:indexmark`의 `hp:secondKey`(한글 macOS 12.30에 대화상자가 없어
두 번째 키워드를 만들 수 없다)와 문자열 뒤 UINT32의 의미. 두 번째 키워드는 첫
키워드와 같은 (길이 + WCHAR) 꼴로 이어 붙이고 합성 입력으로만 잠갔다.

가드: `HwpxSectionMarkMapperTests`(비트·기본값·강등·게이트·진단),
`HwpxHwpEquivalenceTests`(`sectionMarks` 축 + `section-marks` 직접 핀),
`HwpxFixtureRenderTests.testHwpxPageChromeMatchesHwpPairs`(쪽 크롬 `[[], ["- 9 -"],
["- 10 -"]]` 직접 핀), `FixturePreviewFidelityTests`(1쪽 PrvImage에도 쪽 번호가
없다).

## 각주·미주 (`hp:footNote`·`hp:endNote`·`hp:autoNum`, #168)

`HwpxFootnoteMapper`가 각주·미주를 `.footnote`/`.endnote(HwpListControl)`(제어
문자 코드 17)로, 그 본문 문단 안 `hp:autoNum`을 `.autoNumber(HwpOtherControl)`
(코드 18)로 승격한다. `HwpxFootnoteShapeMapper`는 구역의 `hp:footNotePr`·
`hp:endNotePr`를 `HwpSectionDef.footNoteShape`·`endNoteShape`(표 133·134)로 옮긴다.

강등 상태에서는 **본문이 통째로 사라졌다** — 미지 요소 강등이 요소 이름만
payload로 담아 `hp:t` 텍스트가 모델에 남지 않는다. **`hp:autoNum` 동반 승격은
선택이 아니다**: 본문 위 첨자 참조 번호는 컨트롤 종류만 보는 경로
(`HwpFootnoteCoordinatorPlacement`)에서 나오지만, 각주 영역 본문 첫머리의 번호
라벨은 `HwpTextRunBuilder.autoNumberReplacements`가 `.autoNumber`의
`autoNumberInfo`를 찾아야 만들어진다.

**payload 게이트는 슬롯마다 다르고 전부 바이너리 로더가 정한다.** 컨트롤 헤더와
리스트 헤더는 `HwpListControl.load`가 ctrl id와 무관하게 `decoupledPayload`를
쓰므로 **양 모드 보존**이다 — 되읽는 소비자가 없다고 `preservedPayload`로 접으면
바이너리가 들고 있는 바이트를 HWPX만 비우는 반대 방향 격차가 된다. `atno`는
반대로 `HwpOtherControl`이 raw만 게이트하고 typed 뷰(`autoNumberInfo`)는 **게이트
전 원본**에서 만들므로, HWPX도 합성 payload를 그 로더에 태워 `.viewer`에서 raw는
비고 번호는 사는 비대칭을 그대로 재현한다.

**각주 모양은 payload 합성이 사실상 필수다.** 조판이 보는 구분선 값은 typed
필드가 아니라 `HwpFootnoteShape.dividerInfo`, 즉 `rawPayload`의 재디코드다.
비워 두면 `dividerInfo`가 nil이라 HWP 쌍이 0.34pt 구분선을 그리는 자리에서
HWPX만 튜닝 폴백 1.0pt를 그린다. 게다가 `HwpFootnoteShape.init(_:)`은 구분선
길이를 스펙 표 133 그대로 **HWPUNIT16(2바이트)** 로 읽지만 실저장본은 4바이트라
typed 저장 필드 일곱이 실물에서 통째로 오정렬돼 있다 — 같은 payload를 같은
로더(`HwpFootnoteShape.load`)에 태워야 그 오정렬까지 HWP 쌍과 똑같아진다.
(`HwpSectionDef()`의 각주·미주 기본값 `-1, -1` · `12280, 224`가 그 2바이트
오독의 화석이다: 4바이트로 이어 붙이면 -1과 14,692,344로 실물과 같다.)

실측 근거는 `footnote-endnote` 변환 쌍 둘이다. (1) 기본값 표본 — HWP 쌍의
컨트롤 헤더 20바이트·리스트 헤더 16바이트·`atno` 16바이트·FOOTNOTE_SHAPE
28바이트가 우리 합성과 **바이트 동일**하다(머리말·꼬리말의 12/34바이트와
다르다는 데 주의). (2) 2026-09-07 한글.app 12.30.0 미주 모양 대화상자로 만든
비기본값 쌍 — `type="CIRCLED_HANGUL_JAMO" prefixChar="[" suffixChar="]"
supscript="1"` · `numbering type="ON_SECTION" newNum="3"` ·
`placement place="END_OF_SECTION"` ↔ property **0x150B** · 시작 번호 3 ·
앞 0x5B · 뒤 0x5D. 즉 bits 0-7 번호 모양(표 134) · bits 8-9 배치 ·
bits 10-11 번호 매김 · bit 12 위 첨자가 확정됐고, 같은 문서의
`<hp:endNote flag="11" number="3" prefixChar="91" suffixChar="93" instId="…">`가
20바이트의 오프셋 8-9(앞 장식)·12-15(`flag`)를 확정했다.

**`@suffixChar`는 이름이 같아도 인코딩이 다르다** — `hp:footNote`/`hp:endNote`의
것은 10진 코드포인트 문자열("41")이고 `hp:autoNumFormat`의 것은 리터럴 문자(")")다.
하나의 읽기로 뭉뚱그리면 `)`가 0으로, 41이 문자 '4'로 접힌다. 열거 변환기는
재사용한다 — `hp:noteLine@type`은 `HwpxCharShapeMapper.lineShapeIndex`(같은 OWPML
`LINETYPE2`를 `hh:underline@shape`·`hh:strikeout@shape`와 공유한다), `@width`는
`HwpxParaShapeMapper.thicknessIndex`, `hp:autoNumFormat@type`은
`HwpxNumberFormatMapper`다. 종류 > 17이나 굵기 > 15를 실으면 `dividerInfo`의 wide
유효성 게이트가 깨져 narrow로 폴백하고 여백·색이 통째로 오염되므로 두 변환기의
상한을 벗어나면 안 된다.

**열거 이름과 생략 기본값의 정본은 한컴 공개 OWPML 모델이다**(`OWPML/Class/enumdef.h`의
직렬화 표와 각 클래스 생성자, `OWPML/Base/Util.cpp`의 `GetAttribute`). 실측만으로는
기본값 문서가 전부 0이라 드러나지 않는 자리가 둘 있었다.
- **이름**: 각주 다단 배열의 셋째 값은 `RIGHT_MOST_COLUMN`(`RIGHT_COLUMN`이 아니다),
  `LINETYPE2`의 3D 넷은 `THICK3D`·`THICKREV3D`·`3D`·`REV3D`다. 지어낸 이름을 쓰면
  정상 입력이 조용히 0으로 접힌다.
- **생략 기본값**: `GetAttribute`는 속성이 없거나 열거 이름이 표에 없으면 값을
  건드리지 않고 false만 돌려주므로 **생성자가 세운 값이 남는다**. `CNoteSpacing()`은
  `betweenNotes` 850·`belowLine` 567·`aboveLine` 567, `CNoteLine()`은 길이 0·`SOLID`·
  `0.12 mm`·검정, `CFNNumbering()`/`CENNumbering()`은 시작 번호 1,
  `CAutoNumNewNumType()`은 번호 1·`ANT_PAGE`, `CAutoNumFormatType()`은 `DIGIT`·위 첨자
  없음, `CFNPlacement()`/`CENPlacement()`는 0, `color="none"`은 **흰색**(0xFFFFFFFF)이다.
  0으로 접으면 `HwpFootnoteLayout.dividerMetrics`가 그 값을 그대로 써서 **구분선 위·
  아래 여백과 주석 사이 간격이 0**이 된다. 종류·굵기는 그렇지 않다 — `DividerMetrics`에
  종류 필드가 없고 굵기도 `max(0.5, …)`에 흡수돼 렌더가 같으므로, 그 둘을 맞추는 실익은
  HWP 쌍과의 payload 동등성과 wide 유효성 게이트다. **명시된 0은 보존한다** — 기본값은
  속성이 아예 없을 때만 쓴다. 참조 생성자 값이 한글이 **저장하는** 값(각주 aboveLine
  850·belowLine 567·betweenNotes 283)과 다른 것은 그대로 둔다: 생략된 문서를 한글이
  읽을 때 쓰는 값이 생성자 쪽이다(payload 자체가 없어 `dividerInfo`가 nil인 경로의
  폴백은 `HwpRenderTuning`이 따로 갖고 있고 그쪽이 저장값에 맞춰져 있다).

**`numType="TOTAL_PAGE"`는 일부러 강등에 남긴다.** OWPML `AUTONUMTYPE`에는 전체 쪽수
(값 6)가 있는데 HWP5 표 143 쪽 `HwpAutoNumberKind`는 0-5뿐이라 `kind`가 그것을
`.page`로 접는다. 승격하면 `HwpPageChromeBuilder`가 그 자리에 논리 쪽 번호를 그려
"1 / 3" 머리말이 "1 / 1"이 된다 — 강등 상태에는 없던 **틀린 숫자**다. 미지 이름도
같은 이유로 강등하며, 자리(코드 18)와 4CC는 그대로라 WCHAR/ctrl 슬롯 정렬은 유지된다.

**이 가드는 XML 이름 단계라 바이너리 경로에는 닿지 않는다** — 같은 문서의 `.hwp`는
표 143 raw 6이 그대로 `.page`로 접혀 여전히 현재 쪽 번호를 그린다. 근본 해결은
`HwpAutoNumberKind`에 값 6을 더하는 것이고, 소비처 넷이 전부 `kind == .page` 게이트라
그것만으로 두 경로가 함께 닫힌다. 다만 공개 열거이고 `HwpPaginator.applyNewNumbers`의
exhaustive switch(`case .picture, .table, .equation`)가 함께 바뀌어야 해서 각주 승격과
분리했다 — 그때 이 강등 분기를 지우고 `autoNumberKinds`에 `TOTAL_PAGE`를 되돌려 넣으면
승격·왕복·진단이 모두 살아난다.

**미실측**: `hp:numbering@type`의 `ON_PAGE`(쪽마다 새로 — 미주 모양 대화상자에 그
항목이 없다. 값 2는 한컴 `g_FNNumberingTypeList`가 정본), 각주 쪽
`hp:placement@place`의 `EACH_COLUMN` 외 값(조판이 각주 다단 배열을 아직 쓰지 않아
렌더 격차는 없다), `@beneathText`가 놓이는 자리(표 134가 위 첨자 **바로 다음 줄**에
적은 항목이라 bit 13으로 실었다 — 실물은 `beneathText="0"`뿐이고 읽는 소비자도 없어
왕복 충실도 몫이다), `hp:noteLine@length`의 유한값 의미(HWP 쌍과
바이트가 같아 매핑은 안전하지만 14,692,344가 한글 대화상자의 "사용자 150.0mm"와 어떤
산식으로 이어지는지는 확정하지 못했다).

**후속 확인 대상**: `HwpxCharShapeMapper.lineShapes`는 `DASH`↔2·`DOT`↔3인데 한컴
`g_LineTypeList2`의 나열 순서는 `LT2_DOT`(2)·`LT2_DASH`(3)로 반대다(HWP5 표 25도 2가
긴 점선·3이 점선). 코퍼스 실물이 `NONE`·`SOLID`뿐이라 이번에는 건드리지 않았다 —
점선 밑줄 쌍을 만들어 확인할 것.

가드: `HwpxFootnoteMapperTests`(승격·앵커 코드·표 143 비트·게이트 비대칭·합성
바이트·강등표 이탈), `HwpxFootnoteShapeMapperTests`(28바이트·`dividerInfo`·
property 비트 실측 표본·양 모드 보존·부재 시 무변경),
`HwpxHwpEquivalenceTests`(`notes`·`noteShapes` 축 + 공허 방지 직접 핀),
`HwpxFixtureRenderTests.testHwpxFootnoteBlocksMatchHwpPairs`(HWP 쌍 텍스트·좌표
등식 + `1) CoreHwp footnote fixture`·`1) CoreHwp endnote fixture` 직접 핀).

## 쪽 번호 위치 (`hp:pageNum` → `pgnp`, #135)

`HwpxPageNumberMapper`가 `.pageNumberPosition(HwpPageNumberPosition)`으로
승격한다 — 구역 부속 컨트롤(코드 21) 중 유일한 typed 매핑이다. `pos` →
`displayPosition`(표 148 bit 8-11), `formatType` → `numberFormat`(표 134,
`HwpxNumberFormatMapper` — `hh:paraHead numFormat`·`hp:autoNumFormat type`도
같은 NumberType1 열거라 승격 시 재사용), `sideChar` → 4번째 WCHAR `unused`
(줄표 문자, #138 — 빈 문자열 0, 두 글자 이상은 첫 UTF-16 unit). 앞/뒤 장식
문자·사용자 기호는 HWPX에 대응 속성이 없어 0. 생략 속성은 OWPML ParaList
스키마의 `default`(`pos` TOP_LEFT·`formatType` DIGIT·`sideChar` "-")를 따르고
미지 이름은 0으로 접는다(위치를 추측해 그리지 않는다) — 한글.app 실저장본은
세 속성을 항상 명시해 생략 경로의 실물은 없다. 조판(`HwpPageChromeBuilder`)은
typed 필드만 읽으므로 표 147 16바이트 payload 합성은 `.default`에서 바이너리
pgnp와 같은 모양을 유지하는 보존용이고, `.viewer`에서는 `preservedPayload`
게이트로 비운다(바이너리 `consumedData`와 패리티 — HWPX 매니페스트에 payload
핀은 없고 등가 투영도 rawPayload를 제외한다). 강등 컨트롤(`degradedControl`)의
요소명 payload는 게이트 없이 남는 선행 편차라 별도 후속이다.
실측 근거는 둘이다. (1) noori 쌍 — `BOTTOM_CENTER`↔5·`DIGIT`↔0·`sideChar=""`↔0,
HWP 쌍 manifest `pageNumberPositions[0]`과 payload 바이트 동일. (2) 2026-09-02
한글.app 12.30.0의 쪽 번호 매기기 대화상자로 만든 .hwp/.hwpx 쌍 4종 —
`OUTSIDE_TOP`+`ROMAN_CAPITAL`+줄표 ↔ property 0x0702·4번째 WCHAR 0x2D,
`INSIDE_BOTTOM`+`DECAGON_CIRCLE_HANJA`+줄표 없음 ↔ 0x0A10·0,
`BOTTOM_LEFT`+`HANGUL_SYLLABLE`+줄표 ↔ 0x0408·0x2D,
`TOP_CENTER`+`CIRCLED_DIGIT`+줄표 ↔ 0x0201·0x2D. 즉 `pos` 5값·`formatType`
5값이 표 148·표 134 코드와 일치하고, "줄표 넣기"는 앞/뒤 장식 WCHAR가 아니라
4번째 WCHAR에만 실리며 HWPX는 `sideChar="-"`/`""`로 쓴다. 네 쌍 모두 payload
16바이트(미해석 UINT32 없음)였다. 가드는
`HwpxPageNumberMapperTests`(대응표·payload·실측 쌍)·`HwpxHwpEquivalenceTests`
(pageNumberPositions 축)·`HwpxFixtureRenderTests.testHwpxPageChromeMatchesHwpPairs`
(noori 각 쪽 "1"·"2"·"3")다.

## 문단 번호·글머리표 (`hh:numbering`·`hh:bullet`, #133)

`HwpxNumberingMapper`가 두 가족을 `HwpNumbering`/`HwpBullet` 배열로 옮긴다.
참조 배선은 그전부터 끝나 있었다 — `HwpxParaShapeMapper`가 `hh:paraPr`의
`hh:heading`을 표 44 bit 23-24(머리 종류)·bit 25-27(수준)과 1-based
`numberingOrBulletId`로 이미 옮겼고, 비어 있던 것은 정의 배열뿐이라 조판이
게이트를 지나고도 `HwpIndex`에서 정의를 못 찾아 아무것도 그리지 않았다.
수준 필드는 3비트라 저장값 0-7(1-8수준)만 담긴다 — `hh:heading@level`이 그
밖(9·10수준)이고 머리 종류가 있으면 `& 0b111`로 접지 않고 **머리 종류 없음**으로
접은 뒤 `heading@level=<값>` 진단 레코드를 남긴다(#153). 그대로 접으면 9수준이
1수준으로 읽혀 번호 생성이 그럴듯하지만 틀린 라벨을 만들고, 한글 자신도
바이너리에서 그 수준을 머리 없음으로 저장한다(헌법주석의 `개요 8`·`개요 9` 스타일
문단 모양이 `headingType == 0`). 탐색 목록은 스타일 이름 폴백으로 그 문단을 여전히
잡는다.

두 가족은 자식 `hh:paraHead`(표 39 문단 머리 정보 12바이트)를 공유한다. 스펙은
항목 4개(속성 UINT32 · 너비 보정값 HWPUNIT16 · 본문과의 거리 HWPUNIT16 · 글자
모양 아이디 참조 INT32)를 적고 "전체 길이 8"로 합계를 틀리게 적었다 — 실물은
12바이트다(같은 정정으로 표 42의 "전체 길이 20"도 24바이트). 12바이트의 합성은
공개 모델 `HwpParaHeadInfo`(#152)가 한다 — 바이너리 쪽 `HwpNumberingFormat.paraHeadInfo`·
`HwpBullet.paraHeadInfo`가 같은 타입으로 디코드하므로 배치가 `HwpParaHeadInfo.bytes`
한 곳에만 있고, `ParaHeadInfoTests`가 전 픽스처 왕복으로 거울상을 잠근다. 정렬(bit
0-1)·거리 종류(bit 4)의 비기본값은 `outline-numbering` 쌍이 실물이다 — 1수준
`align="RIGHT" textOffsetType="HWPUNIT" textOffset="1000" widthAdjust="200"`이 HWP 쌍의
속성 `0x52`·거리 1000·너비 보정 200과, 2수준 `align="CENTER"`가 `0x10D`와 같아
스키마 나열 순서 배치가 맞다. 번호 형식 지시자의 경계(캐럿은 한 자리 숫자만,
`^n`은 1수준부터 그 수준까지의 경로, 그 밖의 캐럿은 문자 그대로)는
`HwpNumberingFormatPattern` doc-comment의 한글.app 미리보기 실측이 정본이다. 속성 비트는 표 40이
bit 0-4(정렬·번호 너비·자동 내어 쓰기·거리 종류)만 적고 **번호 모양은 적지
않는데, 실측이 bit 5-8이다**: 빈 문서 기본 `numberingArray`(`HwpIdMappings`)의
수준별 선두 UINT32가 `^1.` 0x0C · `^2.` 0x10C · `^7` 0x2C이고 noori HWPX의 같은
수준이 `DIGIT`(표 41 값 0)·`HANGUL_SYLLABLE`(8)·`CIRCLED_DIGIT`(1)이다. 4비트라
표 41의 0-14만 담기고 `SYMBOL`(0x80) 같은 표 밖 코드는 접힌다. 표 41은 표 134
번호 모양의 0-14 구간과 항목이 같아 `HwpxNumberFormatMapper`를 재사용한다.

생략 속성의 기본값은 **참조 리더의 생략 처리**에서 온다. 한컴 `Util.cpp`의
`GetAttribute(..., bool& value)`는 속성이 없으면 `value`를 건드리지 않고 false를
반환하므로, 생성자가 세운 값이 그대로 남는다 — `useInstWidth`·`autoIndent`는
`m_bUseInstWidth(true)`·`m_bAutoIndent(true)`라 **생략이 참**이다(우리 기본값도
참이다). 같은 생성자의 `m_uCharPrIDRef(0)`은 따르지 않는다: 0은 실재하는 charPr
참조라 생략을 0으로 접으면 없는 참조가 첫 글자 모양을 가리키고, `HwpBullet`의
계약(`-1`이면 바탕글)과도 어긋난다 — 생략·센티널 모두 -1이다. `hh:paraHead@start`는
표 38이 UINT(4바이트)이고 한컴도 `UINT m_StartNumber`라 16비트로 읽으면 65,535
초과가 조용히 기본값이 된다(문서 수준 `hh:numbering@start`만 UINT16이다).
번호 형식 문자열은 표 38의 WORD 길이 필드를 넘으면 거부한다 — 절단은 서러게이트
쌍을 갈라 조용히 손상시킨다. 다만 거부 대상은 **수준 슬롯을 얻은 형식만**이다:
중복 수준과 1-10 밖 수준의 `hh:paraHead`는 형식이 되지 않아 불변식을 깨뜨릴 수
없으므로, 문서를 거부하는 대신 아래 강등 규약을 따른다.

주의할 지점 셋이다. (1) `charPrIDRef="4294967295"`는 id 테이블 참조가 아니라
-1 센티널(바탕글 모양)이라 리맵하면 안 된다 — `resolvedOffset`에 넣으면 댕글링
폴백 0이 되어 charShape 0을 가리킨다. (2) 수준 슬롯은 문서 순서가 아니라 `level`
속성이 정하고, 배열 길이는 바이너리와 같게 7 + 3으로 고정한다(빈 수준은 형식
길이 0·속성 0·바탕글 -1). 중복 수준은 첫 등장이 이기고, 1-10 밖 수준과 두 번째
이후 `hh:paraHead`는 진단으로 강등한다. (3) 글머리표 문자는 빈 문자열로 접는다 —
U+0000 한 자로 두면 조판의 `char.isEmpty` 게이트를 지나 NUL 글리프를 그린다.
체크 글머리표 문자(`hh:bullet@checkedChar`)도 같은 WCHAR 규약으로 읽되 **등가
축에는 올리지 않는다** — 바이너리는 표 42의 고정 WCHAR라 값이 없어도 U+0000을
담고 HWPX는 선택 속성이라 부재가 빈 문자열이어서, 정규화 없이는 같은 문서가
포맷마다 다른 값이 된다. 표 42의 필드가 WCHAR **하나**라 비BMP 문자
(`char="😀"`)도 담기지 않는데, 첫 unit만 떼면 반쪽 서러게이트를 `String`이
U+FFFD로 복구해 문서에 없던 대체 글리프를 **우리가 만들어** 그리게 된다 —
표현 불가한 unit은 U+0000과 같이 빈 문자열로 접는다(`surrogateSafePrefix`가
자기 절단이 만든 U+FFFD를 떨구는 것과 같은 태도다).

레코드 payload는 합성하지 않는다 — `rawPayload`·`charRawPayload`뿐 아니라
**`HwpNumberingFormat.formatRawPayload`도 `Data()`로 명시**한다
(`HwpBorderFill`·`HwpFaceName`의 HWPX 전용 init과 같은 DocInfo 가족 관행).
범용 init에 맡기면 기본 인자가 문자열 전체를 UTF-16으로 합성해 **양 모드에서**
들고 있는데, 게이트 여부의 기준은 대응 바이너리 로더다 — 번호 형식은
`consumedData`(`.viewer`에서 비움)라 HWPX도 비워야 패리티이고, `hp:ole`처럼
`decoupledPayload`(양 모드 보존)인 것은 반대로 비우면 안 된다
(`HwpxOleMapperTests.testPayloadSurvivesViewerOptions`). noori 실측으로
`.viewer`에서 HWP 0바이트 대 HWPX 88바이트로 갈렸던 자리다.

조판은 무변경이다 — `bulletArray`만 차면 `HwpTextRunBuilder.appendBulletHeading`이
`bullet.char + " "`를 문단 앞에 전치한다. **번호 문단 머리의 라벨은 이 승격으로도
그려지지 않는다** (위 "1차 범위 밖").

실측 근거는 noori 쌍이다. 수준 1-7의 12바이트와 `start`(1·0)·수준별 시작 번호가
HWP 쌍과 **바이트 동일**하고, 글머리표는 `info` `08 00 00 00 00 00 32 00` ·
글자 모양 ID -1 · 문자 `-`가 동일하다. 두 쌍을 조판하면 선행 `- `가 붙은 두 줄이
같은 좌표(1쪽 59,291·59,321)에 선다. 확장 수준(8-10)만 갈린다 — 표 38의 확장
필드는 5.1.0.0 이상에만 있고 HWP 쌍은 5.0.3.4라 배열 자체가 없으므로 **등가
투영에서 수준 개수를 비교하면 안 된다**. 가드는 `HwpxNumberingMapperTests`
(비트·센티널·슬롯·상한·강등)·`HwpxHwpEquivalenceTests`(정의 축과 문단 머리 축 —
번호 정의는 14쌍 전부에서 비어 있지 않고 글머리표는 noori 1쌍뿐이다)·
`HwpxFixtureRenderTests.testHwpxBulletHeadingsMatchHwpPairs`(선행 `- ` 줄 등식과
noori 직접 핀)·noori HWPX manifest의 `numberingCount` 2·`bulletCount` 1이다.

## 구역의 개요 번호 참조 (`hp:secPr@outlineShapeIDRef`, #152)

개요(문단 머리 종류 1) 문단의 번호 정의는 문단 모양이 아니라 **구역 정의**가
가리킨다 — HWP5 `HwpSectionDef.numberParaShapeId`(1-based, 0 = 없음)이고
HWPX는 `hp:secPr@outlineShapeIDRef`다. `HwpxSecPrMapper.outlineNumberingId`가
`HwpxIdTables.numbering` 오프셋 + 1로 리맵한다 — id는 dense가 아니라 숫자를
그대로 실으면 안 된다 (noori·`outline-numbering` 실물: `hh:numbering id="1"`·`"2"`
중 `"2"` → 오프셋 1 → 2, HWP 쌍의 필드도 2; multi-section은 구역마다 `"1"`·`"2"`).
`outline-numbering`은 한글.app이 개요 번호 사용자 정의를 **새 정의**(id "2")로
저장하고 구역 참조를 그쪽으로 옮기며, 문단 번호(`hh:heading type="NUMBER"`)는
기본 정의 id "1"을 그대로 참조한다는 실물이기도 하다.

세 경로를 가른다. **생략**은 0이다 — 한컴 참조 모델 `SectionDefinitionType.cpp`가
`m_uOutlineShapeIDRef(0)`으로 세우고 `GetAttribute`가 속성 부재 시 값을 건드리지
않으므로, 바이너리 빈 문서 기본값 1(`HwpSectionDef()`)을 지어내지 않는다.
**잘못된 참조**(테이블에 없는 id)도 0으로 접되 `unknownChildren`에 합성 레코드
(payload `secPr@outlineShapeIDRef=<값>`)를 남겨 생략과 구분한다 — 요소 강등의
payload가 local name인 것과 달리 **속성 강등**이라 `요소@속성=값` 꼴이고,
`parseDiagnostics()`가 tagId 0 `unknownRecord`로 그대로 낸다 (첫 속성 수준
강등 채널). 정상·생략·잘못된 참조는 `HwpxSecPrOutlineReferenceTests`, HWP 쌍
대조는 `HwpxHwpEquivalenceTests`의 `sectionOutlineNumberingIds` 축이 잠근다.
조판 쪽 소비자는 `HwpNumberingHeadingReference`(HwpKitCore)다.

## OLE 개체 (`hp:ole` → `$ole`, #134)

`HwpxOleMapper`가 `.ole(HwpShapeControl)`로 승격한다 — `hp:pic` → `.picture`와
같은 꼴이고, 개체 요소는 `HwpShapeComponent(ctrlId: .ole, oleArray:
[HwpShapeComponentOLE])` 하나다. 렌더가 읽는 것은
`HwpShapeComponentOLE.binaryDataId`뿐이다: `binaryItemIDRef`를
`binItemIdByManifestId`(BinData 매퍼가 manifest 순서로 채운 표 — `.ole` 항목도
`BIN%04X.ole` 스트림으로 이미 등록된다)로 리맵하면 `HwpPaginator.chartFrame`이
`HwpImageStore` → `HwpEmbeddedChart`(4바이트 길이 프리픽스 + CFB의
`OOXMLChartContents`) → `HwpChartParser` → `HwpChartPainter`로 내장 차트를 근사
렌더한다. 뷰어는 무변경이다 — 조판은 `.ole`을 `.genShapeObject`와 같은 개체
분기로 이미 보내고, `HwpUnsupportedDetector`는 `.ole` 컨트롤(`unsupportedHint`)과
gso의 OLE 개체 요소(`unsupportedComponentHint`)에 같은 힌트 "OLE"를 낸다 (근사
렌더라 placeholder 진단은 유지된다). 댕글링 참조는 그림처럼 0으로 접어 도형
상자 경로로 폴백한다.

한글.app은 차트를 `<hp:switch>`에 두 벌로 적는다 — `hp:case`(`required-namespace`
2016 `ooxmlchart`)의 `<hp:chart chartIDRef="Chart/chart1.xml">`과 `hp:default`의
`<hp:ole>`. `supportedSwitchNamespaces`에 ooxmlchart가 없어 파서가 `hp:default`를
채택하므로 매퍼는 `hp:ole`만 본다. fallback 없이 `hp:chart`만 오는 문서는
종전대로 같은 4CC(`$ole`)의 강등 앵커다 (`objectFourCCs["chart"]` — 실물이 없고
`chartIDRef` 직접 읽기는 픽스처 확보 후).

표 118 payload(실물 레이아웃: 속성 UINT32 · extent INT32×2 · BinData ID
UINT16(offset 12) · 테두리 3필드 = 26바이트)는 보존용으로 합성한다. 게이트는
없다 — 바이너리 `HwpShapeComponentOLE`가 `decoupledPayload`(양 모드 보존)라
`.viewer`에서도 남는 것이 패리티다 (그림 73바이트와 같은 부류이고 pgnp의
`preservedPayload`와 다르다). 속성 대응(값은 표 119, **이름은 한컴 공개 OWPML
모델 `OWPML/Class/enumdef.h`의 직렬화 표**): `drawAspect`(CONTENT 1 ·
THUMB_NAIL 2 · ICON 4 · DOC_PRINT 8, 생략은 CONTENT) → bit 0-7, `hasMoniker` →
bit 8, `eqBaseLine`(0~127 클램프) → bit 9-15, `objectType`(UNKNOWN 0 · EMBEDDED 1 ·
LINK 2 · STATIC 3 · EQUATION 4) → bit 16-21, 미지 이름은 0. `THUMB_NAIL`·
`DOC_PRINT`의 밑줄은 `g_OleDrawAspectList` 실측이다 — 붙여 쓴 이름으로 표를
만들면 실물 문서의 표시 방식이 조용히 0으로 접힌다. `hc:extent` →
extent(없으면 `hp:sz`). 테두리 3필드는 0이고 `hp:lineShape`는 소비하지 않는다
(그림 매퍼와 같음 — 렌더가 읽지 않는다). 미소비 자식(`offset`·`orgSz`·`curSz`·
`flip`·`rotationInfo`·`renderingInfo`·`lineShape`)은 `shapeControl.unknownChildren`
으로 강등돼 진단에 남는다.

실측 근거는 chart 변환 쌍이다. HWPX `hp:ole objectType="UNKNOWN"
binaryItemIDRef="ole1" hasMoniker="0" drawAspect="CONTENT" eqBaseLine="0"` +
`hc:extent 7200×7200` ↔ HWP 쌍 `gso` + `$ole` 개체 요소 payload
`01 00 00 00 | 20 1C 00 00 | 20 1C 00 00 | 01 00 …` (30바이트 — 문서화된 26바이트
뒤 미해석 4바이트는 0). BinData는 HWPX `BinData/ole1.ole`(15,876바이트) ↔ HWP
`BIN0001.OLE`(압축 해제 15,876바이트): 둘 다 4바이트 길이 프리픽스 + CFB이고
`OOXMLChartContents` 4,926바이트는 바이트 동일, `Contents` 스트림 1바이트(파일
오프셋 10282 = 스트림 오프셋 8742)만 다르다. `hp:case` 쪽 `Chart/chart1.xml`도
같은 XML이다.

`eqBaseLine`은 **수식 개체에서만** 표 119 코드로 변환한다. 스펙은 raw 0을
"디폴트(85%)", 1~101을 0~100%로 적고 "현재는 수식만이 베이스라인을 별도로
가진다"고 명시한다. HWPX 값이 백분율이라는 근거는 한컴 모델이 그 속성을 85로
초기화해 직렬화한다는 것이다(`OWPML/Class/Para/OLEType.cpp`의
`m_uEqBaseLine(85)`; 공개 모델에 XSD는 없다) — raw를 담는 속성이었다면 기본값이
"디폴트"를 뜻하는 0이었을 것이다. 그래서
`objectType="EQUATION"`의 명시값만 0~100으로 좁혀 `+1`로 싣고(0% → 1,
50% → 51, 100% → 101), 생략·형식 오류는 raw 0("디폴트 85%")이다.
수식이 아닌 종류는 값을 그대로 싣는다 — 스펙상 베이스라인을 갖지 않는
종류이고, chart 쌍이 그 경로의 실측이다(HWPX `eqBaseLine="0"` ↔ HWP payload
0x00000001, 베이스라인 비트 0). 그쪽에 +1을 걸면 한글.app이 쓴 바이트와
어긋난다 — 안 쓰는 필드를 양쪽에서 0으로 적을 뿐이다.

가드는 `HwpxOleMapperTests`(payload·속성 비트·리맵·폴백·viewer 패리티·진단
강등·실물 쌍)·`HwpxSectionMapperTests`(`hp:chart` 단독 강등 유지)·
`HwpxHwpEquivalenceTests`(`oleObjects` 축 — BinItem id 숫자가 아니라 참조가
닿는지와 차트 XML digest를 비교한다. id 공간은 재저장이 재생성하므로 숫자
등식은 유효한 쌍을 깨뜨릴 수 있고, payload 전체도 `Contents` 1바이트 차이 때문에
축이 아니다)·`HwpxFixtureRenderTests.testHwpxChartBlocksMatchHwpPairs`
(chart 쌍 `.chart` 블록 1개 · 힌트 "OLE")다.

## 실파일 검증 대기 항목

- HWPX lineseg `textpos`가 컨트롤을 8 WCHAR로 세는지 (틀리면 sanity 밸브가
  reflow로 강등할 뿐 오렌더는 없다 — 실측 후 산술을 맞출 것).
- `hp:pagePr landscape` 값 의미 (실측: 세로 A4가 `WIDELY`) — 조판은
  width/height만 쓰므로 property로 옮기지 않았다.
- textWrap 6값 전체 목록·`hp:t` 내 비앵커 요소 목록·배포용 HWPX의 표식.
- `hp:pageNum` 열거 대응표의 미실측 값 — `pos` 11값 중 실측은 5값(위 "쪽 번호
  위치")이고 미실측은 `TOP_LEFT`·`TOP_RIGHT`·`BOTTOM_RIGHT`·`OUTSIDE_BOTTOM`·
  `INSIDE_TOP`과 `NONE`(0 — 쪽 번호 없는 문서는 `hp:pageNum` 자체를 쓰지 않아
  실물이 없다). `formatType` 19값 중 실측은 5값, 미실측은 대화상자가 제공하는
  9종 중 `ROMAN_SMALL`·`LATIN_CAPITAL`·`IDEOGRAPH`·`DECAGON_CIRCLE`과 대화상자에
  없는 10종(`LATIN_SMALL`·`CIRCLED_LATIN_CAPITAL`·`CIRCLED_LATIN_SMALL`·
  `CIRCLED_HANGUL_SYLLABLE`·`CIRCLED_HANGUL_JAMO`·`CIRCLED_IDEOGRAPH`·
  `HANGUL_JAMO`·`HANGUL_PHONETIC`·`SYMBOL`·`USER_CHAR`). 실측된 값이 모두
  스키마 나열 순서 = 표 코드였으므로 나머지도 같은 규칙으로 채웠다.
  `USER_CHAR`의 문자(표 147 사용자 기호 WCHAR)를 HWPX가 어느 속성에 쓰는지는
  미확정 — 확정하려면 한글.app 쪽 번호 매기기 대화상자로 만든 문서를 .hwp와
  .hwpx로 저장한 뒤, .hwp는 `HwpFile`로 열어 `pgnp`(`HwpPageNumberPosition`의
  `property`·`userSymbol`·`unused`)를, .hwpx는 `Contents/section0.xml`의
  `hp:pageNum` 속성을 읽어 대조한다 (2026-09-02 실측 4쌍이 이 절차다).
- `hp:secPr@outlineShapeIDRef` 생략의 실물 — 한글.app 저장본은 항상 명시한다.
  참조 모델 기본값(0 = 참조 없음)을 따랐다.
- `<hp:pageNum/>`(속성 생략)을 한글.app이 실제로 왼쪽 위 "- N -"으로 그리는지
  — 우리는 스키마 `default`대로 TOP_LEFT(1)·"-"(0x2D)로 읽지만, 실저장본은
  항상 세 속성을 명시해 실물이 없다(제3자 저장기 문서를 확보하면 대조할 것).
- `hp:ole` 열거의 미실측 값 — 이름은 한컴 모델의 직렬화 표에서 왔지만 실물로
  본 값은 `objectType` `UNKNOWN`과 `drawAspect` `CONTENT`뿐이다
  (`EMBEDDED`·`LINK`·`STATIC`·`EQUATION`, `THUMB_NAIL`·`ICON`·`DOC_PRINT` 미실측).
  `eqBaseLine`은 수식 개체의 백분율 인코딩(`+1`)을 스펙과 한컴 모델의 기본값
  85로 세웠을 뿐 실물이 없다 — 실측은 수식이 아닌 chart 쌍의 0 하나뿐이다.
  베이스라인을 실제로 쓰는 **수식 OLE**(`objectType="EQUATION"`) 문서를
  확보하면 확정된다. 절차는 쪽 번호와 같다 — 한글.app으로 .hwp/.hwpx 쌍을
  만들어 `$ole` payload 선두 UINT32와 `hp:ole` 속성을 대조한다.
- HWP `$ole` 개체 요소 payload의 뒤 4바이트 — 표 118의 24바이트(실물 26바이트)
  뒤에 붙는 미해석 UINT32(chart 픽스처 0). HWPX 합성은 26바이트로 끝낸다.
- `hp:default` fallback 없이 `hp:chart chartIDRef`만 적는 저장기 — 실물이 없어
  `$ole` 강등 앵커로 두었다. 확보되면 `Chart/*.xml`(DrawingML `c:chartSpace`,
  chart 픽스처에서 CFB `OOXMLChartContents`와 바이트 동일)을 직접
  `HwpChartParser`에 넘기는 경로를 승격한다.
