import CoreGraphics
import CoreText
import Foundation

/// 메모 (댓글) 풍선 패널의 paint 명령을 만든다 — 한글.app 편집 뷰 실측
/// (memo 픽스처 2026-07-10 캡처): 페이지 오른쪽 바깥의 회색 패널에
/// 연녹색 풍선 (작성자 · 시각 · "댓글" 헤더 + 본문), 페이지 경계에서
/// 풍선까지 점선 연결선.
public enum HwpMemoPanelPainter {
    public struct Balloon: Sendable {
        public let anchorY: CGFloat
        public let author: String
        public let dateText: String
        public let body: String

        public init(anchorY: CGFloat, author: String, dateText: String, body: String) {
            self.anchorY = anchorY
            self.author = author
            self.dateText = dateText
            self.body = body
        }
    }

    /// 앵커 텍스트 강조·풍선 배경의 연녹색 (한글.app 실측 근사)
    public static let anchorFillColor = CGColor(
        srgbRed: 0.925, green: 0.965, blue: 0.882, alpha: 1
    )
    static let borderColor = CGColor(srgbRed: 0.678, green: 0.827, blue: 0.549, alpha: 1)
    static let panelWidthRatio: CGFloat = 0.312

    static let headerFontSize: CGFloat = 8
    static let bodyFontSize: CGFloat = 9
    static let balloonPadding: CGFloat = 5
    static let balloonInsetX: CGFloat = 8
    static let balloonSpacing: CGFloat = 6
    /// 풍선 하나의 본문 최대 문자 수·줄 수 — 미신뢰 긴 메모의 객체/커맨드 폭발
    /// 방어 (#4). 실측 메모는 수십 자·몇 줄이라 이 한도를 한참 밑돈다.
    static let maxBodyChars = 5000
    static let maxBodyLines = 200
    /// 한 페이지 메모 풍선 최대 개수 — crafted 문서가 메모 필드를 대량 삽입해
    /// 패널 backing layer와 paint 명령을 폭발시키는 것을 막는다 (P1). 실측 메모
    /// 문서는 페이지당 몇 개라 이 한도를 한참 밑돈다.
    static let maxBalloonsPerPage = 200

    public static func panel(balloons: [Balloon], pageSize: CGSize) -> HwpMemoPanel {
        let width = (pageSize.width * panelWidthRatio).rounded()
        var commands: [HwpPaintCommand] = []
        var nextTop: CGFloat = balloonSpacing
        for balloon in balloons.prefix(maxBalloonsPerPage) {
            let frame = append(
                balloon,
                panelWidth: width,
                minTop: nextTop,
                to: &commands
            )
            nextTop = frame.maxY + balloonSpacing
        }
        return HwpMemoPanel(
            width: width,
            paintList: HwpPaintList(commands: commands),
            contentHeight: nextTop
        )
    }

    /// 풍선 하나를 그리고 그 프레임을 돌려준다.
    private static func append(
        _ balloon: Balloon,
        panelWidth: CGFloat,
        minTop: CGFloat,
        to commands: inout [HwpPaintCommand]
    ) -> CGRect {
        let balloonWidth = panelWidth - balloonInsetX * 2
        let textWidth = balloonWidth - balloonPadding * 2
        let headerHeight = headerFontSize + 3
        let bodyLines = wrappedLines(
            of: balloon.body,
            attributes: bodyAttributes,
            width: textWidth
        )
        let bodyLineHeight = bodyFontSize + 3
        let height = balloonPadding + headerHeight + 3
            + CGFloat(bodyLines.count) * bodyLineHeight + balloonPadding
        // 본문 첫 줄이 앵커 줄과 나란하도록 헤더 높이만큼 위로 올린다 (실측)
        let top = max(minTop, balloon.anchorY - headerHeight - balloonPadding - 3)
        let frame = CGRect(x: balloonInsetX, y: top, width: balloonWidth, height: height)

        appendConnector(anchorY: balloon.anchorY, balloonFrame: frame, to: &commands)
        commands.append(.fillRect(rect: frame, color: anchorFillColor))
        commands.append(.strokeRect(rect: frame, color: borderColor, width: 0.6))

        var textY = frame.minY + balloonPadding
        appendHeader(balloon, frame: frame, baselineTop: textY, to: &commands)
        textY += headerHeight + 3
        for line in bodyLines {
            commands.append(.drawText(
                attributedString: line,
                origin: CGPoint(x: frame.minX + balloonPadding, y: textY),
                lineWidth: textWidth
            ))
            textY += bodyLineHeight
        }
        return frame
    }

