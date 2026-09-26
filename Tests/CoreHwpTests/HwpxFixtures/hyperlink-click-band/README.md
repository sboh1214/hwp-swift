# hyperlink-click-band

HWP fixture `hyperlink-click-band`(`Tests/CoreHwpTests/Fixtures/hyperlink-click-band/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **한글 문서**
(`hh:compatibleDocument@targetProgram="HWP201X"`)에 함초롬바탕 10pt 하이퍼링크(`hp:fieldBegin
type="HYPERLINK"`)를 줄마다 왼쪽·오른쪽 칸에 번갈아 두고, 줄 상자를 키우는 40pt 문단 끝 글자·
책갈피·글자처럼 취급 그림·글자, 문단 아래/위 간격 24pt, 한 줄 끝으로 나눈 두 줄(비율 160%·고정
8pt), 줄 간격 100%, 쪽 마지막 줄, 셀 여백 20pt 표의 셀 문단 셋, 문서 마지막 줄과 각주 둘(두 문단 +
한 문단)을 실은, 링크를 여는 클릭 띠(#233)의 실물 문서다. `document.hwpx`의 파싱 기대값은
`manifest.json`에 있다.

2026-09-26 현재 HWPX 매퍼는 `hp:fieldBegin`을 typed 하이퍼링크(`.hyperLink`)로 승격하지 않고
강등 컨트롤(`.notImplemented`, 필드 4CC `%hlk`)로 보존한다 — HWP 쌍의 링크 29개가 이 쪽에서는
`notImplemented` 29개로 파싱되므로, 링크 글자·밑줄은 같게 그려져도 링크 영역은 HWP 쌍에만 선다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/hyperlink-click-band/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-26 (System Events 접근성 자동화로 저장)
