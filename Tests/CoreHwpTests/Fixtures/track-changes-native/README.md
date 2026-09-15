# track-changes-native

`document.hwp`는 **한글 문서**(호환 문서 대상 프로그램 0, `CT_HWP201X`)에 변경 내용 추적
표시(삽입·삭제)와 일반 밑줄·취소선을 같은 줄에 실은 합성 HWPX를 한컴오피스 한글 12.30.0
(build 6446)에서 열어 2026-09-15에 `한글 문서 (*.hwp)`로 저장한 binary HWP fixture다.
코퍼스의 유일한 변경 추적 실물이던 `track-changes`는 MS 워드 호환 문서라, 한글 문서에서
변경 추적 표시선이 일반 밑줄·취소선과 **같은 자리·같은 두께**인지(#187)를 잠글 실물이
없었다. 같은 세션의 PDF 내보내기 좌표가 렌더 핀의 오라클이다
(`HwpKitTests/FixtureDecorationLineRenderTests+Compat.swift`).

## 포함 기능

- FileHeader `isTracingChange == true`, `TRACK_CHANGE_CONTENT`·`TRACK_CHANGE_AUTHOR`
  raw record(`track-changes`의 것을 물려받음), 함초롬돋움 한 글꼴
- 한 구역, 6문단 — 첫 문단은 구역 정의만 있는 빈 문단이고:
  1. `밑줄 `(10pt, 글자 아래 밑줄 초록 `#00FF00`) + `삽입 Ag`(10pt, 삽입 표식)
  2. `취소 `(10pt, 취소선 청록 `#00FFFF`) + `삭제 Ag`(10pt, 삭제 표식)
  3. 1과 같은 조합 20pt
  4. 2와 같은 조합 20pt
  5. `끝` 10pt
- 변경 추적 표시(PARA_RANGE_TAG 16·17)와 줄 캐시는 **ViewText**(표시본)에 있고 BodyText는
  최종 본문(삭제 글자 없음)이다 — 뷰어는 표시본을 그린다.

## 한글.app 실측 (같은 세션 PDF 내보내기, 베이스라인 기준 em)

변경 내용 추적 문서의 PDF 내보내기는 왼쪽 변경 막대 여백 때문에 쪽 전체가 약 0.8배로
축소된다(글리프 7.92·15.84pt) — em 비율은 그대로다.

| 문단 | 일반 선 | 변경 추적 표시선 | 두께 |
|---|---:|---:|---:|
| 1 (10pt) | 밑줄 −0.1667 | 삽입 밑줄 −0.1667 | 둘 다 0.36pt |
| 2 (10pt) | 취소선 +0.3485 | 삭제선 +0.3485 | 둘 다 0.36pt |
| 3 (20pt) | 밑줄 −0.1667 | 삽입 밑줄 −0.1667 | 둘 다 0.60pt |
| 4 (20pt) | 취소선 +0.3485 | 삭제선 +0.3485 | 둘 다 0.60pt |

같은 줄의 일반 선과 변경 추적 표시선이 장치 좌표(0.12pt)까지 같은 자리·같은 두께다.

## 재생성 절차

1. `Fixtures/track-changes/document.hwp`의 사본을 한글에서 `한글 표준 문서 (*.hwpx)`로
   저장해 풀고, `header.xml`의 `hh:compatibleDocument`를 `targetProgram="HWP201X"`
   (`<hh:layoutCompatibility/>`)로 바꾼 뒤 `hh:charPr id="0"`을 복제해 위 글자 모양을
   만들고, `section0.xml`은 첫 문단(`hp:secPr`)만 남기고 위 순서의 5문단을 `hp:insertBegin`/
   `hp:insertEnd`(TcId 2)·`hp:deleteBegin`/`hp:deleteEnd`(TcId 1) 표식과 함께
   `hp:linesegarray` **없이** 적는다. `mimetype`을 `ZIP_STORED` 첫 항목으로 다시 압축한다.
2. 그 HWPX를 `open -b com.hancom.office.hwp12.mac.general`로 연다.
3. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 파일명만
   입력 → 저장 (System Events 접근성 자동화).
4. `파일 > PDF로 저장하기...`로 오라클 PDF를 내보내 벡터 좌표를 읽는다.
5. 저장된 `.hwp`를 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`을 갱신한 뒤
   `swift test --filter "FixtureManifestTests|FixtureDecorationLineRenderTests"`를 실행한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6446`
- 생성일: 2026-09-15
