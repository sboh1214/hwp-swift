# HWP Reader Errata Audit

이 문서는 CoreHwp Reader 관점에서 공식 HWP 5.0 revision 1.3 PDF와 rhwp
`hwp_spec_errata.md`를 대조한 작업용 기록이다.

- 공식 사양: 한글과컴퓨터 공개 문서 `한글문서파일형식_5.0_revision1.3.pdf`
  (HWP 5.0 revision 1.3, author `(주)한글과컴퓨터`, PDF CreationDate 2018-11-23,
  ModDate 2020-11-13, SHA-256
  `391261ec810e83e8bf72166743cfc884ead626b320a2a5818a3e9fce15984fcc`)
- rhwp 정오표: <https://github.com/edwardkim/rhwp/blob/devel/mydocs/tech/hwp_spec_errata.md>
  (`origin/devel` `1d8c25778edd44896208525a672570123a6892f7`, 2026-06-29)
- rhwp samples: <https://github.com/edwardkim/rhwp/tree/main/samples>
  (`origin/main` `10f5c51e65e0e8e9260cf1498972db14ea04c29e`, 2026-06-25)
- rhwp 참고 clone: local rhwp clone (root license: MIT)
- 상태 값: `implemented`, `already correct`, `not reader scope`, `needs Hancom fixture`, `blocked by dependency`

rhwp sample은 보조 검증 단서로만 사용한다. CoreHwp XCTest fixture로 추가하려면 한컴오피스 한글에서
직접 생성하거나 재저장한 `.hwp`와 재생성 절차를 함께 남긴다.

