import CoreGraphics
import CoreHwp
import Foundation

/// 흐름 분할(`HwpPaginator.appendParagraphAcrossColumns`) 조각의 각주 귀속 (#207) — 절대
/// 캐시 run의 조각별 귀속(#95·#165, `HwpAbsoluteCachePlacer.controlOrdinalRanges`)에 해당한다.
///
/// 한글은 각주를 **참조가 놓인 쪽**에 싣고, 줄을 남길지 판정할 때 그 줄의 각주 몫까지 센다
/// (한글 12.30 실측 2026-09-21, `probes/207`: 남은 49.62pt에 4줄 문단의 첫 줄 뒤 각주 24.17pt가
/// 들어가면 1줄 + 각주만 남고 나머지 3줄은 다음 쪽; 각주가 마지막 줄 참조면 앞 두 줄만 남고
/// 각주는 참조 줄과 함께 다음 쪽). 흐름 분할은 조각을 **점진적으로** 만들므로 조각 전부를
/// 받아 범위를 나누는 절대 경로의 정적 함수 대신, 줄마다 "그 줄까지 그려진 마지막 컨트롤
/// 서수 + 1"(`ordinalEnd`)을 두고 커서(`collectedEnd`)부터 그 값까지를 조각의 범위로 삼는다.
///
/// - 조각을 자르기 **전**: `reservation(for:isLast:compute:)`가 후보 줄까지의 범위를 예약
///   높이로 재어 적합 판정(`HwpFragmentRemainder.fit(in:extra:)`)에 더한다 — 수집
///   (`collectFootnotes`)과 같은 술어(비최종 조각은 범위 안 직접 각주, 최종 조각은 중첩
///   컨테이너까지)라 예약 ≡ 수집이다.
/// - 조각을 놓은 **뒤**: 호출자가 그 범위를 걷어 이 쪽의 `pendingFootnotes`에 담고
///   `markCollected`로 커서를 옮긴다. 마지막 조각은 서수 범위와 무관하게 중첩 컨테이너 전부를
///   걷는다.
///
/// 마커 ↔ 컨트롤 배열이 어긋난 문단(서수 ≥ 컨트롤 수)은 만들지 않는다(`init` nil) — 호출자는
/// 문단 전체 예약 + 문단 단위 수집(종전 동작)으로 폴백한다. 한글이 각주를 참조 줄과 같은 쪽에
/// 못 실을 때 줄은 남기고 각주만 이월하는 규칙(실측 MB·ME)은 모델링하지 않는다 — 첫 줄과 그
/// 각주가 함께 안 들어가면 문단이 통째로 다음 쪽으로 간다 (종전 동작).
///
/// 참조 의미(클래스)다 — 조각 루프의 적합 판정 클로저와 수집이 같은 커서·줄 표를 본다.
final class HwpFlowFragmentFootnotes {
    /// 각주를 걷을 문단.
    let paragraph: CoreHwp.HwpParagraph
    /// 문단의 top-level 컨트롤 수.
    let controlCount: Int
    /// 문단 조판 문자열의 컨트롤 마커 — 위치 오름차순. 각주 참조 번호로 치환된 run도 같은
    /// 속성을 단다 (`HwpTextRunBuilder.appendControlMarker`).
    private let markers: [(ordinal: Int, range: NSRange)]
    /// 지금까지 걷은 서수의 끝 — 다음 조각 범위의 시작.
    private(set) var collectedEnd = 0
    /// 나머지 줄 목록의 줄별 서수 끝 (누적 최댓값 + 1) — 줄 목록이 바뀌면(목적 단 폭으로
    /// 다시 잼) 다시 만든다.
    private var lineOrdinalEnds: [Int] = []
    private var lineOrdinalEndsStamp = -1
    /// 같은 쪽·같은 커서에서 잰 예약의 메모 — 후보 줄마다 잰 값이 같은 범위면 같다. 커서가
    /// 움직이면(조각을 걷으면) 비운다.
    private var reservationMemo: [ReservationKey: CGFloat] = [:]

    private struct ReservationKey: Hashable {
        let upperBound: Int
        let isLast: Bool
    }

