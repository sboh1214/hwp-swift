# 프로젝트 지식 베이스

**Branch:** feat/pdf-export-print

## 개요

한글과컴퓨터의 한글 문서 파일(`.hwp`)을 파싱하고 렌더링하는 Swift package.
HWP 파일은 OLE compound document이며, 그 안의 stream들은 record tree 구조로
인코딩되어 있다. Swift 5.9+, macOS 14+/iOS 17+, LGPL.

**4개 library target**:
- `CoreHwp` — 파서 (read-only, binary HWP → typed model)
- `HwpKitCore` — 렌더 코어 (platform-neutral, CoreGraphics/CoreText/Foundation only)
- `HwpKitNative` — 플랫폼 브릿지 (AppKit + UIKit)
- `HwpKit` — SwiftUI 공개 API + PDF 내보내기

## 구조

```
hwp-swift/
├── Sources/CoreHwp/       # 파서
├── Sources/HwpKitCore/    # 렌더 코어 — 파이프라인/모델/paint list (AGENTS.md 참조)
├── Sources/HwpKitNative/  # 플랫폼 브릿지 — CALayer/View (AGENTS.md 참조)
├── Sources/HwpKit/        # SwiftUI 공개 API + PDF 내보내기 (AGENTS.md 참조)
├── Tests/{CoreHwp,HwpKitCore,HwpKitNative,HwpKit}Tests/
├── Sample/                # HwpSwiftSample.xcodeproj (xcodegen, path: ..)
├── Package.swift          # swift-tools-version:5.9
├── .github/workflows/     # ci.yml, cd.yml
└── .github/pages/         # DocC 사이트 루트 랜딩
```

폴더명과 파일명은 **공백 없는 PascalCase**를 사용한다 (예:
`CtrlHeader/`, `DocumentProperties/`, `IdMappings/`). 한컴 공개 문서의
절 제목은 public doc-comment와 문서 설명에서 보존하고, 실제 경로명에서는
공백을 제거한다.

## 어디를 볼 것인가

| 작업 | 위치 |
|------|------|
| 새 stream 파서 추가 | `Sources/CoreHwp/Streams/` + `HwpFile.init(fromOLE:)`에 등록 |
| 새 record 태그 추가 | `Sources/CoreHwp/Enums/Hwp{DocInfo,Section}Tag.swift` |
| 새 컨트롤 ID 추가 | `Sources/CoreHwp/Enums/CtrlId/` + `Models/Section/CtrlHeader/` + `HwpCtrlId` enum |
| 새 모델 추가 | `Sources/CoreHwp/Models/...` 하위에 `Utils/Protocols/`의 프로토콜을 채택하여 작성 |
| 기본 타입 확장 | `Sources/CoreHwp/Utils/Extensions/` |
| 테스트 픽스처 추가 | 테스트 파일과 같은 폴더에 `.hwp` 배치 (`openHwp(#file, "name")` 사용) |

## 코드 맵

| 심볼 | 위치 | 역할 |
|------|------|------|
| `HwpFile` | [HwpFile.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/HwpFile.swift) | 유일한 public 진입점: `init(fromPath:)`/`init(fromData:)`/`init(fromWrapper:)` (각각 `readLimits:` 또는 `options:` 오버로드), `init()` |
| `HwpLoadOptions` | [HwpLoadOptions.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/HwpLoadOptions.swift) | `readLimits` + `preserveRawPayload`(기본 true). `.viewer` 프리셋은 rawPayload 보존을 꺼 압축 해제 버퍼를 파싱 후 즉시 해제 (뷰어 상주 메모리 대폭 절감) |
| `HwpError` | [HwpError.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/HwpError.swift) | `CustomStringConvertible` + `LocalizedError`를 채택한 public error enum |
| `HwpStreamName` | [Enums/HwpStreamName.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Enums/HwpStreamName.swift) | OLE stream 이름 (`FileHeader`, `DocInfo`, `BodyText`, `\005HwpSummaryInformation`, `PrvText`, `PrvImage`) |
| `parseTreeRecord` | [Utils/HwpRecord.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Utils/HwpRecord.swift) | stream에서 tag/level/size record tree를 구성 |
| `StreamReader` | [Utils/Readers/StreamReader.swift](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Utils/Readers/StreamReader.swift) | OLE → `Data` 변환 (SWCompression으로 deflate 처리) |

## 파싱 파이프라인

```
.hwp 파일
  → OLEFile (OLEKit)              # OLE compound document
  → StreamReader                   # 이름 있는 stream → Data (필요시 deflate)
  → DataReader / BitsReader        # Data 위의 cursor
  → parseTreeRecord (Utils)        # 10-bit tag / 10-bit level / 12-bit size 헤더로 record tree 구성
  → Hwp* 모델 (Models/)            # Hwp{FromData,FromRecord,...} 프로토콜을 통해 디코딩
  → HwpFile (public struct)
```