| 항목 번호/제목 | PDF 근거 | CoreHwp Reader 적용 여부 | 현재 구현 상태 | 필요한 모델/enum/record/parser 변경 | 검증 가능한 fixture | rhwp samples 사용 가능 여부 | 한컴 프로그램으로 재생성 가능한지 여부 | 비적용/보류 사유 |
|---|---|---:|---|---|---|---|---|---|
| 1. BorderFill 직렬화/파싱 순서 | 표 23 테두리/배경 | 예 | needs Hancom fixture | 완료: `HwpBorderFill`이 실제 바이너리의 `(line_type + width + color) × 4` interleaved 순서로 읽고 `HwpBorderLine` side model을 노출한다. 필요: 4방향이 모두 다른 전용 한컴 fixture. | 있음: `text-box` Hancom fixture에서 기본 none line 확인. 보조: `noori` migrated fixture에서 non-default interleaved 색상 확인. | 없음 | 가능: 표/문단/도형 테두리를 방향별로 다르게 지정 | non-default 4방향 raw 기대값을 전용 한컴 fixture로 보강 필요 |
| 2. BorderLineType 열거값 | 표 25 테두리선 종류 | 예 | needs Hancom fixture | 완료: `HwpBorderType`을 0=None, 1=Solid, 2=Dash, ... 기준 raw-value enum으로 정리하고 `HwpBorderLine.type`으로 노출한다. 필요: 여러 선 종류 전용 한컴 fixture. | 있음: `text-box` Hancom fixture에서 0=None 확인. 보조: `noori` migrated fixture에서 1=Solid 확인. | 없음 | 가능: 테두리 종류별 셀/문단/도형 생성 | Dash/Double/Wave 등 실제 raw 값 대응은 전용 한컴 fixture 필요 |
| 3. LIST_HEADER 속성 비트 위치 | 표 65 문단 리스트 헤더 | 예 | implemented | 완료. `HwpListHeader.propertyInfo`와 `HwpTableCellHeader.propertyInfo`가 bit 16~22 text direction, wrap, vertical align typed view를 노출한다. 표 셀은 실제 layout인 `UInt16 paragraphCount + UInt32 listAttr + UInt16 widthRef`로 정정했다. | 있음: `Tests/CoreHwpTests/Fixtures/noori/document.hwp`에서 `listAttr=0x00200000`(center), `0x00400000`(bottom) 보조 검증. 전용 Hancom fixture는 추가 가능. | 보조 가능: errata 문서의 `list_attr=0x00200000` 검증값 | 가능: 글상자 또는 표 셀 속성으로 세로 정렬/텍스트 방향/줄바꿈 문서 생성 | - |
| 4. FootnoteShape 레코드 크기 | HWPTAG_FOOTNOTE_SHAPE | 예 | already correct | 추가 변경 없음. `HwpFootnoteShape`가 divider color 뒤 unknown 2바이트와 trailing payload를 보존한다. | 있음: `Tests/CoreHwpTests/Fixtures/footnote-endnote` | 보조 가능: `samples/footnote-01.hwp`, `samples/endnote-01.hwp` | 이미 있음: 한컴오피스 한글 직접 생성 fixture | - |
| 5. PARA_HEADER char_count MSB | 표 60 문단 헤더 | 예 | already correct | 추가 변경 없음. `HwpParaHeader`가 MSB를 `isLastInList`로 분리하고 `charCount`를 마스킹한다. | 있음: 기존 실제 fixture와 paragraph stability tests | 특정 errata sample 없음 | 기존 fixture로 충분, 특수 scope 문서는 추가 가능 | 직렬화 규칙은 Reader 범위 밖 |
| 6. 빈 문단 PARA_TEXT 금지 | 표 60, 표 62 | 아니오 | not reader scope | 없음 | serializer 도입 시 필요 | 특정 errata sample 없음 | 가능: 빈 문단만 있는 문서 저장 전후 비교 | 한컴 저장 호환을 위한 writer/serializer 검증 규칙 |
| 7. control_mask 재계산 | 표 60 문단 헤더 | 아니오 | not reader scope | 없음. Reader는 `HwpParaHeader.controlMask` raw 값을 노출한다. | serializer 도입 시 필요 | 특정 errata sample 없음 | 가능: 컨트롤 추가/삭제 저장 전후 비교 | 재계산은 writer/editor 책임 |
| 8. 채우기 alpha 바이트 | 표 30 채우기 정보 | 예 | needs Hancom fixture | `HwpBorderFill.fillInfo` raw 뒤 단색/그라데이션/이미지 alpha typed parser를 추가하고 정렬 보존을 검증한다. | 필요: 투명도 있는 도형/배경 문서 | 보조 가능: `samples/basic/Worldcup_FIFA2010_32.hwp` | 가능: 채우기 투명도 지정 도형 생성 | alpha raw 기대값을 한컴 fixture로 확인 필요 |
| 9. 확장 제어문자 16바이트 | 표 6, 표 62 | 예 | already correct | 추가 변경 없음. `HwpParaText`가 제어문자 코드 2바이트와 추가 14바이트를 합쳐 16바이트를 보존한다. | 있음: noori/track-change 계열 실제 fixture와 stability tests | 특정 errata sample 없음 | 기존 fixture로 충분, TAB 전용 fixture 추가 가능 | - |
| 10. 셀 제목 행 bit | 표 65, 표 79, 표 80 | 예 | needs Hancom fixture | 완료: `HwpTableCellHeader.listHeaderWidthRef`, `cellPropertyInfo`, `isHeader`가 LIST_HEADER bytes 6~7 bit 2를 노출한다. 필요: bit 2가 켜진 반복 제목 행 fixture. | 있음: `noori` migrated fixture에서 `widthRef=0x0000/0x0400/0x0500` off 상태 보조 검증. 필요: 반복 제목 행 표 fixture | 보조 가능: `samples/table-ipc.hwp` 여부 검토 | 가능: 첫 행 반복/제목 셀 표 생성 | 제목행 true raw 기대값 필요 |
| 11. ColumnDef 비례 너비/간격 | 4.3.10.2 단 정의, 표 138/139 단 정의/속성 | 예 | implemented | 완료. `HwpColumn`의 variable width 경로가 실제 layout인 `[attr][attr2][w0+gap0][w1+gap1]...` 순서로 `property2`, `widthArray`, `gapArray`를 읽고 구분선 필드를 정상 정렬한다. 값은 HWPUNIT 절대값이 아니라 32768 합계 기준 비례값으로 해석해야 한다. | 있음: `Tests/CoreHwpTests/Fixtures/Column/document.hwp`에서 raw `00 00 63 28 d3 06 ca 50 00 00...`를 `property2=0`, `width=[10339,20682]`, `gap=[1747,0]`로 검증. 기존 이관 fixture이므로 전용 Hancom 재저장 fixture로 갱신 가능. | 보조 가능: `samples/KTX.hwp`, `samples/basic/KTX.hwp` (`w0=13722`, `g0=590`, `w1=18456`, `g1=0`) | 가능: 서로 다른 폭의 다단 문서 생성 | - |
| 12. PageNumberPos 속성 참조 | 표 147, 표 148 | 예 | implemented | 완료. `HwpPageNumberPosition.propertyInfo`와 `HwpPageNumberPositionProperty`가 bit 0~7 번호 모양, bit 8~11 표시 위치를 노출한다. | 있음: `Tests/CoreHwpTests/Fixtures/noori/document.hwp` (`attr=0x00000500`) | 특정 errata sample 없음 | 기존 fixture 사용, 전용 fixture 추가 가능 | - |
| 13. CommonObjAttr prevent_page_break | 표 72 공통 객체 속성 | 예 | already correct | 추가 변경 없음. `HwpCommonCtrlProperty`가 `instanceId` 뒤 optional Int32를 읽어 후속 개체 설명문 오프셋을 보존한다. 의미 alias/rename은 후속 정리 대상이다. | 있음: legacy-common-control-property, shape/table fixture tests | 특정 errata sample 없음 | 기존 fixture로 충분, 그림 저장 fixture 추가 가능 | - |
| 14. CommonObjAttr attr bit 15~19 | 표 70 공통 객체 속성의 속성 | 예 | implemented | 완료. `HwpCommonCtrlProperty.propertyInfo`가 폭/높이 기준 raw 값과 enum view를 노출한다. | 있음: `equation`, `noori`, `text-box` fixture에서 absolute width/height 기준 검증 | 보조 가능: `samples/test-image.hwp`, `samples/ta-pic-001-r*.hwp(x)` | 가능: 추가 기준별 그림 fixture 생성 | - |
| 15. SHAPE_COMPONENT 그림 ctrl_id `$pic` | 표 86 SHAPE_COMPONENT | 예 | already correct | 추가 변경 없음. `HwpCommonCtrlId.picture == "$pic"`이고 `HwpShapeComponent.rawCtrlId/ctrlId`가 이를 노출한다. | 있음: `BinData`/`noori` 그림 fixture | 특정 errata sample 없음 | 기존 fixture로 충분 | - |
| 16. bin_data_id는 DocInfo BinData 순번 | 이미지 참조 관련 | 예 | already correct | 추가 변경 없음. `HwpShapeComponentPicture.binaryDataId`는 payload의 1-based 참조값을 보존하고 `HwpDocInfo.idMappings.binDataArray`는 record 순서 배열이다. | 있음: `BinData` fixture. 비순차 storage id fixture는 추가 가능 | 보조 가능: `samples/basic/Worldcup_FIFA2010_32.hwp` | 가능: 여러 이미지를 삽입/삭제해 storage id 비순차 문서 생성 | 렌더러 resolver는 별도 범위 |
| 17. ShapeComponent shadow info | 표 86~87 SHAPE_COMPONENT | 예 | needs Hancom fixture | shape component 세부 record의 fill/shadow 이후 typed layout을 추가하고 raw fallback을 유지한다. | 필요: 그림자와 투명 채우기 도형 fixture | 보조 가능: `samples/basic/Worldcup_FIFA2010_32.hwp` | 가능: 그림자/채우기 지정 도형 생성 | shadow 16바이트 기대값 필요 |
| 18. 필드 CTRL_HEADER memo_index | 표 154 필드 컨트롤 | 예 | implemented | 완료. `HwpFieldControl`이 `properties + extra_properties + command_len + command + field_id + memo_index` typed layout을 우선 파싱하고 기존 짧은 raw parameter fallback은 보존한다. | 있음: `Tests/CoreHwpTests/Fixtures/memo/document.hwp`에서 `memoIndex=1`, `fieldId=0x4279408c` 확인 | 보조 가능: `samples/field-01-memo.hwp` | 이미 있음: 한컴오피스 한글 12.30.0 build 6382 직접 생성 fixture | - |
| 19. 누름틀 HelpState | 표 154, HWPML 3.0 §10.1.5 | 예 | needs Hancom fixture | ClickHere command 문자열에서 `Direction`, `HelpState`, `Name` wstring을 파싱하고 trailing space 보존을 검증한다. | 필요: 안내문/메모/이름이 모두 지정된 누름틀 fixture | 보조 가능: `samples/field-01-memo.hwp` | 가능: 누름틀 속성 지정 문서 생성 | command 문자열 기대값 필요 |
| 20. 누름틀 필드 이름 CTRL_DATA | 표 154, HWPML 3.0 §8.8 | 예 | needs Hancom fixture | 부분 완료: `HwpCtrlDataParameterSet`이 ParameterSet 0x021B / item 0x4000 String layout을 typed view로 노출하고, 책갈피의 동일한 ctrlData 문자열 payload는 이 typed view를 사용한다. 필요: 이름이 지정된 ClickHere field fixture로 같은 layout의 필드 이름 의미를 검증. | 있음: `bookmark` Hancom fixture에서 shared `CTRL_DATA` ParameterSet raw `1B 02 01 00 00 00 00 40 01 00`과 UTF-16 이름 확인. 필요: 이름이 지정된 ClickHere field fixture | 보조 가능: `samples/field-01.hwp` | 가능: 누름틀 필드 이름 변경 문서 생성 | ClickHere CTRL_DATA 의미와 raw 기대값은 전용 한컴 fixture 필요 |
| 21. 필드 properties bit 15 | 표 155 필드 속성 | 예 | needs Hancom fixture | 완료: `HwpFieldControl.propertyInfo.isInitialState`가 bit 15의 inverse 의미를 노출한다. 필요: bit 15 off 초기 상태 누름틀 fixture. | 있음: `memo` Hancom fixture에서 bit 15 on 상태(`properties=0x8001`, `isInitialState=false`) 확인. 필요: bit 15 off ClickHere fixture | 보조 가능: `samples/field-01-memo.hwp` | 가능: 초기 안내문/입력 완료 문서 각각 생성 | 초기 상태(bit 15 off) raw 기대값은 전용 한컴 fixture 필요 |
| 22. control_mask TAB/FIELD_END/LINE_BREAK | 표 60 | 아니오 | not reader scope | 없음. Reader는 `controlMask` raw와 `HwpParaText.charArray` 순서를 보존한다. | serializer 도입 시 필요 | 특정 errata sample 없음 | 가능: TAB/field/line break 문서 생성 | 누락 비트 재계산은 serializer 책임 |
| 23. PARA_TEXT FIELD_BEGIN/FIELD_END 순서 | 표 62 | 아니오 | not reader scope | 없음. Reader는 PARA_TEXT 순서를 그대로 읽는다. | serializer 도입 시 ClickHere fixture 필요 | 보조 가능: `samples/field-01.hwp` | 가능: 누름틀 문서 생성 | 필드 범위 재배치는 writer/serializer 책임 |
| 24. TAB 확장 데이터 7 code unit | 표 62 | 예 | already correct | 추가 변경 없음. `HwpParaText`에서 TAB(0x0009)은 inline control로 분류되고 추가 14바이트 payload를 보존한다. | 있음: stability/raw preservation tests. 전용 TAB fixture는 추가 가능 | 특정 errata sample 없음 | 가능: 탭 포함 문서 생성 | - |
| 25. numbering_id 기반 문단번호 시작 | 표 40, 표 45, 표 146 | 아니오 | not reader scope | 없음. Reader는 `HwpParaShape.numberingOrBulletId`와 `nwno` control raw/typed 일부를 보존한다. | renderer/editor 도입 시 필요 | 보조 가능: `rhwp-studio/public/samples/para-head-num-2.hwp` | 가능: 문단 번호 시작값 변경 문서 생성 | 카운터 history는 renderer/editor semantics |
| 26. 표 CTRL_HEADER CommonObjAttr | 표 68, 표 75 | 예 | already correct | 추가 변경 없음. `HwpTable`이 CTRL_HEADER payload를 `HwpCommonCtrlProperty`로 읽고 ctrl id `.table`을 검증한다. | 있음: noori/table fixture와 table assembly tests | 보조 가능: `samples/table-ipc.hwp` | 기존 fixture로 충분, IPC 전용 fixture 추가 가능 | - |
| 26b. CommonObjAttr text wrap bits | 표 70 공통 객체 속성의 속성 | 예 | implemented | 완료. `HwpCommonCtrlProperty.propertyInfo.textWrap`이 HWP5 실측 mapping `0=Square`, `1=TopAndBottom`, `2=BehindText`, `3=InFrontOfText`를 노출한다. | 있음: `equation`, `noori`, `text-box` fixture에서 raw value 1/3 검증 | 보조 가능: `samples/test-image.hwp`, `samples/test-image.hwpx` | 가능: 배치 방식별 그림 fixture 생성 | - |
| 27. PrvImage PNG 포맷 | PrvImage stream 설명 | 예 | already correct | 추가 변경 없음. `HwpPreviewImageFormat`이 BMP/GIF/PNG/JPEG magic bytes를 감지하고 raw payload를 보존한다. | 있음: preview fixtures | 보조 가능: `samples/biz_plan.hwp`, `samples/shift-return.hwp` | 가능: PNG preview 포함 문서 저장 | - |
| 28. CFB directory FAT chain | Compound File/OLE2 설명 | 간접 | blocked by dependency | CoreHwp 코드 변경 없음. OLE directory traversal은 OLEKit 책임이다. | OLEKit 이슈/패치 시 필요 | 보조 가능: `samples/shift-return.hwp` | 가능하나 CoreHwp 직접 fixture보다 OLEKit regression 필요 | OLEKit 또는 별도 OLE reader 의존성 범위 |
| 29. SectionDef.flags hide_master_page bit 2 | 표 129/130, §4.3.10.1 | 예 | needs Hancom fixture | 완료: `HwpSectionDef`가 ctrl id 다음 `UInt32 property`를 읽고 `HwpSectionDefProperty.hideMasterPage`를 bit 2로 노출한다. `columnSpacing`, `defaultTabSpacing`, `numberParaShapeId` 등 뒤 필드도 PDF 순서로 재정렬했다. 필요: bit 2가 켜진 한컴 fixture. | 있음: `plain-text-minimal` Hancom fixture에서 `property=0`, `columnSpacing=1134`, `defaultTabSpacing=8000`, `numberParaShapeId=1` off 상태 검증. 필요: 바탕쪽 첫쪽 감춤 on fixture | 보조 가능: `samples/21_언어_기출_편집가능본.hwp`(`0xC0080004`), `samples/exam_kor.hwp`/`exam_eng.hwp`(`0xC0000004`), `samples/exam_math.hwp`(`0x20000000`) | 가능: 바탕쪽/첫쪽 감춤 설정 문서 생성 | positive bit true raw 기대값을 전용 한컴 fixture로 고정 필요 |
| 30. TabDef.position 조판 의미 | 표 7 TabDef, §4.2.7 | 아니오 | not reader scope | 없음. `HwpTabDef`는 position/type/fill raw data를 읽는다. | renderer 도입 시 필요 | 보조 가능: `samples/KTX.hwp` | 가능: 오른쪽 탭/채움선 문서 생성 | RIGHT leader effective position은 조판 알고리즘 |
| 31a. PAGE_BORDER_FILL 위치 기준 | 표 136 PAGE_BORDER_FILL | 아니오 | not reader scope | 없음. `HwpPageBorderFill.property`는 raw로 보존한다. | renderer/format bridge 도입 시 필요 | 특정 errata sample 없음 | 가능: HWP5/HWPX/HWP3 비교 fixture 생성 | HWP3/HWP5/HWPX 렌더링 계약 분리 문제 |
| EQEDIT. baseline 뒤 UINT16 zero | 표 105 수식 개체 속성 | 예 | implemented | 완료. `HwpEquationEdit`가 property, 수식 문자열, letterSize, color, baseline, `unknownAfterBaseline`, versionInfo, fontName을 best-effort typed view로 노출한다. | 있음: `Tests/CoreHwpTests/Fixtures/equation/document.hwp` | 보조 가능: `samples/math-001.hwp` | 이미 있음: 한컴오피스 한글 12.30.0 build 6382 직접 생성 fixture | - |
| 31b. CommonObjAttr bit 13 flowWithText | 표 70 공통 객체 속성의 속성 | 예 | implemented | 완료. `HwpCommonCtrlProperty.propertyInfo`가 `restrictInPage`, `allowOverlap`, `effectiveAllowOverlap`을 노출한다. | 있음: `equation`, `noori`, `text-box` fixture와 rhwp raw value `0x002a2210`/`0x002a0210` unit check | 보조 가능: `samples/ta-pic-001-r-쪽영역안제한*.hwp(x)` | 가능: `쪽 영역 안으로 제한` on/off 그림 문서 생성 | - |
| 32. ParaShape attr1 bit 28/29 | HWPTAG_PARA_SHAPE | 예 | needs Hancom fixture | 완료: `HwpParaShape.property1Info`가 `borderConnect`/`borderIgnoreMargin` typed view를 노출한다. 필요: 두 bit가 켜진 실제 한컴 fixture 추가. | 있음: `noori` fixture에서 raw wiring과 off 상태 확인. 필요: 문단 테두리 연결/여백 무시 on/off fixture | 보조 가능: `samples/[2027] 온새미로 1 본교재.hwp(x)` | 가능: 문단 테두리 옵션 on/off 문서 생성 | attr1 bit 28/29 on 상태 기대값을 한컴 fixture로 확인 필요 |

