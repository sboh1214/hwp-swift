# page-end-line-box

HWP fixture `page-end-line-box`(`Tests/CoreHwpTests/Fixtures/page-end-line-box/document.hwp`)와 같은
편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. 본문 97.62pt의 작은 쪽마다 채움 줄로
남은 자리를 만들고 그 끝에 16·18·17.62·17.61pt 한 줄, 고정 8pt 줄, 아래 간격 20pt 줄, 한 줄
끝(`hp:lineBreak`)으로 나눈 여러 줄 문단(보호 없음·문단 보호·외톨이줄 보호), 빈 문단, 각주 위
20pt 줄을 실어, HWPX 매퍼가 HWP 쌍과 같은 문단 모양(`hh:breakSetting`·줄 간격)·글자 크기를 옮기는지와
두 포맷의 재조판이 쪽 끝 적합을 **줄 상자 하단**으로 판정하는지를 고정한다 (#222). 한글이 다시
저장한 `hp:linesegarray`(`vertpos`·`vertsize`·`baseline`)가 쪽 나눔의 오라클이다
(`HwpKitTests/FixturePageEndLineBoxTests.swift`). `document.hwpx`의 파싱 기대값은
`manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/page-end-line-box/README.md`)를
   따라 합성 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-24 (System Events 접근성 자동화로 저장)