압축 여부는 `HwpFileHeader.fileProperty.isCompressed`에 있고, 이후 모든
하위 `load` 호출에 인자로 전달된다.

`HwpReadLimits`는 OLE directory의 `streamSize`를 이용해 압축 입력과 비압축
stream을 읽기 전에 제한하고, 압축 해제 결과가 한도를 넘으면 typed
`HwpError.streamSizeLimitExceeded`로 후처리 거부한다. 현재 `SWCompression`
Deflate API는 bounded streaming inflate를 노출하지 않으므로, 압축 해제 결과
한도는 메모리 할당 cap이 아니다. PR/문서에서 decompression-bomb 방어를 설명할 때
이 한계를 명시한다.

per-stream 한도만으로는 유효한 자식이 많은 파일(BodyText·ViewText·BinData)이
집계로 메모리를 고갈시킬 수 있어 **파일 단위 집계 한도**(`maxAggregateStreamBytes`,
기본 1 GiB)를 둔다. `StreamReader`가 모든 read 경로에서 보유 byte를 누적해
초과 시 `HwpError.aggregateStreamSizeLimitExceeded`를 던진다 (오버플로 안전 비교).
ViewText는 optional이라 파싱 실패엔 빈 폴백이지만, 이 두 자원 한도 error는
폴백하지 않고 그대로 전파한다.

byte 한도와 별개로 **레코드 트리 깊이 한도**(`maxNestingDepth`, 기본 64)를 둔다.
위 두 자원 한도와 달리 이것은 **구조 유효성 한도**다 — 이미 읽어 들인 byte를
파싱하는 단계에서 발동하고, 인접한 level jump 가드와 같은
`HwpError.invalidRecordTree`로 보고되며, 따라서 ViewText의 파싱 폴백에도
동일하게 흡수된다(깊게 중첩된 ViewText는 정의상 손상·적대 입력이므로 BodyText
렌더로 폴백하는 것이 맞다). 전파되는 "자원 한도 error 2종"에 이것을 더하지 말 것.
레코드 헤더의 level은 10비트(≤1023)라 스펙만으로는 수백 단계 중첩이 가능한데,
typed 디코더들이 그 트리를 재귀로 내려가므로(표 셀 문단·리스트 컨트롤·글상자
문단·메모) 조작 문서가 catch 불가능한 스택 오버플로를 일으킬 수 있다.
`parseTreeRecord`는 `parentIndex = Int(level)` + 스택 절단/append 방식이라
`record.level == 실제 트리 깊이` 불변식이 성립하고 typed 재귀는 전부 자식
방향으로만 내려가므로, **이 한 지점의 level 가드가 모든 재귀를 함께 상한한다** —
모델에 depth를 부착하거나 `load` 시그니처를 바꿀 필요가 없다. 가드는 payload와
확장 크기를 읽기 **전**에 있어 조작 입력이 할당을 유도하지 못한다. 전 픽스처
실측 최대 level은 5이며, 회귀 테스트가 `maxNestingDepth: 8`로 이를 잠근다.

## 컨벤션

