# missing-summary-derived

- `document.hwp`: Hancom Office HWP for macOS 12.30.0 build 6382가 저장한
  `plain-text-minimal` HWP를 기반으로, OLE directory entry의
  `U+0005 HwpSummaryInformation` stream name만 같은 길이의
  `U+0005 XwpSummaryInformation`으로 바꾼 파생 fixture.
- 목적: summary stream이 이름 기준으로 없을 때 `CoreHwp`가 crash나 필수 stream 오류
  없이 빈 `HwpSummary` raw payload를 반환하는지 manifest 기반으로 검증한다.
- 이 fixture는 실제 한컴오피스 저장본의 optional stream 누락 동작을 완전히 대체하지
  않는다. 무수정 한컴 저장본 중 summary stream이 없는 readable HWP가 발견되면 별도
  fixture로 추가할 수 있다.

## 재생성

1. `plain-text-minimal/document.hwp`를 이 디렉터리의 `document.hwp`로 복사한다.
2. 파일 bytes에서 UTF-16LE `U+0005 HwpSummaryInformation` directory entry 이름 한
   건만 찾아 `U+0005 XwpSummaryInformation`으로 교체한다. stream payload와 다른 OLE
   구조는 변경하지 않는다.
3. `manifest.json`의 `summaryLength`를 `0`, `summaryPrefixBytes`와
   `summarySuffixBytes`를 빈 배열로 둔다.
4. `swift test --filter FixtureManifestTests/testFixtureManifests`를 실행한다.
