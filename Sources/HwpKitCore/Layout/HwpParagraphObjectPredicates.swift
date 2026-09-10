import CoreGraphics
import CoreHwp
import Foundation

// 개체 배치 술어 — 흐름 점유·컨테이너 하한·수집 대상 판정. 배치(`objects()`)와 사전
// 판정(예약·표 셀 하한 재수집)이 **같은 술어**를 봐야 한다. `HwpParagraphObjectCollector.swift`
// 가 SwiftLint file_length 상한(700줄)에 닿아 갈라 뒀다.

extension HwpParagraphObjectCollector {
    /// 수집 결과 — 종류별 개체 목록 + 떠 있는 개체 하단.
    struct Objects {
        var images: [HwpCellImage] = []
        var shapes: [HwpCellShape] = []
        var textboxes: [HwpCellTextbox] = []
        /// 문단에 붙은 표 (`collectsTables`가 참일 때만 채워진다, #94)
        var nestedTables: [HwpNestedTableFrame] = []
        /// 떠 있는 개체 (글자처럼 취급 아님)의 하단 최대값 (paragraphRect 좌표계).
        /// 한글 줄 캐시도 저작된 셀 높이 (표 80)도 이 개체를 담지 않으므로,
        /// 컨테이너 높이를 그 둘로만 정하면 개체가 컨테이너 밖으로 흘러나간다
        /// (#91). 배치와 같은 origin/size 산식에서 뽑아야 측정과 어긋나지 않아
        /// 여기서 함께 낸다.
        var floatingBottom: CGFloat?

        /// 수집 총량 — 다음 문단의 firstSourceOrder (원본 순서 ordinal 연속).
        /// 표도 평면·정렬 키를 가지므로 (R47 #1) 함께 센다 — 빼면 표 뒤에 오는
        /// 개체의 ordinal이 표와 겹쳐 같은 zOrder에서 순서가 뒤집힌다.
        var count: Int {
            images.count + shapes.count + textboxes.count + nestedTables.count
        }

        /// 종류별 개수 스냅샷 — 컨트롤 하나가 새로 넣은 개체 범위를 잡는 표식.
        var marker: ObjectMarker {
            ObjectMarker(
                images: images.count,
                shapes: shapes.count,
                textboxes: textboxes.count,
                nestedTables: nestedTables.count
            )
        }

        /// 표식 이후 추가된 개체들의 하단 최대값을 떠 있는 개체 하단으로 기록한다.
        /// '떠 있음'은 컴포넌트가 아니라 **컨트롤**의 속성이라 호출부가 컨트롤
        /// 단위로 부른다.
        mutating func noteFloating(since marker: ObjectMarker, exceeding reserved: CGFloat? = nil) {
            let bottoms = images[marker.images...].map(\.rect.maxY)
                + shapes[marker.shapes...].map(\.rect.maxY)
                + textboxes[marker.textboxes...].map(\.rect.maxY)
                + nestedTables[marker.nestedTables...].map(\.rect.maxY)
            guard let bottom = bottoms.max() else { return }
            // 줄이 잡아 준 상자 안이면 줄 높이가 이미 담는다 — 넘친 만큼만 하한이다
            if let reserved, bottom <= reserved {
                return
            }
            floatingBottom = Swift.max(floatingBottom ?? bottom, bottom)
        }
    }

    /// `Objects.marker` 스냅샷 (중첩 depth 상한을 넘지 않게 형제로 둔다)
    struct ObjectMarker {
        let images: Int
        let shapes: Int
        let textboxes: Int
        let nestedTables: Int
    }

    /// 배치 방식 (표 70 textWrap)이 흐름을 점유하는지 — 어울림·자리 차지는
    /// 자리를 잡고, 글 뒤로·글 앞으로는 겹쳐 그리는 오버레이라 잡지 않는다.
    ///
    /// **이 술어의 소유자는 여기다** — 페이지 흐름 경로 (`HwpPaginator`)와 셀
    /// 높이 하한 (`growsContainer`)이 같은 답을 써야 한다. 갈리면 흐름에서
    /// 자리를 안 주는 개체가 컨테이너는 키우는 모순이 생긴다.
    static func consumesFlow(_ info: CoreHwp.HwpCommonCtrlPropertyInfo) -> Bool {
        switch info.textWrap {
        case .square, .topAndBottom, nil:
            true
        case .behindText, .inFrontOfText:
            false
        }
    }

