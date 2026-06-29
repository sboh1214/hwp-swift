# 2007

- `document.hwp`: 기존 `Tests/CoreHwpTests/Versions/2007.hwp`에서 이관.
- 목적: 구버전 HWP가 `BinData` storage를 포함하지 않아도 reader가 빈 binary data
  배열로 처리하는지 검증한다.
- 재생성: 한컴오피스 한글에서 HWP 2007 계열 문서를 저장하고 `manifest.json`의 버전/기대값을 갱신한다.
