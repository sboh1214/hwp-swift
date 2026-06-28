import Foundation

func documentedPercentage(after marker: String, in text: String) -> Double? {
    guard let markerRange = text.range(of: marker) else {
        return nil
    }
    let suffix = text[markerRange.upperBound...]
    guard let percentageRange = suffix.range(
        of: #"[0-9]+(\.[0-9]+)?%"#,
        options: .regularExpression
    ) else {
        return nil
    }
    return Double(suffix[percentageRange].dropLast())
}