    /// 컨테이너 높이를 키워야 하는 개체인지 — 글자처럼 취급이 **아니고**,
    /// 세로 기준이 **'문단'**이고, 배치 방식이 **흐름을 점유**하는 것 (#91).
    ///
    /// 공통 속성이 없으면 `origin()`이 흐름 배치를 택하므로 떠 있는 개체가
    /// 아니다. 세로 기준을 함께 보는 이유: 쪽/종이 기준 개체의 저작
    /// `verticalOffset`은 **페이지 상단 기준 절대 좌표**라 수백 pt가 정상인데,
    /// 컨테이너 안에는 쪽 기하가 없어 `origin()`이 그 값을 문단 rect에 그대로
    /// 더하는 근사를 쓴다 (R32 #3). 그 근사는 개체 **위치**만 틀리는 기존 한계인데,
    /// 높이 하한으로 승격시키면 표 총높이·페이지 분할 오차로 번진다 (실측:
    /// 저작 10pt 셀 + 쪽 기준 오프셋 600pt 개체 → 행 700pt). 한글도 쪽/종이에
    /// 걸린 개체를 담으려고 셀을 키우지 않는다 — 그건 쪽에 놓인 개체다.
    /// #91이 실제로 측정한 noori 형상 행 개체는 세로 기준 '문단'이다.
    ///
    /// 배치 방식을 함께 보는 이유도 같은 꼴이다: 글 뒤로·글 앞으로는 **겹치는
    /// 것이 설계**라 (앵커 규칙 "text 블록과 겹칠 수 있음") 담으려고 컨테이너를
    /// 키우면 안 된다 — 셀 안 큰 워터마크·말풍선이 행을 부풀려 표 총높이와
    /// 페이지 분할을 함께 어긋내고, `maximumCellHeight`는 이 규모를 막지 못한다.
    /// 여기 걸리는 개체도 셀 콘텐츠로 그려지는 것은 그대로다 (`paintsBehindText`) —
    /// 빠지는 것은 **높이 하한뿐**이다. noori 형상 행 개체는 '자리 차지'
    /// (`.topAndBottom`) 라 #91은 그대로 성립한다 (실측).
    static func growsContainer(_ commonProperty: CoreHwp.HwpCommonCtrlProperty?) -> Bool {
        guard let commonProperty else { return false }
        let info = commonProperty.propertyInfo
        return !info.treatAsChar
            && info.verticalRelativeTo == .paragraph
            && consumesFlow(info)
    }

    /// 줄 상자가 자리를 예약하지 못한 개체 — 글자처럼 취급인데 줄 앵커
    /// (U+FFFC)를 못 얻었거나, **얻었어도 예약 치수가 0인** 경우다 (R40 #1, R53).
    ///
    /// 앵커가 있으면 run delegate가 개체 크기만큼 줄 높이를 잡으므로 컨테이너
    /// 높이는 라인 캐시가 담는다 (#94 실측: 헌법주석 883쪽 표 62.52pt가 캐시
    /// 71.32pt 안, 459쪽 그림 10.8pt가 3줄 36.96pt 안). 앵커가 없으면
    /// `Placement.origin`이 문단 상단 커서로 폴백해 그리는데 **그 자리를 예약한
    /// 줄이 없다** — 컨테이너가 직접 담지 않으면 개체가 다음 각주·꼬리말 위로
    /// 흘러나간다. 앵커 없는 treatAsChar가 높이를 소비한다는 것은 루트 규약이다
    /// (AGENTS.md "앵커 규칙").
    static func escapesLineBox(
        _ commonProperty: CoreHwp.HwpCommonCtrlProperty?,
        anchor: LineAnchor?
    ) -> Bool {
        // 앵커의 **예약 치수**를 본다 — 마커만 있고 자리를 안 잡은 앵커가 실재해
        // (`LineAnchor`) 위치만 보면 담기지 않은 개체의 하한이 죽는다 (R53).
        guard anchor?.reservesSpace != true else { return false }
        // 공통 속성이 없으면 배치(`collect`의 `advancesCursor`)가 글자처럼 취급으로
        // 보고 커서 흐름에 놓는데, run builder는 그 개체에 줄 공간을 예약하지
        // 않는다 — 줄도 컨테이너도 안 담으므로 여기서 기본값을 배치와 **같게**
        // 둬야 하한이 걸린다 (R51 #3).
        return commonProperty?.propertyInfo.treatAsChar ?? true
    }