    /// 작성자 (왼쪽) · 시각 + "댓글" (오른쪽 정렬) 헤더 줄
    private static func appendHeader(
        _ balloon: Balloon,
        frame: CGRect,
        baselineTop: CGFloat,
        to commands: inout [HwpPaintCommand]
    ) {
        if !balloon.author.isEmpty {
            commands.append(.drawText(
                attributedString: NSAttributedString(
                    string: balloon.author, attributes: headerAttributes
                ),
                origin: CGPoint(x: frame.minX + balloonPadding, y: baselineTop),
                lineWidth: frame.width
            ))
        }
        let trailingText = NSMutableAttributedString()
        if !balloon.dateText.isEmpty {
            trailingText.append(NSAttributedString(
                string: balloon.dateText + " ", attributes: dateAttributes
            ))
        }
        trailingText.append(NSAttributedString(string: "댓글", attributes: headerAttributes))
        let trailingWidth = lineWidth(of: trailingText)
        commands.append(.drawText(
            attributedString: trailingText,
            origin: CGPoint(
                x: frame.maxX - balloonPadding - trailingWidth,
                y: baselineTop
            ),
            lineWidth: frame.width
        ))
    }

    /// 페이지 오른쪽 경계 (패널 x=0)에서 풍선 왼쪽까지의 점선 연결선
    private static func appendConnector(
        anchorY: CGFloat,
        balloonFrame: CGRect,
        to commands: inout [HwpPaintCommand]
    ) {
        let path = CGMutablePath()
        let lineY = anchorY + bodyFontSize
        var x: CGFloat = 0
        while x < balloonFrame.minX {
            let dashEnd = min(x + 2, balloonFrame.minX)
            path.move(to: CGPoint(x: x, y: lineY))
            path.addLine(to: CGPoint(x: dashEnd, y: lineY))
            x += 4
        }
        commands.append(.drawPath(
            path: path, fill: nil, stroke: borderColor, strokeWidth: 0.7
        ))
    }

    private static var headerAttributes: [NSAttributedString.Key: Any] {
        [
            kCTFontAttributeName as NSAttributedString.Key:
                CTFontCreateWithName("AppleSDGothicNeo-Medium" as CFString, headerFontSize, nil),
            kCTForegroundColorAttributeName as NSAttributedString.Key:
                CGColor(gray: 0.1, alpha: 1),
        ]
    }

    private static var dateAttributes: [NSAttributedString.Key: Any] {
        [
            kCTFontAttributeName as NSAttributedString.Key:
                CTFontCreateWithName(
                    "AppleSDGothicNeo-Regular" as CFString, headerFontSize - 0.5, nil
                ),
            kCTForegroundColorAttributeName as NSAttributedString.Key:
                CGColor(gray: 0.45, alpha: 1),
        ]
    }

    private static var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            kCTFontAttributeName as NSAttributedString.Key:
                CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, bodyFontSize, nil),
            kCTForegroundColorAttributeName as NSAttributedString.Key:
                CGColor(gray: 0.05, alpha: 1),
        ]
    }

    private static func lineWidth(of attributedString: NSAttributedString) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributedString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// 본문을 폭에 맞춰 줄 단위 attributed string으로 나눈다.
    private static func wrappedLines(
        of text: String,
        attributes: [NSAttributedString.Key: Any],
        width: CGFloat
    ) -> [NSAttributedString] {
        // 본문 길이·줄 수를 상한한다 — 미신뢰 BodyText(최대 256MB)의 긴 메모가
        // 줄마다 NSAttributedString + paint 커맨드로 팽창해 페이지네이션 중 메모리를
        // 고갈시키는 것을 막는다 (#4). 실측 메모는 이 한도를 한참 밑돈다.
        let capped = text.count > Self.maxBodyChars ? String(text.prefix(Self.maxBodyChars)) : text
        let full = NSAttributedString(string: capped, attributes: attributes)
        guard full.length > 0 else { return [] }
        let typesetter = CTTypesetterCreateWithAttributedString(full)
        var lines: [NSAttributedString] = []
        var start = 0
        while start < full.length, lines.count < Self.maxBodyLines {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            guard count > 0 else { break }
            lines.append(full.attributedSubstring(
                from: NSRange(location: start, length: count)
            ))
            start += count
        }
        return lines
    }
}
