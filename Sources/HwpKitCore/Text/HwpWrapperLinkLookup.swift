import CoreGraphics
import Foundation

// MARK: - 감싼 링크 조회

/// 개체를 감싼 `%hlk`는 개체 페이로드가 아니라 **부모 문단의 스팬**에 산다 (R49) —
/// 조회는 (문단 `paraId`, 서수) 열쇠로 그 run을 찾는다. 형태는 둘인데 **규칙은
/// 하나여야 한다** (R63): 히트는 점 조회(`wrapperHyperlinkURL`), 방출은 일괄
/// 색인(`wrapperHyperlinkIndex`)을 쓰고, 둘이 갈리면 밑줄과 탭이 다른 URL을 연다.
extension HwpDrawnTextLayout {
    /// 이 컨트롤을 감싼 `%hlk` 의 URL — 링크가 붙은 run 중 `controlIndex` 가
    /// 일치하는 것만 본다 (R50 #1). 개체의 링크는 개체가 아니라 부모 문단의
    /// U+FFFC run에 살지만, 지점 포함만으로 고르면 그 개체가 **덮고 있을 뿐인**
    /// 다른 링크까지 살아난다.
    static func wrapperHyperlinkURL(
        in paragraphs: [HwpLaidOutParagraph], paragraphId: UInt32, controlIndex: Int
    ) -> String? {
        guard controlIndex >= 0 else { return nil }
        // 서수는 문단마다 0부터 다시 시작하므로 **그 개체를 낸 문단에서만** 찾는다
        // (R51 #1) — 컨테이너 전체를 훑으면 앞 문단의 같은 서수 링크가 열린다.
        for paragraph in paragraphs where paragraph.paragraphId == paragraphId {
            let attributed = paragraph.attributedString
            var url: String?
            attributed.enumerateAttribute(
                HwpAttributedStringKey.controlIndex,
                in: NSRange(location: 0, length: attributed.length)
            ) { value, range, stop in
                guard value as? Int == controlIndex else { return }
                url = attributed.attribute(
                    HwpAttributedStringKey.hyperlink, at: range.location, effectiveRange: nil
                ) as? String
                stop.pointee = true
            }
            if let url {
                return url
            }
        }
        return nil
    }

    /// `wrapperHyperlinkURL`의 **일괄 형태** — 같은 규칙을 한 번의 순회로 낸다 (R63).
    ///
    /// 개체마다 조회하면 그때마다 문단을 처음부터 훑어 한 문단 N개체가 O(N²)가
    /// 된다 (링크가 하나도 없어도 전량 순회한다) — 한 셀·각주에 개체가 수천인
    /// 조작 문서가 paint list 구성에서 멈출 수 있다. 규칙은 그대로 옮긴다: 문단
    /// 안에서는 그 서수의 **첫** run만 보고 (`stop.pointee = true`와 같다), 같은
    /// `paraId` 문단이 여럿이면 **앞 문단이 이긴다**.
    static func wrapperHyperlinkIndex(
        in paragraphs: [HwpLaidOutParagraph]
    ) -> [HwpWrapperLinkKey: String] {
        var index: [HwpWrapperLinkKey: String] = [:]
        for paragraph in paragraphs {
            let attributed = paragraph.attributedString
            var seen: Set<Int> = []
            attributed.enumerateAttribute(
                HwpAttributedStringKey.controlIndex,
                in: NSRange(location: 0, length: attributed.length)
            ) { value, range, _ in
                guard let controlIndex = value as? Int, controlIndex >= 0,
                      seen.insert(controlIndex).inserted
                else { return }
                let key = HwpWrapperLinkKey(
                    paragraphId: paragraph.paragraphId, controlIndex: controlIndex
                )
                guard index[key] == nil, let url = attributed.attribute(
                    HwpAttributedStringKey.hyperlink, at: range.location, effectiveRange: nil
                ) as? String
                else { return }
                index[key] = url
            }
        }
        return index
    }
}

/// 감싼 링크 색인의 열쇠 — 서수는 문단마다 0부터 다시 시작하므로 **(문단 `paraId`,
/// 서수) 쌍**이어야 유일하다 (R51 #1).
struct HwpWrapperLinkKey: Hashable, Sendable {
    let paragraphId: UInt32
    let controlIndex: Int
}
