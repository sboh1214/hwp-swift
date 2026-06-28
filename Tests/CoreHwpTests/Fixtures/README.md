# CoreHwp fixture guide

이 디렉터리는 실제 `.hwp` 문서로 reader 동작을 검증하기 위한 fixture 루트입니다.
저수준 corrupt/malformed 입력을 제외한 기능 검증은 synthetic byte 배열보다 이 구조의
실제 문서를 우선합니다.

## 구조

```text
Tests/CoreHwpTests/Fixtures/<fixture-id>/
  document.hwp
  manifest.json
  README.md
```

- `document.hwp`: 실제 한컴오피스 또는 기존 repository fixture에서 온 HWP 파일.
- `manifest.json`: 생성 도구, HWP 버전, 출처, 포함 기능, 기대 결과.
- `README.md`: fixture별 출처와 재생성 절차.

## 로컬 생성 도구 확인

현재 로컬 환경에는 `/Applications/Hancom Office HWP.app`이 설치되어 있습니다.

- bundle id: `com.hancom.office.hwp12.mac.general`
- version: `12.30.0` (`CFBundleVersion` 6382)
- `CFBundleDocumentTypes`는 `.hwp`를 `Editor` 역할로 등록합니다.
- 2026-06-16 재확인: 앱 실행 파일은
  `Contents/MacOS/Hancom Office HWP` 하나이며, `.hwp`, `.hwpx`, `.hwt`,
  `.docx`, `.doc`, `.odt` 등을 편집 가능한 문서 타입으로 등록합니다.
- AppleScript dictionary: 없음. `sdef /Applications/Hancom\ Office\ HWP.app`는
  `error -10827`을 반환합니다.
- AppleScript app lookup: 2026-06-16 이전 확인에서는
  `osascript -e 'id of app "Hancom Office HWP"'`가 `-1728`로 실패했고
  `application "Hancom Office HWP"을(를) 가져올 수 없습니다.` 메시지로 재현됩니다.
- 2026-06-19 재확인: bundle 안에 `.sdef`, `.scriptSuite`,
  `.scriptTerminology`, `.aeut` 파일이 없고, 같은 `sdef` 호출은 현재 shell에서
  `error -192`를 반환합니다. `Info.plist`에는 `hwp` URL scheme만 등록되어 있으며,
  도움말의 `automatic_action` 항목은 외부 자동화가 아니라 빠른 교정의
  `입력어 자동 실행` 옵션입니다.
- 2026-06-23 재확인: `osascript -e 'id of application id
  "com.hancom.office.hwp12.mac.general"'`는 bundle id를 반환하고,
  `osascript -e 'tell application "Hancom Office HWP" to get name'`도 앱 이름을
  반환합니다. 다만 `sdef '/Applications/Hancom Office HWP.app'`는 여전히
  `error -192`로 실패하고 bundle 안에 `.sdef`, `.scriptSuite`,
  `.scriptTerminology`, `.aeut` 파일이 없어 저장 자동화 dictionary는 없습니다.
- 2026-06-24 재확인: bundle id/version/build는
  `com.hancom.office.hwp12.mac.general` / `12.30.0` / `6382`로 동일합니다.
  `osascript -e 'id of application id "com.hancom.office.hwp12.mac.general"'`는
  bundle id를 반환하지만 `sdef '/Applications/Hancom Office HWP.app'`는 계속
  `error -192`입니다. `hwp`, `hwp5txt`, `hwp5proc`는 PATH에서 여전히 확인되지
  않았고, `Contents/MacOS`의 독립 실행 파일은 `Hancom Office HWP` 하나입니다.
- 2026-06-25 재확인: `PlistBuddy`로 읽은 bundle id/version/build는
  `com.hancom.office.hwp12.mac.general` / `12.30.0` / `6382`로 동일하고
  `CFBundleURLTypes`에는 `hwp` scheme이 있습니다. 다만
  `sdef '/Applications/Hancom Office HWP.app'`는 `error -10827`로 실패했고,
  `command -v hwp`, `command -v hwp5txt`, `command -v hwp5proc`도 모두 PATH에서
  확인되지 않았습니다.
- 2026-06-27 재확인: `/Applications/Hancom Office HWP.app`은 계속 설치되어 있고,
  bundle id/version/build는
  `com.hancom.office.hwp12.mac.general` / `12.30.0` / `6382`입니다.
  `osascript -e 'id of application id "com.hancom.office.hwp12.mac.general"'`와
  `osascript -e 'tell application "Hancom Office HWP" to get name'`는 각각 bundle id와
  앱 이름을 반환하지만, `sdef '/Applications/Hancom Office HWP.app'`는 `error -192`로
  실패합니다. bundle 안에 `.sdef`, `.scriptSuite`, `.scriptTerminology`, `.aeut`
  파일도 없고, `hwp`, `hwpctl`, `hwp5txt`, `hwp5proc` CLI 후보도 PATH에 없습니다.
- CLI 후보: `hwp`, `hwp5txt`, `hwp5proc`는 PATH에서 확인되지 않았습니다.
- 앱 번들의 `Contents/Frameworks/Hnc/Bin/Hwp`는 실행 파일이 아니라 `DocFilters`
  디렉터리이며, 그 안의 `lib*DocGroup.dylib` 파일들은 앱 내부 문서 필터입니다.
  같은 `Bin` 디렉터리에서 독립 실행 파일로 확인되는 `HncLogUploader`는 로그 업로더로,
  fixture 생성이나 변환 CLI로 보지 않습니다.

따라서 새 macOS fixture는 우선 Hancom Office HWP GUI로 직접 저장하고, 자동 생성이
필요하면 Computer Use 기반 GUI 조작을 별도 승인 후 사용합니다. 로그인, 라이선스,
보안 설정, 저장 권한 팝업은 사용자 확인을 받아 처리합니다.

## manifest 작성 기준