- **`HwpPrimitive = Codable & Hashable & Sendable`** — 모든 모델이 채택 (typealias는 [`HwpPrimitive.swift`](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Utils/Protocols/HwpPrimitive.swift)). 전 모델이 값 타입이라 `Sendable`은 자동 충족 — 백그라운드 파싱 → UI 전달이 컴파일러 검증된다.
- [`Utils/Protocols/`](file:///Users/sboh/Repos/hwp-swift/Sources/CoreHwp/Utils/Protocols/)의 **loader 프로토콜**은 `static load(...)`를 default 구현으로 제공하며 EOF를 강제한다 — reader에 잔여 byte가 있으면 `HwpError.bytesAreNotEOF`를 throw. 채택 측은 `init(_ reader: inout DataReader, ...)`만 작성.
- public 타입의 **한국어 doc-comment**는 한컴 공개 문서의 절을 참조한다. 편집 시 보존할 것.
- **`Tests/` 외부에서 `import XCTest` 금지.**
- **SwiftFormat** (`--swiftversion 5.9 --disable hoistTry`)과 **SwiftLint**가 CI 및 `pre-commit`에서 강제됨.

## 안티 패턴 (이 프로젝트 한정)

- 테스트에서 `XCTAssert*` 사용 — SwiftLint custom rule `no_xctassert` (severity: error)로 금지. Nimble `expect(...) == ...` 사용.
- EOF를 검사하지 않고 silent하게 byte 잔여 — loader 프로토콜의 `load`가 `bytesAreNotEOF`를 throw하도록 설계되어 있으므로, manual `init` 호출로 우회 금지.
- 공백이 있는 새 파일/디렉터리명 추가 — 경로명은 PascalCase + 무공백을 유지.
- `Package.swift`의 Darwin platform 최소 버전을 더 낮추기 — 의존성 `SWCompression 4.9.1` / `BitByteData 2.1.0`이 macOS 14+/iOS 17+를 요구한다. Linux는 CoreHwp·CoreHwpTests만 지원한다 (뷰어 타깃은 Apple 전용 프레임워크 의존 — `Package.swift`의 `canImport(Darwin)` 분기; CI matrix: macOS + ubuntu-latest).
- `swift-tools-version` 변경 시 `.swift-version`, `.swiftformat`, **양쪽** `Test-*.yml` matrix 동시 갱신 누락 (`CONTRIBUTING.md` 참조).
- 테스트에서 **CoreFoundation 타입에 `as!`** 쓰기 — SwiftFormat의 `noForceUnwrapInTests`가 이를 `try XCTUnwrap(... as? CFType)`으로 자동 변환하는데, CF 타입 대상 `as?`는 컴파일러가 "항상 성공한다"며 **에러**로 막는다. 즉 포매터가 컴파일 불가능한 코드를 만들어 낸다. `// swiftformat:disable:next` 주석도 듣지 않으므로, 캐스트 자체를 없애 우회한다 (컴파일러 note가 제안하는 방식):
  ```swift
  let ref = value as CFTypeRef
  if CFGetTypeID(ref) == CTParagraphStyleGetTypeID() {
      let style = unsafeBitCast(ref, to: CTParagraphStyle.self)
  }
  ```
  타입을 실제로 검사하므로 `as!`보다 안전하기도 하다. CoreText 객체 (CTFont/CTLine/CTParagraphStyle)를 `Any`로 받아 오는 테스트 코드에서 재발하기 쉽다.
- **폰트 바이너리 커밋** (`.ttf`/`.otf`/`.ttc`/`.woff`/`.woff2`) — 이 라이브러리는 폰트를 동봉하지 않는다 (README "폰트"). 세 겹으로 막혀 있다: `.gitignore` 확장자 패턴 → pre-commit 훅 `no-font-binaries` (`git add -f` 차단) → CI lint job의 `No font binaries` (훅 미설치 기여자·웹 UI 업로드 차단). 오픈 라이선스 폰트를 의도적으로 동봉하려면 `.gitignore`의 `!` 예외만으로는 안 된다 — 훅과 CI는 확장자만 보고 거부하므로 세 곳이 같은 예외 목록을 공유하도록 함께 고쳐야 한다. 한 번 커밋되면 history에 영구히 남으니 그 전에 라이선스를 확인할 것.

## 명령어

```bash
swift build                                    # 빌드
swift test                                     # 테스트 실행
swift test --enable-code-coverage              # 커버리지 (lcov 추출·CoreHwp 95% 게이트는 .github/workflows/ci.yml의 coverage job)
HWP_PERF=1 swift test --filter Performance     # 성능 실측 (N=20,000 합성 + 타이트 임계; 기본은 N=1,000 스모크)
HWP_SNAPSHOT_TESTS=1 swift test --filter "FixtureRenderHash|FixturePreviewFidelity"  # 환경 의존 스위트 (기본 swift test·CI에서는 skip)
HWP_HANCOM_FONTS=1 swift test                  # 한컴오피스 번들 폰트 opt-in (기본 off — README "폰트"). 렌더 해시 기준선이 이 모드용으로 따로 있다
RECORD_RENDER_HASHES=1 swift test --filter FixtureRenderHash     # 렌더 픽셀 해시 기준선 레코딩 (Snapshots/ — gitignore, 이 머신·현재 폰트 모드 전용)
RECORD_BLOCK_SNAPSHOTS=1 swift test --filter FixtureBlockLayout  # 블록 좌표 스냅샷 재생성 (기준선은 커밋 대상 — diff 리뷰 필수)
RECORD_RENDER_GOLDENS=1 swift test --filter FixtureRenderGolden  # 결정론 잉크 그리드 골든 재기록 (기준선은 커밋 대상 — diff 리뷰 필수)
xcodebuild test -scheme Hwp-Swift-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'  # iOS 테스트 (#if os(iOS) 코드는 여기서만 실행)
swiftformat .                                  # 포맷
swiftformat --lint .                           # CI lint 체크
swiftlint                                      # lint
pre-commit install && pre-commit run --all     # hook 설치 + 전체 실행
```

성능 게이트: CI는 스모크 파라미터만 상시 실행 (공유 러너 wall-time 하드
게이트는 flaky). 타이트 임계는 로컬 `HWP_PERF=1`로 확인 — 성능에 닿는
PR은 실측 수치를 커밋 메시지에 기록한다.

## 렌더 가드 4층 (#69·#95)

| 스위트 | 축 | 기준선 | CI |
|--------|-----|--------|-----|
| `FixtureRenderHashSnapshotTests` | 엄격·비이동 (전 픽스처 × 전 페이지 SHA-256) | `Snapshots/` **gitignore** | ✗ opt-in |
| `FixturePreviewFidelityTests` | 정합성 (PrvImage 오라클) — **1쪽뿐** | 소스 상수 임계 | ✗ opt-in |
| `FixtureBlockLayoutSnapshotTests`·`FixtureRenderGoldenTests`·`testPageCountsMatchManifest` | 관대·이동 가능 (좌표·잉크 그리드·페이지 수) | **커밋됨** | ✓ 상시 |
| `FixtureFootnoteOverlapTests` | 성질 (각주 스택 ∩ 본문 = ∅, 각주 ⊆ 종이, 각주 영역 상단 ≥ 본문 상단) | **커밋됨** (소스 상수) | ✓ 상시 |

넷째 줄은 좌표를 기록하지 않고 **성질**을 검사한다 (#95) — 위 셋은 전부 "안
바뀜"만 증명해서, 각주가 본문을 덮는 렌더가 헌법주석 362쪽에서 기준선으로 굳어
있어도 아무도 빨개지지 않았다. 겹침은 아직 0이 아니라 **예산**이라 (한글 각주
이어짐 미구현 — `Sources/HwpKitCore/AGENTS.md`) 개선하면 상한을 함께 낮춰야
한다. 쪽수 하나로는 오독한다 — #95는 362 → 368쪽으로 **늘리면서** 총 침범을
14,707 → 6,917pt로 줄였다 (각주가 제 페이지로 돌아와 집계 대상 페이지는 늘고,
마지막 조각에 몰렸던 스택은 흩어진다). 그래서 예산이 쪽수·총 침범·최대 침범
세 축이다. 각주 영역 **상단**이 본문 상단 위로 올라가지 않는 것과 각주가
**종이 밖으로** 나가지 않는 것은 예산이 아니라 불변식(0)이다. 두 경계는 블록
프레임이 아니라 **그려지는 범위**(프레임 ∪ 자손 개체 rect, 페인트와 같은
walker로 받는다)로 잰다 — 오버레이 개체는 블록을 키우지 않고 그려져 프레임만
보면 종이를 넘는 자손을 놓친다.

프레임 **하단**은 다르다 — 거기는 빚이다 (헌법주석 1쪽·최대 3.5pt). 스택이
콘텐츠 높이를 넘을 때 상단 클램프가 초과분을 아래로 밀어내 아래 여백을 그만큼
침범하기 때문이다. 자르면 각주가 사라지고 강제 이월은 한글에 없는 페이지를
만들므로 (1,030 → 1,035쪽), 각주 이어짐을 구현하기 전까지는 남는다. **문서가
불변식이라고 적은 것을 가드가 절반만 검사하면 그 절반은 없는 것과 같다** —
#95 리뷰가 이 구멍을 상단만 보던 가드에서 찾아냈다.

**예산을 올려도 되는 경우는 하나뿐이다** — 정합성 수정이 총량을 늘릴 때. #95
리뷰 반영(조각 경계를 그려진 슬라이스로 통일)이 그 사례다: 368 → 366쪽·최대
353.0pt 불변인데 총 침범은 6,917 → 7,521pt로 올랐다. 캐시 좌표를 믿던 시절
뒷 쪽으로 밀려나 겹침을 면했던 각주가 참조 쪽으로 돌아와 제 쪽 본문 위에 다시
쌓이기 때문이다 (참조가 그 쪽에 없는 각주 43 → 1건). 이때도 **다른 축이
개선됨을 함께 보이고 근거를 소스 상수 옆에 남긴다** — 그러지 않으면 완화와
구분되지 않는다.

CI ✓인 네 스위트가 도는 근거는 전부 `HwpFontResolver.testDeterministic`
하나다 — 폰트 조회 세 축(시스템 등록 폰트·한컴 번들·문서 대체 글꼴)을 모두
닫아 설치 폰트와 무관하게 같은 CTFont가 나온다. **이 스위트들의 로더를 기본
resolver로 되돌리면 안 된다**: 좌표가 설치 폰트 메트릭의 함수가 되어
한컴오피스가 없는 CI 러너와 갈리고, 굴림·바탕·함초롬체가 설치된 한국인 기여자
머신에서만 빨개진다. **넷째 축은 대체 폰트다** — 세 축을 닫아 모든 face를 Menlo로
보내도 Menlo가 못 가진 글자는 CoreText가 호스트 폰트 목록에서 고른다. 헌법주석은
2,054자 중 1,929자(94%)가 Menlo 밖이라 사실상 조판 전체가 그 선택에 달려 있었고,
로마숫자 `Ⅵ`가 러너마다 다른 폰트로 잡혀 블록 좌표 기준선이 CI에서 갈렸다(#95).
`fallbackCascade`로 대체 목록을 명시해 닫았다 — macOS·iOS가 이제 같은 값을 낸다
(각주 겹침 총 침범 7,542pt 동일). 골든
임계를 잉크량 **비율**로 잡아 그 잔차를 흡수하되, 전역은 페이지 총잉크에
국소는 **그 셀 자신의** 잉크에 비례시킨다 — 국소를 페이지 최대 셀에서 뽑으면
표 테두리처럼 얇은 장식이 저잉크 셀에서 통째로 사라져도 통과한다 (실측:
noori p2에서 비영 셀의 30%까지 지워도 양쪽 통과).

골든 대상은 PrvImage 오라클이 닿지 않는 2쪽 이후만 고른다 (1쪽은 fidelity가
본다). 그래서 **골든을 새로 뜨기 전에 한글.app 실물과 육안 대조할 것** —
골든은 "바뀌었나"에만 답하고 "맞나"에는 답하지 않아, 틀린 렌더를 커밋하면
나중의 올바른 수정이 리뷰에서 회귀처럼 보인다.
`HWP_ALLPAGES=<id> HWP_ALLPAGES_DIR=<dir> swift test --filter testDumpAllPages`.
이 대조로 이미 한 장을 걸렀다 — noori p3은 표 높이가 틀리게 그려져 (선언
627.0pt vs 렌더 181.6pt) 대상에서 뺐고, 그 렌더 버그(#91 — 셀 안 떠 있는
개체가 셀 높이에 안 잡힘)를 고친 뒤 골든에 합류시켰다. **틀린 렌더를 골든에서
먼저 떼어 내는 이 절차가 실제로 작동한 사례다.**

한글.app에서 실측 지점을 찾을 때 **쪽 번호 오프셋**을 확인할 것 —
`legacy-common-control-property`(헌법주석)는 앞 로마자 12쪽 뒤 본문이 1로
재시작하므로 렌더 페이지 인덱스 N ↔ 한글 인쇄/상태바 쪽번호 N−12다. 한글의
찾아가기(`편집 > 찾기 > 찾아가기`)도 인쇄 번호를 받으므로, 렌더 471쪽을 보려면
459를 넣어야 한다 (#94 실측에서 확인).

블록 스냅샷의 **표본 페이지는 실측 지점을 따라 늘린다** — 1,030쪽 헌법주석은
전 페이지를 뜨면 기준선이 비대해져 표본만 커밋하는데(현재 10쪽), 그 표본이
"한글.app 실물과 대조해 옳다고 확인한 페이지" 목록을 겸한다. 표 셀 각주
귀속(484·485)에 이어 #94가 각주 안 그림·표 페이지(470·894)를 넣었다 — 실물
대조를 마친 페이지를 표본에 남겨야 다음 회귀가 그 지점에서 잡힌다.
#95가 넣은 721·722·723은 성격이 다르다: 조각 단위 각주 귀속의 **회귀 앵커**일 뿐
아직 실물 대조 전이다 (인쇄 711쪽 = 렌더 722에서 한글은 22)–26), 우리는 23)–26)).
표본에 실물 미대조 페이지를 넣을 때는 이렇게 주석으로 갈라 둘 것 — 안 그러면
다음 사람이 그 좌표를 "옳다고 확인된 값"으로 읽는다.

