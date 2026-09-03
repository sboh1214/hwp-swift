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
  조판이 `> 0` 게이트 뒤에서 -1로 되돌린다. 댕글링은 0 폴백.
- **lineseg 안전밸브** — `<hp:linesegarray>`는 절대 캐시 조판의 입력이다.
  미지 요소로 위치가 불확실하거나 sanity(첫 textpos 0·단조·범위)를 어기면
  **빈 배열로 강등**한다. 틀린 캐시로 오렌더하는 것보다 reflow가 낫다.
- **미지 요소는 `hwpxSyntheticTagId`(0) + 요소명 payload**로
  `HwpUnknownRecord`에 남긴다 — `parseDiagnostics()`가 무변경으로 HWPX
  미해석 요소를 보고하는 규약이다. HWPX 문서의 진단에서 tagId 0의 payload는
  UTF-8 OWPML local name으로 읽는다.
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

번호 매기기 라벨(정의는 #133에서 승격됐고 `^1.` 캐럿 서식 파서·자동 번호
카운터·수준 승계가 HWP 경로에도 없다 — 두 포맷 공통 격차라
`HwpPaginator`가 "(미렌더)"로 보고만 한다), 각주/미주·머리말/꼬리말
내용(`.notImplemented`), 도형(line/rect/…)·수식·글상자
(`.notImplemented`; `hp:default` fallback 없이 `hp:chart`만 오는 문서도 여기 —
OLE 개체 `hp:ole`은 #134에서 승격됐다), 자동 번호·새 번호·홀/짝수 조정
(`atno`·`nwno`·`pgct` — HWPX 픽스처 10종에 사례 없음), 형광펜·변경 추적
표식(zero-width 진단), 그러데이션/이미지 채우기, 명시 탭 정지, 쪽 테두리.
승격 시 대응 요소를 `HwpxControlMapper` 분류표에서 옮긴다.

2026-09-02 한글.app 12.30.0 나란히 육안 대조(변환 쌍 10종 13쪽, 한컴 폰트
모드): 쪽수 10종 전부 일치, 표·그림·다단·글자 장식·쪽나눔 일치. HWPX
렌더에만 보이던 격차는 범위 밖 3건(글머리표 "-" #133·차트 OLE #134·쪽 번호
#135)이었고, HWP 쌍 렌더와 HWPX 렌더는 그 3건을 빼면 동일했다. 쪽 번호는
#135, 차트 OLE는 #134, 글머리표는 #133에서 승격돼 남은 격차는 없다. 한글.app
자체가 포맷에 따라 다르게 그리는 것이 하나 있다 — CharShape 취소선 견본(HWP
밑줄 종류 raw 2 ↔
HWPX `<hh:strikeout>`)을 .hwp는 글자 아래 단선으로, .hwpx는 글자 가운데
취소선으로 그린다. 우리는 두 포맷 모두 HWP 쪽(아래 단선)으로 그린다 (#136).

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

두 가족은 자식 `hh:paraHead`(표 39 문단 머리 정보 12바이트)를 공유한다. 스펙은
항목 4개(속성 UINT32 · 너비 보정값 HWPUNIT16 · 본문과의 거리 HWPUNIT16 · 글자
모양 아이디 참조 INT32)를 적고 "전체 길이 8"로 합계를 틀리게 적었다 — 실물은
12바이트다(같은 정정으로 표 42의 "전체 길이 20"도 24바이트). 속성 비트는 표 40이
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
번호 정의는 10쌍 전부에서 비어 있지 않고 글머리표는 noori 1쌍뿐이다)·
`HwpxFixtureRenderTests.testHwpxBulletHeadingsMatchHwpPairs`(선행 `- ` 줄 등식과
noori 직접 핀)·noori HWPX manifest의 `numberingCount` 2·`bulletCount` 1이다.

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
