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

numbering/bullet(배열 비움 — 번호·글머리표 문자가 렌더에서 빠진다: noori
제목 블록의 선행 "-"가 HWP 렌더에만 보이는 것이 실측 사례다. 파스 텍스트
등가에는 영향 없음), 각주/미주·머리말/꼬리말
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
#135, 차트 OLE는 #134에서 승격돼 남은 격차는 글머리표 1건이다. 한글.app
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
가진다"고 명시한다. HWPX 값이 백분율이라는 근거는 한컴 모델의 XML 기본값이
85라는 것이다(`OWPML/Class/Para/OLEType.cpp`의 `m_uEqBaseLine(85)`) — raw를
담는 속성이었다면 기본값이 "디폴트"를 뜻하는 0이었을 것이다. 그래서
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
