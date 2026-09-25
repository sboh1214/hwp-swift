# ms-word-paragraph-end-box

HWP fixture `ms-word-paragraph-end-box`(`Tests/CoreHwpTests/Fixtures/ms-word-paragraph-end-box/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **MS 워드 호환 문서**
(`hh:compatibleDocument@targetProgram="MS_WORD"`)에 문단 끝 글자(CR)·한 줄 끝(`hp:lineBreak`)의
글꼴 줄 상자가 본문 글자보다 큰 줄(Apple SD 산돌고딕 Neo·Menlo·Helvetica·Times New Roman 조합,
줄 간격 종류 4종, 한 줄 끝 3종, 글자처럼 취급 표 6개, 글자 아래·위 밑줄)을 실어, HWPX 매퍼가 문단
마지막의 빈 run(`<hp:run charPrIDRef="N"><hp:t/></hp:run>`)을 HWP 쌍과 같은 문단 끝 글자 모양으로,
대상 프로그램을 같은 값(`HwpCompatibleDocumentTarget.msWord`)으로 옮기는지와 두 포맷의 렌더가 끝
글자 상자를 본문 상자 위에 쌓는 한글의 줄 상자를 따르는지를 고정한다 (#223). 한글이 다시 저장한
`hp:linesegarray`(`vertsize`·`textheight`·`baseline`·`spacing`)가 줄 상자의 오라클이다.
`document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/ms-word-paragraph-end-box/README.md`)를
   따라 합성 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-25 (System Events 접근성 자동화로 저장)
