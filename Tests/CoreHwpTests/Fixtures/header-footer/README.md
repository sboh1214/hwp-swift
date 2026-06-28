# header-footer

`document.hwp`는 macOS용 한컴오피스 한글에서 직접 저장한 머리말/꼬리말 fixture다.

## 포함 기능

- 본문 문단 텍스트 1개
- 양쪽 머리말 1개
- 양쪽 꼬리말 1개
- 기본 DocInfo/id mapping
- PreviewText stream

## 재생성 절차

1. `/Applications/Hancom Office HWP.app`에서 plain-text-minimal 문서를 연다.
2. `쪽 > 머리말/꼬리말...`을 열고 `머리말`, `양 쪽`, `없음`으로 `만들기`를 누른다.
3. 머리말 편집 영역에 `CoreHwp header fixture`를 입력한 뒤 머리말/꼬리말 편집을 닫는다.
4. 다시 `쪽 > 머리말/꼬리말...`을 열고 `꼬리말`, `양 쪽`, `없음`으로 `만들기`를 누른다.
5. 꼬리말 편집 영역에 `CoreHwp footer fixture`를 입력한 뒤 편집을 닫는다.
6. `파일 > 다른 이름으로 저장하기...`에서 파일 형식을 `한글 문서 (*.hwp)`로 둔다.
7. 파일명을 `header-footer.hwp`로 지정해 저장한다.
8. 저장된 파일을 이 디렉터리의 `document.hwp`로 복사한다.
9. `manifest.json`의 머리말/꼬리말 control count, nested text, payload 기대값을
   parser 출력에 맞춰 갱신한다.

생성 확인 환경:

- 앱: Hancom Office HWP for macOS
- 번들 ID: `com.hancom.office.hwp12.mac.general`
- 버전: `12.30.0` build `6382`
- 생성일: 2026-06-14