- `id`는 디렉터리명과 정확히 일치해야 합니다.
- `features`는 테스트 의도를 드러내는 작은 태그 목록으로 작성합니다.
- unsupported 문서는 정상 파싱 기대값 대신 `expectedError`와 FileHeader 원인 bit
  기대값(`isEncrypted`, `isDeploymentDocument`, `isDRMDocument`,
  `isAccreditedCertificateDRMDocument`)을 기록합니다. fixture assertion은
  `HwpFile(fromPath:)`, `HwpFile(fromData:)`, `HwpFile(fromWrapper:)` 모두 같은
  `HwpError.unsupportedFeature`를 반환하는지 검증합니다.
- 읽기 가능한 문서는 최소한 stream/doc-info/body 중 해당 기능의 의미 있는 기대값을
  기록합니다. 예: section stream raw payload totals, paragraph count, visible text
  snippet, control count, table cell count, paragraph text record raw payload totals,
  paragraph text control-char payload prefix/suffix, paragraph header/char-shape/line-seg
  raw payload totals, DocInfo stream raw payload length, summary stream
  length/prefix/suffix, PrvText raw byte length/prefix/suffix, PrvImage raw prefix/suffix,
  BinData stream
  name/id/extension/payload prefix/suffix, picture/OLE shape component BinData id,
  equation `eqEdit` text,
  DocInfo mapping raw payload total.
- raw preservation을 검증할 수 있는 경우 `rawPayloadLength` 또는
  `*RawPayloadTotalByteCount` 값을 기록합니다.

## 재생성 절차

1. 한컴오피스 한글에서 대상 기능만 포함한 최소 문서를 만듭니다.
2. HWP binary 형식으로 저장합니다.
3. `document.hwp`를 교체합니다.
4. `manifest.json`의 version, source, features, expectations를 갱신합니다.
5. fixture별 `README.md`에 사용한 앱/버전과 수동 조작 절차를 기록합니다.
6. `swift test --filter FixtureManifestTests/testFixtureManifests`를 먼저 실행합니다.
7. 전체 `swift test`와 coverage를 확인합니다.

## 로컬 생성 완료 fixture

- `plain-text-minimal`: Hancom Office HWP for macOS 12.30.0 build 6382로 생성.
- `plain-text-hancom-mac2026`: Hancom Office HWP for macOS 12.30.0 build 6382로
  2026-06-24에 직접 저장. 두 문단 plain text, PreviewText/PreviewImage stream,
  BinData 부재를 manifest로 검증.
- `header-footer`: Hancom Office HWP for macOS 12.30.0 build 6382로 생성.
- `footnote-endnote`: Hancom Office HWP for macOS 12.30.0 build 6382로 생성.
- `memo`: Hancom Office HWP for macOS 12.30.0 build 6382로 생성.
  Unknown field ctrl id에 붙은 `MEMO/...` parameter를 memo control로 분류하고
  raw payload, structured parameter, Codable round-trip 보존을 실제 fixture로 검증.
- `bookmark`: Hancom Office HWP for macOS 12.30.0 build 6382로 생성.
- `equation`: Hancom Office HWP for macOS 12.30.0 build 6382로 생성.
- `chart`: Hancom Office HWP for macOS 12.30.0 build 6382로 생성.
  OLE shape component와 `BIN0001.OLE` BinData stream의 id/raw payload 연결을
  manifest와 실제 fixture 회귀 테스트로 검증.
- `multi-section`: Hancom Office HWP for macOS 12.30.0 build 6382로 생성.
- `track-changes`: WordprocessingML tracked changes DOCX를 Hancom Office HWP for macOS
  12.30.0 build 6382에서 열고 HWP로 저장. FileHeader, 본문/preview,
  DocumentProperties, DocInfo id mappings를 manifest로 검증.
- `noori`: 기존 공개 보도자료 fixture에서 `DOC_DATA`, `FORBIDDEN_CHAR`,
  `LAYOUT_COMPATIBILITY`, BinData/image/table/style 계열 기대값을 manifest로 검증.
- `legacy-common-control-property`: 기존 HWP 5.0.2.2 샘플에서 object description 길이
  필드 없이 44바이트로 끝나는 `genShapeObject` 개체 공통 속성과 polygon shape
  component raw payload, `pageHide` raw bit field, `indexmark` UTF-16LE 문자열을
  manifest 및 실제 fixture Codable round-trip으로 검증. `FixtureCorruptionStabilityTests`의
  representative truncation/corruption set에도 포함해 large/legacy HWP가 malformed
  입력에서도 crash 대신 typed `HwpError`를 반환하는지 확인.
- `missing-preview-image-derived`: `plain-text-minimal` 한컴 저장본에서 OLE directory의
  `PrvImage` 이름만 `XrvImage`로 바꾼 파생 fixture. 선택 stream 누락 reader 경로를
  검증하지만, 무수정 한컴 저장본 fixture를 대체하지는 않음.
- `missing-preview-text-derived`: `plain-text-minimal` 한컴 저장본에서 OLE directory의
  `PrvText` 이름만 `XrvText`로 바꾼 파생 fixture. `PrvText`가 없을 때 기본 preview
  text raw payload(`[0x0D, 0x00, 0x0A, 0x00]`)를 반환하는 reader 경로를 manifest로
  검증함.
- `missing-summary-derived`: `plain-text-minimal` 한컴 저장본에서 OLE directory의
  `U+0005 HwpSummaryInformation` 이름만 `U+0005 XwpSummaryInformation`으로 바꾼
  파생 fixture. summary stream이 없을 때 빈 `HwpSummary` raw payload를 반환하는
  reader 경로를 manifest로 검증함.

## 아직 필요한 fixture

- 실제 DRM 보호 문서 unsupported fixture
- DocInfo `DISTRIBUTE_DOC_DATA` 실제 readable fixture
  (`distribute-doc-data` feature)
- DocInfo top-level `TRACK_CHANGE` 실제 readable fixture
- `PrvImage` stream이 없는 재배포 가능한 실제 readable fixture
  (`missing-preview-image` feature)

