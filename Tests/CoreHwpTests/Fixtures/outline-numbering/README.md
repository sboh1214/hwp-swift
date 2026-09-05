# outline-numbering

`document.hwp`는 `plain-text-minimal`의 `document.hwp` 사본을 한컴오피스 한글
12.30.0 (build 6446)에서 열어 개요 문단 3개·본문 문단 1개·문단 번호 문단 2개를
입력하고 개요 번호 모양을 사용자 정의로 바꿔 2026-09-05에 저장한 binary HWP
fixture다. 저장소에서 헌법주석(`legacy-common-control-property`) 다음으로 최상위
개요 문단을 가진 두 번째 fixture이고, 문단 번호(문단 머리 종류 2) 문단을 가진
**유일한** fixture다 (#152).

## 포함 기능

- 한 구역, 문단 7개: "Hello CoreHwp plain text fixture." / 개요 1~3수준
  ("Outline level one/two/three") / "Plain body paragraph" / 문단 번호
  ("Numbered item one/two")
- 문단 번호 정의 2개 — `numberingArray[0]`은 한글 기본 정의(`^1.`·`^2.`·`^3)`…,
  문단 번호 문단이 `numberingOrBulletId` 1로 참조), `numberingArray[1]`은 사용자
  정의 개요 번호(구역 정의 `numberParaShapeId` 2가 참조)
- 사용자 정의 정의의 표 39 문단 머리 정보 비기본값:
  1수준 속성 `0x52`(정렬 오른쪽 2 · 번호 너비 자릿수 맞춤 해제 · 자동 내어쓰기 해제 ·
  본문과의 거리 종류 HWPUNIT · 번호 모양 로마 대문자 2) · 거리 1000(10pt) ·
  너비 보정 200(2pt), 2수준 속성 `0x10D`(정렬 가운데 1 · 한글 가나다 8),
  9수준 서식 `^n)`(레벨 경로), 10수준 서식 `^9.^10)`(캐럿은 한 자리만 먹어
  한글.app이 `ㄱ.I0)`로 그린다)
- 개요 문단의 `paraShape.numberingOrBulletId`는 전부 0 — 개요 정의는 구역 정의가
  가리킨다
- PreviewText·PreviewImage stream, BinData storage 없음

## 재생성 절차

1. `Tests/CoreHwpTests/Fixtures/plain-text-minimal/document.hwp` **사본**을
   한컴오피스 한글에서 연다 (열람만으로 원본이 재기록되므로 사본 필수).
2. 첫 문단 끝에서 Return 뒤 "Outline level one"을 입력하고 `서식 > 개요 적용/해제`,
   Return 뒤 "Outline level two"와 `서식 > 한 수준 감소`, 같은 방법으로
   "Outline level three"(3수준), Return 뒤 "Plain body paragraph"와
   `서식 > 개요 적용/해제`(해제), Return 뒤 "Numbered item one"과
   `서식 > 문단 번호 적용/해제`, Return 뒤 "Numbered item two"를 입력한다.
3. `서식 > 개요 번호 모양...` › **사용자 정의...**에서 1수준: 번호 모양 I,II,III ·
   번호 너비를 자릿수에 맞춤 해제 · 너비 조정 2.0pt · 정렬 오른쪽 · 본문과의 간격
   10.0pt · 자동으로 내어쓰기 해제, 2수준: 정렬 가운데, 9수준: 번호 서식 `^n)`,
   10수준: 번호 서식 `^9.^10)`으로 바꾸고 **설정**, 바깥 대화상자도 **설정**한다.
   (대화상자가 현재 문단을 개요로 바꾸면 마지막 문단에 `서식 > 문단 번호 적용/해제`를
   다시 적용한다.)
4. `파일 > 저장하기`로 저장한다 (형식은 `한글 문서 (*.hwp)` 그대로).
5. 저장된 파일을 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`을 갱신한 뒤
   `swift test --filter "FixtureManifestTests|ParaHeadInfoTests|NumberingFormatPatternTests|HwpxHwpEquivalenceTests|HwpNumberingHeadingFixtureTests"`를
   실행한다.
6. 같은 편집 세션에서 `파일 > 다른 이름으로 저장하기...` › 한글 표준 문서 (*.hwpx)로도
   저장해 `HwpxFixtures/outline-numbering/document.hwpx`를 갱신한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6446`
- 생성일: 2026-09-05
