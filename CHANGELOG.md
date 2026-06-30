# Changelog

## Unreleased

### Breaking Changes

- `Sources/CoreHwp/Enums/HwpBorderType.swift`의 `HwpBorderType.rawValue`를 실제 HWP
  binary 값에 맞춰 정정했습니다. `none = 0`이 추가되었고, 기존 `line`,
  `longDotLine`, `dotLine`의 raw value는 각각 `0`, `1`, `2`에서 `1`, `2`, `3`으로
  바뀝니다. 저장된 raw value나 JSON snapshot에서 `HwpBorderType`을 직접 비교하던
  코드는 새 값으로 갱신해야 합니다.
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

### Added

- 공식 HWP 5.0 revision 1.3 PDF와 `edwardkim/rhwp` errata를 대조한
  `Documentation/ErrataAudit.md`를 추가했습니다.
- page number, equation edit, common object property, paragraph shape, border fill,
  list header, column, field control, ctrl data, section definition 관련 typed reader view를
  보강했습니다.

### Documentation

- 최상위 README의 상세 지원 범위와 fixture 기준을 하위 문서로 이관했습니다.
- `edwardkim/rhwp` 원본 저장소, `hwp_spec_errata.md`, CoreHwp에서 받은 도움을
  README의 감사 섹션에 기록했습니다.
