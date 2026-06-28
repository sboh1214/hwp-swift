# drm-unsupported-derived

- `document.hwp`: Hancom Office HWP for macOS 12.30.0 build 6382가 저장한
  `plain-text-minimal` HWP를 기반으로, OLE `FileHeader` stream의 fileProperty
  DRM bit만 켠 파생 fixture.
- 목적: DRM bit가 켜진 HWP를 `CoreHwp`가 본문 stream 파싱 전에
  `HwpError.unsupportedFeature(.drmDocument)`로 거부하는지 검증한다.
- 기대 오류: `unsupportedFeature.drmDocument`
- 이 fixture는 실제 DRM 보호 문서를 대체하지 않는다. DRM 저장 기능이 노출되는
  한컴오피스 설치본이나 합법적으로 제공받은 DRM HWP는 여전히 별도 확보가 필요하다.

## 재생성

1. `plain-text-minimal/document.hwp`를 이 디렉터리의 `document.hwp`로 복사한다.
2. 파일 bytes에서 ASCII `HWP Document File` signature가 포함된 `FileHeader` stream
   payload를 찾는다.
3. signature 시작 offset에서 36바이트 뒤의 little-endian `fileProperty` DWORD에
   `0x10` DRM bit를 OR 한다. 현재 원본 값은 `0x00000001`이고 파생 값은
   `0x00000011`이다.
4. `swift test --filter FixtureManifestTests --filter FixtureKnownMissingGoalTests`를
   실행한다.
