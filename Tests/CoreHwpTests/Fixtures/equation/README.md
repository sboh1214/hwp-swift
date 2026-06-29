# equation

`document.hwp`는 macOS용 Hancom Office HWP 12.30.0 build 6382에서 직접 저장한
수식 fixture입니다.

## 포함 기능

- 본문 paragraph text
- 수식 object
- DocInfo id mappings
- document properties
- preview text

## 재생성

1. `/Applications/Hancom Office HWP.app`을 실행한다.
2. 새 문서를 만든다.
3. 본문에 `CoreHwp equation fixture text.`를 입력하고 줄을 바꾼다.
4. `입력 > 수식...`을 연다.
5. 수식 편집기에 `x=1`을 입력한다.
6. `넣기`를 눌러 본문에 삽입한다.
7. HWP 형식으로 `equation.hwp`를 저장한다.
8. 저장한 파일을 이 디렉터리의 `document.hwp`로 교체한다.
9. `manifest.json`의 기대값을 parser 출력에 맞춰 갱신한다.
