# memo

`document.hwp`는 macOS용 한컴오피스 한글에서 직접 저장한 메모 fixture다.
현재 reader는 메모 본문을 별도 typed model로 해석하지 않고 field control raw payload로
보존한다. `MEMO/...` field parameter는 marker/components/author를 구조화한
typed value로 함께 노출한다.

## 포함 기능

- 본문 문단 텍스트 1개
- 메모 1개
- 메모 field control raw payload 및 structured parameter 보존
- 기본 DocInfo/id mapping
- PreviewText stream

## 재생성 절차

1. `/Applications/Hancom Office HWP.app`에서 새 문서를 연다.
2. 본문에 `CoreHwp memo fixture bod.`를 입력한다.
3. `입력 > 메모 > 새 메모`를 선택한다.
4. 메모 입력 영역에 `CoreHwp memo fixture`를 입력한다.
5. `파일 > 다른 이름으로 저장하기...`에서 파일 형식을 `한글 문서 (*.hwp)`로 둔다.
6. 파일명을 `memo.hwp`로 지정해 저장한다.
7. 저장된 파일을 이 디렉터리의 `document.hwp`로 복사한다.
8. `manifest.json`의 memo field parameter, raw payload, control 기대값을 parser 출력에
   맞춰 갱신한다.

생성 확인 환경:

- 앱: Hancom Office HWP for macOS
- 번들 ID: `com.hancom.office.hwp12.mac.general`
- 버전: `12.30.0` build `6382`
- 생성일: 2026-06-15
