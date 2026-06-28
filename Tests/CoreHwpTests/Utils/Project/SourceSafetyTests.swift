import Foundation
import Nimble
import XCTest

final class SourceSafetyTests: XCTestCase {
    func testProductionSourcesAvoidCrashProneConstructs() throws {
        let forbiddenTokens = [
            "precondition(",
            "preconditionFailure(",
            "assert(",
            "assertionFailure(",
            "fatalError(",
            "try?",
            "try!",
            "as!",
            ".unsafelyUnwrapped",
            "unsafeBitCast(",
        ]
        let sourceFiles = try productionSourceFiles()

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for token in forbiddenTokens {
                expect(source).notTo(
                    contain(token),
                    description: "\(sourceFile.path) contains \(token)"
                )
            }
            let forceUnwrapLines = forceUnwrapLineNumbers(in: source)
            expect(forceUnwrapLines).to(
                beEmpty(),
                description: "\(sourceFile.path) contains force unwrap on lines \(forceUnwrapLines)"
            )
        }
    }

    func testInternalAgentGuidanceAvoidsCrashProneExamples() throws {
        let forbiddenExamples = [
            "precondition(",
            "preconditionFailure(",
            "fatalError(",
            "try!",
            "as!",
            "first!",
            "last!",
        ]
        let guidanceFiles = try internalAgentGuidanceFiles()

        for guidanceFile in guidanceFiles {
            let source = try String(contentsOf: guidanceFile, encoding: .utf8)
            for example in forbiddenExamples {
                expect(source).notTo(
                    contain(example),
                    description: "\(guidanceFile.path) contains crash-prone example \(example)"
                )
            }
        }
    }

    func testProductionSourcesAvoidTestOnlyDependencies() throws {
        let forbiddenTokens = [
            "import XCTest",
            "import Nimble",
            "@testable",
        ]
        let sourceFiles = try productionSourceFiles()

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for token in forbiddenTokens {
                expect(source).notTo(
                    contain(token),
                    description: "\(sourceFile.path) contains test-only dependency \(token)"
                )
            }
        }
    }

    func testSectionGuidanceDocumentsUnknownControlPreservationPolicy() throws {
        let source = try String(contentsOf: sectionAgentGuidanceFile(), encoding: .utf8)

        expect(source).to(contain("HwpCtrlId.unknown(HwpCtrlHeader)"))
        expect(source).to(contain("HwpCtrlId.notImplemented(HwpCtrlHeader)"))
        expect(source).to(contain("typed `HwpError`"))
    }
}

private func forceUnwrapLineNumbers(in source: String) -> [Int] {
    source.components(separatedBy: .newlines).enumerated().compactMap { lineOffset, line in
        let code = line.components(separatedBy: "//")[0]
        guard containsPostfixForceUnwrap(in: code) else {
            return nil
        }
        return lineOffset + 1
    }
}

private func containsPostfixForceUnwrap(in code: String) -> Bool {
    let scalars = Array(code.unicodeScalars)
    guard scalars.count >= 2 else {
        return false
    }

    for index in 1 ..< scalars.count where scalars[index] == "!" {
        let previous = scalars[index - 1]
        if previous == "=" || previous == "<" || previous == ">" || previous == "!" {
            continue
        }
        if previous.isASCII, CharacterSet.alphanumerics.contains(previous) {
            return true
        }
        if previous == ")" || previous == "]" {
            return true
        }
    }

    return false
}

private func productionSourceFiles() throws -> [URL] {
    let sourceRoot = testsRoot(from: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources")
        .appendingPathComponent("CoreHwp")
    let fileManager = FileManager.default
    let enumerator = fileManager.enumerator(
        at: sourceRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    var urls = [URL]()

    while let url = enumerator?.nextObject() as? URL {
        let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
        if resourceValues.isRegularFile == true, url.pathExtension == "swift" {
            urls.append(url)
        }
    }

    return urls.sorted { $0.path < $1.path }
}

private func internalAgentGuidanceFiles() throws -> [URL] {
    let sourceRoot = testsRoot(from: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources")
        .appendingPathComponent("CoreHwp")
    let fileManager = FileManager.default
    let enumerator = fileManager.enumerator(
        at: sourceRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    var urls = [URL]()

    while let url = enumerator?.nextObject() as? URL {
        let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
        if resourceValues.isRegularFile == true, url.lastPathComponent == "AGENTS.md" {
            urls.append(url)
        }
    }

    return urls.sorted { $0.path < $1.path }
}

private func sectionAgentGuidanceFile() -> URL {
    testsRoot(from: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources")
        .appendingPathComponent("CoreHwp")
        .appendingPathComponent("Models")
        .appendingPathComponent("Section")
        .appendingPathComponent("AGENTS.md")
}