    /// 컨테이너 높이 하한을 올리는 개체인지 — 떠 있는 개체 (`growsContainer`)
    /// 이거나 줄 상자를 벗어난 개체 (`escapesLineBox`).
    static func raisesContainerFloor(
        _ commonProperty: CoreHwp.HwpCommonCtrlProperty?,
        anchor: LineAnchor?
    ) -> Bool {
        growsContainer(commonProperty) || escapesLineBox(commonProperty, anchor: anchor)
    }

    /// 문단에 컨테이너 높이 하한을 만들 수 있는 수집 대상 컨트롤이 있는지.
    /// 개체를 다시 수집해야 높이를 알 수 있는 컨테이너만 고르는 값싼 사전
    /// 판정이다 (#91) — 컨트롤 없는 문단이 대다수라 재수집이 거의 안 돈다.
    ///
    /// 줄 앵커가 없는 자리라 `escapesLineBox` 축은 **상위집합**이다 (글자처럼
    /// 취급이면 앵커 유무와 무관하게 참). 기록 여부의 판정은 앵커를 아는
    /// `objects()`에 있다 — 좁으면 하한을 놓치고 넓으면 재수집만 한 번 더 도므로
    /// **불일치는 이 방향으로만 안전하다** (R40 #1).
    static func hasFloatingObject(
        in paragraph: CoreHwp.HwpParagraph,
        collectsTextboxes: Bool,
        collectsTables: Bool = false
    ) -> Bool {
        (paragraph.ctrlHeaderArray ?? []).contains { ctrl in
            if collectsTables, case let .table(nested) = ctrl {
                return mayRaiseContainerFloor(nested.commonCtrlProperty)
            }
            guard let (commonProperty, components) = handledControl(ctrl),
                  mayRaiseContainerFloor(commonProperty)
            else { return false }
            return collectible(components, collectsTextboxes: collectsTextboxes)
        }
    }

    /// 문단에 **수집기가 그릴** 컨트롤이 하나라도 있는지 — `objects()`가 거치는 관문
    /// (`collectsTables`의 표, `handledControl` + `collectible`) 을 그대로 되풀이한 값싼
    /// 사전 판정이다 (#165 리뷰).
    ///
    /// `hasFloatingObject`와 다르다: 그쪽은 **높이 하한을 만들 수 있는** 개체만 보므로
    /// 글 앞으로·글 뒤로 배치한 개체(오버레이 — 흐름을 안 점유하고 줄에도 안 담긴다)를
    /// 뺀다. 그런 개체도 수집돼 그려지므로, "이 각주가 개체를 담는가"(쪽 끝 분할 금지·
    /// CT 높이 보존)의 판정은 이 술어여야 예약과 배치가 같은 답을 본다 — 배치는 수집
    /// 결과로 판정하는데 예약만 하한 술어로 판정하면 오버레이 개체를 담은 각주에서
    /// 예약(캐시 합)과 배치(CT)가 갈린다 (실측: 58.36 vs 78.2pt).
    static func hasCollectibleObject(
        in paragraph: CoreHwp.HwpParagraph,
        collectsTextboxes: Bool,
        collectsTables: Bool
    ) -> Bool {
        (paragraph.ctrlHeaderArray ?? []).contains { ctrl in
            if collectsTables, case .table = ctrl {
                return true
            }
            guard let (_, components) = handledControl(ctrl) else { return false }
            return collectible(components, collectsTextboxes: collectsTextboxes)
        }
    }

    /// 앵커를 모르는 자리의 상위집합 판정 (`hasFloatingObject` 전용).
    private static func mayRaiseContainerFloor(
        _ commonProperty: CoreHwp.HwpCommonCtrlProperty?
    ) -> Bool {
        growsContainer(commonProperty)
            || (commonProperty?.propertyInfo.treatAsChar ?? true)
    }
}