골든 스위트는 macOS 전용이다: iOS 시뮬레이터는 호스트 파일시스템의 폰트를 읽어
같은 기준선이 재현되지 않아 `#if os(macOS)`로 통째로 뺐다 (CI의 iOS 잡에서는
이 스위트가 존재하지 않는다). 반면 **블록 스냅샷·페이지 수에는 그 가드를 두지
않았다** — macOS에서 뜬 기준선이 시뮬레이터에서 그대로 통과함을 실측했고
(2026-07-29, iPhone 17 Pro, `xcodebuild test`), 즉 Menlo에 없는 한글이 타는 OS
캐스케이드가 두 OS에서 스냅샷 반올림(0.1pt) 안으로 일치한다. 러너 시뮬레이터의
폰트 구성은 다를 수 있으니 **첫 push의 iOS 잡을 확인할 것** — 갈리면 임계를
풀지 말고 이 둘도 macOS 전용으로 내리는 쪽이 맞다 (기준선의 의미가 흐려진다).

렌더 경로 최적화(캐시 도입 등)는 **속도는 실측, 등가성은 해시**로 나눠
증명한다: 같은 문서를 최적화 무력화 A/B로 N회 재조판·재드로해 배수를 재고,
같은 PR에서 픽셀 해시가 **양 폰트 모드 모두 무변화**임을 함께 보인다.
캐시는 파이프라인 단계로 층이 갈린다 — 조판 **입력**은 `HwpTextAttributeCache`
(글자 모양별 속성 사전; paginate 1.78x, 1,030쪽 문서 로드 1.42x —
`Sources/HwpKitCore/AGENTS.md`), 조판 **결과**는 `HwpPageLayer` 줄 배치 캐시
(재드로 1.85x/1.53x — `Sources/HwpKitNative/AGENTS.md`). 문서 빌드와 draw로
단계가 갈려 서로 독립이다.

