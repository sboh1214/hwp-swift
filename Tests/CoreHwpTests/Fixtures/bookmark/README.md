# bookmark

`document.hwp`는 macOS용 Hancom Office HWP 12.30.0 build 6382에서 직접 저장한
책갈피 fixture입니다.

## 포함 기능

- 본문 paragraph text
- 책갈피 control (`CoreHwpBookmark`)
- DocInfo id mappings
- document properties
- preview text

## Reader 검증 메모

- 이 fixture의 책갈피 child `CTRL_DATA`는 ParameterSet `0x021B`, item raw id
  `0x40000000`, value type `1` 문자열로 `CoreHwpBookmark`를 저장한다.
- rhwp errata 항목 20의 ClickHere field name과 같은 ParameterSet 문자열 layout을
  검증하는 보조 Hancom fixture로 사용한다. ClickHere field name 의미 검증은 별도
  누름틀 fixture가 필요하다.

## 재생성

1. `/Applications/Hancom Office HWP.app`을 실행한다.
2. 새 문서를 만든다.
3. 본문에 `CoreHwp bookmark fixture text.`를 입력한다.
4. 본문 텍스트 범위를 선택한다.
5. `입력 > 책갈피...`를 연다.
6. 책갈피 이름을 `CoreHwpBookmark`로 지정하고 `넣기`를 누른다.
7. HWP 형식으로 저장한다.
8. 저장한 파일을 이 디렉터리의 `document.hwp`로 교체한다.
9. `manifest.json`의 기대값을 parser 출력에 맞춰 갱신한다.
