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
(`.notImplemented`), 형광펜·변경 추적 표식(zero-width 진단), 그러데이션/
이미지 채우기, 명시 탭 정지, 쪽 테두리. 승격 시 대응 요소를
`HwpxControlMapper` 분류표에서 옮긴다.

## 실파일 검증 대기 항목

- HWPX lineseg `textpos`가 컨트롤을 8 WCHAR로 세는지 (틀리면 sanity 밸브가
  reflow로 강등할 뿐 오렌더는 없다 — 실측 후 산술을 맞출 것).
- `hp:pagePr landscape` 값 의미 (실측: 세로 A4가 `WIDELY`) — 조판은
  width/height만 쓰므로 property로 옮기지 않았다.
- textWrap 6값 전체 목록·`hp:t` 내 비앵커 요소 목록·배포용 HWPX의 표식.
