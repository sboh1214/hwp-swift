# Hwp-Swift

> If you want English version of documentation, please contact to [sboh1214@gmail.com](sboh1214@gmail.com)

> 본 제품은 한글과컴퓨터의 한글 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

[![CI](https://github.com/sboh1214/hwp-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/sboh1214/hwp-swift/actions/workflows/ci.yml)
[![CD](https://github.com/sboh1214/hwp-swift/actions/workflows/cd.yml/badge.svg)](https://github.com/sboh1214/hwp-swift/actions/workflows/cd.yml)
[![codecov](https://codecov.io/gh/sboh1214/hwp-swift/branch/main/graph/badge.svg)](https://codecov.io/gh/sboh1214/hwp-swift)

한글 파일을 읽고 쓰기 위한 스위프트 패키지

## 설치

### 스위프트 패키지 관리자

Xcode에서 ```File``` > ```Swift Packages``` > ```Add Package Dependency...``` 메뉴를 선택하세요.

또는 의존성을 아래와 같이 수동으로 추가합니다.

```swift
dependencies: [
    .package(url: "https://github.com/sboh1214/hwp-swift.git", branch: "main"),
],
```

> 안정 릴리스가 태깅되면 `branch: "main"` 대신 `from: "x.y.z"`로 고정하는 것을 권장합니다.

## 라이브러리 구조

![Structure](https://github.com/sboh1214/hwp-swift/blob/main/.github/structure/Structure.png)

## 지원 범위

현재 목표는 읽기 전용 binary HWP reader입니다. 파싱 실패는 crash가 아니라
`HwpError`로 반환하고, 아직 완전히 해석하지 못한 record/control은 raw payload를
보존하는 방향으로 확장하고 있습니다.

`HwpReadLimits`는 OLE directory의 stream size를 기준으로 압축 입력과 비압축
stream을 읽기 전에 제한하고, 압축 해제 결과가 한도를 넘으면
`HwpError.streamSizeLimitExceeded`로 거부합니다. 단, 현재 `SWCompression`
Deflate API는 bounded streaming inflate를 제공하지 않으므로 압축 해제 결과 한도는
inflate가 끝난 뒤 검사하는 후처리 거부입니다. 이 제한은 typed error 반환을 위한
검증이지, 압축 해제 중 메모리 할당 상한을 보장하지 않습니다.

2026-06-28 기준 `swift test --enable-code-coverage`를 실행한 뒤
`.build/out/Products/Debug/codecov/Hwp-Swift.json`에서 `Sources/CoreHwp`만
집계했을 때 line coverage는 98.60% (5481/5559), region coverage는
97.56% (2483/2545)입니다.

| 영역 | 상태 |
| --- | --- |
| OLE compound document 열기 | 지원 |
| `FileHeader`, `DocInfo`, `BodyText/Section*` | 부분 지원. DocInfo/section stream raw payload는 fixture manifest에서 byte 검증하고, 실제 fixture stream 기반 주입 테스트로 unknown section record와 corrupt record 처리를 확인 |
| `U+0005 HwpSummaryInformation` | raw payload 보존. fixture manifest에서 summary length/prefix/suffix bytes를 검증하고, `missing-summary-derived` fixture와 directory-entry mutation/Codable round-trip 테스트로 stream 부재 시 빈 summary로 처리되는지 검증 |
| `PrvText` | UTF-16LE text와 raw payload 보존. `missing-preview-text-derived` fixture와 directory-entry mutation/Codable round-trip 테스트로 stream 부재 시 기본 preview text raw payload(`[0x0D, 0x00, 0x0A, 0x00]`)를 반환하는지 검증 |
| `PrvImage` | raw payload와 image format signature 보존, fixture manifest에서 prefix/suffix bytes 검증, 없으면 빈 preview image로 처리 |
| `BinData` storage | stream 이름, stream id, 확장자, raw payload 보존. fixture manifest에서 storage metadata와 payload prefix/suffix bytes 검증하고, `chart` 실제 fixture의 OLE object가 참조하는 `BIN0001.OLE` stream 연결과 payload sample을 별도 회귀 테스트로 확인. 없으면 빈 배열로 처리 |
| `BodyText/Section*` 정렬 | `Section0`, `Section1` 숫자 순 정렬 |
| 추가 root entry (`DocOptions`, `Scripts` 등) | 현재 별도 public model로 노출하지 않음. 실제 한컴오피스 저장본 fixture에서 존재 여부를 manifest로 검증하고, 알려진 stream 파싱이 영향받지 않는지 확인 |
| DocInfo 미해석 record | `unknownRecords`에 raw payload 보존 |
| DocInfo id mappings | fixture manifest에서 주요 mapping count와 raw payload total 검증 |
| DocInfo raw records | `DOC_DATA`는 실제 fixture 기반으로 32-bit word 배열과 trailing bytes를 typed raw model로 노출하고 payload/child를 검증. `DISTRIBUTE_DOC_DATA`도 32-bit word 배열과 trailing bytes를 typed raw model로 보존하며 synthetic/stream 주입 테스트로 확인한다. `MEMO_SHAPE`, `TRACK_CHANGE_CONTENT`, `TRACK_CHANGE_AUTHOR`는 top-level 및 `ID_MAPPINGS` child record를 typed raw model로 보존하고 `track-changes` fixture/synthetic test로 확인. `TRACK_CHANGE_CONTENT`는 kind와 변경 시각, `TRACK_CHANGE_AUTHOR`는 작성자 이름, `TRACK_CHANGE`는 선행 32-bit header 값을 typed model로 노출한다. DocInfo `TRACK_CHANGE`는 `noori` fixture의 compatible document child record(`compatible-track-change-records`)로 검증. 전체 `HwpFile` 조립 경로는 `plain-text-minimal`의 실제 `DocInfo`/`BodyText` stream에 `DISTRIBUTE_DOC_DATA`와 top-level `TRACK_CHANGE` raw record를 주입해 보존을 검증한다. 실제 `DISTRIBUTE_DOC_DATA`와 top-level `TRACK_CHANGE` fixture(`top-level-track-change-records`)는 추가 필요 |
| `DOC_DATA` 하위 `FORBIDDEN_CHAR` | 실제 fixture 기반 typed model로 파싱하고 raw payload/child records 보존 |
| DocInfo compatible/layout compatibility | 실제 fixture 기반 typed model로 파싱하고 raw payload/child records 보존 |
| section/column/page-number controls | typed model로 파싱하고 raw payload/child records 보존. page-number position은 property와 장식 문자 필드를 fixture manifest로 검증 |
| header/footer/footnote/endnote controls | list header와 내부 paragraph를 typed raw model로 파싱하고 raw payload/child records 보존 |
| table control (`tbl `) | table property와 cell paragraph를 typed model로 파싱하고 cell header raw payload 보존 |
| field hyperlink control (`%hlk`) | URL을 typed model로 파싱하고 raw payload/trailing bytes 보존 |
| field controls | known field ctrl id를 enum으로 보존하고 raw payload/trailing bytes/child records 보존. `memo` 실제 fixture의 `MEMO/...` parameter를 가진 unknown field는 memo control로 분류하고 parameter marker/components/author 및 Codable round-trip 보존을 검증 |
| 일반 개체 controls (`$pic`, `$lin`, `eqed`/`equd`, `$ole`, 글상자 등) | typed raw model로 분리하고 common property/shape component/raw payload 보존. `ctrlData` child record는 `HwpCtrlData` typed raw model로 보존. 수식 `eqed`는 `eqEdit` raw record와 수식 문자열을 별도 보존. 글상자는 `genShapeObject` + `rectangle` shape component 및 내부 list/paragraph records를 typed model로 노출하고 미해석 rectangle detail record를 raw payload로 보존. `legacy-common-control-property`의 legacy 44바이트 common property와 polygon component raw payload는 실제 fixture와 Codable round-trip으로 검증 |
| gen shape object control (`gso `) | 공통 속성, shape component ctrl id, picture/OLE BinData id를 typed model로 파싱하고 raw payload 보존. `chart` 실제 fixture의 OLE shape component는 raw payload/BinData id를 `HwpCtrlId` Codable round-trip 후에도 보존하는지 검증 |
| 기타 known controls (`bokm`, `atno`, `nwno`, `pghd`, `idxm`, `tdut` 등) | typed raw model로 분리하고 raw payload/trailing bytes/child records 보존. `bokm`은 `ctrlData`의 책갈피 이름, `pghd`는 쪽 감추기 raw bit field, `idxm`은 찾아보기 표식 문자열을 typed model로 노출. `legacy-common-control-property`의 `hiddenComment` unknown child/grandchild raw payload를 실제 fixture와 Codable round-trip으로 검증 |
| 미구현/알 수 없는 control | `.notImplemented` 또는 `.unknown`으로 raw payload 보존. 실제 fixture section stream 기반 주입 테스트로 unknown control payload/child 보존을 확인 |
| 암호 문서 | `HwpError.unsupportedFeature(.encryptedDocument)`. 공인 인증서 암호화 bit도 같은 unsupported로 처리 |
| 배포용 문서 | `HwpError.unsupportedFeature(.deploymentDocument)` |
| DRM 문서 | `HwpError.unsupportedFeature(.drmDocument)`. 일반 DRM 및 공인 인증서 DRM bit 모두 차단 |
| 쓰기/저장 | 미지원 |

## Fixture 기준

실제 한컴오피스 또는 기존 repository fixture에서 온 `.hwp` 파일은 다음 구조로
관리합니다.

```text
Tests/CoreHwpTests/Fixtures/<fixture-id>/
  document.hwp
  manifest.json
  README.md
```

`manifest.json`에는 생성 도구, HWP 버전, 출처, 포함 기능, 기대 결과를 기록합니다.
테스트는 단순히 “열린다”가 아니라 section 수, paragraph 수, preview 길이, control
수, control 종류별 수, 본문 텍스트 snippet, unsupported error 등 의미 있는 기대값을
검증합니다. unsupported fixture는 `HwpFile(fromPath:)`, `HwpFile(fromData:)`,
`HwpFile(fromWrapper:)` 모두 manifest의 같은 `HwpError.unsupportedFeature`를
반환해야 합니다. 저수준 corrupt/malformed 입력만 synthetic data 테스트를 허용합니다.

### Fixture coverage

현재 fixture suite는 기존 repository `.hwp`와 새 한컴오피스 생성 `.hwp`를 새
구조로 편입한 상태이며, 새 fixture가 필요한 항목은 명시적으로 공백으로 둡니다.

| 목표 항목 | 현재 상태 | 대표 fixture |
| --- | --- | --- |
| blank | 검증 중 | `blank-mac2014vp`, `blank-win2018`, `blank-win2020` |
| plain text | 검증 중: 한컴오피스 생성 최소 문서의 paragraph text record raw payload total, control-char payload prefix/suffix, char-shape/line-seg raw payload total, preview, DocInfo count 기준 | `plain-text-minimal`, `plain-text-hancom-mac2026`, `CCL`, `공공누리`, `noori` |
| multi-paragraph | 검증 중 | `noori` |
| multiple sections | 검증 중: 한컴오피스 생성 문서의 `BodyText` storage child 이름(`Section0`, `Section1`)과 구역별 paragraph count 기준 | `multi-section` |
| table | 검증 중: cell paragraph까지 recursive count 검증 | `noori` |
| image / BinData | 검증 중: `BinData` stream과 picture component id/BinData id 연결, storage stream id/extension, stream payload prefix/suffix 검증 | `BinData`, `noori`, `CCL`, `공공누리`, `legacy-common-control-property` |
| equation | 검증 중: 한컴오피스 생성 문서의 `eqed` shape control, `eqEdit` raw record, 수식 문자열 보존 기준 | `equation` |
| chart | 검증 중: 한컴오피스 생성 문서의 chart OLE BinData storage child 이름, genShapeObject, `shapeComponentOle` raw record와 OLE BinData id 보존 기준 | `chart` |
| text box | 검증 중: 한컴오피스 생성 가로 글상자의 `genShapeObject`, `rectangle` shape component, 내부 list/paragraph text, 미해석 rectangle detail raw payload 보존 기준 | `text-box` |
| header/footer | 검증 중: 한컴오피스 생성 문서의 header/footer control count와 nested text 기준 | `header-footer` |
| footnote/endnote | 검증 중: 한컴오피스 생성 문서의 footnote/endnote control count와 nested text 기준 | `footnote-endnote` |
| page number | 검증 중: `pgnp` control의 property, 장식 문자 필드, raw payload 기준 | `noori` |
| large/legacy document | 검증 중: 41개 section, 14,000개 이상 nested paragraph, 7,000개 이상 control을 가진 HWP 5.0.2.2 문서 기준. 대표 fixture truncation/corruption 테스트에도 포함해 typed `HwpError` 반환을 확인 | `legacy-common-control-property` |
| other known controls | 검증 중: `atno`, `nwno`, `pghd`, `idxm`, `tdut` raw payload/trailing bytes/unknown child records 기준. `pghd`는 raw bit field, `idxm`은 UTF-16LE 문자열 typed value까지 검증 | `legacy-common-control-property` |
| columns | 검증 중: 다단 control과 DocInfo/document properties 기준 | `Column`, `noori` |
| styles | 검증 중: DocInfo style mapping count 기준 | `noori` |
| bullets/numbering | 검증 중: DocInfo numbering/bullet mapping count 기준 | `noori` |
| DocInfo raw records | 검증 중: `DOC_DATA`, `FORBIDDEN_CHAR`, `LAYOUT_COMPATIBILITY` 실제 fixture 기준. `MEMO_SHAPE`, `TRACK_CHANGE_CONTENT`, `TRACK_CHANGE_AUTHOR`는 `ID_MAPPINGS` child raw model까지 구현하고 `track-changes` fixture로 검증하며, content record는 kind/변경 시각, author record는 작성자 이름을 typed model로 노출. DocInfo `TRACK_CHANGE`는 `noori` fixture의 compatible document child record(`compatible-track-change-records`)로 검증. 전체 `HwpFile` 조립 경로는 `plain-text-minimal`의 실제 stream 기반 주입 테스트로 `DISTRIBUTE_DOC_DATA`와 top-level `TRACK_CHANGE` raw record 보존을 확인. 2026-06-20에 Downloads 잔여 HWP 5개를 `DISTRIBUTE_DOC_DATA = 28`, top-level `TRACK_CHANGE = 32` 기준으로 재스캔했지만 후보는 없었음. 2026-06-22 Python 표준 라이브러리 OLE/CFB scanner 재확인에서도 top-level DocInfo tag 조합은 `[16, 17, 27, 30]` 3개, `[16, 17, 30]` 1개, `[16, 17]` 1개뿐이었음. 2026-06-25 현재 Downloads HWP 5개에는 재배포 가능한 top-level `TRACK_CHANGE` 후보가 없었고, 한컴오피스 앱 번들 HWP/HWT 후보 317개 중 316개에는 tree 기준 `COMPATIBLE_DOCUMENT` child `TRACK_CHANGE = 32`가 있었지만 top-level record도 아니고 로컬 앱 resource라 fixture로 커밋하지 않음. 앱 번들의 top-level DocInfo tag 조합은 `[16, 17, 30]` 289개와 `[16, 17, 27, 30]` 28개뿐이었음. 2026-06-27 repository scanner로 `/Users/sboh/Downloads`와 한컴오피스 앱 번들 HWP/HWT 후보 322개를 재확인한 결과 `scanned=322`, `errors=0`, `markers={}`였고, external 322개 후보의 top-level DocInfo tag 조합은 `[16, 17, 30]` 290개, `[16, 17, 27, 30]` 31개, `[16, 17]` 1개였습니다. `nested_track_change=320`이었지만 모두 compatible document child record이며, `DISTRIBUTE_DOC_DATA = 28`, top-level `TRACK_CHANGE = 32`, 실제 DRM/certDRM bit, 무수정 `PrvImage` 누락 후보는 없었음. 일부 Downloads 후보의 `TRACK_CHANGE = 32`도 level 1 compatible document child record라서 top-level fixture gap을 대체하지 않음. `DISTRIBUTE_DOC_DATA`(`distribute-doc-data`)와 재배포 가능한 top-level `TRACK_CHANGE` fixture(`top-level-track-change-records`)는 추가 필요 | `noori`, `track-changes`, `plain-text-minimal` |
| bookmark | 검증 중: 한컴오피스 생성 문서의 other control raw payload, `HwpCtrlData` typed raw model, 책갈피 이름 기준 | `bookmark` |
| hyperlink | 검증 중: hyperlink field와 license image BinData 보존 기준 | `CCL`, `공공누리` |
| memo | 검증 중: 한컴오피스 생성 문서의 `MEMO/...` parameter field를 memo control로 분류하고 raw payload, structured parameter, Codable round-trip 보존 | `memo` |
| track changes | 검증 중: WordprocessingML tracked changes DOCX를 한컴오피스에서 열고 HWP로 저장한 문서의 `isTracingChange`, 본문/preview 보존, paragraph text inline control id, DocumentProperties, DocInfo id mappings, `TRACK_CHANGE_CONTENT`/`TRACK_CHANGE_AUTHOR` raw records 기준. DocInfo `TRACK_CHANGE` raw record는 `noori`의 compatible document child record로 검증합니다. 2026-06-27 현재 Downloads HWP 5개와 앱 번들 HWP/HWT 317개를 포함한 external 322개 재스캔에서는 `nested_track_change=320`으로 level 1 compatible document child `TRACK_CHANGE`만 확인됐고 top-level `TRACK_CHANGE`는 없었습니다. 재배포 가능한 top-level record fixture(`top-level-track-change-records`)는 추가 필요 | `track-changes`, `noori` |
| doc properties | 검증 중 | `noori`, `track-changes`, `Column` |
| encrypted/deployment unsupported | 검증 중: unsupported 원인 FileHeader bit와 `HwpError.unsupportedFeature` 반환 기준. 공인 인증서 암호화/DRM bit도 각각 encrypted/DRM unsupported로 처리. 현재 `배포용문서` fixture의 DocInfo raw record count는 0이므로 `DISTRIBUTE_DOC_DATA` 검증에는 별도 fixture가 필요 | `문서암호설정-*`, `배포용문서` |
| missing optional streams | 검증 중: `BinData` storage가 없는 실제 HWP를 빈 binary data 배열로 처리. Summary stream 누락 reader 경로는 `plain-text-minimal` 한컴 저장본에서 OLE directory name만 바꾼 `missing-summary-derived`로 검증하며, 없으면 빈 summary raw payload를 반환한다. `PrvText` 누락 reader 경로는 같은 방식의 `missing-preview-text-derived`와 `DirectoryEntryTypeStabilityTests`/`OptionalStreamCodableStabilityTests`로 검증하며, 없으면 기본 preview text raw payload(`[0x0D, 0x00, 0x0A, 0x00]`)를 반환한다. `PrvImage` 누락 reader 경로는 `plain-text-minimal` 한컴 저장본에서 OLE directory name만 바꾼 `missing-preview-image-derived`로 검증. `PrvText`와 `PrvImage`가 동시에 없는 reader 경로도 directory-entry mutation 기반 `OptionalStreamCodableStabilityTests`로 검증. 다만 현재 repository의 무수정 readable fixture는 모두 `PrvImage`를 포함하므로 실제 한컴 저장본 `PrvImage` 누락 fixture(`missing-preview-image`)는 추가 필요. 2026-06-16에 한컴오피스 12.30.0의 `AppState\Preview` 값을 `0`으로 바꾼 뒤 blank HWP를 저장해 봤지만 `PrvImage` stream은 계속 생성됨(`previewImageBytes=15295`). 2026-06-20에 repo fixture, Downloads, 한컴오피스 앱 번들의 `.hwp`/`.hwt` 352개를 Swift scanner로 다시 스캔해도 무수정 누락 후보는 없었음. 2026-06-21 같은 기본 scanner 재실행에서도 `missing-preview-image-derived` 1개만 발견됐고 무수정 누락 후보는 없었음. 같은 날 CloudStorage 후보 1,446개 중 보안/배포/변경 추적 keyword 2개와 크기순 최소 100개를 bounded OLE scan했지만 무수정 `PrvImage` 누락 후보는 없었음. 2026-06-22 Python 표준 라이브러리 OLE/CFB scanner로 확인한 Downloads 후보 5개도 모두 `PrvImage` stream을 포함했음. 2026-06-24에 같은 한컴오피스 12.30.0 build 6382에서 직접 저장한 `plain-text-hancom-mac2026`도 `PrvImage` stream을 포함했고 `previewImageBytes=22690`, `BinData` storage 없음으로 확인됨. 2026-06-27 현재 Downloads HWP 5개와 한컴오피스 앱 번들 HWP/HWT 후보 317개를 repository scanner로 다시 확인해도 external 322개 readable 후보 모두 `PrvImage` stream을 포함했음(`missing_preview_image_ok=0`). 2026-06-25 사용자 CloudStorage/Downloads/repo 후보 1,518개를 크기별 bounded OLE scan으로 재확인한 결과 readable external 후보 384개 중 개인 CloudStorage 문서 1개에서 `PrvImage`와 `PrvText`가 모두 없는 compressed HWP를 발견했지만, 개인 문서라 별도 승인 없이 repository fixture로 편입하지 않음. 2026-06-27 공개 GitHub 저장소 `mete0r/pyhwp`, `indosaram/hwpers`, `volexity/hwp-extract`, `neolord0/hwplib`의 HWP/HWT 샘플 84개를 임시 clone 후 scanner로 확인했을 때 `markers={deployment:2, encrypted:1, missing-preview-image:26, missing-preview-text:26}`였고, `hwplib`은 Apache-2.0이라 재배포 가능성은 있지만 해당 샘플이 실제 한컴오피스 저장본이라는 provenance가 확인되지 않아 goal의 실제 `missing-preview-image` fixture gap을 대체하지 않음 | `2007`, `문서이력관리`, `변경내용추적`, `missing-summary-derived`, `missing-preview-text-derived`, `missing-preview-image-derived`, `plain-text-hancom-mac2026` |
| extra root entries | 검증 중: 한컴오피스 저장본에 `DocOptions`, `Scripts`가 있어도 reader가 알려진 필수/선택 stream만 안정적으로 조립 | `plain-text-minimal` |
| DRM unsupported | 검증 중: `plain-text-minimal` 한컴 저장본의 FileHeader DRM bit만 켠 `drm-unsupported-derived` fixture로 `HwpError.unsupportedFeature(.drmDocument)` 반환을 검증. 실제 DRM 보호 문서는 현재 macOS 한컴오피스 12.30.0 설치본에서 저장 UI 미노출이며, 2026-06-20에 repo fixture, Downloads, 한컴오피스 앱 번들의 `.hwp`/`.hwt` 352개와 CloudStorage bounded scan(보안/배포/변경 추적 keyword 2개 + 크기순 최소 100개)을 확인했지만 실제 DRM 후보는 발견하지 못했습니다. 2026-06-21 기본 scanner 재실행에서도 DRM 후보는 `drm-unsupported-derived` 파생 fixture 1개뿐이고, 2026-06-22 Python 표준 라이브러리 OLE/CFB scanner로 확인한 Downloads 후보 5개에도 DRM/certDRM bit가 없었습니다. 2026-06-27 현재 Downloads HWP 5개와 한컴오피스 앱 번들 HWP/HWT 후보 317개를 포함한 external 322개를 재확인해도 DRM/certDRM bit가 없어 실제 DRM fixture는 별도 확보 필요 | `drm-unsupported-derived` |

같은 날 공개 GitHub 저장소 `edwardkim/rhwp`, `iyulab/unhwp`,
`DoHyun468/claw-hwp`, `123jimin/node-hwp`도 `/tmp`에 임시 clone해 HWP/HWT 후보를
재확인했습니다. `node-hwp`의 HWP 샘플 59개는 `errors=0`,
`markers={missing-preview-image:2, missing-preview-text:2}`였고,
`rhwp`의 HWP 샘플 280개는 HWP 3.x 등 OLE가 아닌 파일 10개를 제외하면
`markers={deployment:3}`였습니다. 이 재스캔 전에 unknown으로 잡혔던 raw id
`1718579821`(`form`) control은 `HwpOtherCtrlId.form`과 `HwpCtrlId.form`으로 추가해
typed raw model로 보존합니다. 추가 공개 샘플에서도
`DISTRIBUTE_DOC_DATA = 28`, top-level `TRACK_CHANGE = 32`, 실제 DRM/certDRM bit는
발견되지 않았고, `node-hwp`의 missing preview 후보는 실제 한컴오피스 저장본
provenance가 확인되지 않아 goal fixture gap을 대체하지 않습니다.
추가로 MIT 라이선스의 `postmelee/alhangeul-macos` HWP 샘플 151개를 같은 방식으로
확인했을 때는 `scanned=151`, `errors=0`, `markers={deployment:3}`였고,
`nested_track_change=26`, `unknown_control_rows=0`, `distribute_top_level=0`,
`track_top_level=0`, `missing_preview_image_ok=0`이었습니다. `re-*-hancom.hwp` 이름의 샘플들이 있지만
남은 fixture gap을 채우는 record/stream 조건은 없었습니다.
이후 추가 public 후보 `disjukr/hwpkit`, `treesoop/hwp-mcp`,
`reallygood83/master-of-hwp`, `dgahn/hwplib-dsl`, `hallazzang/ole-py`의 HWP/HWT
샘플 84개를 확인했을 때는 `scanned=84`, `errors=0`,
`markers={deployment:6, missing-preview-image:19, missing-preview-text:19}`였습니다.
`nested_track_change=73`, `unknown_control_rows=0`, `unknown_docinfo_rows=0`,
`unknown_section_rows=0`, `distribute_top_level=0`, `track_top_level=0`,
`drm=0`이었습니다. `dgahn/hwplib-dsl`의 missing preview 후보는 README 기준
`hwplib` DSL 생성 샘플이라 실제 한컴오피스 저장본 provenance가 확인되지 않아
`missing-preview-image` fixture gap을 대체하지 않습니다.

macOS fixture 재생성은 로컬 `/Applications/Hancom Office HWP.app`을 우선
사용합니다. 2026-06-27에 현재 설치본을 다시 확인했을 때 bundle id는
`com.hancom.office.hwp12.mac.general`, `CFBundleShortVersionString`은 `12.30.0`,
`CFBundleVersion`은 `6382`입니다. `CFBundleURLTypes`에는 `hwp` scheme이 등록되어
있지만 문서 연결용 URL scheme일 뿐 저장 자동화 API로 확인된 것은 없습니다.
AppleScript 앱 식별은
`osascript -e 'id of application id "com.hancom.office.hwp12.mac.general"'`와
`osascript -e 'tell application "Hancom Office HWP" to get name'`로 가능하지만, 앱은
AppleScript dictionary를 제공하지 않습니다(`sdef`는 이전 확인에서 error -10827,
2026-06-24 shell 재확인에서 error -192, 2026-06-25 app path 재확인에서
error -10827, 2026-06-27 app path 재확인에서 error -192). `command -v hwp`,
`command -v hwpctl`, `command -v hwp5txt`, `command -v hwp5proc`도 PATH에서
확인되지 않았고, 앱 번들의 `Hwp/DocFilters`는 dylib 기반 내부 필터 묶음입니다.
2026-06-19에는
Computer Use screenshot이 `failedToCreateImageDestination`로 실패했고,
`System Events`로 메뉴 이름은 읽을 수 있었지만 Codex 전체 화면 Space에서 한컴 창을
전면 캡처하거나 변경 내용 추적 리본을 조작하지는 못했습니다. 자동 생성이 필요할 때는
GUI 조작 또는 수동 저장 절차로 fixture를 만든 뒤 manifest 기대값을 갱신합니다.

## 기여

[CONTRIBUTING.md](https://github.com/sboh1214/hwp-swift/blob/main/CONTRIBUTING.md)를 방문하세요.

## 라이센스

본 라이브러리는 LGPL 라이센스를 따릅니다.

본 라이브러리의 이름, 주소, 그리고 저작자를 표기하여 주십시오.

스위프트 패키지 매니저와 같이 본 라이브러리를 일체의 변경 없이 의존성으로서 사용한다면 코드 공개의 의무가 없습니다.

![GitHub](https://img.shields.io/github/license/sboh1214/hwp-swift)