## 문서 내 검색 (#75)

검색은 **선택과 같은 조판을 공유**한다 — `HwpSearchController.attach(to:)` 가
`HwpSelectionController` 의 지오메트리를 그대로 쓰므로 하이라이트 좌표가
화면과 어긋날 수 없고 단위 캐시가 이중화되지 않는다. 별도 텍스트 인덱스를
만들지 않는다.

- 계층: 엔진·세션은 `HwpKitCore/Search/`, 오버레이·스크롤은 `HwpKitNative`,
  공개 UI (`HwpSearchBar`/`HwpSearchNavigator`) 는 `HwpKit/Search/`.
- 매칭은 `HwpTextUnit.attributedString.string` 의 **UTF-16 오프셋** 위에서
  한다 (`HwpTextPosition.characterOffset` 의 정의). `plainText(for:)` 위에서
  매칭하면 U+FFFC 제거·문단 조각 결합 때문에 하이라이트 좌표계와 어긋난다.
- `.literal` 을 쓰지 않아 한글 NFD/NFC 가 동치로 비교된다. 대가로 **반환
  range 의 길이가 질의의 UTF-16 길이와 다를 수 있다** — 경계·커서 전진은
  반드시 반환된 range 를 그대로 쓴다 (`HwpSearchNormalizationTests` 가 고정).
