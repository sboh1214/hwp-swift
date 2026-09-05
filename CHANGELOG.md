# Changelog

## Unreleased

### Added

- **HWPX(OWPML) 문서를 읽습니다**. `HwpFile(fromPath:)`·`(fromData:)`·
  `(fromWrapper:)`가 파일 선두 바이트로 HWP(OLE)/HWPX(ZIP)를 자동 감지해
  같은 문서 모델로 변환하므로, 뷰어(`HwpKit`)는 코드 변경 없이 `.hwpx`를
  렌더합니다. 1차 지원 범위는 본문 텍스트·글자/문단 모양·스타일·구역/쪽
  설정·단·표·그림·쪽 번호 위치(#135)·OLE 개체(내장 차트, #134)·문단 번호와
  글머리표 정의(#133 — 글머리표 문자는 그려지고, 번호 매기기 라벨은 HWP 경로에도
  없어 두 포맷 공통으로 미렌더입니다)이며, 조판
  캐시(`<hp:linesegarray>`)를 매핑해 한글.app과 같은 쪽나눔을 유지합니다. 범위 밖
  요소는 `HwpFile.parseDiagnostics()`에 보고하고 건너뜁니다. ZIP 컨테이너는 외부
  의존성 없이 읽으며, 잘못된 아카이브·XML은 새 `HwpError` 케이스(`invalidArchive`·
  `archiveEntryDoesNotExist`·`archiveEntrySizeLimitExceeded`·`invalidXML`)로
  보고됩니다. 암호화 HWPX(`META-INF/encryption.xml`)는 기존
  `unsupportedFeature(.encryptedDocument)`로 거부됩니다. `.hwpx`를 파일
  선택기·드롭에서 **고르게** 하는 것은 호스트 몫입니다 — `.hwpx` 콘텐츠
  타입(imported UTI)을 `Info.plist`의 문서 타입에 선언하고
  `fileImporter(allowedContentTypes:)`·드롭 허용 타입에 넣지 않으면 선택기가
  `.hwpx`를 비활성화합니다. `Sample/`이 그 배선 예를 보입니다
  (`project.yml`의 `dev.sboh.hwpx` 선언, `DropOpenSupport.swift`,
  `ContentView.swift`).

### Breaking Changes

- **`HwpUnderlineType`의 raw 값을 HWP 5.0 스펙(표 33)에 맞췄습니다** (#149).
  한글.app은 글자 모양 › 밑줄 위치 '위쪽'을 밑줄 종류 **3**으로 저장하는데
  종전 enum은 `above = 2`뿐이라 그런 문서는 DocInfo 파싱이
  `HwpError.invalidRawValueForEnum`으로 끝나 문서 전체가 열리지 않았고, 뷰어
  옵션(`HwpLoadOptions.viewer`)의 부분 복구도 DocInfo에는 미치지 않아 살아나지
  않았습니다. 이제 `above`의 raw 값이 3이고, 스펙에 정의가 없는 2는 새 케이스
  `undefined2`로 값만 보존합니다 (`CharShape` 픽스처의 취소선 견본이 이 값을
  취소선 비트와 함께 갖고, 한글.app은 HWPX로 재저장할 때 밑줄 없음으로
  씁니다). HWPX `<hh:underline type="TOP"/>`은 계속 `.above`로 매핑되며 합성
  `rawValue`의 bit 2~3도 스펙 값 3이 됩니다. `above.rawValue`를 숫자 2로
  대조하던 코드와 `default` 없이 모든 케이스를 나열한 `switch`는 수정이
  필요합니다. 렌더는 종전대로 글자 아래 밑줄만 그립니다 — 글자 위 밑줄의 선
  위치는 취소선(#136)과 함께 실측한 뒤 다룹니다.

### Changed

- **빈 문단이 선택·복사 단위에 들어갑니다** (#145). 종전에는 빈 문단의 조판
  문자열이 비어 있어 선택 단위가 만들어지지 않았고, 그래서 `A / 빈 문단 / B`를
  복사하면 평문·RTF 모두 `A\n\nB` 대신 `A\nB`가 나왔으며 빈 줄에 캐럿을 놓을
  수도 없었습니다. 이제 글자가 없는 문단(HWP의 PARA_TEXT 없음·HWPX의 문단 끝
  코드뿐)은 #137의 빈 줄 앵커와 같은 표식이 붙은 빈칸 하나를 조판 문자열로
  가집니다. 잉크가 없고 장식도 붙지 않아 화면은 그대로이고, 복사에서는 글자가
  빠지되 그 문단을 종결하는 개행이 문단 스타일·글꼴을 실어 RTF에 빈 문단의
  서식이 남습니다. 검색은 이 빈칸에 걸리지 않고 낭독도 읽지 않습니다.
- **복사가 서로 다른 문단을 한 줄로 붙이지 않습니다** (#145). 조각 사이 개행
  판정이 문단 `paraId` 동일성을 전제했는데, 한글.app 저장본은 `paraId`가 문단마다
  고유하지 않아(noori 픽스처 65문단 중 고유 값 2개) 서로 다른 본문 문단·표 셀
  문단이 개행 없이 이어졌습니다. 이제 본문 문단은 조판이 블록에 싣는 위치
  열쇠(`HwpBlockSource.sectionIndex`/`paragraphIndex`, 새 `HwpParagraphKey`)가
  같을 때만, 컨테이너 문단은 '이어짐' 표식이 있을 때만 잇습니다. `HwpTextUnit`에
  `paragraphKey`가 추가됐습니다.
- **문단 끝 코드는 조판 문자열에 남지 않습니다** (#137). 모든 문단의 WCHAR
  스트림은 문단 끝 코드 13으로 끝나는데, 종전에는 이 코드가 U+000D로 조판
  문자열에 그대로 실렸습니다. 그래서 (1) 문단 끝이 문단 마지막 글자 모양의
  라틴 슬롯 폰트로 조판되면서 본문 글꼴보다 큰 ascent를 끌어와 줄 높이가
  부풀었고(표 셀은 세로 가운데 정렬이라 글이 위로 밀렸습니다), (2) U+000D에
  글리프가 있는 폰트(HY 계열)로 해석되면 문단 끝마다 `¬` 조판 부호가
  그려졌으며, (3) 복사·낭독 문자열에 U+000D가 실려 나갔습니다. 문단 끝은
  조판 폭에 기여하지 않으므로 줄 나눔과 줄 폭은 그대로입니다. 한 줄 끝(10)은
  의도된 줄 나눔이라 종전대로 남고, 한 줄 끝으로 끝난 문단의 마지막 빈 줄도
  그대로 유지됩니다.
- **쪽 번호 줄표는 문서가 지정한 경우에만 그립니다** (#138). 쪽 번호 위치
  컨트롤(`pgnp`)의 4번째 WCHAR(`HwpPageNumberPosition.unused`)가 줄표 문자를
  실을 때만 "- 1 -"처럼 양옆에 붙이고, 0이면 "1"만 그립니다. 종전에는 앞/뒤
  장식 문자가 없으면 무조건 줄표를 붙여, 줄표를 넣지 않은 문서가 한글.app과
  다르게 보였습니다. 공개 문서(표 147)가 '항상 "-"'라 적은 이 필드는 실물에서
  줄표 문자(0x2D) 또는 0으로 갈립니다.

## 0.17.0 (2026-08-28)

### Added

- **복사가 서식을 함께 싣습니다** (#118). 선택 영역을 복사하면 평문 옆에
  RTF 표현형이 같은 페이스트보드 항목으로 실려, 서식을 이해하는 앱에
  붙여넣으면 폰트·색·밑줄·취소선·첨자·글자 위치·하이퍼링크·문단 정렬이
  유지됩니다. 평문만 읽는 앱은 이전과 같은 결과를 받습니다. 공개 API로는
  `HwpSelectionController.selectedAttributedText()`와
  `HwpSelectionGeometry.attributedText(for:)`가 추가됩니다 — 반환
  문자열은 평문 복사(`selectedText()`)와 항상 같습니다.
- **키보드로 페이지를 이동할 수 있습니다** (#120). 문서 뷰가 포커스(첫
  응답자)를 가진 동안 PageUp/PageDown은 한 쪽씩, Home/End는 문서 처음과
  끝으로 이동합니다. macOS는 `pageUp(_:)`·`scrollToBeginningOfDocument(_:)` 등
  NSResponder 표준 액션으로도 같은 동작에 닿고, iOS는 하드웨어 키보드의
  `UIKeyCommand`로 동작하며 문서를 탭하면 포커스가 잡힙니다. 라이브러리는
  전역 단축키를 소유하지 않는다는 규약 그대로 — 호스트 검색 필드가 포커스를
  가진 동안에는 반응하지 않고, `HwpDocumentView(isKeyboardPageNavigationEnabled:)`
  또는 네이티브 뷰의 같은 이름 프로퍼티로 끌 수 있습니다 (기본 켜짐).
- **`HwpPageNavigator`에 페이지 번호 입력 필드가 생겼습니다** (#120).
  "Page N of M" 라벨 자리에 번호를 직접 입력하고 Enter로 확정하면
  `1...totalPages`로 클램프해 이동합니다. 숫자가 아닌 입력은 무시하고 현재
  쪽으로 되돌리며, 포커스를 잃으면 커밋하지 않고 되돌립니다. 새 API 없이
  기존 `currentPage` 바인딩을 그대로 사용합니다.

### Breaking Changes

- **CoreHwp 모델에서 `Codable` 채택을 제거했습니다** (#81).
  `HwpPrimitive`가 `Hashable & Sendable`로 줄어 `HwpFile` 등 모든 CoreHwp
  모델을 `JSONEncoder`/`JSONDecoder`로 직렬화하던 코드는 더 이상 컴파일되지
  않습니다. 공식 사용자 문서에서는 모델 직렬화 형식의 안정성을 보장하지
  않았고, 저장소 내부에서는 테스트에서만 사용했습니다. 직렬화가 필요한
  소비자는 필요한 필드만 담는 자체 투영 타입을 정의하십시오.
  `HwpCharType`·`HwpShapeArcKind`·`HwpTablePageBreakMode`처럼
  `RawRepresentable`인 enum은 `extension X: Codable {}` 한 줄로 다시 채택할
  수 있습니다.
- **`HwpDocumentLoadError`에 `unsupportedDocument(HwpUnsupportedDocumentKind)`
  케이스를 추가했습니다** (#117). 암호로 보호된 문서·배포용 문서·DRM 문서를
  읽을 때 발생하는 오류는
  `presentationBuildFailed("Unsupported HWP feature: …")`로 변환되는 대신 문서
  종류를 보존한 전용 케이스로 전달됩니다. 따라서 호스트는 `CoreHwp`를
  `import`하지 않고도 알맞은 안내 문구를 표시하거나 종류별로 분기할 수 있습니다.
  이 `enum`은 `@frozen`이 아니므로, `default` 없이 모든 케이스를 나열한 `switch`로
  처리하던 소비자는 새 케이스 분기를 추가해야 합니다.
- **`HwpDocumentLoadError`의 오류 설명을 한국어로 바꿨습니다** (#117).
  `localizedDescription`/`description`을 그대로 표시하면 "암호로 보호된 문서는
  열 수 없습니다"와 같은 한국어 안내가 나옵니다. `presentationBuildFailed`의
  `reason`에는 하위 파서나 페이지네이터가 보고한 원문이 그대로 보존되므로
  영문일 수 있습니다. 기존 영문 문구를 부분 문자열로 대조하던 코드는 더 이상
  동작하지 않습니다 — 오류 케이스로 분기하십시오.

### Changed

- **record tag 검증 보일러플레이트를 loader 프로토콜 default로 흡수했습니다**
  (#83). `HwpTagValidatedRecord` / `HwpTagValidatedRecordWithVersion`(둘 다
  internal)을 채택하고 `static let expectedTag`(`HwpSectionTag` 또는
  `HwpDocInfoTag`)만 선언하면 tag 검증 + reader 생성 + init + EOF 강제를
  default `load`가 제공합니다. 모델 18개 파일에 흩어져 있던 커스텀 `load` 구현
  31개와 `// MARK: loader contract exemption` 주석 28개가 사라지고 신설 프로토콜
  파일(118줄)의 default 구현 6개가 그 자리를 대신해, 파서 소스가 순 126줄
  줄었습니다. 공개 API·파싱 동작·렌더 산출물은 무변화입니다.
  - load 반환 직전 `rawPayload`를 record 전체 payload로 복원하던 반복은
    `HwpRawPayloadRestoringRecord` 표식으로 옮겼습니다. 복원이
    `preservedPayload` 게이트를 그대로 지나므로 `.viewer` 프리셋의 메모리
    이득도 유지됩니다 — load 후 `rawPayload`를 다시 읽는 `HwpListControl`은
    이 표식 대신 커스텀 `load`에서 `decoupledPayload`를 유지합니다.
  - `enforcesEOF = false`는 커스텀 load 시절 EOF를 검사하지 않던 8종의 **현행
    동작을 동결**하는 스위치입니다. 새 타입에서 끄지 마십시오 — 일괄 강제
    전환은 실문서 확인과 함께 후속 이슈로 분리했습니다.

### Documentation

- **문서 사이트에서 네 라이브러리 문서를 모두 제공합니다.** CoreHwp
  문서만 게시하던 hwp-swift.sboh.dev를 네 타깃의 문서를 통합한 DocC 사이트로
  전환해 HwpKitCore·HwpKitNative·HwpKit 문서도 함께 배포합니다. 기존
  `documentation/corehwp/` 주소는 유지됩니다. 각 타깃에 DocC 카탈로그를
  신설해 모듈 시작 페이지(개요와 사용 예)와 Topics 구성을 추가했으며,
  주요 진입점은 각 모듈 문서의 첫 번째 주제 그룹에 노출됩니다. PR
  단계에서도 같은 절차로 문서 빌드를 검증합니다(`docs-check.yml`).

## 0.16.0 (2026-08-24)

### Breaking Changes

- `HwpPaintListBuilder.build(for:index:)` **에서 `index:` 인자가 제거되었습니다.**
  이 인자는 도입 이래 한 번도 읽히지 않았습니다 — 412줄 구현 전체에서 `index`가
  등장하는 곳이 시그니처 한 줄뿐이었습니다.
  - *이행*: 호출부에서 `index:` 인자만 지우면 됩니다
    (`builder.build(for: page, index: someIndex)` → `builder.build(for: page)`).
    넘기던 `HwpIndex`를 다른 데 쓰지 않았다면 그 값도 함께 죽습니다.

- **`HwpPage`의 `==`/`hash`가 더 이상 `paintList`를 보지 않습니다.** 종전에는
  본문과 메모 패널의 `paintList.commands.count`를 항으로 들고 있었습니다. 이제
  `size`·`margins`·`blocks`·`pageNumber`와 메모 패널 기하(`width`·`contentHeight`)
  로만 판정합니다. 소스 브레이킹은 아니지만 **동작이 바뀝니다.**
  - 본문 paint 커맨드는 `blocks`의 파생값이라 판별력을 더하지 못했고, CF
    페이로드(`NSAttributedString`/`CGImage`/`CGPath`/`CGColor`)는 Equatable이
    아니라 애초에 개수 말고는 비교할 수단도 없었습니다.
  - *영향*: 커맨드 수만 다른 두 페이지가 이제 **같다고** 판정됩니다. 이 동등성은
    렌더 갱신 스킵뿐 아니라 선택 지오메트리 재생성과 검색 재스캔 생략
    (`HwpGeometryChange.isEquivalentRefresh`)의 입력이므로, 그런 재전달에서
    재스캔이 생략되고 지오메트리 재생성이 건너뛰어집니다. 조판 구조가 같으면
    지오메트리도 같으므로 의도된 개선입니다.
  - 렌더 결과가 다른지 확인하는 데 `HwpPage.==`를 쓰던 코드는 `blocks`나
    `paintList.commands`를 직접 순회해야 합니다 — 종전에도 커맨드 **개수**만
    맞으면 통과했으므로 신뢰할 수 없는 방법이었습니다.

- `HwpParagraphLayout.layout(attributedString:paraShape:columnWidth:tabStops:maxLineFrames:)`
  에서 **`tabStops:` 인자가 제거되었습니다.** 이 함수는 이제 입력
  `attributedString`에 **문단 스타일이 이미 부착돼 있다고 전제하고** 그것을 그대로
  framesetting합니다 (종전에는 문단마다 전체 사본을 떠 `paraShape`로
  `CTParagraphStyle`을 재생성해 부착했습니다). 정렬·들여쓰기·줄 간격·문서 정의 탭은
  전부 부착본이 나르므로 `tabStops:`가 CoreText에 닿을 경로가 없어졌습니다.
  `paraShape:`는 부착본이 나르지 못하는 값(문단 위/아래 간격, 강제 줄 높이 클램프)에만
  쓰이므로 **스타일을 부착한 paraShape와 같은 값**이어야 합니다.
  `HwpTextRunBuilder.build`를 거친 문자열은 자동으로 부착되어 있어 호출부 수정이
  필요 없고, 문자열을 직접 만들어 넘기던 호출부는
  `HwpParagraphLayout.paragraphStyle(for:attributedString:tabStops:)`로 만든 스타일을
  `kCTParagraphStyleAttributeName`에 달아야 합니다. 달지 않으면 CoreText 기본값
  (natural 정렬·자연 줄 높이)으로 조판됩니다.
- `HwpTextRunBuilder.build`가 붙이는 문단 스타일의 shape 해석이
  `HwpIndex.paraShape(for:)`(nil 가능)에서 `paraShapeOrDefault(for:)`로 바뀌었습니다.
  DocInfo에 문단 모양이 **하나도 없는** 문서에서 종전에는 스타일이 통째로 생략되어
  측정(기본 shape)과 렌더(스타일 없음)가 갈렸는데, 이제 양쪽이 같은 기본 shape를
  씁니다. 같은 이유로 `HwpPaginator`의 본문 측정도 종전의 "문단 모양이 없으면 높이
  0으로 조기 반환"(본문이 같은 y에 겹쳐 그려졌습니다)을 버리고 같은 기본 shape로
  조판합니다. 그런 문서의 렌더 결과(정렬·줄 간격·문단 높이)가 달라집니다.
  **문단 모양이 하나라도 있는 정상 문서는 영향이 없습니다** — 문단 모양 id는 배열
  오프셋으로 매겨진 조밀한 값이라 표가 비어 있지 않으면 항상 id 0이 있고 폴백이
  걸리기 때문입니다. 즉 이 변경이 닿는 것은 DocInfo에 문단 모양 레코드가 하나도 없는
  손상·조작 문서뿐입니다(저장소 픽스처 33종 전부 비해당 — 렌더 픽셀 해시 전 픽스처 ×
  전 페이지 무변화, 양 폰트 모드).

- 한컴오피스 앱 번들 폰트(`Contents/Resources/Hnc/Shared/TTF/`) 사용이 **기본
  비활성**으로 바뀌었습니다. 그 디렉터리에는 한컴이 자사 오피스 안에서 쓰도록
  라이선스받은 타사 폰트(Monotype·한양정보통신·윤디자인 등)가 섞여 있어, 제3자 앱이
  아무 선택 없이 로드하는 것이 라이선스 범위 밖일 수 있기 때문입니다. 한컴오피스가
  설치된 기기에서 이 라이브러리를 쓰던 소비자는 이번 변경 이후 `굴림`·`맑은 고딕`·
  `HY헤드라인M` 같은 글꼴이 시스템 폴백(Apple SD Gothic Neo·AppleMyungjo)으로
  렌더되어 결과가 달라집니다. 종전 동작이 필요하면 환경변수 `HWP_HANCOM_FONTS=1`
  또는 `HwpFontResolver(usesInstalledHancomFonts: true)`로 opt-in 하십시오
  (해당 폰트들의 라이선스 준수는 켜는 쪽 책임입니다). 시스템 폰트 디렉터리에 정식
  설치된 함초롬체는 종전과 동일하게 사용되므로 영향받지 않습니다.
  `HwpFontResolver.init`에 `usesInstalledHancomFonts` 인자가 추가되었지만 기본값이
  있어 기존 호출부는 수정 없이 컴파일됩니다.
- `HwpFontMap.default`의 폴백 매핑이 보강되면서 일부 face의 해석 결과가 달라집니다.
  `Myeongjo`·`HY Sinmyeongjo`는 매핑이 없어 script 폴백(한글 = 고딕)으로 떨어져
  **명조가 고딕으로** 렌더되던 것을 명조 계열로 교정했고, `Apple SD 산돌고딕 Neo`는
  시스템 폰트의 한글 표시명이라 매핑이 없으면 로마자 슬롯이 Helvetica로 대체되던
  것을 실제 폰트로 보냅니다. `한컴바탕확장`은 이름과 달리 한자용 송체이므로
  (문서 자신이 `FaceName.defaultFaceName`에 `FZSong_Superfont`를 기록합니다)
  CJK 송체 계열로 보냅니다. `굴림체`·`HY헤드라인M`·`HY울릉도M` 매핑도 추가했습니다.
- 세리프 라틴 폴백(`HwpTextRunBuilder.serifLatinFallback`)이 한컴 번들 폰트 opt-in
  상태를 따르도록 고쳤습니다. 종전에는 opt-in과 무관하게 한컴 인덱스를 조회해,
  꺼 둔 상태에서도 앱 번들 폰트 파일을 열거했고 결과가 한컴오피스 설치 여부에
  좌우되어 기본 경로의 렌더가 기기마다 달라졌습니다. 이제 opt-in이 꺼져 있으면
  설치 폰트가 없는 것으로 보고 함초롬 라틴으로 가므로 기기와 무관하게 같은
  결과가 나옵니다. 한컴오피스가 설치된 기기의 기본 경로에서는 명조/바탕 계열의
  라틴·숫자 글리프 렌더가 달라집니다(opt-in을 켠 경우는 종전과 동일).
  `HwpFontResolver.usesInstalledHancomFonts`가 public으로 노출됩니다.
- `HwpFontResolver.resolve`에 `alternatives` 인자가 추가되었습니다 (기본값이 있어
  기존 호출부는 수정 없이 컴파일됩니다). 문서가 `HwpFaceName`에 적어 둔 대체
  글꼴(`alternativeFaceName`)·기반 글꼴(`defaultFaceName`)을 폴백 후보로 씁니다.
  내장 폴백 맵을 모두 시도한 **뒤** script 폴백 직전에만 쓰이므로 맵에 있는 face의
  해석은 달라지지 않고, 맵에 없는 face만 문서가 알려준 이름으로 구제됩니다.

- `Sources/CoreHwp/Enums/HwpBorderType.swift`의 `HwpBorderType.rawValue`를 실제 HWP
  binary 값에 맞춰 정정했습니다. `none = 0`이 추가되었고, 기존 `line`,
  `longDotLine`, `dotLine`의 raw value는 각각 `0`, `1`, `2`에서 `1`, `2`, `3`으로
  바뀝니다. 저장된 raw value나 JSON snapshot에서 `HwpBorderType`을 직접 비교하던
  코드는 새 값으로 갱신해야 합니다. 예를 들어 snapshot에서 raw 숫자 `0`을 `line`으로
  기대했다면 이제 `0`은 `none`, `1`이 `line`이므로 expected JSON을 재생성하거나
  숫자 대신 enum case 의미를 비교하도록 마이그레이션합니다.
- `Sources/CoreHwp/Models/Section/CtrlHeader/Field/HwpFieldControl.swift`의
  `HwpFieldControl` `Codable` 형상이 바뀌었습니다. 필드 payload를 `properties`,
  `propertyInfo`, `extraProperties`, `command`, `fieldId`, `memoIndex`와 각 raw payload
  조각으로 노출하면서 encoded key가 늘었습니다. 기존
  `fieldParameter*` 계열 alias는 유지하지만, 완전한 field control layout으로 해석된
  payload에서는 `command` 기반 값과 trailing payload를 반영합니다.
- public reader model의 `Codable` snapshot 형상이 추가 typed view 때문에 확장되었습니다.
  영향 모델은 `HwpBorderFill.borderLineArray`, `HwpParaShape.property1Info`,
  `HwpColumn.gapArray`, `HwpCommonCtrlProperty.propertyInfo`, `HwpCtrlData.parameterSet`,
  `HwpPageNumberPosition.propertyInfo`, `HwpSectionDef.property`/`propertyInfo`,
  `HwpEquationEdit`의 수식 속성/버전/폰트 typed fields,
  `HwpTableCellHeader.propertyInfo`/`listHeaderWidthRef`/`cellPropertyInfo`/`isHeader`,
  `HwpListHeader.propertyInfo`입니다. 이전 버전에서 만든 Codable JSON을 그대로
  재사용하는 코드는 schema 차이를 고려해야 합니다.
- 공식 PDF와 실제 binary layout 차이를 반영하면서 일부 기존 public decoded value가
  달라집니다. `HwpBorderFill`의 방향별 선 정보, 서로 다른 폭 다단의 `HwpColumn`,
  `HwpSectionDef`의 속성 이후 field order, 표 셀 `LIST_HEADER`,
  `HwpEquationEdit.rawTrailing`은 이전의 잘못 정렬된 해석값과 다를 수 있습니다.
- `HwpDocumentNSView.documentActor`/`HwpDocumentUIView.documentActor` public
  프로퍼티를 제거했습니다. 어디서도 할당되지 않는 죽은 배선이었고
  (`HwpDocumentLoader`가 항상 완전 페이지네이션된 문서를 전달), 이에 의존하던
  macOS 클릭 폴백 경로는 도달 불능 코드였습니다. 지연 페이지네이션 배선은
  프로그레시브 로딩 설계에서 새로 도입됩니다.
- **비-Apple 플랫폼(Linux 등)의 빌드·실행에 zlib이 필요합니다.** 압축 해제
  폴백을 `SWCompression`에서 시스템 zlib으로 옮겼기 때문입니다 — 빌드에는 개발
  헤더(`zlib1g-dev`, rpm 계열은 `zlib-devel`)가, 실행에는 zlib 런타임이 있어야
  합니다. Debian/Ubuntu 계열 공식 Swift 도커 이미지에는 이미 포함되어 있습니다.
  Apple 플랫폼은 SDK 내장 `Compression`을 쓰므로 영향이 없습니다. 같은 변경으로
  `CoreHwp`의 `SWCompression` 의존이 사라졌습니다 (테스트 타깃에만 남습니다) —
  이 라이브러리를 통해 `SWCompression`을 전이 의존으로 받아 쓰던 코드는 직접
  의존을 선언해야 합니다.

### Changed

- **개체 앵커 산식의 소유자를 일원화했습니다** (#73). 페이지 흐름 경로
  (`HwpPaginator`)와 컨테이너 안 수집 경로(`HwpParagraphObjectCollector`)가
  정렬 반영 좌표와 글자처럼 취급 개체의 줄 앵커 좌표를 각자 구현하고 "같은
  산식"이라는 주석으로만 묶여 있던 것을 `HwpObjectAnchorGeometry`(internal)로
  합쳤습니다. 산식은 한 글자도 바뀌지 않았고 렌더 픽셀도 무변화입니다.
  컨테이너 경로의 `origin(...)`은 페이지 경로의 **문단 rect 근사**라 같은
  함수가 아니므로 합치지 않았습니다.
- `HwpPaginator.computeNextPage`를 `processParagraph` / `measuredParagraph` /
  `finishPagination` 셋으로 나눴습니다 (#73). 동작은 같고, 이 파일의
  `function_body_length` 위반이 5건에서 4건으로 줄었습니다.
- **문단마다 최대 두 번 돌던 `Task.yield()`를 16문단마다 한 번으로 배칭했습니다**
  (#73). 20,000문단 문서 기준 최대 40,000회이던 스케줄러 왕복이 2,500회가
  됩니다. 취소 **관찰**은 이 배칭과 독립입니다 — `processParagraph`가 문단마다
  `Task.checkCancellation()`을 그대로 부르며, 신설
  `HwpPaginatorCancellationTests`가 그 분리를 잠급니다.
- 변경 추적 표시색이 두 곳(`HwpTextRunBuilderMarks`·`HwpPaginator`)에
  하드코딩돼 있던 것을 `CGColor.hwpTrackChange` 하나로 모았습니다 (#73).

- `HwpParaText.wcharCount`가 문단당 reduce 재계산에서 **파스 루프 누적 저장값**
  으로 바뀌었습니다 (#67). 값·공개 API는 동일하고(`charArray` 변경 시 didSet
  재동기화), 파생값이므로 custom Codable로 인코딩 형상(`rawPayload`/`charArray`
  두 키)은 그대로입니다.
- 표 셀 헤더의 도달 불가능한 음수 `paragraphCount` 가드를 제거했습니다 (#67).
  표 셀 파싱은 `UInt16`을 `Int32`로 승격해 읽어 항상 비음수입니다 — 리스트/
  글상자와 달리 표 셀 헤더는 bytes 6-7이 셀 확장 속성이라 읽기 폭을 `Int32`로
  넓힐 수 없다는 근거를 주석으로 못박았습니다. 동작 변화는 없습니다.
- 책갈피 컨트롤(`bokm`)이 더 이상 **미지원 요소로 보고되지 않습니다**
  (`HwpUnsupportedDetector` → nil). 화면 출력이 없는 앵커이고, 이제 탐색 목록
  (`HwpDocumentMetadata.outline`)의 재료로 소비되기 때문입니다. 책갈피가 있는
  문서에서 `HwpDocument.unsupportedElements`의 `"알 수 없음: bookmark"` 항목이
  사라지므로, 그 문자열을 세거나 비교하던 코드는 갱신해야 합니다.
- 압축 stream 해제를 스트리밍 inflate로 전환했습니다 (`HwpInflate`). Apple
  플랫폼은 `Compression`, 그 외 플랫폼은 시스템 zlib
  (`inflateInit2(..., -MAX_WBITS)`)입니다. 공개 API 표면은 그대로이고 압축 해제
  결과 바이트도 동일합니다 — 코퍼스의 모든 deflate stream에서 두 프로덕션
  경로와 순수 Swift 기준선의 바이트 동등성을 테스트로 고정했습니다. 실문서
  (1,030쪽) 로드가 debug 3.281s → 0.914s, release 0.252s → 0.090s로 줄었습니다.
  손상 판정은 디코더에 맡기지 않습니다 — 선행 stored block의 `NLEN`이 `LEN`의
  1의 보수인지 라이브러리가 직접 검사해, 규격을 어긴 stream을 두 플랫폼 모두
  `streamDecompressFailed`로 거부합니다 (huffman block 뒤의 stored block은 블록
  경계를 알 수 없어 검사 범위 밖입니다). 손상 입력에서 파싱 실패를 crash가 아닌
  `HwpError`로 보고한다는 계약도 이제 전 플랫폼에서 성립합니다 — 종전 비-Apple
  폴백은 특정 손상 입력에서 catch할 수 없는 런타임 트랩으로 프로세스를
  중단시켰습니다.
- `HwpReadLimits`의 압축 해제 한도가 전 플랫폼에서 **실제 메모리 할당 상한**이
  되었습니다. 종전에는 다 풀고 나서 크기를 재는 후처리 거부라 decompression bomb의
  할당 자체를 막지 못했지만, 이제 개별 stream 한도와 남은 집계 예산의 min을
  압축 해제 도중에 적용해 상한을 넘는 순간 중단합니다. 던지는 error
  (`streamSizeLimitExceeded` / `aggregateStreamSizeLimitExceeded`)와 `limit`
  payload는 대체로 종전과 같지만 두 가지가 달라집니다. 첫째, `actual`은 정확한 압축
  해제 크기가 아니라 중단 시점까지의 **하한**이 됩니다 — 전체 크기를 알려면 끝까지
  풀어야 하기 때문입니다. 둘째, **두 한도를 동시에 넘고 남은 집계 예산이 개별 stream
  한도보다 작으면** 종전의 `streamSizeLimitExceeded` 대신
  `aggregateStreamSizeLimitExceeded`를 던집니다 — min에서 멈추므로 개별 한도 초과가
  증명되지 않았고, 확인하려면 집계 예산을 넘겨 풀어야 해서 이 상한의 목적과
  충돌하기 때문입니다. 두 error를 구분해 처리하는 코드는 이 조합에서 경로가
  달라집니다. 비-Apple 플랫폼에서는 이 두 변화가 폴백 교체와 함께 적용됩니다 —
  종전 폴백은 후처리 거부라 `actual`이 정확한 크기였고 이중 위반 시 분류도
  달랐습니다.

### Added

- **미해석 요소 집계 API**가 들어왔습니다 (#66). 새 public 메서드
  `HwpFile.parseDiagnostics()`가 문서 전체 — DocInfo·BodyText·ViewText(표시본)·
  메모·표 셀/리스트/글상자 안 중첩 문단 — 를 순회해 파서가 해석하지 못한
  요소를 `[HwpParseDiagnostic]`로 돌려줍니다. 진단은
  kind(`unknownRecord`/`unknownControl`/`notImplementedControl`/
  `recoveredSection`/`recoveredParagraph`/`recoveredMemoParagraph`) +
  tagId/ctrlId + 위치 path(`"section[0].paragraph[12].ctrl[1].cell[0]…"`) +
  detail(복구 placeholder의 `parseFailure` 사유)로 구성되며, 결과는 결정적이고
  `.default`/`.viewer` 두 로드 모드에서 같습니다. 렌더 스택의
  `HwpUnsupportedDetector`("미지원 요소가 화면에서 placeholder로 보이는가")와
  달리 조판과 무관하게 "파서가 무엇을 해석하지 못했는가"를 다루는 QA·
  텔레메트리·버그 리포트·픽스처 회귀용 표면입니다. 인접 정정으로, 문단의
  메모 계열 소비가 태그 blanket 제외에서 실제 소비 인덱스 기반으로 바뀌어
  첫 MEMO_LIST 앞의 stray 문단 record가 `unknownChildren`에 보존되고(종전에는
  모델에서 소리 없이 사라짐), 문단 없는 MEMO_LIST가 빈 그룹으로 typed 소비
  됐는데도 `unknownChildren`에 중복 보존되던 것이 제거됐습니다.
- **손상 문단·구역 best-effort 복구**가 들어왔습니다 (#65).
  `HwpLoadOptions.recoverPartialContent`(기본 `false`)를 켜면 문단 카운트
  불일치·필수 레코드 누락 같은 문단 파싱 실패, 그리고 구역 스트림 파싱 실패가
  문서 전체를 실패시키는 대신 placeholder(문단은 `paraText == nil` + 원본
  레코드 `unknownChildren` 보존, 구역은 빈 문서 템플릿 문단)로 대체되고, 새
  public 필드 `HwpParagraph.parseFailure`/`HwpSection.parseFailure`에 원인이
  남습니다. 손상 메모 문단도 같은 방식으로 복구되어 메모 그룹 경계가
  보존됩니다. `.viewer` 프리셋은 이 옵션을 켜므로 뷰어는 한 문단 손상으로
  백지가 되는 대신 나머지 본문을 그리고, placeholder는
  `HwpPaginator.unsupportedElements()`에 "손상 문단/구역 복구" 진단으로
  노출됩니다. 기본 모드는 종전 그대로 fail-fast입니다. FileHeader
  `unsupportedFeature`(암호·배포용·DRM)와 자원 한도
  2종(`streamSizeLimitExceeded`·`aggregateStreamSizeLimitExceeded`)은 복구
  모드에서도 계속 throw되며, ViewText(표시본)는 복구를 적용하지 않고 구역
  하나라도 실패하면 전량 폐기해 BodyText로 강등하는 기존 채택 규칙을
  유지합니다 — placeholder로 개수를 보존하면 불완전 표시본이 채택되어 해당
  구역이 백지가 되기 때문입니다.
- **문서 뷰 VoiceOver 지원**이 들어왔습니다 (#79). 문서 본문은 뷰가 아니라
  `CALayer`로 그려져 지금까지 AX 트리가 없었는데, 이제 두 네이티브 뷰가 가시
  (±2) 페이지의 텍스트를 접근성 요소로 합성합니다 — 본문 단위(선택과 같은
  조판·같은 캐시)에 더해 머리말/꼬리말/쪽 번호(선택·검색에서는 빠지는 쪽
  크롬)와 메모 풍선 패널 텍스트까지 낭독됩니다. 요소는 레이어 가상화와 함께
  생기고 사라지며, 문서 교체·프로그레시브 스냅샷마다 무효화되어 낡은 라벨이
  남지 않습니다. iOS에서는 개요(#77) 제목 문단에 헤딩 트레이트가 붙어
  VoiceOver 로터 "제목" 탐색이 가시 페이지 안에서 동작합니다(macOS는
  staticText로만 냅니다 — AppKit의 헤딩 role은 macOS 26에야 생겨 지원 하한
  macOS 14+에서는 쓸 수 없습니다). 합성 모델은 공개 API입니다 —
  `HwpAccessibilityContent.pageUnits(page:bodyUnits:headingTitles:)`/
  `memoPanelUnits(panel:)`가 (라벨, 페이지·패널 로컬 top-down rect) 목록을
  주므로 커스텀 뷰도 같은 재료로 AX 트리를 만들 수 있습니다. 렌더 경로는
  건드리지 않았습니다 — 페인트·조판·좌표 기준선은 그대로입니다.
- **툴바 컴포넌트에 VoiceOver 라벨**이 붙었습니다 (#79).
  `HwpZoomControls`(축소/확대/배율 초기화/폭 맞춤/쪽 맞춤),
  `HwpPageNavigator`(이전 쪽/다음 쪽), `HwpSearchNavigator`(이전·다음 검색
  결과), `HwpSearchBar`(검색어 지우기/검색 닫기) — `-`·`+`·`‹`·`›` 같은
  문장부호 버튼을 VoiceOver가 문맥 없이 읽던 것이 사라집니다. 문구는
  한국어입니다(#78 1번 에러 한국어화와 같은 정책).
- **폭 맞춤 · 쪽 맞춤 줌**이 들어왔습니다 (`HwpZoomFit`, `HwpKitCore`).
  `HwpDocumentView(fitZoom:)`에 `.width`/`.page`를 넣으면 뷰가 배율을 한 번
  맞추고 바인딩을 `nil`로 되돌리는 **원샷 명령**이며, `HwpZoomControls(fitZoom:)`에
  같은 바인딩을 넘기면 버튼 두 개가 함께 나옵니다(안 넘기면 버튼도 나오지 않아
  기존 호출부의 모습은 그대로입니다). 두 인자 모두 기본값이 있어 기존 호출부는
  수정 없이 컴파일됩니다.
  배율 계산은 뷰포트를 아는 문서 뷰가 합니다 — 라이브러리가 뷰포트 크기를
  공개 API로 내보내지 않는 쪽을 택했기 때문이고, 결과 배율은 `zoomScale`
  바인딩으로 돌아오므로 툴바 라벨은 저절로 맞습니다. 기준은 현재 쪽 폭이 아니라
  **문서 전체 스크롤 캔버스**(메모 패널 포함)라, 더 넓은 구역이 섞인 문서에서도
  맞춘 뒤 가로 스크롤이 남지 않습니다. 쪽 맞춤은 폭·높이 중 빡빡한 축에 맞추고
  그 쪽 위로 옮깁니다(폭 맞춤은 읽던 자리를 지킵니다).
  세 가지를 알아 두십시오. (1) 배율은 네이티브 한계 `0.25...5.0`으로 클램프되므로
  거대한 쪽·좁은 창에서는 "맞춤"이 근사치입니다. (2) macOS는 스크롤 캔버스에
  595pt 폭 하한이 있어 그보다 좁은 문서에서 iOS보다 작은 배율이 나옵니다 —
  각 플랫폼에서 실제로 스크롤되는 것에 맞춘 결과입니다. (3) 로딩이 끝나기 전
  (`metadata.isComplete == false`)에 맞추면 그 시점까지 도착한 쪽이 기준이라,
  뒤에 더 넓은 쪽(예: 메모 패널이 달린 쪽)이 오면 결과가 낡습니다 — 배치가 끝난 뒤
  한 번 더 누르면 최종 폭에 맞습니다.
  뷰포트가 아직 실측되지 않았거나(창에 붙기 전, SwiftUI 첫 배선) 문서에 쪽이 아직
  없을 때 들어온 요청은 버리지 않고 실측·도착 시점에 적용합니다. 다만 그 사이
  **다른 문서로 교체**되면 예약을 버립니다(옛 문서를 향한 요청이 새 문서의 배율을
  뺏지 않도록). 프로그레시브 스냅샷은 교체가 아니므로 예약이 살아남습니다.

- **선택 끝점 조정 API**를 추가했습니다 (`HwpKitCore`). `HwpSelectionController.beginAdjusting(edge:)`가
  확정된 선택의 한쪽 끝점을 잡아 `focus`로 만들고(반대쪽이 `anchor`가 됩니다), 그 뒤
  이동은 기존 `extend(to:)`가 그대로 합니다 — 제스처 시작에서 **한 번만** 부르는 것이
  계약입니다(`.changed`마다 부르면 매 프레임 anchor/focus가 뒤집힙니다). 시작 끝점을
  반대쪽 너머로 밀면 `range` 정규화로 역할이 뒤바뀌지만 손가락을 따라오는 것은 계속
  `focus`라, 호출부는 아무 상태도 뒤집지 않습니다. 끝점 캐럿은
  `HwpSelectionController.selectionCarets()`(양 끝, `HwpSelectionCaret`)와
  `HwpSelectionGeometry.caretRect(at:affinity:)`(임의 위치)로 받습니다 — 기존 하이라이트
  경로는 폭 0을 두 번 버리므로(collapsed 가드·폭 가드) 재사용할 수 없었습니다.
  `HwpCaretAffinity`는 줄 끝 오프셋과 다음 줄 첫 오프셋이 **같은 값**인 자리에서 캐럿을
  어느 줄에 그릴지만 고르는 질의 인자이며, `HwpTextPosition`의 비교·정규화 규약은
  그대로입니다.
- **iOS 텍스트 선택 핸들**이 붙었습니다. 롱프레스로 만든 선택의 양 끝에 그립 달린
  핸들이 서고, 끌어서 선택 범위를 나중에 다시 조정할 수 있습니다 — 종전에는 롱프레스
  제스처가 끝나면 끝점을 다시 잡을 방법이 없어 처음부터 다시 그어야 했습니다. 시작
  핸들을 끝 핸들 너머로 끌면 역할이 뒤바뀌고(UITextView와 같은 동작), 뷰포트 엣지에서는
  기존 44pt 존 오토스크롤이 그대로 이어지며, 드래그를 놓으면 편집 메뉴가 다시 뜹니다.
  핸들은 줌 대상 밖(스크롤 뷰의 형제)에 살아 0.25x~5x 어디서도 크기가 일정하고, 본문
  탭·롱프레스·스크롤 pan과 터치를 두고 경합하지 않습니다. 반대 핸들 위에 정확히
  겹쳐 범위가 비면 선택을 지웁니다(macOS `mouseUp`과 같은 정리 — iOS에는 이 정리가
  없었습니다). macOS는 끝점 재조정이 여전히 없습니다(shift-click 확장 경로도 없습니다)
  — 이번 변경에서 남겨 둔 비대칭입니다.
- **쪽 축소판 API**를 추가했습니다 (`HwpKit.HwpPageThumbnails`). `update(document:)`로
  대상 문서를 걸고 `image(forPageAt:pixelWidth:)`로 0-기반 쪽의 `CGImage`를 받습니다
  (`HwpPageNavigator`·`HwpOutlineItem.pageNumber`는 1-기반이므로 그쪽 값은 `- 1`을
  하거나 `HwpOutlineItem.pageIndex`를 씁니다). 화면·PDF와 **같은 paint list·같은
  조판**이며, 종횡비는 `HwpPageThumbnails.pixelHeight(for:pixelWidth:)`가 줍니다.
  요청은 직렬화되고 이미 그린 쪽은 같은 인스턴스로 즉시 돌아옵니다. 호출 태스크를
  취소하면 대기가 끊기고 남은 디코드는 시작되지 않습니다(이미 스폰된 디코드까지
  놓으려면 `cancelOutstanding()`입니다) — 디코드 스로틀이 화면 뷰와 공유되는 전역
  3슬롯이라, 스크롤로 사라진 셀이 요청을 취소하는 것이 성능 장치가 아니라 계약입니다.
  PDF 내보내기와 두 군데서 갈립니다: 프로그레시브 **중간 스냅샷을 거부하지 않고**
  (증분이면 이미 그린 축소판을 유지합니다), 바이트 예산에 걸린 그림을 실패로 보지 않고
  회색 플레이스홀더로 남깁니다(그림 하나 때문에 쪽 전체를 잃는 것이 더 나쁩니다).
  에러는 `HwpThumbnailError`입니다. 그리드·목록 UI는 종전대로 라이브러리 밖이며
  (`Sample/HwpSwiftSample/ThumbnailSidebar.swift`가 배선 예입니다) 샘플 앱에 축소판
  사이드바가 함께 들어왔습니다 — 개요가 없는 문서에서는 사이드바가 통째로 사라져
  이동 수단이 쪽 이동 버튼과 검색뿐이었습니다.
- 페이지 → 비트맵 렌더러 `HwpKitNative.HwpPageBitmapRenderer`를 추가했습니다.
  `HwpPage`를 뷰와 같은 draw 경로로 `CGImage`에 그리며, PDF 내보내기와 **그리기
  몸통과 이미지 확정 계약을 공유합니다**(`retainOnlyImages` →
  `predecodeImageReferences` → `unsettledImageVariants`, 그리고 변형 예산과 원본
  캐시 예산을 함께 거는 자리). 미확정 이미지 처리만 `HwpUnresolvedImagePolicy`로
  갈립니다 — PDF는 실패, 축소판은 플레이스홀더입니다. 이 코드의 원본은 테스트
  유틸(`FixturePreview.renderImage`)이었고 이제 그 유틸이 승격본에 위임하므로,
  커밋된 렌더 골든이 테스트 전용 사본이 아니라 **출하되는 코드**를 검사합니다
  (승격 리팩터는 기준선 재기록 없이 통과합니다). 출력 픽셀에는 축별 상한
  (`maximumPixelDimension`)이 있습니다 — 종횡비는 문서가 정하는 값이라 병적인
  페이지 하나가 수백 GB 비트맵을 요구할 수 있어, 크기 헬퍼는 클램프하고
  렌더러는 `.invalidPixelSize`로 거부합니다. `sourceRect`도 크기가 양수인지만이
  아니라 **파생되는 변환이 유한한지**까지 봅니다 — NaN 원점·무한/비정규 크기에서
  CoreGraphics는 실패하지 않고 빈 비트맵을 성공으로 돌려주므로
  `.invalidSourceRect`로 끝냅니다. 축별 상한과 별개로 **총 면적 상한**
  (`maximumPixelCount`, 64 MiB)이 있습니다 — 세로 페이지에서는 폭 하나만 상한으로
  줘도 높이가 상한까지 클램프돼 1 GiB가 되기 때문입니다. 이 검증은 모두 그림
  디코드 **전에** 끝나므로, 잘못된 요청이 예산을 쓰거나 원인이 아닌 오류로
  보고되지 않습니다.
- 개요·책갈피 **탐색 목록**을 공개 API로 추가했습니다
  (`HwpDocumentMetadata.outline: [HwpOutlineItem]`). 조판이 확정한 쪽을 들고
  있어 사이드바·목차에서 항목을 눌러 그 쪽으로 바로 이동할 수 있습니다.
  개요 수준은 문단 모양 속성1의 문단 수준 비트(표 44 bit 25-27)에서 읽고,
  그 비트가 개요로 설정돼 있지 않은 문단(`개요 8` 이상 스타일이 그렇습니다)은
  스타일 이름(`개요 N` / `Outline N`)으로 보완합니다. 수준은
  `HwpOutlineItem.maximumLevel`(10)로 클램프되고(상한을 넘는 사용자 스타일도
  버리지 않습니다), 페이지 상한에 걸려 문서에 실리지 못한 쪽의 항목은 목록에
  담기지 않으므로 `pageNumber`는 언제나 `pageCount` 이하입니다(프로그레시브
  중간 스냅샷에서도 그렇습니다 — 그 스냅샷이 담은 쪽까지만 실립니다). 책갈피는 본문만
  대상이며 머리말·꼬리말은 빠집니다(검색과 같은 스코프 규약). 항목은
  `Identifiable` + 1-기반 `pageNumber`(0-기반 `pageIndex`도 함께) + 1-기반
  `level`이라 호스트가 `List`로 열 줄 안에 목록을 만듭니다 —
  라이브러리는 목록 UI를 내지 않고 `Sample`이 사이드바 배선 예를 보입니다.
  프로그레시브 로딩의 **중간 스냅샷에도** 지금까지 확정된 접두가 실립니다
  (`unsupportedElements`는 종전대로 최종 스냅샷에만 옵니다).
  목록이 자원 상한에 걸려 잘리면 `HwpDocumentMetadata.isOutlineTruncated`가
  `true`입니다 — 책갈피는 미지원 요소로도 보고되지 않으므로 이 값이 유실의
  유일한 신호입니다.
- `HwpParaShapeProperty1.headingLevelRawValue`(CoreHwp)를 추가했습니다 —
  문단 수준(표 44 bit 25-27)의 **0-기반 저장값**입니다(사람이 읽는 수준은 +1).
  계산 프로퍼티라 `Codable` 형상은 그대로입니다.
- 문서 내 검색을 **공개 API**로 추가했습니다. 엔진(`HwpTextSearcher`)·세션
  (`HwpSearchController`)은 HwpKitCore, 하이라이트와 매치 노출 스크롤은
  HwpKitNative, SwiftUI 컴포넌트(`HwpSearchBar` / `HwpSearchNavigator`)는
  HwpKit에 있습니다. 호스트는 컨트롤러 하나를 `@State`로 소유해
  `HwpDocumentView(searchController:)`와 `HwpSearchBar(controller:)`에 같은
  인스턴스를 넘기면 되고, UI를 직접 만들고 싶으면 컨트롤러만 물려도
  하이라이트·스크롤·프로그레시브 재스캔이 그대로 동작합니다. 검색은 텍스트
  선택과 **같은 조판을 공유**하므로 하이라이트가 화면과 어긋나지 않고 단위
  캐시가 이중화되지 않습니다. 한글은 조합형/완성형이 동치로 비교되고,
  대소문자·발음 구별 부호 무시와 단어 단위 검색을 `HwpSearchOptions`로
  고릅니다. 검색 대상은 본문이며 머리말·꼬리말·쪽 번호와 메모 풍선은 빠지고
  각주·표 셀·글상자·중첩 표는 포함됩니다. 매치가 수만 건이 되는 짧은 질의는
  `matchLimit`(기본 5,000)에서 잘리고 `phase == .truncated`로 알립니다.
  Cmd+F 같은 전역 단축키는 호스트 몫입니다 — 라이브러리는 포커스 훅만 받습니다.
- HWP 문서를 PDF로 내보내는 `HwpPDFExporter`(HwpKit)를 추가했습니다.
  `export(document:to:onProgress:)`는 파일로 스트리밍하고
  `exportData(document:onProgress:)`는 바이트를 돌려줍니다(전량이 메모리에
  남으므로 대형 문서는 파일 쪽을 쓰십시오). 화면 렌더와 **같은 paint list·같은
  조판**을 씁니다 — 페이지 레이어가 뷰 계층 없이 임의 `CGContext`에 그리는 순수
  오프스크린 렌더러라 가능합니다. 텍스트는 벡터로 들어가고, 페이지마다 mediaBox를
  따로 넘겨 구역별 용지 크기·방향 차이를 보존하며, 종이 밖 편집 화면 장식인 메모
  풍선은 한글의 인쇄 뷰와 마찬가지로 빠집니다. 페이지 단위 스트리밍이라 상주
  메모리는 1페이지 몫이며(이미지는 현재 페이지 변형 + 원본 캐시가 각각 디코드
  예산 이하), 페이지 경계마다 `Task.checkCancellation()`과
  `HwpPDFExportProgress` 진행률 콜백이 발화합니다. **임시 파일에 완성한 뒤에만
  목적지를 건드리므로**, 기존 PDF를 덮어쓰는 중에 취소·실패해도 이전 파일이
  그대로 남고 열리지 않는 부분 파일도 남지 않습니다. 한 페이지가 참조하는
  이미지가 디코드 예산(256MB)을 넘으면 이미지가 빠진 PDF를 돌려주는 대신
  실패합니다. 같은 이유로 페이지네이션이 끝나지 않은 문서(`loadUpdates(from:)`의
  중간 스냅샷)도 `.incompleteDocument`로 거부합니다 — 그대로 내보내면 페이지가
  빠진 PDF가 성공으로 나가는데, 열리고 페이지 수도 맞아 산출물 검증에도
  걸리지 않습니다. 다 쓴 PDF는 **열어서 페이지 수를 확인한 뒤에만** 목적지로
  옮깁니다 — Core Graphics는 쓰기 실패를 로그로만 알려서, 디스크가 차면 절단된
  파일이 성공으로 설치될 수 있었습니다. 에러는 `HwpPDFExportError`(`CustomStringConvertible` +
  `LocalizedError`)입니다.
  **인쇄·저장·공유 UI는 앱 책임입니다** — 라이브러리는 PDF 바이트까지만
  만듭니다. `Sample/`이 macOS `PDFDocument.printOperation`, iOS
  `UIPrintInteractionController`, 양 플랫폼 `fileExporter` 배선 예를 보입니다
  (뷰를 직접 인쇄하는 경로는 없습니다 — 레이어 가상화가 가시 ± 2쪽만 들고 있어
  인쇄 페이지네이션과 충돌합니다).
- `HwpPageImageProvider`에 화면 없는 경로용 이미지 해석 API
  `resolveImage(for:style:)` / `predecodeImageReferences(in:)`(둘 다 `async`)과
  `imageVariantKeys(in:)`을 추가했습니다. 기존 `requestImage`는 레이어 재드로우로
  완료를 소비하는 fire-and-forget이라 PDF 내보내기·썸네일처럼 화면이 없는
  경로에서는 완료를 알 방법이 없었습니다. 새 API는 확정을 직접 기다리되
  백프레셔로 **드롭된** 요청까지 감지해 재요청하므로 영구 대기가 없습니다.
  뷰 경로의 시그니처와 동작은 그대로입니다.
- `HwpReadLimits.maxNestingDepth`(기본 64)를 추가해 레코드 트리 중첩 깊이를
  제한합니다. 레코드 헤더의 level은 10비트(≤1023)라 스펙만으로는 수백 단계
  중첩이 가능한데, typed 디코더들이 그 트리를 재귀로 내려가므로(표 셀 문단·
  리스트 컨트롤·글상자 문단·메모) 깊게 조작된 문서가 **catch 불가능한 스택
  오버플로**를 일으킬 수 있었습니다. 뷰어가 파싱을 스택이 작은 오프-메인
  스레드에서 돌리므로 위험이 더 컸습니다. 한도를 넘으면 payload를 읽기 전에
  `HwpError.invalidRecordTree`로 거부합니다. 전 픽스처 실측 최대 level은 5라
  정상 문서는 영향받지 않으며, 필요하면 `HwpReadLimits(maxNestingDepth:)`로
  조정할 수 있습니다. `init`에 인자가 추가되었지만 기본값이 있어 기존 호출부는
  수정 없이 컴파일되고, 구 아카이브는 키가 없어도 기본값으로 디코딩됩니다.
- HWP 문서를 렌더링·표시하는 뷰어 스택을 추가했습니다. 플랫폼 중립 렌더 코어
  `HwpKitCore`, AppKit/UIKit 브릿지 `HwpKitNative`, SwiftUI 공개 API `HwpKit`
  3개 라이브러리 타깃으로 구성되며, 표·중첩 표·글상자·각주/미주·머리말/꼬리말·
  다단·도형/이미지·treatAsChar 인라인 앵커를 다루는 페이지네이션 렌더
  파이프라인과 텍스트 드래그 선택·복사·전체 선택, `Sample/`의 SwiftUI 샘플 앱을
  제공합니다. 뷰어 3개 타깃은 `canImport(Darwin)` 조건이라 Apple 플랫폼
  전용이고, `CoreHwp` 파서는 Linux 지원을 유지합니다.
- 렌더가 요구하는 record/control을 typed 모델로 승격했습니다. 도형 세부 레코드
  (`HwpShapeComponentDetail`), 그림 속성(`HwpPictureProperty`), 표 셀 속성
  (`HwpTableCellProperty`), 각주 구분선(`HwpFootnoteDividerInfo`), 글상자 텍스트
  속성(`HwpTextBoxListInfo`), 머리말/꼬리말 적용 범위(`HwpHeaderFooterProperty`)가
  추가되고, BinData의 내장 OLE 차트에서 `OOXMLChartContents` XML을 꺼내는 최소
  CFB 리더(`HwpEmbeddedChart`)가 붙었습니다.
- `HwpLoadOptions`를 추가했습니다. `preserveRawPayload`(기본 true)를 끄면
  파싱 모델의 rawPayload/rawTrailing 보존을 생략해 압축 해제 스트림 버퍼가
  파싱 후 즉시 해제됩니다 (`.viewer` 프리셋 — 1,030쪽급 문서 상주 수십 MB
  절감). `HwpFile.init(fromPath/fromData/fromWrapper:options:)`가 추가됐고
  기존 `readLimits` init은 그대로 동작합니다.
- 프로그레시브 로딩: `HwpDocumentActor.loadDocumentUpdates(from:)`와
  `HwpDocumentLoader.loadUpdates(from:)`가 첫 페이지 확정 즉시 스냅샷을
  방출하는 `AsyncThrowingStream<HwpDocumentSnapshot, Error>`를 제공합니다.
  `HwpDocumentMetadata.loadToken`으로 macOS/iOS 뷰가 스크롤 리셋 없이
  증분 적용합니다.
- 전 파싱 모델이 `Sendable`을 채택했습니다 (`HwpPrimitive`에 요구 추가).
- 대형 문서 성능이 크게 개선됐습니다: DataReader 무슬라이스 읽기,
  `HwpChar` 컨트롤 payload 박싱 (stride 80B → 16B), 절대 라인 캐시 모드의
  CT 측정 생략. 1,030쪽 실문서 기준 전량 로드 23.8s → 16.6s, 첫 페이지
  표시 3.2s, 파스 후 상주 메모리 약 -290MB.
- 공식 HWP 5.0 revision 1.3 PDF와 `edwardkim/rhwp` errata를 대조한
  `Documentation/ErrataAudit.md`를 추가했습니다.
- page number, equation edit, common object property, paragraph shape, border fill,
  list header, column, field control, ctrl data, section definition 관련 typed reader view를
  보강했습니다.

### Documentation

- 최상위 README의 상세 지원 범위와 fixture 기준을 하위 문서로 이관했습니다.
- `edwardkim/rhwp` 원본 저장소, `hwp_spec_errata.md`, CoreHwp에서 받은 도움을
  README의 감사 섹션에 기록했습니다.
