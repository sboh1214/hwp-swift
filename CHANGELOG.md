# Changelog

## Unreleased

### Breaking Changes

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

### Changed

- 압축 stream 해제를 Apple `Compression`의 스트리밍 inflate로 전환했습니다
  (`HwpInflate`). 비-Apple 플랫폼은 종전 `SWCompression` 폴백을 그대로 씁니다.
  공개 API 표면은 그대로이고 압축 해제 결과 바이트도 동일합니다 — 코퍼스의 모든
  deflate stream에서 양 경로 바이트 동등성을 테스트로 고정했습니다. 실문서
  (1,030쪽) 로드가 debug 3.281s → 0.914s, release 0.252s → 0.090s로 줄었습니다.
- `HwpReadLimits`의 압축 해제 한도가 Apple 플랫폼에서 **실제 메모리 할당 상한**이
  되었습니다. 종전에는 다 풀고 나서 크기를 재는 후처리 거부라 decompression bomb의
  할당 자체를 막지 못했지만, 이제 개별 stream 한도와 남은 집계 예산의 min을
  압축 해제 도중에 적용해 상한을 넘는 순간 중단합니다. 던지는 error
  (`streamSizeLimitExceeded` / `aggregateStreamSizeLimitExceeded`)와 `limit`
  payload는 종전과 같지만, `actual`은 정확한 압축 해제 크기가 아니라 중단 시점까지의
  **하한**이 됩니다 — 전체 크기를 알려면 끝까지 풀어야 하기 때문입니다.

### Added

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
