import Foundation
import Nimble
import XCTest

final class FixtureManifestJSONKeyTests: XCTestCase {
    func testFixtureManifestJSONUsesKnownTopLevelKeys() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            let manifestURL = fixture.fixtureURL.appendingPathComponent("manifest.json")
            let manifestObject = try manifestJSONObject(at: manifestURL)
            assertKnownJSONKeys(
                manifestObject,
                allowedKeys: fixtureManifestJSONKeys,
                context: "\(fixture.manifest.id) manifest"
            )

            guard let expectations = manifestObject["expectations"] as? [String: Any] else {
                fail("\(fixture.manifest.id) manifest is missing expectations object")
                continue
            }
            assertKnownJSONKeys(
                expectations,
                allowedKeys: fixtureExpectationJSONKeys,
                context: "\(fixture.manifest.id) expectations"
            )

            guard let expectedError = manifestObject["expectedError"] as? [String: Any] else {
                continue
            }
            assertKnownJSONKeys(
                expectedError,
                allowedKeys: fixtureExpectedErrorJSONKeys,
                context: "\(fixture.manifest.id) expectedError"
            )
        }
    }

    func testFixtureManifestJSONUsesKnownNestedExpectationKeys() throws {
        let fixtures = try FixtureLoader.loadAll()
        let fieldIndex = try fixtureManifestDecodableFieldIndex()
        let schema = fixtureManifestJSONSchema

        assertSchemaTypesHaveFieldDefinitions(schema, fieldIndex: fieldIndex)
        for fixture in fixtures {
            let manifestURL = fixture.fixtureURL.appendingPathComponent("manifest.json")
            let manifestObject = try manifestJSONObject(at: manifestURL)
            assertKnownJSONKeys(
                manifestObject,
                schema: schema,
                fieldIndex: fieldIndex,
                context: "\(fixture.manifest.id) manifest"
            )
        }
    }
}

private indirect enum FixtureJSONSchema {
    case object(structName: String, children: [String: FixtureJSONSchema])
    case array(FixtureJSONSchema)
}

private var fixtureManifestJSONSchema: FixtureJSONSchema {
    object(
        "FixtureManifest",
        children: [
            "expectations": fixtureExpectationsJSONSchema,
            "expectedError": object("FixtureExpectedError"),
        ]
    )
}

private var fixtureExpectationsJSONSchema: FixtureJSONSchema {
    object(
        "FixtureExpectations",
        children: [
            "fileProperty": object("FixtureFilePropertyExpectations"),
            "fileLicense": object("FixtureFileLicenseExpectations"),
            "documentProperties": object(
                "FixtureDocumentPropertiesExpectations",
                children: [
                    "startingIndex": object("FixtureStartingIndexExpectations"),
                    "caratLocation": object("FixtureCaratLocationExpectations"),
                ]
            ),
            "compatibleDocument": object(
                "FixtureCompatibleDocumentExpectations",
                children: [
                    "trackChanges": arrayOf(object("FixtureRawRecordExpectations")),
                    "layoutCompatibility": object("FixtureLayoutCompatibilityExpectations"),
                ]
            ),
            "layoutCompatibility": object("FixtureLayoutCompatibilityExpectations"),
            "docInfoIdMappings": object("FixtureDocInfoIdMappingsExpectations"),
            "docInfoRawRecords": object(
                "FixtureDocInfoRawRecordsExpectations",
                children: [
                    "docData": object("FixtureRawRecordExpectations"),
                    "distributeDocData": object("FixtureRawRecordExpectations"),
                    "trackChanges": arrayOf(object("FixtureRawRecordExpectations")),
                    "memoShapes": arrayOf(object("FixtureRawRecordExpectations")),
                    "trackChangeContents": arrayOf(object("FixtureRawRecordExpectations")),
                    "trackChangeAuthors": arrayOf(object("FixtureRawRecordExpectations")),
                    "forbiddenChars": arrayOf(object("FixtureRawRecordExpectations")),
                ]
            ),
            "docInfoBinData": arrayOf(object("FixtureBinDataExpectations")),
            "docInfoStyles": arrayOf(object("FixtureStyleExpectations")),
            "docInfoNumberings": arrayOf(object("FixtureNumberingExpectations")),
            "docInfoBullets": arrayOf(object("FixtureBulletExpectations")),
            "hyperlinks": arrayOf(object("FixtureHyperlinkExpectations")),
            "genShapeObjects": arrayOf(
                object(
                    "FixtureGenShapeObjectExpectations",
                    children: [
                        "shapeComponents": arrayOf(
                            object(
                                "FixtureShapeComponentExpectations",
                                children: [
                                    "rawChildren": arrayOf(
                                        object("FixtureShapeRawChildExpectations")
                                    ),
                                ]
                            )
                        ),
                    ]
                )
            ),
            "shapeControls": arrayOf(object("FixtureShapeControlExpectations")),
            "tables": arrayOf(object("FixtureTableExpectations")),
            "columns": arrayOf(object("FixtureColumnExpectations")),
            "listControls": arrayOf(object("FixtureListControlExpectations")),
            "pageNumberPositions": arrayOf(object("FixturePageNumberPositionExpectations")),
            "sections": arrayOf(object("FixtureSectionExpectations")),
            "preservedControls": arrayOf(object("FixtureControlPreservationExpectations")),
            "preservedControlSamples": arrayOf(
                object("FixtureControlPreservationExpectations")
            ),
            "fieldControls": arrayOf(
                object(
                    "FixtureFieldControlExpectations",
                    children: [
                        "memoParameter": object("FixtureMemoFieldParameterExpectations"),
                    ]
                )
            ),
            "otherControls": arrayOf(object("FixtureOtherControlExpectations")),
            "otherControlSamples": arrayOf(object("FixtureOtherControlExpectations")),
            "paraRangeTags": arrayOf(object("FixtureParaRangeTagExpectations")),
        ]
    )
}

