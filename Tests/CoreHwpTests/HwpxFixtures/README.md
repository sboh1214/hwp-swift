# CoreHwp HWPX fixture guide

이 디렉터리는 실제 `.hwpx`(OWPML) 문서로 HWPX 변환 파싱을 검증하기 위한
fixture 루트다. 구조는 `Fixtures/`와 같은 canonical layout을 따르되 별도
루트를 쓴다 — 기존 하니스의 OLE 매직·개수 핀 가드와 충돌하지 않기 위해서다.

```text
Tests/CoreHwpTests/HwpxFixtures/<fixture-id>/
  document.hwpx
  manifest.json
  README.md
```

## 생성 정책

fixture는 **기존 HWP fixture를 한글.app에서 재저장한 쌍**이다. 같은 문서의
HWP↔HWPX 파싱 등가(`HwpxHwpEquivalenceTests`)가 핵심 회귀 축이 되고,
`manifest.json`의 `sourceHwpFixture`가 쌍을 잇는다.

재생성 절차 (fixture별 README에도 기록):

1. `/Applications/한컴오피스 한글.app`(bundle
   `com.hancom.office.hwp12.mac.general`, 12.30.0 build 6446)에서
   `Fixtures/<id>/document.hwp`의 **사본**을 연다 (열람만으로 원본이 재기록될 수
   있다 — 4단계). 새로 저작하는 쌍(`section-marks`·`section-page-starts-on`·
   `line-shapes`·`script-decorations`·`section-page-number-skip`·`compat-decorations`·
   `hwp2007-decorations`·`inline-object-baseline`·`inline-object-marker-size`·
   `inline-table-actual-height`·`ms-word-paragraph-end-box`·`page-end-line-box`·
   `paragraph-end-char-size`)은 `.hwp`와 `.hwpx`를 **같은 편집 세션에서 연달아** 저장해야 두
   파일이 같은 문서가 된다. 한글 GUI로 만들기 어려운 조합은 합성 HWPX를 한글로 열어 두 형식으로
   저장해도 된다
   (`line-shapes` — 17종 선 모양을 네 자리에 모두 실은 문서, `script-decorations` —
   첨자 × 장식선 × 글자 위치 조합 11문단, `section-page-number-skip` — 쪽 번호 매기기 +
   구역 시작 종류 7구역; 각각 `Fixtures/<id>/README.md`의 절차).
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)**
   → 저장. 저장본을 `HwpxFixtures/<id>/document.hwpx`로 복사한다.
3. `manifest.json` 기대값을 갱신하고
   `swift test --filter "HwpxFixtureManifestTests|HwpxHwpEquivalenceTests"`를
   실행한다.
4. **원본 `document.hwp`가 변하지 않았는지 `git status`로 확인한다** —
   한글.app은 열람만으로도 OLE 원본을 다시 쓸 수 있다 (2026-08-28 chart
   fixture 실측: 크기 동일한 바이너리 변경 발생 → 원복함). 변했으면
   `git checkout -- <경로>`로 되돌린다.

한글.app은 AppleScript를 지원하지 않으므로 자동화는 GUI 조작뿐이다 —
`Fixtures/README.md`의 자동화 정책(별도 승인 하의 Computer Use)이 그대로
적용된다. 2026-08-28 초기 10종은 그 정책대로 승인 하의 GUI 자동화로
생성했다.

## 변환 불가·제외 fixture

- 암호(`문서암호설정-*`)·배포용(`배포용문서`)·DRM(`drm-unsupported-derived`)
  fixture는 열 수 없어 변환할 수 없다 (HWPX의 대응 표면은
  `META-INF/encryption.xml` 거부 — 합성 테스트가 고정).
