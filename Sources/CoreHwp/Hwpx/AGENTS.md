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
내용(`.notImplemented`), 도형(line/rect/…)·OLE·수식·차트·글상자
(`.notImplemented`), 자동 번호·새 번호·홀/짝수 조정(`atno`·`nwno`·`pgct` —
HWPX 픽스처 10종에 사례 없음), 형광펜·변경 추적 표식(zero-width
진단), 그러데이션/이미지 채우기, 명시 탭 정지, 쪽 테두리. 승격 시 대응
요소를 `HwpxControlMapper` 분류표에서 옮긴다.

2026-09-02 한글.app 12.30.0 나란히 육안 대조(변환 쌍 10종 13쪽, 한컴 폰트
모드): 쪽수 10종 전부 일치, 표·그림·다단·글자 장식·쪽나눔 일치. HWPX
렌더에만 보이던 격차는 범위 밖 3건(글머리표 "-" #133·차트 OLE #134·쪽 번호
#135)이었고, HWP 쌍 렌더와 HWPX 렌더는 그 3건을 빼면 동일했다. 쪽 번호는
#135에서 승격돼 남은 격차는 2건이다. 한글.app 자체가 포맷에 따라
다르게 그리는 것이 하나 있다 — CharShape 취소선 견본(HWP 밑줄 종류 raw 2 ↔
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
