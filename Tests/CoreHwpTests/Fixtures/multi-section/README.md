# multi-section

`document.hwp`는 macOS용 한컴오피스 한글에서 직접 저장한 2구역 fixture다.

## 포함 기능

- `Section0`, `Section1` body stream
- 구역별 본문 문단 1개
- 구역별 기본 section/column control
- 기본 DocInfo/id mapping
- DocInfo `MEMO_SHAPE` raw record
- PreviewText stream
- PreviewImage stream
- BinData storage 없음

## 재생성 절차

1. `/Applications/Hancom Office HWP.app`에서 새 빈 문서를 만든다.
2. 첫 번째 구역 본문에 `se`를 입력한다.
3. `쪽 > 구역 나누기`를 실행해 두 번째 구역을 만든다.
4. 두 번째 구역 본문에 `tw`를 입력한다.
5. `파일 > 다른 이름으로 저장하기...`에서 파일 형식을 `한글 문서 (*.hwp)`로 둔다.
6. 파일명을 `multi-section.hwp`로 지정해 저장한다.
7. 저장된 파일을 이 디렉터리의 `document.hwp`로 복사한다.
8. `manifest.json`의 `Section0`, `Section1` entry 이름, 구역별 paragraph/control
   count, stream payload 기대값을 parser 출력에 맞춰 갱신한다.

생성 확인 환경:

- 앱: Hancom Office HWP for macOS
- 번들 ID: `com.hancom.office.hwp12.mac.general`
- 버전: `12.30.0` build `6382`
- 생성일: 2026-06-15
