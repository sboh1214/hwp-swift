# section-page-number-skip

HWP fixture `section-page-number-skip`(`Tests/CoreHwpTests/Fixtures/section-page-number-skip/document.hwp`)과
**같은 편집 세션**에서 `한글 표준 문서 (*.hwpx)`로 저장한 HWPX(OWPML) 쌍 fixture다. 구역 시작
종류(`hp:startNum@pageStartsOn`)가 쪽 번호 매기기(`hp:pageNum`)에 찍히는 번호를 어떻게 건너뛰게
하는지를 HWP 쌍·한글 PDF와 대조한다 (#185). `document.hwpx`의 파싱 기대값은 `manifest.json`에
있다.

## 담긴 구조

구역 7개의 `hp:secPr` 안 `hp:startNum`이 순서대로 다음과 같고, 첫 구역 첫 문단에
`<hp:pageNum pos="BOTTOM_CENTER" formatType="DIGIT" sideChar="-"/>`가 있다.

```xml
<hp:startNum pageStartsOn="BOTH" page="0" pic="0" tbl="0" equation="0"/>
<hp:startNum pageStartsOn="ODD" page="0" pic="0" tbl="0" equation="0"/>
<hp:startNum pageStartsOn="EVEN" page="0" pic="0" tbl="0" equation="0"/>
<hp:startNum pageStartsOn="EVEN" page="0" pic="0" tbl="0" equation="0"/>
<hp:startNum pageStartsOn="ODD" page="0" pic="0" tbl="0" equation="0"/>
<hp:startNum pageStartsOn="BOTH" page="9" pic="0" tbl="0" equation="0"/>
<hp:startNum pageStartsOn="BOTH" page="0" pic="0" tbl="0" equation="0"/>
```

| 구역 | `pageStartsOn` | `page` | HWP 쌍 bits 20-21 | 한글 쪽 번호 (PDF) |
|---|---|---:|---:|---:|
| 1 | `BOTH` | 0 | 0 | 1 |
| 2 | `ODD` | 0 | 2 | 3 |
| 3 | `EVEN` | 0 | 1 | 4 |
| 4 | `EVEN` | 0 | 1 | 6 |
| 5 | `ODD` | 0 | 2 | 7 |
| 6 | `BOTH` | 9 | 0 | 9 |
| 7 | `BOTH` | 0 | 0 | 10 |

물리 7쪽에 빈 쪽은 없다. 한글이 저장한 두 형식은 구역 시작 설정 축(`sectionSettings`)이
같고, 뷰어 렌더의 쪽 크롬 텍스트도 HWP 쌍과 같아야 한다
(`HwpxFixtureRenderTests.testHwpxPageChromeMatchesHwpPairs`의 직접 핀).

## 재생성

1. `Tests/CoreHwpTests/Fixtures/section-page-number-skip/README.md`의 재생성 절차대로 합성
   HWPX를 만들어 한글로 연다 (`.hwp`와 `.hwpx`는 **같은 편집 세션**에서 연달아 저장해야
   쌍이 성립한다).
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사하고 `git status`로 HWP 원본이 변경되지
   않았는지 확인한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다. `pageCount`는
   같은 세션의 `파일 > PDF로 저장하기` 쪽수(7)로 확인한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-15 (osascript System Events 접근성 자동화로 저장)