`HwpFileDocInfoRawRecordAssemblyTests`는 `plain-text-minimal`의 실제 `DocInfo`와
`BodyText` stream을 기반으로 `DISTRIBUTE_DOC_DATA`와 top-level `TRACK_CHANGE` raw
record를 주입해 전체 `HwpFile` 조립 경로의 보존 정책을 검증합니다. 이는 실제
readable fixture 확보 전까지의 reader 회귀 테스트이며, 위 실제 fixture 갭을 대체하지
않습니다.

현재 `배포용문서` fixture는 FileHeader의 deployment bit와
`unsupportedFeature.deploymentDocument` 반환을 검증합니다. 이 파일의 DocInfo stream은
낮은 수준에서 읽을 수 있지만 raw DocInfo record count가 0으로, `DISTRIBUTE_DOC_DATA`
coverage로 사용하지 않습니다.

## MEMO_SHAPE fixture 확보 상태

2026-06-15 기준 `track-changes` fixture는 Hancom Office HWP for macOS 12.30.0
build 6382가 저장한 실제 HWP이며, `ID_MAPPINGS` child로 `MEMO_SHAPE` record 1개를
포함합니다. CoreHwp는 이 변형을 typed raw model로 파싱하고
`HwpDocInfo.memoShapeArray`에 노출하며, fixture manifest의 `memo-shape` feature와
`docInfoRawRecords.memoShapes` 기대값으로 raw payload 보존을 검증합니다.

참고로 로컬 앱 번들에는 `Contents/Resources/Preset/memo_preset.hwp`와
`Contents/Resources/Hnc/Shared/memo_preset.hwp`도 있고, 두 파일 모두
`ID_MAPPINGS` child로 `MEMO_SHAPE` record 10개를 포함합니다. 앱 번들 자원은
repository fixture로 직접 편입하지 않았습니다.

## Track changes fixture 확보 상태

2026-06-15 기준 로컬 Hancom Office HWP for macOS 12.30.0 build 6382 번들에는
`HWPAID_MENUEX_TRACKCHANGE`, `HWPAID_VIEW_OPTION_TRACKCHANGE`, `HWPAID_TBOXTAB_REVIEW`
명령 문자열과 변경 내용 추적 대화상자 리소스가 존재합니다. 그러나 Computer Use로
확인한 현재 macOS 메뉴(`보안`, `보기`, `도구`)에는 `검토` 또는 `변경 내용 추적`
명령이 노출되지 않았고, 상태바에서도 변경 내용 추적 상태 토글이 표시되지 않았습니다.
2026-06-17 재확인에서는 Computer Use의 `click` action이 session을 이어받지 못해
System Events UI scripting으로 메뉴를 조회했습니다. `도구 > 교정 부호` 하위에는
`교정 부호 넣기...`, `자료 연결...`만 있고, `교정 부호 넣기...` 대화상자는
띄움표/넣음표/지움표 등 교정 부호 삽입 UI로 확인되어 `변경 내용 추적` 토글 경로로
보지 않습니다. 앱 내부 문자열에는 `TrackChange*` action id가 남아 있지만 공개
AppleScript dictionary나 CLI 호출 경로는 확인하지 못했습니다.

직접 생성 경로 대신 WordprocessingML `w:trackRevisions`, `w:del`, `w:ins`를 포함한
최소 DOCX를 한컴오피스에서 열고 HWP로 저장해 `track-changes` fixture를 확보했습니다.
한컴오피스 화면에서는 삭제된 `old text`와 삽입된 `new text`가 변경 내용으로 표시되고,
저장된 HWP의 FileHeader는 `isTracingChange == true`입니다. 현재 CoreHwp 모델에서는
최종 본문 텍스트 `new text`가 보이며, `HwpParaText` inline control payload는
`HwpInlineControl`로 raw payload와 `section`/`column` control id를 보존합니다.
이 fixture는 DocumentProperties, DocInfo id mappings,
`TRACK_CHANGE_CONTENT`/`TRACK_CHANGE_AUTHOR` raw payload도 검증합니다.
DocInfo `TRACK_CHANGE` raw record는 `noori` fixture의 `COMPATIBLE_DOCUMENT` child
record로 확보해 `track-change-records` 및 `compatible-track-change-records`
feature와 manifest raw payload 기대값으로 검증합니다. top-level `TRACK_CHANGE`
record는 `plain-text-minimal` 실제 stream 기반 주입 테스트로 전체 조립 경로의 raw
payload 보존을 확인하지만, 실제 fixture(`top-level-track-change-records`)는 아직 별도로
필요합니다.

기존 `변경내용추적` fixture는 이름과 달리 `isTracingChange` bit가 `false`인 legacy
file header 회귀 fixture입니다. 따라서 해당 fixture는 `track-changes-flag`로만
분류합니다.

## PrvImage fixture 확보 상태

현재 확보된 readable fixture는 모두 `PrvImage` stream을 포함합니다. 기존 manifest에서
기대값이 비어 있던 fixture도 실제 파싱값을 확인해 `previewImageLength`,
`previewImageFormat`, `previewImagePrefixBytes`, `previewImageSuffixBytes`를
기록했습니다.
따라서 `PrvImage` raw payload 보존은 실제 fixture로 검증합니다. `PrvImage` stream이
없는 경우 빈 preview image로 처리되는 reader 경로는 `missing-preview-image-derived`
fixture로 검증하지만, 이 파일은 OLE directory name을 바꾼 파생 fixture이므로 실제
한컴오피스가 무수정으로 저장한 `PrvImage` 누락 HWP는 여전히 별도로 필요합니다.

