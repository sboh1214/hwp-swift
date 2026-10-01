# dash-patterns

HWP fixture `dash-patterns`(`Tests/CoreHwpTests/Fixtures/dash-patterns/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **한글 문서**
(`hh:compatibleDocument@targetProgram="HWP201X"`)에 대시 무늬(긴 점선·점선·일점쇄선·이점쇄선·긴 파선)를
셀 테두리(`hh:borderFill`)로 단 글자처럼 취급 표 9개, 취소선(`hh:strikeout@shape`) 문단 5개, 2단 밴드의
단 구분선(`hp:colLine`) 하나에 싣고 꼬리표(` #0`…` #13`, `#14`)를 붙여, 두 포맷의 렌더가 대시 무늬의
선·공백 길이와 셀 테두리·단 구분선의 획 두께를 한글처럼 600dpi 장치 단위(0.12pt) 정수로 그리는지를
고정한다 (#245). `document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/dash-patterns/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-10-01 (System Events 접근성 자동화로 저장)
