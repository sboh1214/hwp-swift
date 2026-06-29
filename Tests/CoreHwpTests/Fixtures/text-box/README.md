# text-box

`document.hwp`는 macOS 한컴오피스 한글 12.30.0에서 직접 저장한 가로 글상자
fixture입니다.

## 포함 기능

- 본문에 가로 글상자 1개
- 글상자 내부 텍스트: `Text box fixture inside box`
- binary `.hwp` 저장 형식
- `PrvText`, `PrvImage` stream 포함
- `BinData` storage 없음

현재 reader는 이 글상자를 `genShapeObject`와 `rectangle` shape component로 읽고,
글상자 내부 list/paragraph records는 `textBoxListArray` typed model로 노출합니다.
rectangle detail record는 `shapeComponentRectangle` typed raw model로 노출하고
payload prefix/suffix를 manifest로 검증합니다.

## 재생성

1. `/Applications/Hancom Office HWP.app`을 연다.
2. 새 빈 문서에서 `입력 > 개체 > 가로 글상자`를 선택한다.
3. 본문 영역에 글상자를 그리고 `Text box fixture`와 `inside box` 두 줄을 입력한다.
4. `파일 > 다른 이름으로 저장하기...`를 선택한다.
5. 파일 형식을 `한글 문서 (*.hwp)`로 바꾸고 `document.hwp`로 저장한다.
6. 저장된 파일을 이 디렉터리로 복사한 뒤 manifest 기대값을 갱신한다.
