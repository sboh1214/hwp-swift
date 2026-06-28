import Foundation
import Nimble
import XCTest

final class FixtureOtherControlFeatureGateTests: XCTestCase {
    func testOtherControlGateRejectsMissingUnknownChildPayloadSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "hiddenComment",
          "rawPayloadLength": 4,
          "rawPayloadPrefixBytes": [116, 109, 99, 116],
          "rawPayloadSuffixBytes": [116, 109, 99, 116],
          "rawTrailingLength": 0,
          "rawTrailingPrefixBytes": [],
          "rawTrailingSuffixBytes": [],
          "unknownChildCount": 1
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == false
    }

    func testOtherControlGateAcceptsUnknownChildPayloadSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "hiddenComment",
          "rawPayloadLength": 4,
          "rawPayloadPrefixBytes": [116, 109, 99, 116],
          "rawPayloadSuffixBytes": [116, 109, 99, 116],
          "rawTrailingLength": 0,
          "rawTrailingPrefixBytes": [],
          "rawTrailingSuffixBytes": [],
          "unknownChildCount": 1,
          "unknownChildTagIds": [66],
          "unknownChildPayloadLengths": [22],
          "unknownChildPayloadPrefixBytes": [[1, 0]],
          "unknownChildPayloadSuffixBytes": [[0, 128]],
          "unknownChildChildTagIds": [[68]],
          "unknownChildChildPayloadLengths": [[8]],
          "unknownChildChildPayloadPrefixBytes": [[[0, 0]]],
          "unknownChildChildPayloadSuffixBytes": [[[0, 0]]]
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == true
    }

    func testOtherControlGateRejectsCtrlDataCountWithoutPayloadSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "bookmark",
          "rawPayloadLength": 4,
          "rawPayloadPrefixBytes": [109, 107, 111, 98],
          "rawPayloadSuffixBytes": [109, 107, 111, 98],
          "rawTrailingLength": 0,
          "rawTrailingPrefixBytes": [],
          "rawTrailingSuffixBytes": [],
          "ctrlDataCount": 1,
          "unknownChildCount": 0
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == false
    }

    func testOtherControlGateAcceptsCtrlDataPayloadSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "bookmark",
          "rawPayloadLength": 4,
          "rawPayloadPrefixBytes": [109, 107, 111, 98],
          "rawPayloadSuffixBytes": [109, 107, 111, 98],
          "rawTrailingLength": 0,
          "rawTrailingPrefixBytes": [],
          "rawTrailingSuffixBytes": [],
          "ctrlDataCount": 1,
          "ctrlDataPayloadLengths": [16],
          "ctrlDataPayloadPrefixBytes": [[0, 0, 0, 0]],
          "ctrlDataPayloadSuffixBytes": [[66, 0, 75, 0]],
          "unknownChildCount": 0
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == true
    }

    func testOtherControlGateRejectsNumberingWithoutRawTrailingSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "autoNumber",
          "numberingKind": 1,
          "numberingValue": 1,
          "numberingFormat": 2686976,
          "rawPayloadLength": 16,
          "rawPayloadPrefixBytes": [111, 110, 116, 97],
          "rawPayloadSuffixBytes": [0, 0, 41, 0],
          "rawTrailingLength": 12,
          "rawTrailingPrefixBytes": [1, 0, 0, 0],
          "rawTrailingSuffixBytes": [0, 0, 41, 0],
          "ctrlDataCount": 0,
          "unknownChildCount": 0
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == false
    }

    func testOtherControlGateAcceptsNumberingRawTrailingSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "autoNumber",
          "numberingKind": 1,
          "numberingValue": 1,
          "numberingFormat": 2686976,
          "numberingRawTrailingLength": 0,
          "numberingRawTrailingPrefixBytes": [],
          "numberingRawTrailingSuffixBytes": [],
          "rawPayloadLength": 16,
          "rawPayloadPrefixBytes": [111, 110, 116, 97],
          "rawPayloadSuffixBytes": [0, 0, 41, 0],
          "rawTrailingLength": 12,
          "rawTrailingPrefixBytes": [1, 0, 0, 0],
          "rawTrailingSuffixBytes": [0, 0, 41, 0],
          "ctrlDataCount": 0,
          "unknownChildCount": 0
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == true
    }

    func testOtherControlGateRejectsBookmarkWithoutRawTrailingSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "bookmark",
          "bookmarkName": "CoreHwpBookmark",
          "bookmarkNameCharacterCount": 15,
          "bookmarkNameLengthRawPayloadLength": 2,
          "bookmarkNameLengthRawPayloadPrefixBytes": [15, 0],
          "bookmarkNameLengthRawPayloadSuffixBytes": [15, 0],
          "bookmarkNameRawPayloadLength": 30,
          "bookmarkNameRawPayloadPrefixBytes": [67, 0],
          "bookmarkNameRawPayloadSuffixBytes": [107, 0],
          "rawPayloadLength": 4,
          "rawPayloadPrefixBytes": [109, 107, 111, 98],
          "rawPayloadSuffixBytes": [109, 107, 111, 98],
          "rawTrailingLength": 0,
          "rawTrailingPrefixBytes": [],
          "rawTrailingSuffixBytes": [],
          "ctrlDataCount": 1,
          "ctrlDataPayloadLengths": [42],
          "ctrlDataPayloadPrefixBytes": [[27, 2, 1, 0]],
          "ctrlDataPayloadSuffixBytes": [[114, 0, 107, 0]],
          "unknownChildCount": 0
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == false
    }

    func testOtherControlGateRejectsBookmarkWithoutLengthRawSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "bookmark",
          "bookmarkName": "CoreHwpBookmark",
          "bookmarkNameCharacterCount": 15,
          "bookmarkNameRawPayloadLength": 30,
          "bookmarkNameRawPayloadPrefixBytes": [67, 0],
          "bookmarkNameRawPayloadSuffixBytes": [107, 0],
          "bookmarkRawTrailingLength": 0,
          "bookmarkRawTrailingPrefixBytes": [],
          "bookmarkRawTrailingSuffixBytes": [],
          "rawPayloadLength": 4,
          "rawPayloadPrefixBytes": [109, 107, 111, 98],
          "rawPayloadSuffixBytes": [109, 107, 111, 98],
          "rawTrailingLength": 0,
          "rawTrailingPrefixBytes": [],
          "rawTrailingSuffixBytes": [],
          "ctrlDataCount": 1,
          "ctrlDataPayloadLengths": [42],
          "ctrlDataPayloadPrefixBytes": [[27, 2, 1, 0]],
          "ctrlDataPayloadSuffixBytes": [[114, 0, 107, 0]],
          "unknownChildCount": 0
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == false
    }

    func testOtherControlGateAcceptsBookmarkRawTrailingSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "bookmark",
          "bookmarkName": "CoreHwpBookmark",
          "bookmarkNameCharacterCount": 15,
          "bookmarkNameLengthRawPayloadLength": 2,
          "bookmarkNameLengthRawPayloadPrefixBytes": [15, 0],
          "bookmarkNameLengthRawPayloadSuffixBytes": [15, 0],
          "bookmarkNameRawPayloadLength": 30,
          "bookmarkNameRawPayloadPrefixBytes": [67, 0],
          "bookmarkNameRawPayloadSuffixBytes": [107, 0],
          "bookmarkRawTrailingLength": 0,
          "bookmarkRawTrailingPrefixBytes": [],
          "bookmarkRawTrailingSuffixBytes": [],
          "rawPayloadLength": 4,
          "rawPayloadPrefixBytes": [109, 107, 111, 98],
          "rawPayloadSuffixBytes": [109, 107, 111, 98],
          "rawTrailingLength": 0,
          "rawTrailingPrefixBytes": [],
          "rawTrailingSuffixBytes": [],
          "ctrlDataCount": 1,
          "ctrlDataPayloadLengths": [42],
          "ctrlDataPayloadPrefixBytes": [[27, 2, 1, 0]],
          "ctrlDataPayloadSuffixBytes": [[114, 0, 107, 0]],
          "unknownChildCount": 0
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == true
    }

    func testOtherControlGateRejectsIndexmarkWithoutLengthRawSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "indexmark",
          "indexmarkText": "개별행위설",
          "indexmarkTextCharacterCount": 5,
          "indexmarkTextRawPayloadLength": 10,
          "indexmarkTextRawPayloadPrefixBytes": [28, 172],
          "indexmarkTextRawPayloadSuffixBytes": [36, 193],
          "indexmarkRawTrailingLength": 6,
          "indexmarkRawTrailingPrefixBytes": [0, 0],
          "indexmarkRawTrailingSuffixBytes": [0, 0],
          "rawPayloadLength": 22,
          "rawPayloadPrefixBytes": [109, 120, 100, 105],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "rawTrailingLength": 18,
          "rawTrailingPrefixBytes": [5, 0],
          "rawTrailingSuffixBytes": [0, 0],
          "ctrlDataCount": 0,
          "unknownChildCount": 0
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == false
    }

    func testOtherControlGateAcceptsIndexmarkLengthRawSamples() throws {
        let control = try decodeOtherControl("""
        {
          "ctrlIdName": "indexmark",
          "indexmarkText": "개별행위설",
          "indexmarkTextCharacterCount": 5,
          "indexmarkTextLengthRawPayloadLength": 2,
          "indexmarkTextLengthRawPayloadPrefixBytes": [5, 0],
          "indexmarkTextLengthRawPayloadSuffixBytes": [5, 0],
          "indexmarkTextRawPayloadLength": 10,
          "indexmarkTextRawPayloadPrefixBytes": [28, 172],
          "indexmarkTextRawPayloadSuffixBytes": [36, 193],
          "indexmarkRawTrailingLength": 6,
          "indexmarkRawTrailingPrefixBytes": [0, 0],
          "indexmarkRawTrailingSuffixBytes": [0, 0],
          "rawPayloadLength": 22,
          "rawPayloadPrefixBytes": [109, 120, 100, 105],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "rawTrailingLength": 18,
          "rawTrailingPrefixBytes": [5, 0],
          "rawTrailingSuffixBytes": [0, 0],
          "ctrlDataCount": 0,
          "unknownChildCount": 0
        }
        """)

        expect(otherControlHasPayloadSamples(control)) == true
    }
}

private func decodeOtherControl(_ json: String) throws -> FixtureOtherControlExpectations {
    try JSONDecoder().decode(FixtureOtherControlExpectations.self, from: Data(json.utf8))
}
