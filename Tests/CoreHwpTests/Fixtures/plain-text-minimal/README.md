# plain-text-minimal

`document.hwp`는 macOS용 한컴오피스 한글에서 직접 저장한 최소 plain-text
binary HWP fixture다.

## 포함 기능

- 문단 텍스트 1개
- 기본 DocInfo/id mapping
- 기본 column/section control
- PreviewText stream
- PreviewImage stream
- BinData storage 없음
- `DocOptions`, `Scripts` top-level entry 존재. CoreHwp는 현재 이 entry들을
  별도 public model로 노출하지 않고, 알려진 HWP stream만 읽는다.

## 재생성 절차

1. `/Applications/Hancom Office HWP.app`을 실행한다.
2. 새 빈 문서에 `Hello CoreHwp plain text fixture.`를 입력한다.
3. `파일 > 다른 이름으로 저장하기...`를 연다.
4. 파일 형식을 `한글 문서 (*.hwp)`로 바꾼다.
5. 파일명을 `plain-text-minimal.hwp`로 지정해 저장한다.
6. 저장된 파일을 이 디렉터리의 `document.hwp`로 복사한다.
7. `manifest.json`의 text, DocInfo, optional stream, payload 기대값을 parser 출력에
   맞춰 갱신한다.

생성 확인 환경:

- 앱: Hancom Office HWP for macOS
- 번들 ID: `com.hancom.office.hwp12.mac.general`
- 버전: `12.30.0` build `6382`
- 생성일: 2026-06-14