- `missing-*-derived` 손상 파생 fixture는 재저장이 결함을 지우므로 제외.
- 버전 프로버넌스 fixture(`2007` 등)와 1차 범위 밖 기능 fixture(메모·수식·
  변경추적 등)는 해당 기능 승격 시 함께 변환한다. 각주·미주는 #168에서
  변환했고, 책갈피는 #169에서 `section-marks` 쌍으로 덮었다 —
  `Fixtures/bookmark`(책갈피 1개짜리 1쪽 문서)는 그 쌍이 같은 컨트롤을 더 넓게
  덮으므로 별도 변환하지 않았다. 구역 시작 종류(홀수·짝수·사용자)는 #173에서
  `section-page-starts-on` 쌍으로 저작했다 — 코퍼스가 전부 `BOTH`라 등가 스위트가
  잡지 못하던 `pageStartsOn` 매핑의 실물 근거다. 그 종류가 쪽 번호 매기기에 찍는
  번호(홀짝이 어긋난 자리만 건너뜀)는 #185에서 `section-page-number-skip` 쌍으로
  저작했다 — 앞 쌍에는 쪽 번호 매기기가 없어 렌더 번호를 잠글 수 없었다. 선 종류
  (`LINETYPE2`)는 #177에서
  `line-shapes` 쌍으로 저작했다 — 코퍼스의 글자선이 `NONE`·`SOLID`뿐이라 실선의 값
  (글자선 0 · 테두리 1)과 `DOT`·`DASH`의 순서를 잡지 못하던 자리의 실물 근거다.
  첨자 run의 장식선은 #179에서 `script-decorations` 쌍으로 저작했다 — 코퍼스에
  첨자와 장식선이 함께 걸린 글자 모양이 0건이라 렌더 해시·골든이 잡지 못하던 자리의
  실물 근거이며, 한글이 취소선만 켠 첨자 글자 모양도 HWP에는 밑줄 종류 2(가운데)를
  함께 적는다는(`line-shapes`와 같은 이중 기록) 표본이기도 하다.
  MS 워드 호환 문서의 장식선은 #187에서 `compat-decorations` 쌍으로 저작했다 — 코퍼스의
  호환 문서 실물이 `track-changes`(HWPX 쌍 없음) 하나라 `hh:compatibleDocument@targetProgram`
  매핑을 등가 스위트가 잡지 못하던 자리의 실물 근거이며, 글꼴을 결정론 resolver와 같은
  Apple SD 산돌고딕 Neo·Menlo로 골라 한글 PDF 좌표를 기기 무관하게 핀한다.
  한글 2007 호환 문서의 장식선은 #210에서 `hwp2007-decorations` 쌍으로 저작했다 — 코퍼스에
  `targetProgram="HWP200X"` 실물이 0건이라 대상 프로그램 1의 매핑과 그 문서의 고정 두께
  (0.36pt) 장식선을 등가 스위트·렌더 핀이 잡지 못하던 자리의 실물 근거이며, 같은 글자
  모양을 10·20·40·60pt로 실어 두께가 크기에 비례하지 않음을 한 문서 안에서 가른다.
  줄 상자보다 작은 글자처럼 취급 개체의 세로 자리는 #195에서 `inline-object-baseline` 쌍으로
  저작했다 — 코퍼스의 글자처럼 취급 개체가 전부 줄 상자를 정하는 키 큰 개체라 작은 개체의
  자리(바깥 상자를 글자로 보아 0.85 × 높이를 베이스라인 위에)를 렌더 해시·골든이 잡지 못하던
  자리의 실물 근거이며, `hp:pic`의 `hp:sz`·`hp:outMargin`과 표의 `hp:outMargin`이 HWP 쌍과
  같은 줄 캐시(`vertsize`·`baseline`)로 이어지는 표본이기도 하다.
  문단 끝 글자(CR)의 글자 모양 크기는 #206에서 `paragraph-end-char-size` 쌍으로 저작했다 —
  코퍼스에서 CR의 글자 모양이 본문보다 큰 문단이 캐시로 놓이는 `noori`·헌법주석 아홉뿐이라
  줄 캐시 없는 재조판의 마지막 줄 상자를 렌더 해시가 잡지 못하던 자리의 실물 근거이며,
  문단 마지막의 빈 run(`<hp:run charPrIDRef="N"><hp:t/></hp:run>`)이 HWP 쌍의
  `PARA_CHAR_SHAPE` 마지막 항목과 같은 문단 끝 글자 모양으로 옮겨지는 표본이기도 하다.
  셀 내용이 저작 높이보다 키운 글자처럼 취급 표의 줄 자리는 #214에서 `inline-table-actual-height`
  쌍으로 저작했다 — 코퍼스의 글자처럼 취급 표 14개가 전부 저작 높이 = 실제 높이라(한글이 저장할 때
  고쳐 쓴다) 줄 예약이 저작 높이를 믿어도 렌더 해시·골든이 잡지 못하던 자리의 실물 근거이며, 각주
  안 글자처럼 취급 표(`hp:footNote` 안 `hp:tbl`)가 HWP 쌍과 같은 줄 캐시로 이어지는 표본이기도 하다.
  글자처럼 취급 개체 마커의 글자 모양 크기는 #217에서 `inline-object-marker-size` 쌍으로 저작했다 —
  수정 전후 기존 픽스처의 렌더 해시가 두 글꼴 모드 모두 불변이라 마커 크기가 줄 상자에 들던 결함을
  렌더 해시·골든이 잡지 못하던 자리의 실물 근거이며, 개체·책갈피만 싣는 run(`<hp:run charPrIDRef="N">` 안
  `hp:pic`·`hp:tbl`·`hp:ctrl/hp:bookmark`)의 글자 모양이 HWP 쌍과 같은 줄 캐시로 이어지는 표본이기도 하다.
  쪽 끝 적합 판정은 #222에서 `page-end-line-box` 쌍으로 저작했다 — 코퍼스 저장본은 줄 캐시로
  쪽 나눔을 그대로 받아 판정 규칙(줄 전진량이 아니라 **줄 상자 하단**)을 렌더 해시·골든이 잡지
  못하던 자리의 실물 근거이며, 본문 97.62pt의 작은 쪽(`hp:pagePr@height` 28186) 29쪽과 각주가 있는
  쪽이 HWP 쌍과 같은 줄 캐시·쪽 나눔으로 이어지는 표본이기도 하다.
  MS 워드 호환 문서의 문단 끝 글자·한 줄 끝 글자 줄 상자는 #223에서 `ms-word-paragraph-end-box`
  쌍으로 저작했다 — 끝 글자의 글꼴 상자가 본문보다 큰 줄에서 한글이 그 상자를 본문 상자 위에
  **쌓는** 규칙(줄 상자 = 끝 글자 상자 + 본문 상자의 베이스라인 아래 몫)의 실물 근거이며, 시스템
  글꼴 넷(Apple SD 산돌고딕 Neo·Menlo·Helvetica·Times New Roman)의 조합과 글자처럼 취급 표·밑줄이
  HWP 쌍과 같은 줄 캐시로 이어지는 표본이기도 하다.

## manifest 작성 기준

- `id`는 디렉터리명과 정확히 일치해야 한다.
- `expectations`는 의미 있는 기대값만 적는다 — 구역/문단 수, 가시 텍스트,
  id 매핑 배열 크기, 쪽 지오메트리(HWPUNIT), 표 셀 수/병합, 그림·OLE BinItem id.
- `pageCount`는 뷰어 렌더 쪽수 핀이다 —
  `Tests/HwpKitTests/HwpxFixtureRenderTests.swift`가
  `HwpDocumentLoader(fontResolver: .testDeterministic)`로 열어 대조하고 HWP
  쌍과 같은지도 본다. `pageCountSource`에 출처를 반드시 명기한다 (한글.app
  실측 / HwpKit 렌더 실측 잠금 + 한글.app 확인 대기 — `Fixtures/`의 관행과
  같다). 한글.app으로 직접 실측할 때는 **사본**을 열 것 — 위 4단계처럼 열람만으로
  원본이 재기록된다.
- 미해석 강등(1차 범위 밖 요소)은 `HwpFile.parseDiagnostics()`로 드러난다 —
  기대값이 아니라 진단으로 다룬다.