- 목록(`matches`)은 반복 표 머리행 클론을 **단위 단위**로 dedup 하고,
  하이라이트(`highlightMatches`)는 클론을 남긴다 — `plainText(for:)` 의 기존
  정책과 같은 의미다.
- 프로그레시브 스냅샷은 `HwpGeometryChange.isProgressiveAppend` 로 **증분**
  재스캔한다. 로더 배치가 24 라 1,030쪽이면 스냅샷이 수십 회 온다.
- 매치를 화면에 들이는 스크롤은 **세로·가로 두 축**이고, 가로는 매치가 이미
  보이면 건드리지 않는다 (좌우 흔들림 방지 — 규칙은
  `Sources/HwpKitNative/AGENTS.md`).
- UI 경계: 검색 **컴포넌트**는 우리 몫이고 Cmd+F 같은 **전역 단축키와
  chrome** 은 호스트 몫이다. SwiftUI `.searchable` 은 호스트 navigation
  chrome 을 점유하므로 스코프 가드가 계속 막는다.

마지막 결함은 **시뮬레이터 육안 확인**이 잡았다 — 오버레이 부착·색·z-순서·
세로 클램프 단언이 전부 초록인 채로 현재 매치가 화면 밖에 있었다. 위 "렌더
가드 4층"의 넷째 줄과 같은 교훈이다: 가드가 "레이어가 올바른가"만 보면
"사용자 눈에 보이는가"는 아무도 보지 않는다.

## PDF 내보내기 (#74)

출력 경로가 둘이 됐지만 **조판은 하나**다 — `HwpKit.HwpPDFExporter`가
`HwpKitNative.HwpPDFRenderer`를 통해 화면과 **같은 paint list·같은 조판**을
CGPDFContext에 쓴다. `HwpPageLayer.draw(in:)`가 뷰 계층 없이 임의 `CGContext`에
그리는 순수 오프스크린 렌더러라 가능했다 — 레이어가 자기 뷰·화면 스케일·스크롤
상태를 읽게 만드는 변경은 **PDF를 조용히 화면과 갈라놓는다**.

