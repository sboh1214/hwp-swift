import Foundation

/// OOXML 차트 XML (`c:chartSpace`)에서 렌더에 필요한 최소 데이터를 파싱한다.
///
/// 대상: 내장 차트 개체의 `OOXMLChartContents` 스트림
/// (CoreHwp `HwpEmbeddedChart.chartXML`). 값은 `c:numCache`/`c:strCache`의
/// 캐시 값을 그대로 쓴다 (수식 참조 재계산 없음 — 한컴 저장 캐시가 곧 표시 값).
enum HwpChartParser {
    /// 파싱 실패 (차트 아님/캐시 없음)면 nil.
    static func parse(xml: String) -> HwpChartFrame? {
        guard let data = xml.data(using: .utf8) else { return nil }
        let delegate = ChartXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        guard !delegate.series.isEmpty else { return nil }

        // 자동 제목 (c:title 존재 + autoTitleDeleted=0 + 텍스트 없음)은
        // 한컴오피스 기본 제목 "차트 제목"으로 표시된다 (chart 픽스처 실측)
        var title = delegate.titleText
        if title == nil, delegate.hasTitle, !delegate.autoTitleDeleted {
            title = "차트 제목"
        }

        return HwpChartFrame(
            title: title,
            categories: delegate.categories,
            series: delegate.series.map {
                HwpChartFrame.Series(name: $0.name, values: $0.values)
            },
            showLegend: delegate.hasLegend,
            kind: .bar(cone: delegate.shapeValue == "cone")
        )
    }
}

/// c:chartSpace 안에서 series/categories/title/legend만 뽑는 SAX delegate.
private final class ChartXMLDelegate: NSObject, XMLParserDelegate {
    struct MutableSeries {
        var name = ""
        var values: [Double] = []
    }

    /// 계열 개수 상한 — <ser>≈7B라 64MB payload 안에 수백만 개가 들어갈 수
    /// 있어, 미신뢰 차트가 계열을 무제한 보유·렌더해 메모리·CPU를 고갈시키는
    /// 것을 막는다 (#1). 실측 차트는 수~수십 계열이라 렌더 불변.
    static let maxSeries = 256

    var series: [MutableSeries] = []
    var categories: [String] = []
    var hasTitle = false
    var autoTitleDeleted = false
    var titleText: String?
    var hasLegend = false
    var shapeValue: String?

    /// 현재 문맥 (요소 경로 기반 상태)
    private var path: [String] = []
    private var currentText = ""
    private var pendingPointIndex: Int?

    private func localName(_ qualified: String) -> String {
        qualified.split(separator: ":").last.map(String.init) ?? qualified
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String]
    ) {
        let name = localName(elementName)
        path.append(name)
        currentText = ""

        switch name {
        case "ser" where series.count < Self.maxSeries:
            series.append(MutableSeries())
        case "title" where path.dropLast().last == "chart":
            hasTitle = true
        case "autoTitleDeleted":
            autoTitleDeleted = attributeDict["val"] == "1"
        case "legend":
            hasLegend = true
        case "shape":
            shapeValue = attributeDict["val"]
        case "pt":
            pendingPointIndex = attributeDict["idx"].flatMap(Int.init)
        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        let name = localName(elementName)
        defer { path.removeLast() }

        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "pt":
            pendingPointIndex = nil
        case "t":
            // 리치 텍스트 제목 (c:title > c:tx > c:rich > a:p > a:r > a:t)
            if path.dropLast().contains("title"), !text.isEmpty {
                titleText = (titleText ?? "") + text
            }
        case "v":
            consumeValue(text)
        default:
            break
        }
    }

    /// c:v 텍스트를 문맥 (요소 경로)에 따라 계열 이름/값/카테고리/제목으로 배분한다.
    /// path 예: [chartSpace, chart, plotArea, bar3DChart, ser, val, numRef,
    ///          numCache, pt, v]
    private func consumeValue(_ text: String) {
        let context = Set(path.dropLast())
        let inSeries = context.contains("ser")

        if inSeries, context.contains("tx") {
            // 계열 이름 (c:ser > c:tx > c:v). strCache 인코딩
            // (c:tx > c:strRef > c:strCache > c:pt > c:v)도 받는다 (#16).
            if !series.isEmpty {
                series[series.count - 1].name = text
            }
        } else if inSeries, context.contains("val"), context.contains("pt") {
            // OOXML idx 위치에 배치 — 희소·역순 pt도 카테고리와 어긋나지 않게 (#15).
            if !series.isEmpty, let value = Double(text) {
                Self.assign(value, at: pendingPointIndex, into: &series[series.count - 1].values)
            }
        } else if inSeries, context.contains("cat"), context.contains("pt") {
            // 카테고리는 계열마다 반복 저장 — 첫 계열 것만 채택
            if series.count == 1 {
                Self.assign(text, at: pendingPointIndex, into: &categories)
            }
        } else if context.contains("title"), context.contains("tx") {
            let existing = titleText ?? ""
            let combined = existing + text
            titleText = combined.isEmpty ? nil : combined
        }
    }

    /// 차트 포인트 배열의 최대 인덱스 — 미신뢰 idx로 인한 정수 오버플로·거대
    /// sparse 할당 방어 (실측 차트는 항목 수십 개 이하).
    private static let maximumPoints = 4096

    /// idx 위치에 값을 배치하고 사이 빈 칸은 0으로 채운다 (희소·역순 pt 대응).
    /// idx가 없으면 순서대로 append한다 (기존 동작과 동일).
    private static func assign(_ value: Double, at index: Int?, into array: inout [Double]) {
        let position = index ?? array.count
        guard position >= 0, position < maximumPoints else { return }
        if position >= array.count {
            array.append(contentsOf: repeatElement(0, count: position - array.count + 1))
        }
        array[position] = value
    }

    /// idx 위치에 문자열을 배치하고 사이 빈 칸은 빈 문자열로 채운다.
    private static func assign(_ value: String, at index: Int?, into array: inout [String]) {
        let position = index ?? array.count
        guard position >= 0, position < maximumPoints else { return }
        if position >= array.count {
            array.append(contentsOf: repeatElement("", count: position - array.count + 1))
        }
        array[position] = value
    }
}