    init?(
        paragraph: CoreHwp.HwpParagraph,
        attributedString: NSAttributedString,
        controlCount: Int
    ) {
        var markers: [(ordinal: Int, range: NSRange)] = []
        var consistent = true
        attributedString.enumerateAttribute(
            HwpAttributedStringKey.controlIndex,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, range, stop in
            guard let ordinal = (value as? NSNumber)?.intValue else { return }
            guard ordinal >= 0, ordinal < controlCount else {
                consistent = false
                stop.pointee = true
                return
            }
            markers.append((ordinal, range))
        }
        guard consistent else { return nil }
        self.paragraph = paragraph
        self.controlCount = controlCount
        self.markers = markers
    }

    /// 나머지의 줄 `lineIndex`까지 놓을 조각이 걷을 서수 범위 — 커서부터 그 줄까지 그려진
    /// 마지막 서수 + 1까지. 마지막 줄이면 남은 서수 전부다 (최종 조각은 범위 밖 컨테이너의
    /// 각주도 걷는다).
    func ordinals(through lineIndex: Int, of remainder: HwpFragmentRemainder) -> Range<Int> {
        refreshLineOrdinalEnds(for: remainder)
        let end: Int = if lineIndex >= remainder.lines.count - 1 {
            controlCount
        } else if lineOrdinalEnds.indices.contains(lineIndex) {
            lineOrdinalEnds[lineIndex]
        } else {
            collectedEnd
        }
        return collectedEnd ..< max(collectedEnd, end)
    }

    /// 범위 `ordinals`의 예약 높이 — 메모가 없으면 `compute`로 잰다.
    func reservation(
        for ordinals: Range<Int>, isLast: Bool, compute: () -> CGFloat
    ) -> CGFloat {
        let key = ReservationKey(upperBound: ordinals.upperBound, isLast: isLast)
        if let memo = reservationMemo[key] {
            return memo
        }
        let value = compute()
        reservationMemo[key] = value
        return value
    }

    /// 조각 `ordinals`를 걷었다 — 커서를 그 끝으로 옮기고 예약 메모를 비운다 (다음 조각은 다른
    /// 쪽·다른 카운터에서 잰다).
    func markCollected(_ ordinals: Range<Int>) {
        collectedEnd = max(collectedEnd, ordinals.upperBound)
        invalidateReservations()
    }

    /// 예약 메모를 비운다 — 조각을 걷지 않고 단·쪽을 넘긴 뒤(줄이 하나도 안 들어가 넘김) 새
    /// 쪽의 각주 상태(구분선 오버헤드·이월 예약)로 다시 재야 한다.
    func invalidateReservations() {
        reservationMemo = [:]
    }

    /// 줄별 서수 끝을 (필요하면) 다시 만든다 — 줄 범위와 마커 범위가 둘 다 위치 오름차순이라
    /// 두 포인터로 한 번에 훑는다. 줄에 걸쳐 그려진 마커는 앞 줄에 귀속된다 (절대 경로의
    /// "그려진 마지막 서수"와 같다).
    private func refreshLineOrdinalEnds(for remainder: HwpFragmentRemainder) {
        let stamp = remainder.remeasureCount
        guard stamp != lineOrdinalEndsStamp || lineOrdinalEnds.count != remainder.lines.count
        else { return }
        var ends: [Int] = []
        ends.reserveCapacity(remainder.lines.count)
        var running = 0
        var markerIndex = 0
        for line in remainder.lines {
            let lineStart = line.attributedRange.location
            let lineEnd = NSMaxRange(line.attributedRange)
            // 이 줄 앞에서 끝난 마커는 지나가고, 이 줄과 겹치는 마커를 전부 센다.
            while markerIndex < markers.count,
                  NSMaxRange(markers[markerIndex].range) <= lineStart
            {
                markerIndex += 1
            }
            var probe = markerIndex
            while probe < markers.count, markers[probe].range.location < lineEnd {
                running = max(running, markers[probe].ordinal + 1)
                probe += 1
            }
            ends.append(running)
        }
        lineOrdinalEnds = ends
        lineOrdinalEndsStamp = stamp
    }
}