경계는 **"바이트는 우리가, UI는 호스트가"**다. 저장 패널·공유 시트·인쇄
대화상자는 라이브러리에 넣지 않고 `Sample/`이 배선 예를 보인다 (뷰를 직접
인쇄하는 경로는 없다 — 레이어 가상화가 가시 ± 2쪽만 들고 있어 인쇄
페이지네이션과 충돌한다). 이 경계는 이제 문장이 아니라 테스트다 —
`Tests/HwpKitTests/HwpKitScopeGuardTests.swift`가 `Sources/HwpKit/**.swift`의
비-주석 줄에서 호스트 UI 토큰(`fileExporter`·`NSSavePanel`·
`UIPrintInteractionController` 등)을 스캔한다. 그전까지 HwpKit/AGENTS.md는
"테스트로 grep 검증 있음"이라 적고 있었지만 HwpKit 소스를 훑는 테스트는 없었다
(`SourceSafetyTests`는 `Sources/CoreHwp`만 본다).

가드 축도 위 4층과 다르다 — **기준선이 없고 두 경로를 맞대 본다**
(`HwpPDFExporterTests`, CI 상시). 페이지 수·mediaBox·잉크 비영만으로는 **상하
반전이 통과**하므로 (flip 보정이 무분기라 조용히 깨진다), 같은 페이지를 PDF
래스터화와 비트맵 렌더로 각각 그려 잉크 분포를 대조하고 **뒤집은 그리드를
대조군**으로 함께 단언한다. 두 경로가 같은 기기의 같은 폰트를 쓰므로 이 비교는
설치 폰트와 무관하다 — 텍스트 벡터 바이트를 비교하면 그 순간 기기 함수가 되어
CI에서 깨진다.

화면 없는 경로의 이미지는 **확정을 직접 기다린다** (`HwpPageImageProvider`의
`resolveImage`/`predecodeImageReferences` — `requestImage`는 재드로우로 완료를
소비하는 fire-and-forget이라 못 쓴다). 픽스처 렌더 하네스의 폴링 + 2초
타임아웃도 이 API로 대체됐다 — 즉 **렌더 가드 4층이 이제 이 프로덕션 코드를
함께 태운다**. 백프레셔 3겹과 영구 대기 회피 규약은 `Sources/HwpKitNative/AGENTS.md`.

## 리뷰 대응 체크리스트 (렌더 회귀 방지)

PR 리뷰를 반영하며 렌더링 코드를 수정할 때, 한글 파일 렌더 결과가 조용히
달라지는 것을 막는 절차. 파서·문서 등 렌더 무관 변경은 3·4단계만.

0. **기준선 동결** — 수정 전
   `RECORD_RENDER_HASHES=1 swift test --filter FixtureRenderHash`로 현재
   렌더를 `Snapshots/`에 레코딩. 기준선은 머신 종속(설치 폰트·OS
   래스터라이저)이라 gitignore — 작업할 이 머신에서 매번 새로 뜬다.
   **폰트 모드마다 파일이 갈린다**: 배포 기본값(한컴 폰트 off)은
   `<id>-nohancom.json`, `HWP_HANCOM_FONTS=1`이면 `<id>.json`. 레코딩은
   현재 모드의 기준선만 갱신하므로, 잠글 모드에서 각각 떠 둔다.
1. **코멘트 분류** — 렌더 영향 여부 먼저 판정. 레이아웃·측정·폰트·색·장식
   관련이면 렌더가 의도적으로 바뀔 수 있고(기준선 갱신 예정), 순수
   correctness·리팩터는 렌더 불변이어야 한다(해시가 증명).