2026-06-15 기준 `/Users/sboh/Downloads`의 HWP 후보와 한컴오피스 앱 번들 preset
HWP(`memo_preset.hwp`, `textart_preset.hwp`)를 CoreHwp로 스캔했을 때 모두
`previewImageLength > 0`이며, `DISTRIBUTE_DOC_DATA`, top-level `TRACK_CHANGE`,
DRM bit도 발견되지 않았습니다. `noori` fixture에는 `COMPATIBLE_DOCUMENT` child인
`TRACK_CHANGE` record가 있어 `compatible-track-change-records` typed raw model로
검증합니다. 2026-06-16에는 repo fixture, `/Users/sboh/Downloads`,
한컴오피스 앱 번들 전체의 `.hwp`/`.hwt` 332개를 CoreHwp로 추가 스캔했지만 같은
gap을 채울 후보를 찾지 못했습니다. `previewImage=false`는 암호화 fixture 2개에서만
나왔고 둘 다 `unsupportedFeature.encryptedDocument` 대상입니다.
2026-06-17에는 한컴오피스 앱 번들의 `Contents/Resources` 아래 `.hwp`/`.hwt`
317개와 사용자 디렉터리에서 확인된 HWP 후보 14개를 다시 스캔했지만
`DISTRIBUTE_DOC_DATA`, top-level `TRACK_CHANGE`, DRM/deployment/encrypted flag
후보를 찾지 못했습니다.
2026-06-18에는 `CoreHwp` public reader 기반 임시 scanner로 repo fixture,
`/Applications/Hancom Office HWP.app/Contents/Resources`, `/Users/sboh/Downloads`
아래 `.hwp`/`.hwt` 360개를 재스캔했습니다. 발견된 후보는 이미 suite에 있는
`drm-unsupported-derived`와 `missing-preview-image-derived`뿐이었고,
`DISTRIBUTE_DOC_DATA`, top-level `TRACK_CHANGE`, 무수정 `PrvImage` 누락 문서는
추가로 발견되지 않았습니다. 같은 날 `/Applications/Hancom Office HWP.app`의
AppleScript dictionary도 `sdef` error -10827로 부재를 재확인했으며, bundle string
검색으로 `HWPAID_FILE_DISTRIBUTE*`, `HWPAID_FILE_SET_DISTRIBUTE`,
`HWPAID_TRACKCHANGE_*` 내부 action id가 존재하는 것만 확인했습니다.
`FixtureManifestTests`는 현재 suite 안에 이 gap들이 manifest 없이 숨어 있지 않은지도
실제 파싱 결과로 확인합니다.
2026-06-19에는 `/Users/sboh/Documents`, `/Users/sboh/Downloads`,
`/Users/sboh/Desktop`, `/private/tmp`의 현재 HWP 후보 17개를 package-internal
임시 scanner로 다시 확인했습니다. 모두 readable이었고 `PrvImage` stream을 포함했으며
`DISTRIBUTE_DOC_DATA`, top-level `TRACK_CHANGE`, DRM bit 후보는 없었습니다.
같은 날 `/Applications/Hancom Office HWP.app` 설치본은 확인됐지만 AppleScript
dictionary는 계속 없었습니다(`sdef` error -10827). `System Events`로 메뉴바
항목(`파일`, `보안`, `도구` 등)과 보안/도구 하위 메뉴 이름은 읽을 수 있었고,
보안 메뉴에는 `문서 암호 설정...`, `문서 암호 변경 및 해제...`,
`배포용 문서 암호 변경/해제...`, `문서 보안 설정...`만 노출됐습니다. Computer Use
screenshot은 `failedToCreateImageDestination`로 실패했고, Codex 전체 화면 Space에서
한컴 창을 전면으로 전환해 캡처하는 것도 실패해 변경 내용 추적 리본을 GUI로 조작하지
못했습니다. 따라서 top-level `TRACK_CHANGE` fixture는 한컴 창을 직접 조작할 수 있는
환경에서 다시 생성해야 합니다.

2026-06-19 추가 확인으로 Python `olefile` 기반 raw OLE scanner를 사용해 repo fixture,
`/Users/sboh/Downloads`, `/Users/sboh/Documents`, `/Users/sboh/Desktop`,
`/Applications/Hancom Office HWP.app/Contents/Resources` 아래 `.hwp`/`.hwt` 361개를
스캔했습니다. 새로 발견된 관심 후보는 없었고, `DISTRIBUTE_DOC_DATA`, top-level
`TRACK_CHANGE`, 실제 DRM bit, 무수정 `PrvImage` 누락은 기존 suite 밖에서 발견되지
않았습니다. 같은 방식으로 repo fixture와 한컴 앱 shared preset/template 345개에서
`CTRL_HEADER` raw id 9,599개를 집계했으며 unique control id 23개가 모두 현재
`HwpCommonCtrlId`, `HwpOtherCtrlId`, `HwpFieldCtrlId`에 포함되어 있었습니다.
같은 날 앱 번들의 AppleScript 관련 리소스(`.sdef`, `.scriptSuite`,
`.scriptTerminology`, `.aeut`)가 없고 `sdef`가 `error -192`로 실패하는 것도
재확인했습니다. `Info.plist`의 `hwp` URL scheme은 문서 열기용 scheme으로 보이며,
도움말의 `automatic_action` 문서는 빠른 교정의 `입력어 자동 실행` 설명이어서
fixture 생성 자동화 API로 보지 않습니다.

