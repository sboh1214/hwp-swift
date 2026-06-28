# chart

- 생성 도구: Hancom Office HWP for macOS 12.30.0 (build 6382)
- 생성일: 2026-06-15
- 목적: 차트 개체가 포함된 HWP 문서를 열고, 현재 reader가 차트를 `genShapeObject`와 BinData/OLE storage로 보존하는지 검증한다.

## 재생성 절차

1. 한컴오피스 한글을 연다.
2. 새 문서를 만든다.
3. 본문에 `CoreHwp  chart fixture text.`를 입력한다.
4. 도구 막대의 차트 버튼을 누른다.
5. 차트 갤러리에서 `묶은 세로 막대형`을 선택한다.
6. 차트 데이터 편집 대화상자의 기본값을 그대로 두고 `확인`을 누른다.
7. `파일 > 다른 이름으로 저장하기...`를 선택한다.
8. 파일 형식을 `한글 문서 (*.hwp)`로 바꾸고 `chart.hwp`로 저장한다.
9. 저장된 파일을 이 디렉터리의 `document.hwp`로 복사한다.