## 이번 브랜치에서 구현한 Reader 범위

- `HwpPageNumberPosition.propertyInfo`
  - 공식 PDF 표 147/148의 bit layout과 rhwp 항목 12의 실측 `attr=0x00000500` 해석을 반영해 번호 모양과 표시 위치를 분리했다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/noori/document.hwp`
- `HwpEquationEdit` typed view
  - 공식 PDF 표 105의 수식 개체 속성에 rhwp EQEDIT errata의 baseline 뒤 UINT16 필드를 반영했다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/equation/document.hwp`
- `HwpCommonCtrlProperty.propertyInfo`
  - 공식 PDF 표 70과 rhwp CommonObjAttr bit 13, bit 15~19, text wrap 실측 정정을 반영했다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/equation/document.hwp`,
    `Tests/CoreHwpTests/Fixtures/noori/document.hwp`,
    `Tests/CoreHwpTests/Fixtures/text-box/document.hwp`
- `HwpParaShape.property1Info`
  - 공식 PDF 표 44의 attr1 bit 28/29와 rhwp ParaShape errata의 `borderConnect`/`borderIgnoreMargin` 해석을 반영했다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/noori/document.hwp` (raw wiring과 off 상태). bit on 상태는 추가 한컴 fixture 필요.
- `HwpBorderFill.borderLineArray`
  - 공식 PDF 표 23의 테두리/배경 fixed field와 rhwp BorderFill errata의 실제 interleaved 순서를 반영했다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/text-box/document.hwp` (Hancom-generated default none line).
    `Tests/CoreHwpTests/Fixtures/noori/document.hwp`는 non-default interleaved side 값의 보조 검증으로만 사용했다.
- `HwpBorderType`
  - rhwp BorderLineType errata에 따라 `0=None`, `1=Solid` 기반 raw value를 노출한다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/text-box/document.hwp` (0=None), `noori` 보조 검증 (1=Solid).
