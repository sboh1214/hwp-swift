# mixed-size-decorations

HWP fixture `mixed-size-decorations`(`Tests/CoreHwpTests/Fixtures/mixed-size-decorations/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **한글 문서**
(`hh:compatibleDocument@targetProgram="HWP201X"`)의 한 줄에 크기가 다른 글자·문단 끝 글자·한 줄
끝·책갈피·글자처럼 취급 표를 섞고 기본 40pt·상대 크기 50% 글자와 위 첨자를 실어, 두 포맷의
렌더가 밑줄을 **줄 단위**(줄 상자 바닥·상단, 두께는 줄 글자 기본 크기)로, 장식선 크기를 **글자
모양 기본 크기**로 그리는지를 고정한다 (#226). 한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo다.
`document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/mixed-size-decorations/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-25 (System Events 접근성 자동화로 저장)
