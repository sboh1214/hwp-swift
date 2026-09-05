# underline-above

HWP fixture `underline-above`(`Tests/CoreHwpTests/Fixtures/underline-above/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. 같은 '글자 위'
밑줄을 HWPX는 `<hh:underline type="TOP" shape="SOLID" color="#000000"/>`로 적으며,
`HwpxCharShapeMapper`가 이를 `HwpUnderlineType.above`(raw 3)로 매핑하는지와
HWP 쌍과의 파싱 등가(`HwpxHwpEquivalenceTests`)를 고정한다 (#149).
`document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/underline-above/README.md`)를
   따라 밑줄 위치 **위쪽**을 적용한다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-05 (Claude Computer Use GUI 자동화로 저장)