- `HwpListHeader.propertyInfo` / `HwpTableCellHeader.propertyInfo`
  - 공식 PDF 표 65의 LIST_HEADER 속성 필드에 rhwp 항목 3의 bit 16~22 실측 위치를 반영했다.
  - 표 셀 `LIST_HEADER`는 `UInt16 paragraphCount + UInt32 listAttr + UInt16 widthRef`로 읽고,
    `widthRef`의 셀 확장 bit는 `HwpTableCellHeader.cellPropertyInfo`로 노출한다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/noori/document.hwp` (`listAttr=0x00200000`,
    `0x00400000` 보조 검증). 반복 제목 셀 true 상태는 추가 한컴 fixture 필요.
- `HwpColumn` variable-width layout
  - 공식 PDF 4.3.10.2 단 정의와 rhwp 항목 11의 실측 byte order를 반영해 서로 다른 폭 다단을
    `[attr][attr2][width+gap pairs][divider]` 순서로 읽는다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/Column/document.hwp` (`width=[10339,20682]`,
    `gap=[1747,0]`, `property2=0`). 이 fixture는 기존 이관본이며 README에 한컴 재생성 절차를 남겼다.
- `HwpFieldControl` typed field header
  - 공식 PDF 표 154/155와 rhwp Field CTRL_HEADER errata의 `memo_index` 4바이트를 반영했다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/memo/document.hwp`
- `HwpCtrlDataParameterSet`
  - 공식 PDF 표 154와 HWPML 3.0 §8.8, rhwp 항목 20의 ParameterSet 0x021B / item 0x4000
    String layout을 반영해 `HwpCtrlData.parameterSet`으로 노출한다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/bookmark/document.hwp` (`parameterSetId=0x021B`,
    `itemId=0x40000000`, `valueType=1`, `value="CoreHwpBookmark"`). ClickHere field name 의미는
    추가 한컴 fixture 필요.
