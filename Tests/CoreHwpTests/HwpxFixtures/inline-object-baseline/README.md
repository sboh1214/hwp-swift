# inline-object-baseline

HWP fixture `inline-object-baseline`(`Tests/CoreHwpTests/Fixtures/inline-object-baseline/document.hwp`)과
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. 줄 상자보다 **작은** 글자처럼
취급 그림(`hp:pic`, 4~50pt)·1칸 표(`hp:tbl`)를 바깥 여백·상대 크기·줄 간격·10pt 줄·한 줄 세
그림·표 셀 안 조건으로 실어, HWPX 매퍼가 HWP 쌍과 같은 개체 크기·바깥 여백·줄 캐시를 옮기는지와
두 포맷의 렌더가 개체를 같은 자리(베이스라인 − 0.85 × 바깥 상자 높이)에 놓는지를 고정한다
(#195). 한글이 다시 저장한 `hp:linesegarray`(`vertsize`·`baseline`)가 줄 상자의 오라클이다.
`document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/inline-object-baseline/README.md`)를
   따라 합성 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-21 (System Events 접근성 자동화로 저장)
