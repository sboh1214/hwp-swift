# plain-text-hancom-mac2026

`document.hwp`는 macOS용 Hancom Office HWP 12.30.0 build 6382에서
2026-06-24에 직접 저장한 binary HWP fixture다.

## 포함 기능

- 한 구역, 두 문단의 plain text
- PreviewText stream
- PreviewImage stream
- BinData storage 없음

## 재생성 절차

1. `/Applications/Hancom Office HWP.app`을 실행한다.
2. 새 빈 문서에 아래 내용을 입력한다.

   ```text
   CoreHwp Hancom macOS 2026 fixture.
   Second line checks paragraph parsing.
   ```

3. `파일 > 다른 이름으로 저장하기...`를 연다.
4. 파일 형식을 `한글 문서 (*.hwp)`로 바꾼다.
5. 파일명을 `plain-text-hancom-mac2026.hwp`로 지정해 저장한다.
6. 저장된 파일을 이 디렉터리의 `document.hwp`로 복사한다.
7. `manifest.json`의 payload prefix/suffix 기대값을 갱신한다.

생성 확인 환경:

- 앱: Hancom Office HWP for macOS
- 번들 ID: `com.hancom.office.hwp12.mac.general`
- 버전: `12.30.0` build `6382`
- 생성일: 2026-06-24
