# table-cell-spacing

HWP fixture `table-cell-spacing`(`Tests/CoreHwpTests/Fixtures/table-cell-spacing/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **한글 문서**
(`hh:compatibleDocument@targetProgram="HWP201X"`)에 셀 간격(`hp:tbl@cellSpacing`)이 있는 표와 없는 표의
원형 점선·긴 점선·실선 셀 테두리(`hh:borderFill`)를 실은 글자처럼 취급 표 9개와 꼬리표(` #0`…` #8`)를
싣고, 두 포맷의 렌더가 셀 간격이 있는 표의 테두리를 한글처럼 **칸마다 상자**로 — 원형 점선은 단
구분선과 같은 점 무늬로, 모서리는 만나는 두 변의 모양·굵기로 — 그리는지를 고정한다 (#243).
`document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/table-cell-spacing/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-28 (System Events 접근성 자동화로 저장)
