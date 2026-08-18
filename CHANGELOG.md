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
- **비-Apple 플랫폼(Linux 등)의 빌드·실행에 zlib이 필요합니다.** 압축 해제
  폴백을 `SWCompression`에서 시스템 zlib으로 옮겼기 때문입니다 — 빌드에는 개발
  헤더(`zlib1g-dev`, rpm 계열은 `zlib-devel`)가, 실행에는 zlib 런타임이 있어야
  합니다. Debian/Ubuntu 계열 공식 Swift 도커 이미지에는 이미 포함되어 있습니다.
  Apple 플랫폼은 SDK 내장 `Compression`을 쓰므로 영향이 없습니다. 같은 변경으로
  `CoreHwp`의 `SWCompression` 의존이 사라졌습니다 (테스트 타깃에만 남습니다) —
  이 라이브러리를 통해 `SWCompression`을 전이 의존으로 받아 쓰던 코드는 직접
  의존을 선언해야 합니다.

### Changed

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
