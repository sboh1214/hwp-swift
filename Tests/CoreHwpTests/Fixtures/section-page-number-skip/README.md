# section-page-number-skip

`document.hwp`는 한컴오피스 한글 12.30.0 (build 6446)이 2026-09-15에 저장한 binary HWP
fixture다. `section-page-starts-on` 쌍의 HWPX를 바탕으로 첫 문단에 **쪽 번호 매기기**(가운데
아래, 줄표 `-`)를 넣고 구역 7개의 `쪽 > 구역 설정... > 종류`를 이어서·홀수·짝수·짝수·홀수·
사용자(시작 9)·이어서로 둔 합성 HWPX를 한글로 열어, 같은 편집 세션에서 `한글 문서 (*.hwp)`와
`한글 표준 문서 (*.hwpx)`로 저장했다 — 구역 시작 종류가 **실제로 찍히는 쪽 번호**를 어떻게
바꾸는지의 실측 오라클이다 (#185). `section-page-starts-on`은 쪽 번호 매기기가 없어 그 번호를
상태 표시줄로만 읽었고, 이 쌍은 같은 세션의 `파일 > PDF로 저장하기` 결과가 근거다.

## 포함 기능

7쪽, 구역 7개, 문단 8개(첫 구역만 2문단). 컨트롤 15개(구역·단 각 7, 쪽 번호 위치 1).
표·그림·주석은 없다.

| 구역 | 본문 | 구역 설정 > 종류 | bits 20-21 | `pageStartNumber` | 이어지는 번호 | 한글 쪽 번호 |
|---|---|---|---:|---:|---:|---:|
| 1 | `쪽 번호 건너뛰기 견본` / `첫째 구역 이어서` | 이어서 | 0 | 0 | 1 | 1 |
| 2 | `둘째 구역 홀수` | 홀수 | 2 | 0 | 2 | **3** |
| 3 | `셋째 구역 짝수` | 짝수 | 1 | 0 | 4 | 4 |
| 4 | `넷째 구역 짝수` | 짝수 | 1 | 0 | 5 | **6** |
| 5 | `다섯째 구역 홀수` | 홀수 | 2 | 0 | 7 | 7 |
| 6 | `여섯째 구역 사용자` | 사용자, 시작 번호 9 | 0 | 9 | 8 | 9 |
| 7 | `일곱째 구역 이어서` | 이어서 | 0 | 0 | 10 | 10 |

'이어지는 번호'는 앞 구역 마지막 쪽 번호 + 1이다. 홀수·짝수 종류는 그 번호의 홀짝이 어긋날
때만 1을 건너뛰고(2 → 3, 5 → 6), 이미 맞으면 그대로다(4, 7). 사용자 지정 시작 번호는 그대로
쓴다. **한글은 건너뛴 번호 자리에 빈 쪽을 끼우지 않는다** — PDF도 7쪽이고 각 쪽 아래 가운데의
쪽 번호가 `- 1 -`, `- 3 -`, `- 4 -`, `- 6 -`, `- 7 -`, `- 9 -`, `- 10 -`이다 (`pdftotext`로 쪽마다
추출). 수정 전 조판(`pageStartNumber`만 반영)은 같은 문서에 1·2·3·4·5·9·10을 찍었다.
저장한 `.hwp`를 한글로 다시 열어 PDF로 저장해도 같은 7쪽·같은 번호이고 열람으로 파일은 변하지
않았다.

같은 방법(합성 HWPX → 한글 → PDF)으로 확인한 경계 사례 두 가지는 픽스처에 넣지 않고 합성
테스트(`HwpPaginatorPageNumberTests`·`HwpSectionPageStartsOnTests`)로만 잠갔다:

- **문서 첫 구역이 짝수 시작이면 첫 쪽의 번호가 2다** (2쪽 문서 2·3). 홀수 시작 첫 구역은
  1 그대로다 (1·2).
- **사용자 지정 시작 번호와 홀수·짝수 종류가 함께 있으면 사용자 지정 번호가 그대로다** —
  HWPX `pageStartsOn="ODD" page="4"`는 4, `pageStartsOn="EVEN" page="7"`은 7로 찍히고 다음
  이어서 구역은 8이다. 한글이 다시 저장한 HWPX에도 두 속성이 그대로 남는다(정규화하지
  않는다). 한글 GUI의 구역 설정 대화상자는 종류가 '사용자'일 때만 시작 번호를 받으므로 이
  조합은 합성 입력에서만 나온다.

## 재생성 절차

1. `Tests/CoreHwpTests/HwpxFixtures/section-page-starts-on/document.hwpx`를 바탕으로 합성
   HWPX를 만든다. `Contents/section0.xml`의 첫 본문 `hp:run` 앞에
   `<hp:ctrl><hp:pageNum pos="BOTTOM_CENTER" formatType="DIGIT" sideChar="-"/></hp:ctrl>`를
   넣고, `Contents/section1.xml`을 본떠 구역 파일을 7개로 늘리며 각 `hp:startNum`의
   `pageStartsOn`·`page`를 위 표대로 둔다(`hp:linesegarray`는 지운다). `Contents/content.hpf`의
   manifest·spine과 `Contents/header.xml`의 `secCnt="7"`을 맞추고 `mimetype`을 첫 항목으로
   무압축 저장한다.
2. 한컴오피스 한글에서 열고 `파일 > PDF로 저장하기...`로 PDF를 만들어 쪽마다 쪽 번호를
   확인한다 (`pdftotext -f N -l N`).
3. `파일 > 다른 이름으로 저장하기...`로 `한글 문서 (*.hwp)` 저장, **같은 세션에서** 다시
   `한글 표준 문서 (*.hwpx)`로도 저장해 `HwpxFixtures/section-page-number-skip/document.hwpx`를
   만든다.
4. 저장본을 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`을 갱신한 뒤
   `swift test --filter "FixtureManifestTests|HwpxHwpEquivalence|HwpxFixtureRenderTests|HwpPaginatorPageNumberTests"`를
   실행한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6446`
- 생성일: 2026-09-15 (osascript System Events 접근성 자동화 — 메뉴 클릭, 저장·PDF 패널의
  형식 팝업·파일명 필드·저장 버튼)
