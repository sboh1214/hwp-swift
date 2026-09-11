# section-page-starts-on

HWP fixture `section-page-starts-on`(`Tests/CoreHwpTests/Fixtures/section-page-starts-on/document.hwp`)과
**같은 편집 세션**에서 `한글 표준 문서 (*.hwpx)`로 저장한 HWPX(OWPML) 쌍 fixture다.
`hp:startNum@pageStartsOn`의 `ODD`·`EVEN`이 구역 정의 속성(표 130 bits 20-21)의 어느
값으로 옮겨져야 하는지를 HWP 쌍과 대조한다 (#173).

수정 전 매핑은 스펙이 값을 적지 않은 이 비트에 `ODD → 1`, `EVEN → 2`를 가정해
읽었는데, 한글은 홀수를 `0x200000`(= 2), 짝수를 `0x100000`(= 1)으로 저장한다. 그래서 같은
문서의 두 저장본이 둘째·셋째 구역에서 서로 바뀐 값으로 파싱됐고, 등가 투영에 구역 시작
설정 축이 없어 검출되지 않았다. `document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 담긴 구조

구역 4개의 `hp:secPr` 안 `hp:startNum`이 순서대로 다음과 같다.

```xml
<hp:startNum pageStartsOn="BOTH" page="0" pic="0" tbl="0" equation="0"/>
<hp:startNum pageStartsOn="ODD" page="0" pic="0" tbl="0" equation="0"/>
<hp:startNum pageStartsOn="EVEN" page="0" pic="0" tbl="0" equation="0"/>
<hp:startNum pageStartsOn="BOTH" page="5" pic="0" tbl="0" equation="0"/>
```

| 구역 | 한글의 구역 시작 종류 | `pageStartsOn` | HWP 쌍 `property` bits 20-21 | 매핑 값 |
|---|---|---|---:|---:|
| 1 | 이어서 | `BOTH` | 0 | 0 |
| 2 | 홀수 | `ODD` | 2 | 2 |
| 3 | 짝수 | `EVEN` | 1 | 1 |
| 4 | 사용자 (시작 5) | `BOTH` + `page="5"` | 0 (`pageStartNumber` 5) | 0 |

한컴 공개 OWPML 모델 `enumdef.h`의 `STARTNUMSTARTONTYPE`(BOTH 0 · EVEN 1 · ODD 2)과
같은 값이다. 한글 12.30.0 macOS에서 두 저장본을 다시 열면 `쪽 > 구역 설정...` 대화상자가
구역마다 이어서·홀수·짝수·사용자(5)를 그대로 보이고, 상태 표시줄 쪽 번호는 1·3·4·5다
(빈 쪽은 끼우지 않는다 — 물리 4쪽).

## 재생성

1. `Tests/CoreHwpTests/Fixtures/section-page-starts-on/README.md`의 재생성 절차대로 문서를
   만든다 (`.hwp`와 `.hwpx`는 **같은 편집 세션**에서 연달아 저장해야 쌍이 성립한다).
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사하고 `git status`로 HWP 원본이
   변경되지 않았는지 확인한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.
   `pageCount`는 변환본을 한글.app에서 열어 상태 표시줄의 `N/M쪽`으로 확인한다
   (이 문서는 마지막 쪽에서 `5/4쪽`으로 보인다).

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-11 (Claude Computer Use GUI 자동화로 저장)
