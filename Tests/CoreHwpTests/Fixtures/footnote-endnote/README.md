# footnote-endnote

`document.hwp`는 macOS용 한컴오피스 한글에서 직접 저장한 각주/미주 fixture다.

## 포함 기능

- 본문 문단 텍스트 1개
- 각주 1개
- 미주 1개
- 기본 DocInfo/id mapping
- PreviewText stream

## 재생성 절차

1. `/Applications/Hancom Office HWP.app`에서 새 문서를 연다.
2. 본문에 `CoreHwp footnote endnote fixture bod.`를 입력한다.
3. `입력 > 주석 > 각주`를 선택한다.
4. 각주 영역에 `CoreHwp footnote fixture`를 입력한다.
5. 본문 영역으로 돌아와 `입력 > 주석 > 미주`를 선택한다.
6. 미주 영역에 `CoreHwp endnote fixture`를 입력한다.
7. `파일 > 다른 이름으로 저장하기...`에서 파일 형식을 `한글 문서 (*.hwp)`로 둔다.
8. 파일명을 `footnote-endnote.hwp`로 지정해 저장한다.
9. 저장된 파일을 이 디렉터리의 `document.hwp`로 복사한다.
10. `manifest.json`의 각주/미주 control count, nested text, payload 기대값을 parser
    출력에 맞춰 갱신한다.

생성 확인 환경:

- 앱: Hancom Office HWP for macOS
- 번들 ID: `com.hancom.office.hwp12.mac.general`
- 버전: `12.30.0` build `6382`
- 생성일: 2026-06-15