2026-06-20에는 `/private/tmp/hwp-swift-local-scan`의 임시 Swift scanner를 사용해
repo fixture, `/Users/sboh/Downloads`, `/Applications/Hancom Office HWP.app`
아래 `.hwp`/`.hwt` 352개를 다시 스캔했습니다. `CoreHwp`로 readable인 파일은
348개였고, unreadable 4개는 기존 suite의 encrypted 2개, deployment 1개,
`drm-unsupported-derived` 1개뿐이었습니다. `DISTRIBUTE_DOC_DATA`, top-level
`TRACK_CHANGE`, 실제 DRM bit, 무수정 `PrvImage` 누락은 새로 발견되지 않았습니다.
2026-06-21에 같은 기본 scanner를 다시 실행했을 때도 scanned 352개,
header-readable 352개, readable-docinfo 348개, unsupported 4개, invalid 0개였습니다.
관심 후보는 suite 안의 `missing-preview-image-derived` 1개, `track-changes` tracing
change flag 1개, `drm-unsupported-derived` DRM unsupported 1개뿐이었고,
`DISTRIBUTE_DOC_DATA`, top-level `TRACK_CHANGE`, 무수정 `PrvImage` 누락, 실제 DRM
후보는 새로 발견되지 않았습니다.
같은 날 `/Users/sboh/Library/CloudStorage`에서 `.hwp`/`.hwt` 후보 1,446개를
추가로 열거했습니다(한 Google Drive `.tmp` 경로는 permission denied). 개인/업무
동기화 문서 전체를 fixture 후보로 열어 보는 것은 부적절하고 I/O도 컸기 때문에,
이름에 보안/배포/변경 추적 관련 keyword가 있는 2개와 크기순 최소 100개만
OLE-level scanner로 확인했습니다. keyword 2개는 모두 readable이었고,
최소 100개는 header-readable 100개, DocInfo readable 99개, encrypted unsupported
1개였습니다. 이 encrypted 후보는 개인 문서 경로에 있어 repo fixture로 가져오지
않았습니다. 두 bounded scan 모두 `DISTRIBUTE_DOC_DATA`, top-level `TRACK_CHANGE`,
tracing-change flag, 실제 DRM/deployment bit, 무수정 `PrvImage` 누락 후보를
새로 찾지 못했습니다.

2026-06-20 추가 확인으로 현재 Downloads에 남아 있는 HWP 후보 5개를 read-only
minimal OLE scanner로 다시 검사했습니다. 이때 DocInfo tag 매핑을
`DISTRIBUTE_DOC_DATA = 28`, top-level `TRACK_CHANGE = 32`로 재확인해 false positive를
배제했습니다. 후보들의 top-level DocInfo tag는 `[16, 17, 27, 30]`, `[16, 17, 30]`,
또는 `[16, 17]` 조합뿐이었고, 모두 readable이며 `PrvImage` stream을 포함했습니다.
따라서 이 잔여 후보들에서도 `DISTRIBUTE_DOC_DATA`, top-level `TRACK_CHANGE`,
실제 DRM/deployment/encrypted bit, 무수정 `PrvImage` 누락 fixture를 확보하지
못했습니다.

2026-06-22에는 Python 표준 라이브러리만 사용한 OLE/CFB scanner로 같은 Downloads
후보 5개를 다시 확인했습니다. top-level DocInfo tag 조합은 `[16, 17, 27, 30]` 3개,
`[16, 17, 30]` 1개, `[16, 17]` 1개였고 모두 `PrvImage` stream을 포함했으며
DRM/certDRM bit가 없었습니다. 마지막 후보는 `Section0`~`Section40`과
`BIN0001.bmp`를 포함했지만 외부 Downloads 문서라 fixture로 가져오지 않았습니다.
따라서 `DISTRIBUTE_DOC_DATA`, top-level `TRACK_CHANGE`, 실제 DRM, 무수정 `PrvImage`
누락 fixture는 새로 확보되지 않았습니다.

2026-06-25에는 현재 Downloads에 남아 있는 HWP 후보 5개를 같은 표준 라이브러리
OLE/CFB scanner로 다시 확인했습니다. 모두 compressed HWP이고 `PrvImage` stream을
포함했으며 top-level DocInfo tag 조합은 `[16, 17, 27, 30]` 3개, `[16, 17, 30]`
1개, `[16, 17]` 1개였습니다. `DISTRIBUTE_DOC_DATA = 28`, top-level
`TRACK_CHANGE = 32`, 실제 DRM/certDRM bit, 무수정 `PrvImage` 누락은 없었습니다.
이 중 4개에는 level 1 `TRACK_CHANGE = 32` compatible document child record가
있었지만, top-level DocInfo record가 아니므로 `top-level-track-change-records`
fixture gap을 대체하지 않습니다.
따라서 현재 Downloads 후보에서도 top-level `TRACK_CHANGE` 실제 fixture를 확보하지
못했습니다.

같은 날 `/Users/sboh/Repos/hwp-swift`, `/Users/sboh/Downloads`,
`/Users/sboh/Library/CloudStorage` 아래 `.hwp`/`.hwt` 후보 1,518개를 다시
열거했습니다. repo 66개, CloudStorage 1,446개, Downloads 5개, other 1개였고
Google Drive `.tmp` 경로 1개는 permission denied로 건너뛰었습니다. 5MB 미만
1,470개는 0.2초 제한으로, 5MB 이상 48개는 5초 제한으로 같은 표준 라이브러리
OLE/CFB scanner를 실행했습니다. 총 scanned 453개, timeout/permission 등 error
1,065개였고, readable external 후보는 384개였습니다. 이 범위에서도
`DISTRIBUTE_DOC_DATA = 28`, top-level `TRACK_CHANGE = 32`, 실제 DRM/certDRM bit는
발견되지 않았습니다. 다만 개인 CloudStorage 문서 1개는 compressed/readable HWP이고
top-level DocInfo tag 조합이 `[16, 17, 27, 30]`이며 `PrvImage`와 `PrvText` stream이
모두 없었습니다. 이 파일은 private 문서라 별도 승인 없이 repository fixture로
가져오지 않았고, 승인 후 내용/라이선스/재배포 가능성을 확인해야만
`missing-preview-image` 실제 fixture 후보로 승격할 수 있습니다.
실제 fixture 편입 전까지는 `plain-text-minimal`의 `PrvText`/`PrvImage` directory
entry를 동시에 rename하는 `OptionalStreamCodableStabilityTests`로 두 preview stream
동시 누락 reader 경로를 회귀 검증합니다.

