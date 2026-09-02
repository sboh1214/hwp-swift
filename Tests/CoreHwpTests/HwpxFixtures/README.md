# CoreHwp HWPX fixture guide

이 디렉터리는 실제 `.hwpx`(OWPML) 문서로 HWPX 변환 파싱을 검증하기 위한
fixture 루트다. 구조는 `Fixtures/`와 같은 canonical layout을 따르되 별도
루트를 쓴다 — 기존 하니스의 OLE 매직·개수 핀 가드와 충돌하지 않기 위해서다.

```text
Tests/CoreHwpTests/HwpxFixtures/<fixture-id>/
  document.hwpx
  manifest.json
  README.md
```

## 생성 정책

fixture는 **기존 HWP fixture를 한글.app에서 재저장한 쌍**이다. 같은 문서의
HWP↔HWPX 파싱 등가(`HwpxHwpEquivalenceTests`)가 핵심 회귀 축이 되고,
`manifest.json`의 `sourceHwpFixture`가 쌍을 잇는다.

재생성 절차 (fixture별 README에도 기록):

1. `/Applications/한컴오피스 한글.app`(bundle
   `com.hancom.office.hwp12.mac.general`, 12.30.0 build 6446)에서
   `Fixtures/<id>/document.hwp`를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)**
   → 저장. 저장본을 `HwpxFixtures/<id>/document.hwpx`로 복사한다.
3. `manifest.json` 기대값을 갱신하고
   `swift test --filter "HwpxFixtureManifestTests|HwpxHwpEquivalenceTests"`를
   실행한다.
4. **원본 `document.hwp`가 변하지 않았는지 `git status`로 확인한다** —
   한글.app은 열람만으로도 OLE 원본을 다시 쓸 수 있다 (2026-08-28 chart
   fixture 실측: 크기 동일한 바이너리 변경 발생 → 원복함). 변했으면
   `git checkout -- <경로>`로 되돌린다.

한글.app은 AppleScript를 지원하지 않으므로 자동화는 GUI 조작뿐이다 —
`Fixtures/README.md`의 자동화 정책(별도 승인 하의 Computer Use)이 그대로
적용된다. 2026-08-28 초기 10종은 그 정책대로 승인 하의 GUI 자동화로
생성했다.

## 변환 불가·제외 fixture

- 암호(`문서암호설정-*`)·배포용(`배포용문서`)·DRM(`drm-unsupported-derived`)
  fixture는 열 수 없어 변환할 수 없다 (HWPX의 대응 표면은
  `META-INF/encryption.xml` 거부 — 합성 테스트가 고정).
- `missing-*-derived` 손상 파생 fixture는 재저장이 결함을 지우므로 제외.
- 버전 프로버넌스 fixture(`2007` 등)와 1차 범위 밖 기능 fixture(각주·메모·
  수식·변경추적·책갈피 등)는 해당 기능 승격 시 함께 변환한다.

## manifest 작성 기준

- `id`는 디렉터리명과 정확히 일치해야 한다.
- `expectations`는 의미 있는 기대값만 적는다 — 구역/문단 수, 가시 텍스트,
  id 매핑 배열 크기, 쪽 지오메트리(HWPUNIT), 표 셀 수/병합, 그림 BinItem id.
- `pageCount`는 한글.app 실측을 기록할 때만 적는다 (`pageCountSource`에
  실측 방법 명기).
- 미해석 강등(1차 범위 밖 요소)은 `HwpFile.parseDiagnostics()`로 드러난다 —
  기대값이 아니라 진단으로 다룬다.
