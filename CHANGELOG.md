# Changelog

## Unreleased

### Added

- **HWPX 문서의 새 번호·쪽 감추기·책갈피·찾아보기 표식을 반영합니다** (#169).
  `hp:newNum`·`hp:pageHiding`·`hp:bookmark`·`hp:indexmark`가
  `.newNumber`·`.pageHide`·`.bookmark`·`.indexmark`로 승격돼, 종전에 미구현으로
  강등되며 무시되던 표식이 HWP 저장본과 같게 동작합니다 — 새 번호로 시작한 쪽·
  각주·미주 번호가 실제로 다시 매겨지고(예: 2·3쪽이 9·10으로), 쪽 감추기가 머리말·
  꼬리말·쪽 번호를 그 쪽에서 지우며, 책갈피가 문서 탐색 목록에 나옵니다. 종전에는
  같은 문서를 HWP로 열 때와 HWPX로 열 때 쪽 번호가 서로 달랐습니다. 한글.app이
  저장한 `section-marks` 쌍(3쪽, 표식 8개)을 HWP·HWPX 픽스처로 추가해 쪽 크롬과
  컨트롤 payload가 HWP 쌍과 같은지 등식으로 잠갔습니다. 이로써 구역 부속 컨트롤의
  강등은 홀/짝수 조정(`hp:pageNumCtrl`) 하나만 남습니다 — 실물 표본이 없어
  payload를 지어내야 하므로 그대로 두고 `parseDiagnostics()`에 보고합니다.
  전체 쪽수 종류(`numType="TOTAL_PAGE"`)는 #168의 자동 번호와 같은 이유로
  승격하지 않습니다.

  같은 변경에서 **새 번호 컨트롤의 제어 문자 코드 오기(18 → 21)를 고쳤습니다** —
  코드 18은 자동 번호 전용이고, 저장소의 실물 HWP 36종에서 `nwno` 41건이 전부
  21입니다. 강등 상태에서도 HWPX만 다른 코드를 쓰고 있었습니다.

- **HWPX 문서의 각주·미주를 그립니다** (#168). `hp:footNote`·`hp:endNote`가
  `.footnote`·`.endnote(HwpListControl)`로, 각주 본문 문단 안의 `hp:autoNum`이
  `.autoNumber`로 함께 승격돼, 종전에 미구현으로 강등되며 본문이 통째로 사라지던
  각주·미주가 HWP 저장본과 같은 자리에 번호 라벨과 구분선까지 그려집니다. 구역의
  각주·미주 모양(`hp:footNotePr`·`hp:endNotePr`)도 옮겨 번호 모양·앞뒤 장식 문자·
  시작 번호·번호 매김 방식·미주 배치와 구분선(길이·여백·종류·굵기·색)이 반영됩니다 —
  종전에는 이 값들이 빈 문서 기본값으로 고정돼, 저작자가 바꾼 문서가 경고 없이
  기본 모양으로 그려졌습니다. 한글.app이 저장한 `footnote-endnote` 변환 쌍을 HWPX
  픽스처로 추가해 각주·미주 블록의 텍스트와 좌표가 HWP 쌍과 같은지 등식으로
  잠갔습니다. 전체 쪽수 자동 번호(`numType="TOTAL_PAGE"`)는 HWP5 번호 종류가 담지
  못해 승격하지 않고 강등에 남깁니다 — 승격하면 그 자리에 현재 쪽 번호가 그려져
  "1 / 3" 머리말이 "1 / 1"이 됩니다. 남은 구역 부속 컨트롤은 #169에서 승격됐습니다.
- **HWPX 문서의 머리말·꼬리말을 그립니다** (#167). `hp:header`·`hp:footer`가
  `.header`·`.footer(HwpListControl)`로 승격돼, 종전에 미구현으로 강등되며 매
  쪽에서 통째로 빠지던 머리말·꼬리말이 HWP 저장본과 같은 자리에 그려집니다.
  적용 범위(`applyPageType`의 `BOTH`·`EVEN`·`ODD`)는 표 141 비트로 옮겨 홀·짝수
  머리말이 갈리고, 생략과 미지 이름은 양쪽으로 접습니다. 한글.app이 저장한
  `header-footer` 변환 쌍을 HWPX 픽스처로 추가해 HWP 쌍과 쪽 크롬 텍스트가 같은지
  등식으로 잠갔습니다. 구역 첫 쪽 감추기(`hp:visibility`의 머리말·꼬리말·쪽 번호)도
  함께 옮겨, 감춰야 할 첫 쪽에 머리말이 그려지지 않습니다. 남은 구역 부속
  컨트롤은 #169에서 승격됐습니다.
- **HWPX(OWPML) 문서를 읽습니다**. `HwpFile(fromPath:)`·`(fromData:)`·
  `(fromWrapper:)`가 파일 선두 바이트로 HWP(OLE)/HWPX(ZIP)를 자동 감지해
  같은 문서 모델로 변환하므로, 뷰어(`HwpKit`)는 코드 변경 없이 `.hwpx`를
  렌더합니다. 1차 지원 범위는 본문 텍스트·글자/문단 모양·스타일·구역/쪽
  설정·단·표·그림·쪽 번호 위치(#135)·OLE 개체(내장 차트, #134)·문단 번호와
  글머리표 정의(#133 — 글머리표 문자는 그려지고, 문단 번호·개요 번호 라벨은
  #154에서 두 포맷 공통으로 그립니다)이며, 조판
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
- **문단 머리 정보와 번호 형식을 해석합니다** (#152 — #151의 첫 단계).
  `HwpNumberingFormat.paraHeadInfo`·`HwpBullet.paraHeadInfo`가 표 39 문단 머리
  정보 12바이트를 새 `HwpParaHeadInfo`(정렬·번호 너비·자동 내어 쓰기·본문과의
  거리 종류·번호 모양·너비 보정값·거리·글자 모양 ID)로 읽고,
  `HwpNumberingFormat.pattern`이 `^1.`·`(^4)`·`^6)` 같은 번호 형식을 문자 조각과
  수준 참조로 분해합니다(`HwpNumberingFormatPattern`). 지시자의 경계는 한글.app
  12.30 실측을 따릅니다 — 캐럿은 숫자 한 자리(1-9)만 먹어 `^10`은 `^1` 뒤의 `0`이고,
  `^n`·`^N`은 레벨 경로 토큰, 그 밖의 캐럿(`^0`·`^x`)은 문자 그대로입니다. `HwpNumbering.format(forLevel:)`이 확장 수준(8-10)
  까지 수준별 형식을 돌려줍니다. HWPX는 `hp:secPr@outlineShapeIDRef`를 id 테이블로
  리맵해 `HwpSectionDef.numberParaShapeId`에 싣습니다 — 생략은 0(참조 없음)이고
  잘못된 참조는 0으로 접되 `parseDiagnostics()`에 합성 레코드로 남습니다. 정렬·
  거리 종류의 비기본값과 개요·문단 번호 문단의 실물 근거로 한글.app이 저장한
  `outline-numbering` 픽스처 쌍을 추가했습니다. 렌더링은 #154에서 다룹니다.
- **문단 번호·개요 번호를 문서 순서로 생성합니다** (#153 — #151의 두 번째 단계).
  새 `HwpParagraphNumbering.generate(sections:index:)`(HwpKitCore)가 구역·문단과
  표 셀·글상자·각주·미주·머리말/꼬리말 안 문단을 한 번 훑어 개요(문단 머리 종류
  1)와 번호 매기기(종류 2) 문단마다 `HwpParagraphNumber`(종류·1수준부터의 번호·
  조립한 라벨)를 만들고, 문단의 위치 경로 `HwpParagraphPath`(최상위는
  `HwpParagraphKey`, 컨테이너 안은 컨트롤·자식 문단 서수)로 조회합니다.
  `HwpPaginator.paragraphNumbering`이 같은 표를 들고 있으며, 조판과 무관한 순수
  함수라 문단을 재측정·재배치해도 번호는 한 번만 늡니다. 카운터 규칙은 한글.app
  12.30 실측을 따릅니다 — 정의마다 목록이 하나라 같은 정의의 문단은 본문·다른
  목록·구역 경계·표를 지나도 자기 번호를 잇고, 정의의 첫 문단에서만 시작 번호
  방식(새 `HwpNumbering.continuesPreviousList`: 0이면 직전 목록·앞 구역의 번호를
  물려받고 1 이상이면 `startingNumber(forLevel:)`의 수준별 시작 번호에서 새로 셈)을
  보며, 상위 수준이 늘면 하위 수준은 시작 번호로 돌아가고 건너뛴 상위 수준은 시작
  번호로 매겨진 것으로 칩니다. 개요와 번호 매기기는 따로 셉니다. `^n`·`^N` 레벨
  경로도 각 수준의 번호 모양으로 조립하므로 #152의
  `HwpNumberingFormatPattern.isSupported`는 없어졌습니다(미공개 API). 실물 근거로
  한글.app이 저장한 `numbering-sequence` 픽스처 쌍(정의 6종·구역 3개·표 셀 번호,
  라벨은 같은 세션의 복사 텍스트로 대조)을 추가했고, 헌법주석의 1수준 표제
  280개는 그 문서가 실은 생성 목차와 번호·제목이 일치하며 개요 문단 1,944개
  전체의 라벨은 스냅샷으로 잠갔습니다. 조작 문서가 문서를 여는 순간 메모리를
  삼키지 못하게 라벨 하나는 `HwpParagraphNumber.textUnitCeiling`(512 UTF-16 단위)
  에서 스칼라 경계로 끊고, 문서 전체는 `HwpParagraphNumbering.maximumDocumentEntries`
  (20,000)와 걸음 수(문단·컨트롤) `maximumVisitedNodes`(500,000)에서 멈추며 취소된
  로드도 걷다 말고 `isTruncated`로 알립니다. 형식 분해도 출력 천장까지만 합니다
  (`HwpNumberingFormatPattern.parse(_:unitCeiling:)`). HWPX의 `hh:heading@level`이
  3비트 밖(9·10수준)이면 머리 종류 없음으로 접고 `parseDiagnostics()`에 남깁니다.
  화면·PDF·복사 텍스트에 번호를 넣는 것은 #154입니다.
- **문단 번호·개요 번호 라벨을 화면·PDF·복사 텍스트·접근성 낭독에 그립니다**
  (#154 — #151의 마지막 단계). `HwpPaginator`가 최상위 문단마다
  `paragraphNumbering`의 번호를 `HwpTextRunBuilder.build`의 새 `number` 매개변수로
  넘기고, 조판 문자열 앞에 `I. `·`가. `·`(1) ` 같은 라벨과 본문과의 거리 빈칸을
  전치합니다(글머리표와 같은 자리). 양쪽 정렬의 단어 간격 벌림은 라벨의 거리
  빈칸을 늘리지 않고, 빈칸 없는 본문은 글자 사이를 벌려 줄 폭을 채웁니다.
  접근성 낭독에는 라벨이 들어가되 개요 제목 판정은 라벨을 뗀 본문으로 합니다.
  쪽·단 경계 뒤로 이어지는 문단 조각은 첫 줄 들여쓰기를 다시 적용하지 않고
  둘째 줄 들여쓰기에서 시작합니다(`HwpParagraphLayout.continuationFragment` —
  들여쓰기·내어쓰기 문단 전반에 적용). 라벨 범위에는 새
  `HwpAttributedStringKey.numberingLabel` 표식이, 자동 내어쓰기 전진량과 번호
  너비 안 정렬의 첫 줄 여백에는 `numberingHeadIndent`·`numberingFirstLineInset`
  (pt)이 붙습니다. 표 39 문단 머리 정보는 한컴 도움말과 한글.app 12.30 실측대로
  해석합니다 — 글자 모양 ID -1은 바탕글이 아니라 **문단 맨 마지막 글자의 글자
  모양**이고(`HwpParaHeadInfo.charShapeId` 문서 정정), 번호 너비는 자릿수 맞춤이면
  라벨 폭 + 너비 보정값·해제면 글자 크기 × 1.5 + 보정값이며, 정렬은 그 너비
  안에서, 본문과의 거리는 비율(글자 크기의 %)·HWPUNIT 절대값, 자동 내어쓰기는
  둘째 줄부터를 첫 줄 본문 시작에 맞춥니다. 헌법주석 개요 1,944문단이 라벨과
  함께 그려져 종전 "(미렌더)" 진단 1,944건이 사라졌고, 진단은 이제 라벨이 나오지
  못한 문단(참조 없음·댕글링·해당 수준의 형식 슬롯 없음 "(N수준 형식 없음)"·순회
  상한)만 보고합니다. `outline-numbering`·
  `numbering-sequence`·헌법주석 13쪽을 한글.app과 대조했습니다(라벨·본문 위치
  0.5pt 이내). 표 셀·글상자·각주·머리말 안 번호 문단의 라벨은 아래 #158
  항목에서 그립니다.
- **표 셀·글상자·각주·미주·머리말/꼬리말 안 문단의 문단 번호·개요 번호 라벨도
  그립니다** (#158). #153이 이미 세어 둔 번호를 컨테이너 조판 경로가 위치 경로
  (`HwpParagraphPath`)로 찾아 #154와 같은 규칙(글자 모양·번호 너비·정렬·본문과의
  거리·자동 내어쓰기)으로 전치하며, 화면·PDF·복사 텍스트·접근성 낭독에 함께
  실립니다. 셀 문단은 `cellArray` 순서, 글상자 문단은 개체 요소 → 리스트 순서,
  각주·미주·머리말·꼬리말은 리스트 순서로 자식 서수를 복원해 번호 생성기의
  순회와 같은 경로를 씁니다. 측정과 배치가 같은 번호로 같은 문자열을 만들어
  셀 줄바꿈·각주 예약·머리말 밴드 캐시가 라벨을 반영하고, 표가 쪽을 넘어
  잘린 셀 문단의 이어지는 조각은 라벨을 되풀이하지 않습니다. 번호 문단 머리
  진단(참조 없음·댕글링·수준 형식 없음·순회 상한)도 컨테이너 안 문단에 같은
  규칙으로 적용됩니다. `numbering-sequence` 3쪽 표 셀의 `9.`·`10.`을 한글.app
  12.30과 대조했습니다(셀 테두리 기준 라벨·본문 위치 0.2pt 이내). 표 셀은
  실물로, 글상자·각주·미주·머리말/꼬리말은 합성 입력으로 검증했습니다.

### Fixed

- **줄글의 베이스라인이 한글보다 1~2pt 낮게 그려지던 것을 바로잡았습니다** (#178).
  한글은 베이스라인을 줄 상자 상단에서 **줄 상자 높이의 0.85배** 아래에 두고, 그 줄
  상자 높이는 그 줄 글자들의 **상대크기 적용 전 기본 크기**입니다(줄 간격의 여분은
  상자 아래 간격으로 나갑니다). 종전 구현은 이 앵커를 폰트 ascent에서 역산해
  (`ascent − 0.85 × 글자 크기`를 CoreText가 준 줄 ascent에서 뺐습니다) 문단에 비율·
  고정 줄 간격이 걸린 줄에서 CoreText가 강제 줄 높이 안으로 ascent를 다시 나눈 몫이
  그대로 새어 나갔습니다 — 함초롬바탕 10pt·줄 간격 160%에서 1.30pt, 상대크기 170%
  줄에서 2.76pt, 줄 간격 300% 줄에서 8.30pt 아래였고 글꼴마다 크기가 달랐습니다.
  베이스라인을 따라가는 밑줄·취소선·강조점·선택 영역도 같이 내려가 있었습니다.
  이제 베이스라인은 앵커가 정합니다 — 줄 상자 상단을 찾고 그 아래 자기 앵커만큼에 둡니다.
  상자 상단은 첫 줄을 블록 상단에 맞추고 나머지는 CoreText 줄 원점 간격에서 그 줄의 ascent
  몫을 되돌려 구하므로, 글자처럼 취급 개체가 문단 중간 줄에 있어도 글자가 개체에서 떨어지지
  않습니다 (`CCL` 로고 문단의 둘째 줄이 한글과 0.7pt 안에서 맞습니다).

  한글은 이 값을 줄 캐시(`PARA_LINE_SEG`)에 직접 적습니다. 한컴오피스 한글 12.30.0이
  저장한 합성 문서 34줄(글자 크기 8종 × 줄 간격 종류 4종 × 글꼴 3종 × 상대크기 2종)의
  `baselineDistance ÷ lineHeight`가 전부 정확히 0.85였고, 같은 문서를 한글이 내보낸
  PDF의 벡터 텍스트 베이스라인이 `lineLocation + baselineDistance`와 최대 0.10pt
  (한글 PDF의 0.12pt 장치 양자화) 차이였습니다. 수정 후 우리 렌더는 `CharShape` 12줄·
  `underline-above`·`footnote-endnote`·`multi-section`·`Column`에서 문서에 적힌 값과
  **정확히** 일치하고, `noori` 본문 18줄은 한글 PDF와 0.09pt 안에서 맞습니다(수정 전
  +1.93 ~ +2.04pt).

  줄마다 상자 높이가 다른 문단의 상자 상단은 CoreText가 **배치에 쓴** ascent를 복원해
  찾습니다. `CTLineGetTypographicBounds`가 돌려주는 ascent는 그 값이 아닙니다 — CoreText는
  줄 슬롯의 여분을 베이스라인 위에 넣으면서 그 몫을 줄 객체에 되돌려 주지 않습니다
  (Helvetica 10pt 자연 조판에서 보고 7.70 vs 배치 9.70). 반면 같은 함수의 descent + leading은
  슬롯의 베이스라인 아래 몫과 정확히 같아, 줄 원점 간격에서 그것과 줄 사이 간격을 빼면 배치
  ascent가 정확히 복원됩니다 — 글꼴 4종 × 라틴·한글 × 강제 줄 높이 5종 × 개체 유무 80조합에서
  0.0003pt 이내입니다(프레임 높이를 줄여 줄이 떨어지는 임계를 이분 탐색하면 CoreText의 실제
  슬롯 경계가 나오고, 그것과 대조했습니다). 이로써 두 가지가 고쳐집니다: ① 줄 높이 **하한만**
  걸린 문단(`.atLeast`·글자처럼 취급 개체가 든 문단)에서 짧은 줄 다음의 큰 줄 상자가 8.2pt
  아래에 놓이던 것, ② 줄 높이 **상한만** 지정된 문단을 고정 높이로 취급해 아무것도 깎지 않는
  상한을 얹기만 해도 베이스라인이 `[108.5, 151.9, 199.9]`에서 `[108.5, 175.0, 223.0]`으로
  바뀌던 것 — `HwpPaintCommand.drawText`에 문자열을 직접 넘기는 호출자 경로입니다. 문단
  아래·위 간격과 줄 뒤 간격은 CoreText가 다음 줄 슬롯 안에 넣으므로 복원에서 걷어내 상자
  **사이**에 남깁니다(한글도 줄 간격 여분을 상자 아래에 둡니다). 줄 높이가 못박힌
  문단(비율·고정 줄 간격, 실물의 대부분)은 모든 슬롯이 같은 높이라 청크 첫 줄의 정확값을
  그대로 쓰며 값이 바뀌지 않습니다 — 코퍼스 표본 147쪽 중 두 쪽만 움직이고, 줄마다 상자가
  다른 각주 문단이 개선됩니다(1,030쪽 문서 470쪽 각주의 |오차| 합 2.58 → 1.96pt).

  **강제 줄 높이 하한은 베이스라인 아래 몫의 바닥을 세웁니다** — 줄 슬롯은 하한보다 짧을 수
  없으므로 아래 몫도 `하한 − 그 줄 ascent`보다 작을 수 없습니다. CoreText가 **양쪽 정렬** 줄의
  지표에 강제 줄 높이를 적용하기 **전** descent를 담기 때문에 이 바닥이 필요합니다(하한 20pt·
  10pt 글자에서 보고 2.2998, 실제 배치 6.0) — 한글 문단은 기본이 양쪽 정렬이라 실물이 이
  조건입니다. 하한이 걸린 줄은 슬롯이 정확히 하한이라 이 바닥이 정확값이고, 걸리지 않은 줄은
  보고값이 이미 배치값이라 큰 쪽을 고르면 됩니다. 그래서 줄마다 상자가 다른 문단에서도(하한이
  걸린 양쪽 정렬 줄 뒤에 큰 글자가 오는 문단) 앞 줄 간격이 정확히 하한으로 남고, 조판 프레임을
  어떻게 나눠도 같은 자리에 그려집니다.

  복원식의 입력도 실측으로 고쳤습니다. 슬롯의 베이스라인 **아래** 몫은 CoreText가 돌려주는
  **descent**이고 **leading은 아닙니다** — CoreText는 글꼴 leading을 베이스라인 위(다음 줄
  몫)에 넣습니다. leading이 있는 글꼴 네 개 × 강제 줄 높이 다섯 종 20조합에서 실측값이 전부
  descent와 같았고 `descent + leading`과는 전부 달랐습니다. 실물에 영향이 있습니다 — Times
  New Roman(0.42pt)·Arial(0.33pt)이 leading을 갖고, 결정론 폰트 리졸버의 캐스케이드 멤버인
  Hiragino Sans는 5.0pt입니다. 또 줄 뒤 간격은 `minimumLineSpacing`·`maximumLineSpacing`에
  갇힌 **유효 간격**을 씁니다 — 상한 4에 줄 뒤 간격 4와 10을 준 두 문단은 CoreText에서 같은
  자리에 조판되는데, 원시 값을 그대로 쓰던 동안에는 그 둘을 6pt 다르게 그렸습니다(공개
  `HwpPaintCommand.drawText` 호출자 경로). 한글 문서에서 나오는 글꼴은 leading이 0이고
  줄 간격 상한은 못박힌 문단에만 걸리므로 픽스처·코퍼스 렌더는 바뀌지 않습니다. 음수 값은
  모두 0에서 끊습니다 — 상한이 줄 높이를 깎으면 CoreText가 descent를 음수로 돌려주고, 음수
  문단 간격은 CoreText가 무시하며, 음수 줄 간격은 줄 상자에 이미 반영돼 있습니다. 줄 높이가
  못박혔는지도 **블록 안 모든 줄**에 대해 봅니다 — 한 블록에 문단이 둘 이상 들어갈 수 있고
  뒤 문단이 다른 높이로 못박으면 앞 문단의 값을 쓸 수 없습니다.

  한글 실물의 PrvImage를 오라클로 쓰는 정합성 측정(34개 픽스처)은 **17개 개선·15개
  불변·2개 악화**로 합계 MAE가 0.0520에서 0.0499로 내려갔습니다. 악화한 둘은 이 수정이
  가려져 있던 다른 축의 격차를 제 크기로 드러낸 것입니다 — `noori`(0.0164 → 0.0183)는
  1쪽을 채우는 제목 글상자·표 안 텍스트의 세로 위치(#193, 글상자 −5.35pt),
  `track-changes`(0.0002 → 0.0003)는 MS Word 호환 문서의 줄 상자 모델(#194, 글꼴 줄
  높이·ascent 기반)입니다. 두 축 모두 수정 전에도 틀려 있었고(각각 −3.75pt·−2.86pt),
  본문 베이스라인이 반대 방향으로 2pt 틀려 절반쯤 상쇄되던 것입니다. 줄 **전진량**
  축은 별도 이슈(#180, #192)에 있습니다.
- **'글자 아래' 밑줄이 한글보다 낮게, 장식선이 큰 글자에서 가늘게 그려지던 것을
  바로잡았습니다** (#176). 밑줄 중심을 베이스라인 아래 글자 크기의 0.20배에 두던
  것을 한컴오피스 한글 12.30이 내보낸 PDF 실측값 **0.17배**로 옮겼습니다 — 5~100pt
  13개 크기와 함초롬바탕·함초롬돋움·Apple SD 산돌고딕 Neo·HY울릉도M 네 글꼴에서
  전부 같은 값이라 글꼴 지표가 아니라 글자 크기 비례입니다. 밑줄·취소선·'글자 위'
  밑줄의 두께는 0.4pt 고정에서 **글자 크기의 0.04배**로 바뀌어(한글 PDF의 선 폭
  `0.12pt × round(크기/3)`은 13개 크기 전부 0.04em을 0.12pt 장치 단위로 반올림한
  값입니다) 40pt 글자의 선이 종전의 4배 굵기인 1.6pt로 그려집니다. 변경 내용 추적 삽입 밑줄은 0.75pt 사각형의 아래 모서리를
  0.35배에 두어 중심이 크기에 비례하지 않던 것을 중심 0.26배·두께 0.064배로 고쳤습니다.
  상수는 `HwpRenderTuning.Text`(`underlineBelowCenterRatio`·
  `decorationLineThicknessRatio`·`trackChangeInsertUnderlineCenterRatio`·
  `trackChangeInsertUnderlineThicknessRatio`)에 실측 근거와 함께 있습니다.

  같은 실측에서 변경 내용 추적 표시선의 위치가 변경 추적 고유의 값이 아니라 **MS
  Word 호환 문서**(`track-changes` 픽스처의 호환 문서 대상 프로그램 2)의 글꼴 지표
  기반 기하라는 것을 확인했습니다 — 네이티브 문서에서 한글은 삽입 밑줄·삭제선을
  일반 밑줄·취소선과 같은 자리에 그립니다. 호환 모드 분기는 #187에서 다룹니다.
- **HWPX 구역 시작 종류의 홀수쪽·짝수쪽이 한글이 저장하는 값으로 읽힙니다** (#173).
  `hp:startNum@pageStartsOn`의 `ODD`·`EVEN`을 구역 정의 속성(표 130 bits 20-21)으로
  옮길 때 스펙이 값을 적지 않은 이 자리에 `ODD`를 1, `EVEN`을 2로 가정해 읽었는데,
  한글 12.30.0이 저장한 HWP는 홀수가 `0x200000`(2), 짝수가 `0x100000`(1)이라 같은
  문서를 HWP로 열 때와 HWPX로 열 때 두 값이 서로 바뀌어 파싱됐습니다. 한컴 공개
  OWPML 모델의 직렬화 표(`STARTNUMSTARTONTYPE`: BOTH 0 · EVEN 1 · ODD 2)도 같은 값이라
  매핑을 바로잡았습니다. 지금은 조판이 이 값을 읽지 않아 그리는 결과는 같지만, 두
  포맷의 파싱 결과가 달랐고 홀수·짝수 시작을 반영할 때 반대로 해석될 값이었습니다.
  한글.app이 저장한 `section-page-starts-on` 쌍(구역 4개 — 이어서·홀수·짝수·사용자
  시작 번호 5)을 HWP·HWPX 픽스처로 추가하고, 포맷 등가 비교에 구역 시작 종류·시작
  번호·첫 쪽 감추기 축(`sectionSettings`)을 더해 이 값이 어긋나면 등식이 깨지도록
  했습니다 — 종전 비교는 구역 정의에서 용지·여백·개요 번호 참조·주석 모양만 보고
  속성 bit field와 시작 번호는 보지 않아 이 격차를 통과시켰습니다. 같은 실측에서
  한글 12.30.0 macOS는 홀수·짝수 시작 때문에 빈 쪽을 끼우지 않고 새 구역 첫 쪽의
  번호만 건너뛴다는 것(물리 4쪽에 쪽 번호 1·3·4·5, PDF 내보내기도 4쪽)을
  확인했습니다.
- **쪽·단·표 행 경계로 나뉜 문단 조각이 측정한 줄 수 그대로 그려집니다** (#166).
  문단을 나눈 조각의 높이는 문단 전체를 잰 줄 전진량에서 오는데, 렌더러는 잘라낸
  문자열에 문단 단위 한 줄 넘침 허용 규칙(자연 폭이 단 폭의 1.06배 이내면 줄바꿈
  없이 한 줄)을 다시 적용해, 문단 전체로는 접히지 않던 두 줄이 조각만으로는 한 줄로
  접혀 조각 아래에 줄 하나만큼 빈 공간이 남았습니다. 이제 측정한 줄 높이로 놓이는
  조각(쪽·단 경계 흐름 분할·표 행 분할·다단 균형 재배치)에 조각 표식을 달아 렌더러와
  조각 재측정이 그 규칙을 건너뛰고 측정한 줄바꿈을 그대로 그립니다. 한글.app 12.30이
  같은 합성 문서(305pt 폭에 `가` 311자, 쪽에 걸친 뒤 조각 31자 + 1자)를 내보낸 PDF와
  대조해 둘째 쪽의 줄 수(두 줄)와 줄 피치(16pt)·다음 문단의 자리가 같음을
  확인했습니다. 표식은 함수가 아니라 높이 출처로 판정합니다 — 한글이 저장한 높이를
  따르는 조각(저장본 줄 캐시 분할·다단 캐시 run·각주 이어짐, 그리고 세 경로에서도
  줄 캐시가 유효한 문단의 마지막 줄을 담은 조각)과 한 줄 조각은 종전 배치를 유지하고,
  폭이 다른 단으로 옮겨진 측정 높이 조각은 그 단 폭으로 다시 재어 조각 높이·줄 수·줄 안
  개체 앵커가 그 줄바꿈의 것입니다 — 종전에는 좁은 단에서 잰 조각이 넓은 단에서 줄이
  합쳐져 상자 아래가 비고, 넓은 단에서 잰 조각이 좁은 단에서 줄이 늘어 상자를 넘쳤습니다.
  캐시 높이 문단의 조각만 잰 폭 그대로 놓이며, 그때 좁은 단은 폭 허용 오차 없이 실제로
  줄바꿈해 그려지는 줄이 측정 줄 수를 넘지 않을 때만 표식을 답니다.
- **각주가 본문과 겹치지 않고 한글처럼 다음 쪽으로 이어집니다** (#165). 저장본의
  줄 위치를 따르는 문서(절대 캐시 모드)에서 한 쪽의 각주가 본문 아래 남은 자리보다
  크면 그 쪽에 전부 쌓아 본문 위에 그려졌습니다 — 헌법주석(1,030쪽)에서 366쪽이
  겹쳤고 최대 353pt까지 덮였습니다. 한글 12.30이 내보낸 같은 문서의 PDF를 쪽마다
  대조해 규칙을 확정했습니다: 각주 스택은 본문 마지막 줄 상자 아래에 바닥 정렬되고,
  통째로 안 들어가는 각주는 줄 캐시에 저장된 분할 지점에서 나뉘어 나머지가 다음 쪽
  첫 각주로 이어지며(구분선은 다시, 번호는 반복하지 않고 이어지는 줄은 내어쓰기
  자리), 분할 지점이 없으면 통째로 다음 쪽으로 갑니다. 각주 사이 여백은 앞 각주
  마지막 줄의 줄 간격을 대체하고 구분선 굵기는 자리에 세지 않아 스택 높이도 한글과
  같아졌습니다(사이 피치 11.83pt). 그 결과 겹침이 0쪽이 되고 쪽수는 1,030 그대로이며,
  각주가 이어져 시작하는 쪽 64곳이 한글과 같습니다. 같은 조사에서 폰트 대체로 각주
  참조가 한글보다 한 쪽 늦게 귀속되던 문단 21곳도 저장본의 절단 위치를 따르게
  했습니다 — 늦은 귀속은 이어짐과 만나 뒤 쪽으로 연쇄해 한글에 없는 쪽을 만들었습니다.

  같은 작업에서 **다각형·곡선 개체의 점 개수 필드를 4바이트로 읽도록 고쳤습니다**.
  스펙 표 99·103은 2바이트로 적었지만 실제 저장본(hwplib도 같습니다)은 4바이트라,
  헌법주석 162쪽의 2.83pt짜리 대각선 표시가 둘째 점 좌표를 잘못 읽어 쪽 전체를
  가로지르는 선으로 그려졌습니다. 각주 자리를 개체가 실제로 칠하는 범위로 재게 되면서
  그 선이 각주 34·35를 다음 쪽으로 밀어내 드러났습니다.
- **쪽에 걸친 문단의 글자처럼 취급 표·개체가 다음 문단과 겹치지 않습니다** (#164).
  한 문단이 두 쪽에 갈릴 때 앞 조각의 줄 안에 있던 표는 앞 쪽이 확정된 뒤에 방출돼
  줄 앵커를 잃고 마지막 조각 아래 흐름 위치로 갔고, 저장본의 줄 위치를 따르는
  문서에서는 다음 문단이 그 자리에 놓여 표와 겹쳤습니다 — 헌법주석 667쪽의 인용
  표 세 개가 `가. 보상기준` 제목과 겹쳐 보였습니다. 이제 쪽·단에 걸친 문단의 각
  조각이 자기 줄 프레임을 조각 기준으로 갖고, 그 줄에 앵커가 있는 글자처럼 취급
  표·개체를 그 조각의 쪽·단이 확정되기 전에 줄 안 자리에 놓습니다 (저장본 줄 캐시
  분할·흐름 분할·다단 캐시 run 세 경로 공통). 앵커가 없는 컨트롤, 자리 차지·글
  앞뒤 개체, 안에 각주를 품은 개체, 줄 안에 놓을 수 없어 흐름으로 가는 개체는
  종전대로 마지막 조각 뒤에 한 번만 방출됩니다. 같은 조사에서 드러난 인접 결함
  셋도 고쳤습니다 — 줄 안에 놓인 표의 셀 각주가 통째로 빠지던 것(띠·세그먼트
  경로처럼 표가 그려지는 쪽에 담습니다), 라인 캐시 없는 문단을 쪽·단으로 나눌 때
  큰 줄 안 개체로 시작하는 뒤 조각이 그 개체 높이만큼 짧게 재어져 다음 문단이 개체
  위에 놓이던 것, 조각이 혼자서는 한 줄에 들어가 렌더러가 한 줄로 그리는데 개체는
  둘째 줄 자리에 놓이던 것입니다. 폭이 다른 단으로 이월된 조각(비등폭 단)은 렌더러가
  그 단 폭으로 다시 줄바꿈하는 것과 같게 목적 단 폭으로 다시 조판한 줄에서 앵커를
  찾고, 한 줄로 접힌 조각의 앵커는 가운데·오른쪽 정렬의 가로 오프셋을 렌더러와 같이
  반영합니다 — 다시 조판한 결과가 이미 한 줄이어도 같은 오프셋을 얹어, 오른쪽 정렬
  조각의 표가 단 오른쪽 경계를 넘지 않습니다. 크기 기준이 '단'·'문단'인 개체는 예약
  폭도 목적 단으로 다시 풀어, 좁은 단에서 넓은 단으로 이월된 단 너비 50% 개체가 절반만
  예약한 채 두 배로 그려져 뒤 글자를 덮던 것을 막습니다 — 잇달아 놓인 개체도 각자 자기
  크기로 예약합니다. 각주 번호를 쪽마다 새로 시작하는 문서에서 조각의 참조 번호가 다시
  쓰여 폭이 달라지면(10) → 9)) 그 뒤의 개체도 함께 옮겨 놓습니다. 키 큰 개체가 있는 줄
  바로 앞의 평범한 줄은 그 개체 줄로 가는 간격이 아니라 자기 몫만 차지하므로, 쪽·단이
  그 줄만큼 비지 않습니다. 앞 조각과 함께 놓인 미지원 개체의 진단 쪽 번호도 실제로
  그려진 쪽을 가리킵니다 — 그 개체 안에 있더라도 문단 끝 흐름으로 나가는 중첩 컨트롤은
  그 폴백이 놓인 쪽으로 보고합니다. 문단이 통째로 다음 단으로 옮겨 갈 때 문단 위 간격을
  유지할지도 같은 기준으로 재어, 개체 줄을 품은 문단이 새 단 맨 위에 붙지 않습니다.
- **Shift+Enter로 나눈 줄 끝에 조판 부호가 그려지던 것을 바로잡았습니다** (#146).
  한 줄 끝 코드 10(U+000A)은 줄 나눔이라 조판 문자열에 남겨야 하는데, 종전에는 그
  글자가 글자 모양의 **영문 글꼴**로 조판돼 그 글꼴이 U+000A에 획 있는 글리프를 가진
  HY 계열(HY울릉도M·HYnamM 등, 한컴오피스 번들 폰트 모드 `HWP_HANCOM_FONTS=1`)에서
  줄 끝마다 아래로 꺾인 부호가 보였습니다. 이제 한 줄 끝은 글리프를 그리지 않는 표식
  run으로 조판되고 글꼴도 직전 글자의 슬롯을 물려받아, 본문과 다른 글꼴이 줄에
  섞이면서 줄 높이를 바꾸는 일도 없습니다(#137이 문단 끝에서 고친 것과 같은 축).
  줄 나눔·줄 폭·정렬·복사·낭독은 그대로입니다. 한컴오피스 한글 12.30이 저장한
  줄 캐시와 PDF로 대조해, 줄 끝에 남던 잉크가 사라지고 줄 나눔 뒤 줄 간격이 한글과
  같은 값(글자 크기 15pt·160%에서 24pt)이 되는 것을 확인했습니다.

  같은 변경에서 **그림자·양각·글자 위치가 걸린 줄의 장평이 풀리던 것을 바로잡았습니다.**
  이런 줄은 run 단위로 그리는데 CoreText의 `CTRunDraw`가 run의 텍스트 매트릭스
  (장평·기울임 근사)를 적용하지 않아, 장평 95% 글꼴이 그 줄에서만 본래 폭으로
  그려졌습니다(잉크 +8.5%). 이제 매트릭스를 직접 적용해 CTLineDraw로 그린 줄과
  픽셀이 같습니다.
- **취소선이 글자 가운데보다 낮게 그려지던 것을 바로잡았습니다** (#136). 종전에는
  선을 폰트의 x-height 절반 높이에 그렸는데, 그 값은 라틴 글자를 기준으로 한
  위치라 한글 글리프에서는 아래로 치우쳐 보였습니다. 한컴오피스 한글 12.30이
  직접 내보낸 PDF의 벡터 좌표를 5~100pt에서 재 보면 취소선은 글꼴과 무관하게
  **베이스라인 위 글자 크기의 0.35배**에 놓입니다. 이제 그 비율로 그립니다 —
  같은 문서를 한글에서 열었을 때처럼 선이 글자의 세로 가운데를 지납니다.
  HWP와 HWPX 저장본은 종전에도 지금도 같은 자리에 그려집니다(한글 자신도
  두 포맷을 같은 자리에 그린다는 것을 같은 PDF 실측으로 확인했습니다).
  변경 내용 추적의 삭제선은 `track-changes` 문서에서 한글이 조금 낮게(0.29배)
  그리므로 분리했습니다 — 이 값이 변경 추적 고유의 것이 아니라 MS Word 호환 문서의
  기하라는 것은 #176에서 확인했습니다(위 항목).

  같은 실측에서 **밑줄 종류 '글자 위'(#149의 raw 3)를 실제로 그리기 시작합니다** —
  베이스라인 위 글자 크기의 0.87배입니다. 종전에는 파싱만 하고 선을 그리지 않아
  `underline-above` 문서에서 밑줄이 통째로 빠졌습니다. 밑줄 종류 '글자 가운데'
  (raw 2)는 취소선과 같은 한 줄로 그립니다 — 한글은 두 값이 함께 켜져 있어도 선을
  하나만 그리고 그때 색은 밑줄 색을 씁니다.

- **자리 차지 표를 품은 문단의 글줄이 표 위에 놓이던 것을 바로잡았습니다** (#161).
  한컴오피스 한글 12.30은 세로 기준이 '문단'인 자리 차지(위·아래 배치) 표를 그 문단의
  글줄 **앞**에 두고 문단 줄을 표 높이 + 바깥 여백만큼 내리는데, 종전에는 문단 글줄을
  먼저 놓고 표를 그 뒤에 방출했습니다. 문단 위치가 줄 캐시로 고정된 문서에서는 그
  자리가 이미 다음 문단의 자리라, 표와 다음 문단이 같은 y에서 시작해 글자가 통째로
  겹쳐 읽히지 않았습니다(`numbering-sequence` 3쪽: 12.82pt × 419.54pt). 이제 저장본이
  비워 둔 띠를 찾아 그 자리에 놓습니다 — 한글.app이 직접 저장한 PDF와 대조해 표 위치가
  0.3pt 안에서 일치합니다. 판정은 캐시로 배치된 문단에만 걸리므로 한/글 2007 계열
  저장본(표를 글줄 뒤에 두는 문서)의 배치는 그대로입니다.

- **HWPX 선 모양 이름 네 개를 한컴 공개 모델의 직렬화 이름으로 바로잡았습니다.**
  밑줄·취소선·각주 구분선이 공유하는 OWPML `LINETYPE2`의 3D 넷은 `THICK3D`·
  `THICKREV3D`·`3D`·`REV3D`인데 종전에는 표에 없는 이름을 써서, 그 값을 담은 문서의
  선 종류가 조용히 "없음"으로 파싱됐습니다. 각주 다단 배열의 셋째 값
  (`RIGHT_MOST_COLUMN`)도 같은 이유로 바로잡았습니다.
- **HWPX 밑줄·취소선 모양과 테두리·구분선 종류가 한글이 저장하는 값으로 읽힙니다**
  (#177). OWPML `LINETYPE2` 이름표 하나를 밑줄·취소선(`hh:underline@shape`·
  `hh:strikeout@shape`), 표 테두리(`hh:borderFill`), 각주·미주 구분선(`hp:noteLine`),
  단 구분선(`hp:colLine`)이 함께 쓰는데, HWP5 바이너리는 자리마다 값의 기준이 달라
  같은 문서를 HWP로 열 때와 HWPX로 열 때 값이 어긋났습니다 — 글자선은 표 전체가 한 칸
  밀려 실선(`SOLID`)이 HWP 0 대신 1로 파싱됐고, 테두리·구분선은 `DOT`·`DASH`가 서로
  바뀌어 파싱됐습니다. 한컴오피스
  한글 12.30이 같은 편집 세션에서 저장한 `line-shapes` 쌍(17종을 네 자리에 모두 실은
  문서)으로 확정한 값은 글자선이 `LINETYPE2 - 1`(실선 0 · DOT 1 · DASH 2 · … · 3D 15,
  4비트를 넘치는 `REV3D`는 한글처럼 실선으로 접음), 테두리·대각선·구분선이
  `LINETYPE2` 그대로(실선 1 · DOT 2 · DASH 3 · … · REV3D 17)입니다. 한글은 `DOT`를 긴
  점선(파선)으로, `DASH`를 점선으로 그리므로 이름의 뜻이 아니라 열거 순서를 따릅니다.
  지금은 조판이 표 셀 테두리의 2중선 판정 외에는 선 모양을 읽지 않아 그리는 결과는
  같지만, `HwpCharShapeProperty`의
  `underlineShape`·`strikethroughShape`와 `HwpBorderFill.borderType`이 HWPX 문서에서
  HWP와 같은 값이 됩니다. 테두리/배경의 대각선(`hh:diagonal`) 종류·굵기·색도 함께
  옮깁니다 — 한글은 대각선을 긋지 않는 기본 테두리/배경에도 실선(1)을 저장합니다.
  포맷 등가 비교에 밑줄·취소선 모양과 표 셀 테두리(`cellBorders`)·단 구분선
  (`columnDividers`) 축을 더해 이 값이 어긋나면 등식이 깨지도록 했습니다 — 종전
  비교는 밑줄 종류·취소선 여부와 셀 수·병합만 봐서 이 격차를 통과시켰습니다.

### Breaking Changes

- **`HwpDrawnTextLayout.baselineLift(of line:)`이 `baselineAnchor(of line:)`으로
  바뀌었습니다** (#178). 종전 함수는 CoreText가 준 줄 ascent에서 빼야 하는 보정량을
  돌려줬는데, 세로 배치가 더 이상 ascent를 쓰지 않아 그 값에 의미가 없습니다. 새 함수는
  **줄 상자 상단에서 베이스라인까지의 거리**를 돌려줍니다. 커스텀 렌더러를 직접
  구현하는 경우에만 영향이 있습니다 — `HwpPaintCommand.drawText`를 그리는 코드는
  `HwpDrawnTextLayout.lines(attributedString:origin:lineWidth:)`가 주는
  `baselineOrigin`을 그대로 쓰면 되고 그 API는 그대로입니다.

- **`HwpUnderlineType`의 raw 값을 HWP 5.0 스펙(표 33)에 맞췄습니다** (#149).
  한글.app은 글자 모양 › 밑줄 위치 '위쪽'을 밑줄 종류 **3**으로 저장하는데
  종전 enum은 `above = 2`뿐이라 그런 문서는 DocInfo 파싱이
  `HwpError.invalidRawValueForEnum`으로 끝나 문서 전체가 열리지 않았고, 뷰어
  옵션(`HwpLoadOptions.viewer`)의 부분 복구도 DocInfo에는 미치지 않아 살아나지
  않았습니다. 이제 `above`의 raw 값이 3이고, 스펙 표가 빠뜨린 2는 새 케이스
  `center`(글자 가운데)입니다 — 한컴 공개 OWPML 모델의 `ULT_CENTER`가 정본이고,
  `CharShape` 픽스처의 취소선 견본이 이 값을 취소선 비트와 함께 갖습니다(#136).
  HWPX `<hh:underline type="TOP"/>`은 계속 `.above`로, `type="CENTER"`는
  `.center`로 매핑되며 합성 `rawValue`의 bit 2~3도 스펙 값 3이 됩니다.
  `above.rawValue`를 숫자 2로 대조하던 코드와 `default` 없이 모든 케이스를
  나열한 `switch`는 수정이 필요합니다. 글자 위 밑줄과 취소선의 선 위치는
  #136에서 실측해 그립니다.

### Changed

- **표 셀의 저장 높이가 줄 캐시보다 작아도 행이 접히지 않습니다** (#160). 셀 문단
  전부가 줄 캐시로 측정된 셀은 저장된 셀 높이(표 80)를 신뢰하는데, 한컴오피스
  한글 12.30 macOS는 `표 만들기`로 만든 셀의 높이를 내용과 무관하게 위아래 안쪽
  여백 합(282 HWPUNIT)으로 저장해 행이 2.82pt로 접히고 셀 글자가 표 밖으로
  벗어나 다음 문단과 겹쳤습니다(`numbering-sequence` 3쪽 HWP·HWPX). 이제 저장
  높이가 줄 캐시로 잰 셀 문단 높이를 쌓은 값에서 마지막 줄의 줄 간격을 뺀 높이
  (마지막 줄 상자의 아래)에 위아래 여백을 더한 값보다 작으면 그 값으로 올립니다 —
  한글.app 화면 실측 12.81pt와 0.01pt 차이인 12.82pt. 줄 간격까지 포함한 캐시 높이를 경계로 삼지 않아
  저장 높이가 그보다 살짝 아래인 정상 셀(헌법주석 25개·noori 8개)은 그대로이고,
  헌법주석의 글자처럼 취급 표 3개(저장 1000 < 두 줄 1108 HWPUNIT)만 11.08pt로
  커지며 쪽 나눔(1,030쪽)은 변하지 않습니다.
- **개요 번호 문단 머리의 미지원 진단이 구역 정의의 참조를 따릅니다** (#152).
  종전 진단은 문단 모양의 번호 참조(`numberingOrBulletId > 0`)만 봐서, 그 값이
  전부 0인 실문서의 개요 문단(헌법주석 1,944개)을 한 건도 보고하지 못했습니다.
  이제 개요(문단 머리 종류 1)는 구역 정의의 `numberParaShapeId`, 번호 매기기
  (종류 2)는 문단 모양의 참조로 정의를 찾아 문단마다 "개요 번호 문단 머리
  (미렌더)"·"번호 매기기 문단 머리 (미렌더)"를 냅니다. 참조가 0이면 "(번호 정의
  참조 없음)", 정의 배열 밖이면 "(없는 번호 정의 N 참조)"로 그 사실을 적습니다.
  라벨을 그리는 #154 뒤에는 번호를 만든 문단이 이 진단에서 빠지므로 "(미렌더)"는
  순회 상한·취소로 번호가 없는 문단에만 남습니다.
- **선택이 지난 문단 경계의 개행이 복사에 남습니다**. 문단 끝 코드가 조판
  문자열에서 빠진 뒤(#137) 끝점이 다음 문단의 시작이면 그 단위를 제외해, A 문단
  시작에서 B 문단 시작까지 고르면 `A\n` 대신 `A`가, 문단 부호만 고르면 빈 문자열이
  복사됐습니다. 이제 선택이 닿은 단위는 글자가 없어도 조각으로 실려 지나온 문단
  경계마다 개행이 나오고, 그 개행은 앞 문단의 문단 스타일·글꼴을 입습니다 —
  한글.app과 같이 A 시작→B 시작은 `A\n`, 문단 부호만은 `\n`, A 끝→B 중간은
  `\nB…`입니다. 평문과 RTF 복사가 함께 바뀝니다.
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