- `HwpSectionDef.propertyInfo`
  - 공식 PDF 4.3.10.1 표 129/130의 `SECTION_DEF` field order와 rhwp 항목 29의
    `hide_master_page = flags & 0x0004` 실측 정정을 반영했다.
  - 검증 fixture: `Tests/CoreHwpTests/Fixtures/plain-text-minimal/document.hwp` (`property=0`,
    `columnSpacing=1134`, `defaultTabSpacing=8000`, `numberParaShapeId=1`). bit 2 on 상태는
    rhwp samples의 raw dump를 보조 단서로만 사용했고 추가 한컴 fixture가 필요하다.

## rhwp 보조 sample 후보

아래 파일은 local rhwp clone의 `origin/main`
`10f5c51e65e0e8e9260cf1498972db14ea04c29e` 기준 보조 분석 후보이다. rhwp root
license는 MIT이지만 각 sample의 원출처가 별도 문서화되어 있지는 않으므로 현재 브랜치에는
commit하지 않았다. CoreHwp XCTest fixture로 쓰려면 한컴오피스 한글에서 직접 생성하거나
재저장한 `.hwp`로 대체한다.

| errata 항목 | rhwp sample 후보 | source URL |
|---|---|---|
| 8, 16, 17 | `samples/basic/Worldcup_FIFA2010_32.hwp` | <https://github.com/edwardkim/rhwp/blob/10f5c51e65e0e8e9260cf1498972db14ea04c29e/samples/basic/Worldcup_FIFA2010_32.hwp> |
| 10, 26 | `samples/table-ipc.hwp` | <https://github.com/edwardkim/rhwp/blob/10f5c51e65e0e8e9260cf1498972db14ea04c29e/samples/table-ipc.hwp> |
| 11, 30 | `samples/KTX.hwp`, `samples/basic/KTX.hwp` | <https://github.com/edwardkim/rhwp/tree/10f5c51e65e0e8e9260cf1498972db14ea04c29e/samples> |
| 19, 21 | `samples/field-01-memo.hwp` | <https://github.com/edwardkim/rhwp/blob/10f5c51e65e0e8e9260cf1498972db14ea04c29e/samples/field-01-memo.hwp> |
| 20, 23 | `samples/field-01.hwp` | <https://github.com/edwardkim/rhwp/blob/10f5c51e65e0e8e9260cf1498972db14ea04c29e/samples/field-01.hwp> |
| 26b, 31b | `samples/test-image.hwp`, `samples/ta-pic-001-r-쪽영역안제한*.hwp(x)` | <https://github.com/edwardkim/rhwp/tree/10f5c51e65e0e8e9260cf1498972db14ea04c29e/samples> |
| 29 | `samples/21_언어_기출_편집가능본.hwp`, `samples/exam_kor.hwp`, `samples/exam_eng.hwp`, `samples/exam_math.hwp` | <https://github.com/edwardkim/rhwp/tree/10f5c51e65e0e8e9260cf1498972db14ea04c29e/samples> |
| EQEDIT | `samples/math-001.hwp` | <https://github.com/edwardkim/rhwp/blob/10f5c51e65e0e8e9260cf1498972db14ea04c29e/samples/math-001.hwp> |