같은 날 `/Applications/Hancom Office HWP.app` 아래 HWP/HWT 후보 317개를 같은
표준 라이브러리 OLE/CFB scanner로 재스캔했습니다. `scanned=317`, `errors=0`,
`missing_preview=0`이었고, flat tag scan 기준 316개 앱 번들 템플릿/프리셋에서
`TRACK_CHANGE = 32`가 보였습니다. tree-aware 재확인 결과 이 record들은
`COMPATIBLE_DOCUMENT = 30`의 level 1 child였고 top-level DocInfo record는
아니었습니다. 앱 번들의 top-level DocInfo tag 조합은 `[16, 17, 30]` 289개와
`[16, 17, 27, 30]` 28개뿐이었습니다. 모두 `PrvImage` stream을 포함했고
`DISTRIBUTE_DOC_DATA = 28`, 실제 DRM/certDRM bit는 발견되지 않았습니다. 이 파일들은
로컬 한컴오피스 앱 번들 resource라 repository에 재배포 가능한 fixture로 커밋하지
않았습니다. 따라서
`top-level-track-change-records` gap은 재배포 가능한 실제 HWP/HWT 샘플을 확보할
때까지 남겨둡니다. 이 tree-aware raw OLE 결과는 2026-06-15~17의 CoreHwp/임시
scanner 기반 앱 번들 `TRACK_CHANGE` 미발견 기록과 2026-06-25 flat tag scan의
top-level 오판을 함께 정정하는 근거입니다.

2026-06-26과 2026-06-27에는 같은 gap 조건을 재확인했습니다.
현재 fixture suite 33개는 `scanned=33`, `errors=0`,
`markers={deployment:1, drm:1, encrypted:2, missing-preview-image:1,
missing-preview-text:1}`로 기존 unsupported/derived fixture만 표시했습니다.
`/Users/sboh/Downloads`와 한컴오피스 앱 번들 `Contents/Resources`의 HWP/HWT 후보
322개는 `scanned=322`, `errors=0`, `markers={}`였습니다. 따라서 이 범위에서도
재배포 가능한 실제 `DISTRIBUTE_DOC_DATA`, top-level `TRACK_CHANGE`, 실제 DRM,
무수정 `PrvImage` 누락 fixture는 새로 확보되지 않았습니다. 같은 확장 scanner의
DocInfo/Section tag 및 `CTRL_HEADER` control id 대조에서도 suite와 외부 322개 후보
모두 `unknown-docinfo-tag`, `unknown-section-tag`, `unknown-control-id` marker가
없었습니다.
2026-06-27 같은 scanner로 fixture suite와 외부 후보를 함께 재확인했을 때 전체
`scanned=355`, `errors=0`, `markers={deployment:1, drm:1, encrypted:2,
missing-preview-image:1, missing-preview-text:1}`였습니다. 외부 322개 후보만 따로
JSON 집계하면 top-level DocInfo tag 조합은 `[16, 17, 30]` 290개,
`[16, 17, 27, 30]` 31개, `[16, 17]` 1개였고, `nested_track_change=320`,
`missing_preview_image_ok=0`, `distribute_top_level=0`, `track_top_level=0`이었습니다.
즉 현재 외부 후보에서 확인되는 `TRACK_CHANGE = 32`는 여전히 compatible document child
record뿐이며, `DISTRIBUTE_DOC_DATA = 28`, top-level `TRACK_CHANGE = 32`,
실제 DRM/certDRM bit, 무수정 `PrvImage` 누락 fixture gap은 그대로 남아 있습니다.

2026-06-27에는 공개 GitHub 저장소
`https://github.com/mete0r/pyhwp`, `https://github.com/indosaram/hwpers`,
`https://github.com/volexity/hwp-extract`, `https://github.com/neolord0/hwplib`를
임시 clone해 포함된 HWP/HWT 샘플 84개를 같은 scanner로 확인했습니다. 결과는
`scanned=84`, `errors=0`, `markers={deployment:2, encrypted:1,
missing-preview-image:26, missing-preview-text:26}`였습니다. `hwplib`의
`sample_hwp/basic/blank.hwp` 등 Apache-2.0 저장소 샘플에서 `PrvImage`와 `PrvText`가
동시에 없는 readable 후보가 발견됐지만, 해당 파일들이 실제 한컴오피스 저장본이라는
provenance가 확인되지 않았습니다. 따라서 이 공개 후보들은 reader 회귀 후보로는
유용하지만, 목표의 실제 한컴오피스 저장본 `missing-preview-image` fixture gap을
대체하지 않습니다. 같은 공개 샘플 스캔에서도 `DISTRIBUTE_DOC_DATA = 28`, top-level
`TRACK_CHANGE = 32`, 실제 DRM/certDRM bit 후보는 발견되지 않았습니다.

같은 날 추가로 `https://github.com/edwardkim/rhwp`,
`https://github.com/iyulab/unhwp`, `https://github.com/DoHyun468/claw-hwp`,
`https://github.com/123jimin/node-hwp`를 임시 clone해 HWP/HWT 후보를
확인했습니다. `unhwp`와 `claw-hwp`에는 scanner 대상 HWP/HWT 경로가 없었습니다.
`node-hwp`의 HWP 샘플 59개는 `scanned=59`, `errors=0`,
`markers={missing-preview-image:2, missing-preview-text:2}`였고, top-level
DocInfo tag 조합은 `[16, 17]` 26개, `[16, 17, 30]` 26개, `[16, 17, 27]` 5개,
`[16, 17, 27, 30]` 2개였습니다. `nested_track_change=16`이었지만
`distribute_top_level=0`, `track_top_level=0`이었습니다. `rhwp`의 HWP 샘플
280개는 `scanned=280`, `errors=10`, `markers={deployment:3}`였습니다.
error 10개는 HWP 3.x 계열 등 OLE compound file이
아닌 샘플이었고, tree-aware 집계에서 top-level DocInfo tag 조합은
`[16, 17, 30]` 203개, `[16, 17, 27, 30]` 65개, `[16, 17]` 2개였으며
`nested_track_change=111`, `distribute_top_level=0`, `track_top_level=0`이었습니다.
이 재스캔 전에 `unknown-control-id`로 표시됐던 raw id `1718579821`(`form`) control은
`HwpOtherCtrlId.form`과 `HwpCtrlId.form`으로 추가해 typed raw model로 보존합니다. 현재
scanner 기준 `unknown_control_rows=0`입니다. 이 공개 샘플 스캔에서도
`DISTRIBUTE_DOC_DATA = 28`, top-level `TRACK_CHANGE = 32`, 실제 DRM/certDRM bit는
없었습니다. `node-hwp`의 missing preview 후보도 실제 한컴오피스 저장본이라는
provenance가 확인되지 않아 goal의 실제
`missing-preview-image` fixture gap을 대체하지 않습니다.

