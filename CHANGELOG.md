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

### Added

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