2. **수정** — 관심사별 커밋 분리 (로직 / 기계적 포맷).
3. **검증 (계층별)**
   - `swift test` — 환경 의존 2종(렌더 해시·fidelity)은 자동 skip. 커밋된
     기준선을 쓰는 4종(블록 스냅샷·렌더 골든·페이지 수·각주 겹침)은 **여기서
     돈다** — 그 실패는 환경 차이가 아니라 진짜 회귀다. 의도된 변경이면
     `RECORD_BLOCK_SNAPSHOTS=1`·`RECORD_RENDER_GOLDENS=1`로 재기록하고
     diff를 리뷰할 것 (레코딩은 의도적으로 실패한다). 각주 겹침만 레코딩이
     없다 — 예산이 소스 상수라 손으로 고치고 **낮추는 방향만**이다 (올려서
     통과시키면 그 스위트가 존재할 이유가 사라진다). 유일한 예외는 위 "렌더
     가드 4층"의 정합성 수정 사례다.
   - `HWP_SNAPSHOT_TESTS=1 swift test --filter "FixtureRenderHash|FixturePreviewFidelity"`
     — 렌더 회귀. 실패 시 어느 픽스처의 몇 페이지가 변했는지 출력된다.
     렌더 해시는 폰트 모드별 기준선이라 `HWP_HANCOM_FONTS=1`을 덧붙인
     실행을 한 번 더 해야 양쪽이 다 검증된다 (fidelity는 양 모드
     공용이라 한 번이면 된다). fidelity 임계는 **함초롬체가 설치된
     기기** 기준이라(README "폰트") 미설치 기기의 실패는 렌더 회귀가 아니라
     환경 차이일 수 있다 — 임계를 올려 덮지 말 것.
   - **변경된 페이지만 육안 확인**:
     `HWP_ALLPAGES=<id> HWP_ALLPAGES_DIR=<dir> swift test --filter testDumpAllPages`로
     덤프해 한글.app 실물과 대조. 의도된 개선이면 해당 픽스처만
     `RECORD_RENDER_HASHES=<id> …`로 재레코딩(이전 기준선은 `.json.bak`
     백업), 회귀면 코드 수정. 안 바뀐 페이지는 해시 0건 통과로 증명됨.
   - **수정한 파일에만** `swiftformat` (로컬·CI 버전 일치 확인 — 다르면
     로컬 포맷이 CI에서 되레 실패) + `swiftlint` error 0.
   - Linux는 **amd64 도커만 신뢰** (arm64는 main도 가짜 `fatalError`):
     `docker run --rm --platform linux/amd64 -v $PWD:/src:ro swift:6.3-noble bash -c "cp -r /src /work && cd /work && rm -rf .build Snapshots && swift test"`.
     렌더·뷰어 코드를 만졌으면 iOS 빌드도 확인.
4. **커밋·푸시** — 논리/포맷 커밋 분리. `Snapshots/`·`Docs/`·스크래치
   파일은 gitignore로 제외됨. push 후 CI 잡별(macOS[커버리지 포함]/iOS/
   Linux·lint) 확인 — 브랜치 첫 PR 전엔 CI가 돈 적 없으니 특히 주시.

원칙: **탐지는 해시, 진단은 블록 스냅샷 diff** (상호보완). 육안 재확인은
바뀐 페이지만. 기준선이 **머신 종속인** 스위트만 기본·CI에서 skip하고 로컬
opt-in — **커밋된** 기준선을 쓰는 스위트는 CI에서 상시 돈다 (위 "렌더 가드 4층").

## 의존성 (모두 exact pinning)

- `OLEKit 0.3.1` — OLE compound document 파싱
- `SWCompression 4.9.1` — 압축 stream의 deflate (4.9.0에서 untrusted Deflate 입력에 대한 crash 패치 포함)
- `Nimble 13.8.0` — 테스트 DSL (testTarget 전용)
- `swift-docc-plugin 1.5.0` — DocC 사이트 빌드 (`cd.yml`의 `docs` job)

## 노트

- `HwpFile.init()`는 완전 빈 객체가 아니라 빈 `HwpSection` 하나가 들어있는 default 객체를 만든다. `Tests/CoreHwpTests/Blank/Create*Tests.swift`에서 파싱된 픽스처와 비교할 때 이를 사용.
- `Streams/HwpDocInfo.swift`의 여러 `// TODO: HWPTAG_*` 주석은 의도된 것으로, 아직 구현되지 않은 기능이다. 리팩토링 중에 조용히 제거하지 말 것.
- `HwpCtrlId` enum의 `Codable`은 hand-rolled 구현이다. 이종(heterogeneous) payload를 가진 associated value enum은 Swift가 자동 합성하지 못하기 때문.
- **Codable 아카이브 호환**: 모델에 새 저장 필드를 추가하면 이전 아카이브(키 부재)가 `keyNotFound`로 깨지거나, 더 나쁘게는 파생 필드가 nil로 조용히 유실된다. 신규 필드는 custom `init(from:)`에서 `decodeIfPresent ?? 기본값`으로 받고, **파싱에서 파생되는 typed 필드는 원본(raw payload/RawValue)에서 파스와 같은 함수로 재수화**한다 (`HwpFile.viewSectionArray`, `HwpBullet.headCharShapeId`, `HwpChar.inlineControl`, `HwpCommonCtrlPropertyInfo`의 enum 9종, `HwpTableCellHeader.cellProperty`, `HwpOtherControl`의 typed payload 6종, `HwpShapeComponent.textBoxListArray`의 `textBoxInfo`). 재수화는 **파스 게이트까지 같아야** 한다 — 예로 글상자 리스트만 표 90을 갖는 규약이라, 재수화도 부모 `HwpShapeComponent` 디코더에서만 수행한다. 회귀 가드는 `Tests/CoreHwpTests/Stability/LegacyArchiveDecodingTests.swift`.
