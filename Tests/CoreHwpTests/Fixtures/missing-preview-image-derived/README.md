# missing-preview-image-derived

- `document.hwp`: Hancom Office HWP for macOS 12.30.0 build 6382가 저장한
  `plain-text-minimal` HWP를 기반으로, OLE directory entry의 `PrvImage` stream
  name만 같은 길이의 `XrvImage`로 바꾼 파생 fixture.
- 목적: `PrvImage` stream이 이름 기준으로 없을 때 `CoreHwp`가 crash나 필수 stream
  오류 없이 빈 `HwpPreviewImage`(`format == .none`)를 반환하는지 검증한다.
- 이 fixture는 실제 한컴오피스 저장본의 optional stream 누락 동작을 완전히 대체하지
  않는다. 무수정 한컴 저장본 중 `PrvImage`가 없는 readable HWP fixture는 여전히 별도
  확보가 필요하다.

## 재생성

1. `plain-text-minimal/document.hwp`를 이 디렉터리의 `document.hwp`로 복사한다.
2. 파일 bytes에서 UTF-16LE `PrvImage` directory entry 이름 한 건만 찾아 `XrvImage`로
   교체한다. stream payload와 다른 OLE 구조는 변경하지 않는다.
3. `manifest.json`의 `previewImageLength`를 `0`, `previewImageFormat`을 `none`으로
   둔다.
4. `swift test --filter FixtureManifestTests/testFixtureManifests`를 실행한다.