## 추가 fixture 우선순위

1. BorderFill 4방향 선/굵기/색과 선 종류를 모두 다르게 지정한 문서.
2. LIST_HEADER text direction/wrap/vertical align과 표 제목 셀을 포함한 문서.
3. 서로 다른 폭 다단의 `Column` fixture를 한컴오피스 한글에서 재저장해 이관본 기대값을 대체한다.
4. ClickHere 누름틀의 안내문, 메모, 이름, 초기 상태와 필드 이름 CTRL_DATA를 모두 포함한 문서.
5. SectionDef 첫쪽 바탕쪽 감춤(bit 2), 첫쪽 테두리/배경, 빈 줄 감춤을 각각 켠 문서.
6. ParaShape attr1 bit 28/29 on/off 문서.

## 한컴 fixture 요청 상세

아래 항목은 Reader 구현을 더 진행하려면 실제 한컴오피스 한글에서 생성하거나 재저장한
fixture가 먼저 필요하다. rhwp sample은 raw 위치를 찾는 보조 자료로만 쓰고, XCTest의
최종 기대값은 이 표의 절차로 만든 `.hwp`에서 추출한다.

| 제안 fixture id | errata 항목 | 한컴 생성 절차 | 구현/검증에 필요한 기대값 |
|---|---|---|---|
| `border-fill-variants` | 1, 2 | 새 문서에 2×2 표 또는 네모 도형을 만들고 위/아래/왼쪽/오른쪽 테두리의 선 종류, 굵기, 색을 모두 다르게 지정해 저장한다. 가능하면 Dash, Double, Wave, Solid를 포함한다. | `HwpBorderFill.borderLineArray` 4개 방향의 `typeRawValue`, `thickness`, `color`가 한컴 UI 설정과 일치해야 한다. `HwpBorderType`의 non-default raw 값은 이 fixture로 고정한다. |
| `fill-alpha` | 8 | 도형을 삽입하고 단색 채우기 투명도를 0%, 중간값(예: 36%), 100% 중 하나 이상으로 지정한다. 가능하면 같은 문서에 그라데이션 채우기와 그림 채우기 투명도도 추가한다. | `HwpBorderFill.fillInfo` 또는 shape fill payload에서 추가 속성 뒤 alpha byte를 소비해야 한다. rhwp 보조값은 `Worldcup_FIFA2010_32.hwp`의 `0xA3`; 한컴 fixture에서는 fill_type bit별 alpha byte 수와 opacity 변환을 고정한다. |
| `table-repeat-header` | 10 | 여러 쪽에 걸치는 표를 만들고 첫 행 반복/제목 셀 옵션을 켠 뒤 저장한다. 같은 파일에 옵션을 끈 표도 하나 둔다. | `HwpTableCellHeader.cellPropertyInfo.isHeader`가 true/false를 구분해야 한다. 반복 제목 행의 `listHeaderWidthRef & 0x0004 != 0` 기대값을 고정한다. |
| `shape-shadow-fill` | 17 | 네모 도형 또는 글상자에 채우기와 그림자를 함께 지정한다. 그림자 색, X/Y offset을 명확히 다르게 지정하고 가능하면 투명도 채우기도 함께 둔다. | shape component 세부 record에서 `lineInfo -> fillInfo -> shadowInfo(16B) -> instid...` 순서를 검증한다. `shadow_type`, `shadow_color`, `offset_x`, `offset_y` typed fields와 뒤 payload 정렬을 고정한다. |
| `clickhere-field` | 19, 20, 21 | 누름틀을 삽입하고 안내문(Direction), 메모(HelpState), 이름(Name)을 모두 지정한다. 저장 후 다시 열어 필드 이름만 변경하고 재저장한 사본도 만든다. 초기 상태 문서와 사용자가 값을 입력한 문서를 각각 만든다. | `HwpFieldControl` command 문자열에서 `Direction:wstring`, `HelpState:wstring`, `Name:wstring` 및 각 값 뒤 공백 1개를 보존해야 한다. `HwpCtrlDataParameterSet` 이름이 command `Name`보다 우선하는지 확인한다. `properties` bit 15 off/on에 대한 `isInitialState` 기대값을 고정한다. |
| `section-def-first-page-hides` | 29 | 구역 설정에서 첫 쪽 바탕쪽 감춤, 첫 쪽 테두리/배경 표시 또는 감춤, 빈 줄 감춤을 각각 켠 구역을 만들고 저장한다. 가능하면 옵션별로 구역을 나눈다. | `HwpSectionDef.propertyInfo.hideMasterPage == true`인 `property & 0x0004` positive case를 고정한다. `showFirstPageBorderOnly`, `showFirstPageFillOnly`, `hideEmptyLine`도 같은 fixture에서 검증한다. |
| `paragraph-border-connect` | 32 | 연속된 두 개 이상의 문단에 문단 테두리를 적용하고 `문단 테두리 연결`, `문단 여백 무시`를 켠 문단 모양과 끈 문단 모양을 함께 저장한다. | `HwpParaShape.property1Info.borderConnect`와 `borderIgnoreMargin`이 bit 28/29 on/off를 구분해야 한다. HWPX 대응 속성은 참고만 하고 XCTest 기대값은 HWP5 attr1 raw에서 추출한다. |
