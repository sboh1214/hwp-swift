# underline-above

`document.hwp`는 `plain-text-minimal`의 `document.hwp` 사본을 한컴오피스 한글
12.30.0 (build 6446)에서 열어 문단 전체에 밑줄 위치 **위쪽**을 적용하고
2026-09-05에 저장한 binary HWP fixture다. 한글.app이 '글자 위' 밑줄을
DocInfo 글자 모양 속성(표 33) bit 2~3의 값 **3**으로 저장한다는 실측 근거이며,
`HwpUnderlineType.above`(raw 3)가 파싱되는지와 뷰어 옵션
(`HwpLoadOptions.viewer`)에서도 열리는지를 고정한다 (#149).

## 포함 기능

- 한 구역, 한 문단의 plain text ("Hello CoreHwp plain text fixture.")
- 글자 모양 8개 — 마지막 `charShape[7]`의 속성이 `0x0000000c`
  (밑줄 종류 3 = 글자 위, 밑줄 모양 0)
- PreviewText stream
- PreviewImage stream
- BinData storage 없음

## 재생성 절차

1. `Tests/CoreHwpTests/Fixtures/plain-text-minimal/document.hwp` **사본**을
   한컴오피스 한글에서 연다 (열람만으로 원본이 재기록되므로 사본 필수).
2. 문단을 선택하고 `서식 > 글자 모양...` › **확장** 탭 › 밑줄 › 위치를
   **위쪽**으로 바꾼 뒤 **설정** 단추를 누른다.
3. `파일 > 저장하기`로 저장한다 (형식은 `한글 문서 (*.hwp)` 그대로).
4. 저장된 파일을 이 디렉터리의 `document.hwp`로 복사한다.
5. `manifest.json`의 payload prefix/suffix 기대값과 `charShapePropertyRawValues`를
   갱신하고 `swift test --filter "FixtureManifestTests|HwpUnderlineTypeTests|HwpxHwpEquivalenceTests"`를
   실행한다.
6. 같은 편집 세션에서 `파일 > 다른 이름으로 저장하기...` › 한글 표준 문서
   (*.hwpx)로도 저장해 `HwpxFixtures/underline-above/document.hwpx`를 갱신한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6446`
- 생성일: 2026-09-05
