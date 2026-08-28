# CharShapeProperty

기존 HWP fixture `CharShapeProperty`(`Tests/CoreHwpTests/Fixtures/CharShapeProperty/document.hwp`)를
한글.app에서 재저장한 HWPX(OWPML) 쌍 fixture다. `document.hwpx`의 파싱
기대값은 `manifest.json`에 있고, HWP 원본과의 파싱 등가는
`HwpxHwpEquivalenceTests`가 검증한다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 원본 `document.hwp`를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-08-28 (Claude Computer Use GUI 자동화로 저장)