같은 검색 라운드에서 `https://github.com/postmelee/alhangeul-macos`도
임시 clone했습니다. README와 LICENSE 기준 MIT 라이선스 저장소이며, HWP/HWT 후보
151개를 scanner로 확인했을 때 `scanned=151`, `errors=0`,
`markers={deployment:3}`였습니다. `nested_track_change=26`이었지만
`unknown_control_rows=0`, `unknown_docinfo_rows=0`, `unknown_section_rows=0`,
`distribute_top_level=0`, `track_top_level=0`, `missing_preview_image_ok=0`이었습니다.
`re-*-hancom.hwp` 이름의 샘플들이 있어 실제 한컴 저장본 provenance 후보로 볼 수
있지만, 이 집합에서도 `DISTRIBUTE_DOC_DATA = 28`, top-level `TRACK_CHANGE = 32`,
실제 DRM/certDRM bit, 무수정 `PrvImage` 누락 fixture gap은 발견되지 않았습니다.

추가로 `disjukr/hwpkit`(46개), `treesoop/hwp-mcp`(5개),
`reallygood83/master-of-hwp`(12개), `dgahn/hwplib-dsl`(20개),
`hallazzang/ole-py`(1개)의 HWP/HWT 후보 84개를 임시 clone 후 scanner로
확인했습니다. 결과는 `scanned=84`, `errors=0`,
`markers={deployment:6, missing-preview-image:19, missing-preview-text:19}`였고
top-level DocInfo tag 조합은 `[16, 17, 30]` 80개, `[16, 17, 27, 30]` 3개,
`[16, 17, 27]` 1개였습니다. `nested_track_change=73`이었지만 모두 top-level
`TRACK_CHANGE`가 아니며, `distribute_top_level=0`, `track_top_level=0`,
`unknown_control_rows=0`, `unknown_docinfo_rows=0`, `unknown_section_rows=0`,
`drm=0`이었습니다. `dgahn/hwplib-dsl`의 19개 missing preview 후보는 README가
`hwplib` DSL로 HWP를 생성하는 프로젝트임을 설명하므로 실제 한컴오피스 저장본
provenance가 확인되지 않아 goal의 무수정 한컴 저장본 `missing-preview-image`
fixture gap을 대체하지 않습니다.

한컴오피스 번들 문자열에는 저장 관련 옵션 설명으로 `미리 보기 이미지 저장`이 있고,
`Hnc/Bin/Strings/ko-KR.lproj/hwp_strings_dlg.strings`의 `IDS_SavePreviewImage`,
`hwp_strings_tooltip.strings`의 `IDH_OPTIONS_EDIT_PREVIEW`가 이 항목을 설명합니다.
`Base.lproj/HwpPreferenceDlg.nib` 문자열에도 `previewImageSave` control이 있으며,
`en.lproj/HwpPreferenceDlg.strings`에서는 같은 항목이 `Include Preview Image`로
노출됩니다. 앱 내 Help(`Resources/Help/file/options/options(edit).htm`)도 이 옵션이
불러오기 대화 상자의 미리 보기 창에 표시할 이미지를 문서에 저장하며, 미리 보기
이미지 크기가 24KB라고 설명합니다. `defaults read com.hancom.office.hwp12.mac.general`에서도
`Software\HNC\Hwp\12.0\HwpFrame\AppState\Preview = 1`로 확인됩니다.
2026-06-24에 `/Applications/Hancom Office HWP.app/Contents/Info.plist`를 다시
확인했을 때 `CFBundleIdentifier`는 `com.hancom.office.hwp12.mac.general`,
`CFBundleShortVersionString`은 `12.30.0`, `CFBundleVersion`은 `6382`였습니다.
`CFBundleDocumentTypes`는 `hwp`, `hwt`, `hwpx`, `hwtx`, `docx`, `doc`, `odt` 등을
editor로 등록하고, `CFBundleURLSchemes`에는 `hwp`가 있지만 저장 자동화용 API로
확인된 것은 아닙니다. 같은 날 `sdef '/Applications/Hancom Office HWP.app'`는
`error -192`로 실패해 AppleScript dictionary가 없음을 재확인했습니다.
2026-06-25에 `PlistBuddy`로 같은 `Info.plist`를 다시 확인했을 때 bundle
id/version/build는 동일했고 `CFBundleURLTypes`에도 `hwp` scheme이 있었습니다.
같은 날 `sdef '/Applications/Hancom Office HWP.app'`는 `error -10827`로 실패했고,
`command -v hwp`, `command -v hwp5txt`, `command -v hwp5proc`도 모두 PATH에서
확인되지 않았습니다.
2026-06-16에는 별도 승인 후 이 값을 `0`으로 바꾸고 한컴오피스 한글 12.30.0에서
빈 HWP(`/private/tmp/corehwp-missing-preview-20260616.hwp`)를 저장한 뒤 값을
`1`로 복원했습니다. 저장된 파일은 readable HWP였지만 OLE stream 목록에 여전히
`PrvImage`가 있었고 CoreHwp 스캔 결과 `previewImageBytes=15295`였습니다. 따라서
`AppState\Preview = 0`만으로는 macOS 12.30.0의 HWP 저장 경로에서 `PrvImage`
누락 fixture를 만들 수 없습니다.

