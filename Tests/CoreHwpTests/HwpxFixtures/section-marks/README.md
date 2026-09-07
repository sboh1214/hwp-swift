# section-marks

HWP fixture `section-marks`(`Tests/CoreHwpTests/Fixtures/section-marks/document.hwp`)와
**같은 편집 세션**에서 `한글 표준 문서 (*.hwpx)`로 저장한 HWPX(OWPML) 쌍 fixture다.
새 번호 지정·쪽 감추기·책갈피·찾아보기 표식의 typed 승격(#169)을 HWP 쌍과 대조한다.

승격 전에는 `hp:newNum`·`hp:pageHiding`·`hp:bookmark`·`hp:indexmark`가 전부
`.notImplemented`로 강등돼 조판이 **쪽 번호를 되돌리지도 감추지도 못했다** —
`HwpPaginator.applyNewNumbers`와 `HwpPageChromeBuilder.pageHideMask`가 typed 컨트롤만
보기 때문이다. `document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 담긴 구조

```xml
<hp:ctrl><hp:indexmark><hp:firstKey>본문</hp:firstKey></hp:indexmark></hp:ctrl>
<hp:ctrl><hp:pageHiding hideHeader="1" hideFooter="0" hideMasterPage="0"
                        hideBorder="1" hideFill="0" hidePageNum="1"/></hp:ctrl>
<hp:ctrl><hp:newNum num="9" numType="PAGE"/></hp:ctrl>
<hp:ctrl><hp:pageHiding hideHeader="0" hideFooter="1" hideMasterPage="1"
                        hideBorder="0" hideFill="1" hidePageNum="0"/></hp:ctrl>
<hp:ctrl><hp:newNum num="5" numType="PICTURE"/></hp:ctrl>
<hp:ctrl><hp:indexmark><hp:firstKey>색인둘본문</hp:firstKey></hp:indexmark></hp:ctrl>
<hp:ctrl><hp:newNum num="7" numType="FOOTNOTE"/></hp:ctrl>
<hp:ctrl><hp:bookmark name="표식 A1"/></hp:ctrl>
```

문서 순서로 표식 8개다 — 찾아보기 표식 2 · 쪽 감추기 2 · 새 번호 3 · 책갈피 1.

HWP 쌍의 컨트롤 payload와 **바이트 단위로 같다**:

| OWPML | 바이너리 payload |
|---|---|
| `hp:pageHiding` 위 두 표본 | `64 68 67 70 29 00 00 00` · `64 68 67 70 16 00 00 00` |
| `hp:newNum` 세 표본 | `6F 6E 77 6E {00,03,01} 00 00 00 {09,05,07} 00` |
| `hp:indexmark` (키워드 `본문`) | `6D 78 64 69 02 00 F8 BC 38 BB 00 00 FF FF FF FF` |
| `hp:bookmark` | 컨트롤 `6D 6B 6F 62` + CTRL_DATA `1B 02 01 00 00 00 00 40 01 00 05 00` + 이름 |

쪽 감추기 두 표본이 서로의 여집합(`0x29` bits 0·3·5 / `0x16` bits 1·2·4)이라 표 145의
여섯 이름이 두 삼중항으로 갈리는 것까지 정해진다 — 삼중항 **안의** 배정은 이 표본으로
정해지지 않는다(HWP 쌍 README 참조). 새 번호의 제어 문자 코드는 **21**이다 — 18은 자동
번호(`atno`) 전용이고, 승격 전 강등 표는 18로 적고 있었다.

## 재생성

1. `Tests/CoreHwpTests/Fixtures/section-marks/README.md`의 재생성 절차대로 문서를 만든다
   (`.hwp`와 `.hwpx`는 **같은 편집 세션**에서 연달아 저장해야 쌍이 성립한다).
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사하고 `git status`로 HWP 원본이
   변경되지 않았는지 확인한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.
   `pageCount`는 변환본을 한글.app에서 열어 상태 표시줄의 `N/M쪽`으로 확인한다
   (이 문서는 새 번호 지정 때문에 인쇄 번호가 10이라 `10/3쪽`으로 보인다).

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-08 (Claude Computer Use GUI 자동화로 저장)