private var fixtureManifestJSONKeys: Set<String> {
    Set(FixtureManifest.CodingKeys.allCases.map(\.stringValue))
}

private var fixtureExpectationJSONKeys: Set<String> {
    Set(FixtureExpectations.CodingKeys.allCases.map(\.stringValue))
}

private var fixtureExpectedErrorJSONKeys: Set<String> {
    Set(FixtureExpectedError.CodingKeys.allCases.map(\.stringValue))
}

private func manifestJSONObject(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        fail("Expected manifest JSON object at \(url.path)")
        return [:]
    }
    return object
}

private func assertKnownJSONKeys(
    _ object: [String: Any],
    allowedKeys: Set<String>,
    context: String
) {
    let unknownKeys = Set(object.keys).subtracting(allowedKeys)
    expect(unknownKeys).to(
        beEmpty(),
        description: "\(context) has unknown keys: \(unknownKeys.sorted().joined(separator: ", "))"
    )
}

private func assertKnownJSONKeys(
    _ value: Any,
    schema: FixtureJSONSchema,
    fieldIndex: [String: Set<String>],
    context: String
) {
    if value is NSNull {
        return
    }

    switch schema {
    case let .object(structName, children):
        guard let object = value as? [String: Any] else {
            fail("\(context) should be a JSON object for \(structName)")
            return
        }
        guard let allowedKeys = fieldIndex[structName] else {
            fail("No fixture manifest field index for \(structName)")
            return
        }

        assertKnownJSONKeys(object, allowedKeys: allowedKeys, context: context)
        for (key, childSchema) in children {
            guard let childValue = object[key] else {
                continue
            }
            assertKnownJSONKeys(
                childValue,
                schema: childSchema,
                fieldIndex: fieldIndex,
                context: "\(context).\(key)"
            )
        }

    case let .array(elementSchema):
        guard let values = value as? [Any] else {
            fail("\(context) should be a JSON array")
            return
        }
        for (index, element) in values.enumerated() {
            assertKnownJSONKeys(
                element,
                schema: elementSchema,
                fieldIndex: fieldIndex,
                context: "\(context)[\(index)]"
            )
        }
    }
}

private func fixtureManifestDecodableFieldIndex() throws -> [String: Set<String>] {
    let root = testsRoot(from: #file)
    let sourceFileNames = [
        "FixtureManifestSupport.swift",
        "FixtureFileHeaderManifestSupport.swift",
        "FixtureDocInfoIdMappingManifestSupport.swift",
        "FixtureFieldControlManifestSupport.swift",
        "FixtureObjectControlManifestSupport.swift",
        "FixturePageNumberPositionManifestSupport.swift",
        "FixtureSectionManifestSupport.swift",
        "FixtureLoader.swift",
    ]

    return try sourceFileNames.reduce(into: [String: Set<String>]()) { result, fileName in
        let url = root.appendingPathComponent(fileName)
        let source = try String(contentsOf: url, encoding: .utf8)
        result.merge(decodableFieldIndex(in: source)) { current, next in
            current.union(next)
        }
    }
}

private func decodableFieldIndex(in source: String) -> [String: Set<String>] {
    var index = [String: Set<String>]()
    var currentStructName: String?

    for line in source.split(separator: "\n") {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if let structName = decodableStructName(in: trimmedLine) {
            currentStructName = structName
            index[structName, default: []] = []
            continue
        }

        guard let structName = currentStructName else {
            continue
        }
        if trimmedLine == "}" {
            currentStructName = nil
            continue
        }
        if let propertyName = storedPropertyName(in: trimmedLine) {
            index[structName, default: []].insert(propertyName)
        }
    }

    return index
}

private func decodableStructName(in line: String) -> String? {
    guard line.hasPrefix("struct "), line.contains(": Decodable") else {
        return nil
    }
    let name = line.dropFirst("struct ".count).prefix(while: isSwiftIdentifierCharacter)
    return name.isEmpty ? nil : String(name)
}

private func storedPropertyName(in line: String) -> String? {
    guard line.hasPrefix("let ") else {
        return nil
    }
    let name = line.dropFirst("let ".count).prefix(while: isSwiftIdentifierCharacter)
    return name.isEmpty ? nil : String(name)
}

private func isSwiftIdentifierCharacter(_ character: Character) -> Bool {
    character == "_" || character.isLetter || character.isNumber
}

private func assertSchemaTypesHaveFieldDefinitions(
    _ schema: FixtureJSONSchema,
    fieldIndex: [String: Set<String>]
) {
    switch schema {
    case let .object(structName, children):
        expect(fieldIndex[structName]).notTo(
            beNil(),
            description: "No fixture manifest field index for \(structName)"
        )
        for childSchema in children.values {
            assertSchemaTypesHaveFieldDefinitions(childSchema, fieldIndex: fieldIndex)
        }

    case let .array(elementSchema):
        assertSchemaTypesHaveFieldDefinitions(elementSchema, fieldIndex: fieldIndex)
    }
}

private func object(
    _ structName: String,
    children: [String: FixtureJSONSchema] = [:]
) -> FixtureJSONSchema {
    .object(structName: structName, children: children)
}

private func arrayOf(_ schema: FixtureJSONSchema) -> FixtureJSONSchema {
    .array(schema)
}
