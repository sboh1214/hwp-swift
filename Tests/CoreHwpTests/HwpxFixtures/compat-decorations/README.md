# compat-decorations

HWP fixture `compat-decorations`(`Tests/CoreHwpTests/Fixtures/compat-decorations/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **MS 워드 호환 문서**
(`hh:compatibleDocument@targetProgram="MS_WORD"`)로, 한글 슬롯 Apple SD 산돌고딕 Neo·라틴
슬롯 Menlo의 글자 아래 밑줄 + 취소선(10·20pt, 한글/라틴 run)·글자 위 밑줄·글자 가운데
밑줄과 글꼴·크기가 섞인 줄 3종을 실어, HWPX 매퍼가 대상 프로그램을 HWP 쌍과 같은 값
(`HwpCompatibleDocumentTarget.msWord`)으로 옮기는지와 두 포맷의 렌더가 같은 글꼴 지표
기하로 장식선을 그리는지를 고정한다 (#187). `document.hwpx`의 파싱 기대값은
`manifest.json`에 있다. 레이아웃 호환성(`hh:layoutCompatibility`)의 35개 요소는 옮기지
않고 `docInfo.compatibleDocument` 아래 진단으로 남는다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/compat-decorations/README.md`)를
   따라 합성 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-15 (System Events 접근성 자동화로 저장)