2026-06-24에는 같은 한컴오피스 12.30.0 build 6382 설치본에서
`plain-text-hancom-mac2026`을 새 문서로 직접 저장했습니다. 저장 과정에서
로그인, 라이선스, 보안 설정, 저장 권한 팝업은 나타나지 않았고, 생성된 readable HWP
5.1.1.0은 `PrvImage` stream을 포함했습니다. CoreHwp 스캔 결과
`previewImageBytes=22690`이고 `BinData` storage는 없었습니다. 따라서 현재 기본
macOS 저장 경로에서도 plain text 문서는 `PrvImage`를 포함합니다.

2026-06-19에는 Computer Use로 한컴오피스 한글 UI의 `한글 > 환경 설정... > 편집`
탭을 직접 확인했습니다. 저장 섹션에 `미리 보기 이미지 저장` checkbox가 실제로
노출되며 accessibility tree에서 `Value: 1`, `ID: P`로 확인됩니다. 설정은 변경하지
않고 `취소`로 닫았습니다.

다음 확보 시도는 이 `미리 보기 이미지 저장` checkbox를 직접 토글했을 때
`AppState\Preview` 외에 다른 설정이 바뀌는지 비교하거나, 외부에서
합법적으로 제공받은 readable HWP 중 `PrvImage` stream이 없는 샘플을 추가하는
경로가 필요합니다. 이 절차는 사용자 한컴오피스 설정을 변경하므로 별도 승인 후
진행합니다.

## DRM fixture 확보 상태

2026-06-16 기준 로컬 Hancom Office HWP for macOS 12.30.0 build 6382의
`보안` 메뉴에는 `문서 암호 설정`, `문서 암호 변경 및 해제`, `배포용 문서 암호
변경/해제`, `문서 보안 설정`만 노출됩니다. `문서 보안 설정`은 악성코드로 사용될
수 있는 기능을 불러올지 정하는 보안 수준 대화상자이며, DRM 문서를 저장하는 기능이
아닙니다.

`drm-unsupported-derived` fixture는 `plain-text-minimal` 한컴 저장본의 OLE
`FileHeader` stream에서 fileProperty DRM bit만 켠 파생 fixture입니다. 이 파일로
reader가 DRM bit를 `HwpError.unsupportedFeature(.drmDocument)`로 거부하는 경로를
검증합니다. 다만 실제 DRM 보호 문서를 대체하지는 않습니다.
실제 DRM 보호 문서를 확보하면 `drm unsupported` fixture로 분류하고, manifest에는
`drm`, `unsupported` feature tag와 `unsupportedFeature.drmDocument` 기대값을 함께
기록합니다.

현재 repo fixture, `/Users/sboh/Downloads`, `/Users/sboh/Documents`,
`/Users/sboh/Desktop`, 한컴오피스 앱 번들의 `.hwp`/`.hwt` 361개를
FileHeader/raw OLE scanner 기준으로 검사했을 때 `encrypted`와
`deployment-document` fixture는 확인됐지만 `isDRMDocument` 또는
`isAccreditedCertificateDRMDocument` bit가 켜진 실제 HWP는 발견되지 않았습니다.
2026-06-20에 repo fixture, `/Users/sboh/Downloads`,
`/Applications/Hancom Office HWP.app` 아래 `.hwp`/`.hwt` 352개를 다시 스캔했을 때도
DRM unsupported는 `drm-unsupported-derived` 파생 fixture 1개뿐이었습니다.
같은 날 CloudStorage bounded scan(보안/배포/변경 추적 keyword 2개 + 크기순 최소
100개)에서도 실제 DRM/deployment bit는 발견되지 않았습니다.
2026-06-22 Python 표준 라이브러리 OLE/CFB scanner로 확인한 Downloads 후보 5개도
DRM/certDRM bit가 없었습니다.
2026-06-25 현재 Downloads 5개와 한컴오피스 앱 번들 HWP/HWT 후보 317개를 같은
scanner로 재확인해도 DRM/certDRM bit가 없었습니다. 앱 번들 후보는
`scanned=317`, `errors=0`, `missing_preview=0`이었고 316개에는
`COMPATIBLE_DOCUMENT` child `TRACK_CHANGE = 32`가 있었지만, tree 기준 top-level
record가 아니며 로컬 앱 resource라 실제 DRM fixture나 재배포 가능한 top-level
track-change fixture를 대체하지 않습니다.
2026-06-27에는 Downloads 5개와 앱 번들 317개를
합친 external 322개를 재확인했고 `scanned=322`, `errors=0`, `markers={}`,
`distribute_top_level=0`, `track_top_level=0`, `missing_preview_image_ok=0`이었습니다.
이 external 322개에도 DRM/certDRM bit는 없었습니다.
같은 날 공인 인증서 암호화/DRM bit를 별도 marker로 노출하도록 scanner를 보강한 뒤
한컴오피스 앱 번들 HWP/HWT 후보 317개를 재확인했을 때도 `scanned=317`,
`errors=0`, `markers={}`로 `accredited-certificate-encrypted`,
`accredited-certificate-drm` 후보는 발견되지 않았습니다.
실제 DRM fixture를 추가하려면
DRM 저장 기능이 노출되는 한컴오피스 설치본 또는 외부에서 합법적으로 제공받은
DRM HWP 샘플이 필요합니다. 확보 후에는 `features`에 `drm`, `unsupported`를 기록하고
`expectedError.code`를 `unsupportedFeature.drmDocument`로 둡니다.

## Coverage 확보 상태

2026-06-28에 `swift test --enable-code-coverage`를 실행한 뒤
`.build/out/Products/Debug/codecov/Hwp-Swift.json`에서 `Sources/CoreHwp`만
집계했습니다. 총 line coverage는 98.60% (5481/5559), region coverage는
97.56% (2483/2545)로 현재 목표치 95% 이상을 만족합니다.
