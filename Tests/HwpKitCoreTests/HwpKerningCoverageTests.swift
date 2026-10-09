import CoreGraphics
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 글꼴 커닝·치환 집합 (#260, `HwpKerningCoverage`) — 이 집합 밖 글리프만 자간을 kern에 싣는다. 해석기는
    /// 설치 글꼴 934종에서 fontTools와 글리프 집합이 같음을 확인했다(2026-10-08, `probes/260`). 여기서는
    /// 합성 표로 형식별 규칙과 "해석 못 하면 전체" 쪽을 잠근다.
    final class HwpKerningCoverageTests: XCTestCase {
        /// 큰 끝 바이트 조립.
        private struct Bytes {
            var data = Data()

            mutating func u16(_ values: Int...) {
                for value in values {
                    data.append(UInt8((value >> 8) & 0xFF))
                    data.append(UInt8(value & 0xFF))
                }
            }

            mutating func u32(_ value: Int) {
                u16(value >> 16, value & 0xFFFF)
            }
        }

        private static func members(_ set: HwpKerningCoverage.GlyphSet?) -> [Int]? {
            set.map { set in (0 ..< 256).filter { set.contains(CGGlyph($0)) } }
        }

        func testMicrosoftKernTableCollectsNonZeroLeftGlyphs() {
            var table = Bytes()
            table.u16(0, 1) // 버전 0, 부분표 1
            table.u16(0, 6 + 8 + 12, 0x0001) // 부분표 버전·길이·coverage(형식 0, 가로)
            table.u16(2, 12, 1, 0) // 짝 2, searchRange·entrySelector·rangeShift
            table.u16(5, 6, 0xFFCE) // (5, 6) −50
            table.u16(7, 8, 0) // (7, 8) 0 — 값 0은 짝이 아니다
            let set = HwpKerningCoverage.parse(kern: table.data, kerx: nil, gpos: nil)
            expect(Self.members(set)) == [5]
        }

        func testAppleKernTableFollowsTheSubtableLengthAcrossPadding() {
            // 애플 판은 부분표 끝에 채움 바이트를 둘 수 있다 — 짝 수로 재면 둘째 부분표 머리를 놓친다.
            var table = Bytes()
            table.u32(0x0001_0000)
            table.u32(2)
            table.u32(8 + 8 + 6 + 2) // 길이(채움 2바이트 포함)
            table.u16(0x0000, 0) // coverage(형식 0)·tuple
            table.u16(1, 6, 0, 0)
            table.u16(10, 11, 0xFFEC)
            table.u16(0) // 채움
            table.u32(8 + 8 + 6)
            table.u16(0x0000, 0)
            table.u16(1, 6, 0, 0)
            table.u16(12, 13, 30)
            let set = HwpKerningCoverage.parse(kern: table.data, kerx: nil, gpos: nil)
            expect(Self.members(set)) == [10, 12]
        }

        func testUnparsedTablesMeanEveryGlyph() {
            var format2 = Bytes()
            format2.u16(0, 1)
            format2.u16(0, 6, 0x0201) // 형식 2
            expect(HwpKerningCoverage.parse(kern: format2.data, kerx: nil, gpos: nil)).to(beNil())
            expect(HwpKerningCoverage.parse(kern: nil, kerx: Data([0]), gpos: nil)).to(beNil())
            expect(HwpKerningCoverage.parse(kern: nil, kerx: nil, gpos: nil, morx: Data([0])))
                .to(beNil())
            // 잘린 표
            expect(HwpKerningCoverage.parse(kern: Data([0, 0, 0, 1]), kerx: nil, gpos: nil))
                .to(beNil())
            // 표가 없으면 빈 집합이다.
            expect(HwpKerningCoverage.parse(kern: nil, kerx: nil, gpos: nil)?.isEmpty) == true
        }

        /// GPOS·GSUB 공통 머리 + 룩업 목록. `lookups`는 (유형, 부분표 바이트) — 부분표 안 오프셋은 부분표
        /// 시작 기준이다.
        private static func layoutTable(_ lookups: [(type: Int, subtable: Data)]) -> Data {
            var table = Bytes()
            table.u16(1, 0, 0, 0, 10) // 버전 1.0, 스크립트·기능 목록 없음, 룩업 목록 10
            let listStart = 10
            var lookupBodies: [Data] = []
            for lookup in lookups {
                var body = Bytes()
                body.u16(lookup.type, 0, 1, 8) // 유형·플래그·부분표 1개·오프셋 8
                body.data.append(lookup.subtable)
                lookupBodies.append(body.data)
            }
            var list = Bytes()
            list.u16(lookups.count)
            var offset = 2 + lookups.count * 2
            for body in lookupBodies {
                list.u16(offset)
                offset += body.count
            }
            for body in lookupBodies {
                list.data.append(body)
            }
            precondition(table.data.count == listStart)
            table.data.append(list.data)
            return table.data
        }

        private static func coverage1(_ glyphs: [Int]) -> Data {
            var bytes = Bytes()
            bytes.u16(1, glyphs.count)
            for glyph in glyphs {
                bytes.u16(glyph)
            }
            return bytes.data
        }

        func testGPOSCollectsSinglePairAndExtensionCoverageButNotMarks() {
            // 짝 조정(형식 1, 커버리지는 +2의 오프셋) [20, 21]
            var pair = Bytes()
            pair.u16(1, 10, 0, 0, 0) // 형식·커버리지 10·값 형식 0·0·짝 집합 0
            pair.data.append(Self.coverage1([20, 21]))
            // 확장(9) → 단일 조정(1) 형식 1, 범위 커버리지 30–32
            var single = Bytes()
            single.u16(1, 6, 0)
            single.u16(2, 1, 30, 32, 0) // 커버리지 형식 2: 범위 1개
            var wrapper = Bytes()
            wrapper.u16(1, 1)
            wrapper.u32(8)
            wrapper.data.append(single.data)
            // 표시 위치 조정(4)은 kern 0에서도 걸리므로 넣지 않는다.
            var mark = Bytes()
            mark.u16(1, 12, 12, 0, 0, 0)
            mark.data.append(Self.coverage1([50]))
            let gpos = Self.layoutTable([(2, pair.data), (9, wrapper.data), (4, mark.data)])
            let set = HwpKerningCoverage.parse(kern: nil, kerx: nil, gpos: gpos)
            expect(Self.members(set)) == [20, 21, 30, 31, 32]
        }

        func testGSUBCollectsLigatureAndContextStartGlyphs() {
            // 합자(4) 형식 1 [41]
            var ligature = Bytes()
            ligature.u16(1, 6, 0)
            ligature.data.append(Self.coverage1([41]))
            // 문맥 연쇄(6) 형식 3: 앞 문맥 1개, 입력 커버리지 [40]
            var chained = Bytes()
            chained.u16(3, 1, 14, 1, 20, 0, 0) // 형식·앞 1·오프셋 14·입력 1·오프셋 20·뒤 0·치환 0
            chained.data.append(Self.coverage1([99])) // 앞 문맥 커버리지(14) — 시작 글리프가 아니다
            chained.data.append(Self.coverage1([40]))
            // 확장(7) → 문맥(5) 형식 3: 입력 1개·치환 0, 커버리지 [42]
            var context = Bytes()
            context.u16(3, 1, 0, 8)
            context.data.append(Self.coverage1([42]))
            var wrapper = Bytes()
            wrapper.u16(1, 5)
            wrapper.u32(8)
            wrapper.data.append(context.data)
            // 결과(60)가 집합 밖인 단일 치환(1)의 입력은 들지 않는다.
            var single = Bytes()
            single.u16(1, 6, 0)
            single.data.append(Self.coverage1([60]))
            let gsub = Self.layoutTable([
                (4, ligature.data), (6, chained.data), (7, wrapper.data), (1, single.data),
            ])
            let set = HwpKerningCoverage.parse(kern: nil, kerx: nil, gpos: nil, gsub: gsub)
            expect(Self.members(set)) == [40, 41, 42]
        }

        /// 단일 치환 형식 2 — `coverage[i]` → `results[i]`.
        private static func singleSubstitution(_ coverage: [Int], _ results: [Int]) -> Data {
            var bytes = Bytes()
            bytes.u16(2, 6 + results.count * 2, results.count)
            for result in results {
                bytes.u16(result)
            }
            bytes.data.append(Self.coverage1(coverage))
            return bytes.data
        }

        /// 다중(2)·대체(3) 치환 형식 1 — 입력 하나와 그 결과 목록.
        private static func sequenceSubstitution(_ input: Int, _ results: [Int]) -> Data {
            var bytes = Bytes()
            bytes.u16(1, 8 + 2 + results.count * 2, 1, 8) // 형식·커버리지·수 1·순서열 오프셋 8
            bytes.u16(results.count)
            for result in results {
                bytes.u16(result)
            }
            bytes.data.append(Self.coverage1([input]))
            return bytes.data
        }

        func testSubstitutionInputsJoinWhenTheirResultsAreCovered() {
            // 커버리지는 치환 뒤 글리프를 가리킨다 — 결과가 집합(여기선 GPOS 단일 조정 [20])에 드는 단일·다중·대체
            // 치환의 입력도 집합이다 (아랍 문자의 어두 형태가 필기체 연결 커버리지에 드는 경우, #260 리뷰).
            var adjustment = Bytes()
            adjustment.u16(1, 6, 0)
            adjustment.data.append(Self.coverage1([20]))
            let gpos = Self.layoutTable([(1, adjustment.data)])
            // 단일 형식 1(델타): 10 → 20.
            var delta = Bytes()
            delta.u16(1, 6, 10)
            delta.data.append(Self.coverage1([10]))
            // 확장(7) → 단일 형식 2: 11 → 30(집합 밖).
            var wrapper = Bytes()
            wrapper.u16(1, 1)
            wrapper.u32(8)
            wrapper.data.append(Self.singleSubstitution([11], [30]))
            // 사슬: 14 → 15 → 20. 앞 규칙이 먼저 훑여도 15가 든 뒤 14가 든다.
            let gsub = Self.layoutTable([
                (1, delta.data), (7, wrapper.data),
                (2, Self.sequenceSubstitution(12, [40, 20])),
                (3, Self.sequenceSubstitution(13, [50])),
                (1, Self.singleSubstitution([14], [15])),
                (1, Self.singleSubstitution([15], [20])),
            ])
            let set = HwpKerningCoverage.parse(kern: nil, kerx: nil, gpos: gpos, gsub: gsub)
            expect(Self.members(set)) == [10, 12, 14, 15, 20]
            // 결과를 집합에 넣는 조정이 없으면 치환 입력은 들지 않는다.
            let unadjusted = HwpKerningCoverage.parse(kern: nil, kerx: nil, gpos: nil, gsub: gsub)
            expect(Self.members(unadjusted)) == []
            // 형식을 모르는 치환 부분표는 해석하지 못한 것이다(nil = 전체 글리프).
            let unknown = Self.layoutTable([(1, Data([0, 3, 0, 6]) + Self.coverage1([1]))])
            let unparsed = HwpKerningCoverage.parse(kern: nil, kerx: nil, gpos: gpos, gsub: unknown)
            expect(unparsed).to(beNil())
        }

        func testSharedOffsetsAreWalkedOnce() {
            // 조작된 표: 룩업 1,000개가 한 룩업을, 그 룩업의 부분표 1,000개가 한 부분표(단일 조정, 커버리지
            // 2글리프)를 가리킨다. 한 번만 훑으면 약 2,000 항목이고, 자리마다 다시 훑으면 1,000 × (1,000 +
            // 1,000 × 2) = 3,000,000 항목으로 예산(2^20)을 넘어 nil(전체 글리프)이 된다.
            let count = 1000
            var table = Bytes()
            table.u16(1, 0, 0, 0, 10)
            table.u16(count)
            for _ in 0 ..< count {
                table.u16(2 + 2 * count) // 룩업 목록 바로 뒤의 한 룩업
            }
            table.u16(1, 0, count) // 유형 1(단일 조정)·플래그·부분표 수
            for _ in 0 ..< count {
                table.u16(6 + 2 * count) // 룩업 머리 바로 뒤의 한 부분표
            }
            table.u16(1, 6, 0) // 형식 1·커버리지 6·값 형식 0
            table.data.append(Self.coverage1([10, 11]))
            let set = HwpKerningCoverage.parse(kern: nil, kerx: nil, gpos: table.data)
            expect(Self.members(set)) == [10, 11]
        }

        func testWideCoverageRangesSpendTheirWords() {
            // 범위 기록 하나는 채우는 낱말(64글리프) 수만큼 예산을 쓴다 — 0…65535 범위 1,100개는 기록 수로는
            // 1,100이지만 낱말로는 1,126,400이라 예산(2^20)을 넘어 해석을 포기한다(nil = 전체 글리프).
            var single = Bytes()
            single.u16(1, 6, 0)
            single.u16(2, 1100)
            for _ in 0 ..< 1100 {
                single.u16(0, 0xFFFF, 0)
            }
            let gpos = Self.layoutTable([(1, single.data)])
            expect(HwpKerningCoverage.parse(kern: nil, kerx: nil, gpos: gpos) == nil) == true
            // 대조군: 같은 기록 수의 좁은 범위는 예산 안이다.
            var narrow = Bytes()
            narrow.u16(1, 6, 0)
            narrow.u16(2, 1100)
            for _ in 0 ..< 1100 {
                narrow.u16(3, 4, 0)
            }
            let narrowSet = HwpKerningCoverage.parse(
                kern: nil, kerx: nil, gpos: Self.layoutTable([(1, narrow.data)])
            )
            expect(Self.members(narrowSet)) == [3, 4]
        }

        func testSubtableSharedAcrossLookupTypesIsReadForEach() {
            // 건너뛰는 유형(GSUB 1)의 룩업과 모으는 유형(GSUB 4)의 룩업이 같은 부분표 바이트를 가리킨다 —
            // `[0001][커버리지][합자 집합 수][오프셋]`은 단일 치환 형식 1로도 합자 치환 형식 1로도 읽힌다.
            // 룩업 순서와 무관하게 합자 시작 글리프가 들어야 한다.
            for types in [[1, 4], [4, 1]] {
                var table = Bytes()
                table.u16(1, 0, 0, 0, 10)
                table.u16(2, 6, 14) // 룩업 둘 (목록 기준 6·14)
                table.u16(types[0], 0, 1, 16) // 룩업 A — 부분표는 목록 기준 22
                table.u16(types[1], 0, 1, 8) // 룩업 B — 같은 자리
                table.u16(1, 8, 1, 10) // 형식 1·커버리지 8·합자 집합 1·오프셋
                table.data.append(Self.coverage1([41]))
                let set = HwpKerningCoverage.parse(
                    kern: nil, kerx: nil, gpos: nil, gsub: table.data
                )
                expect(Self.members(set)).to(equal([41]), description: "\(types)")
            }
        }

        func testWorkBudgetGivesUpAsEveryGlyph() {
            var walk = HwpKerningCoverage.Walk()
            expect(walk.spend(HwpKerningCoverage.Walk.maximumWork)) == true
            expect(walk.spend(1)) == false
        }

        func testUnknownLookupTypeMeansEveryGlyph() {
            let gpos = Self.layoutTable([(10, Data([0, 1, 0, 6]))])
            expect(HwpKerningCoverage.parse(kern: nil, kerx: nil, gpos: gpos)).to(beNil())
        }

        func testSystemFonts() {
            func glyph(_ character: UniChar, _ font: CTFont) -> CGGlyph {
                var character = character
                var glyph = CGGlyph()
                _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
                return glyph
            }
            // macOS·iOS 공통 글꼴(iOS 27 런타임 글꼴 파일로도 같은 판정을 확인했다): Times New Roman은 `A`가 짝
            // 커닝의 첫 글리프, Apple SD 산돌고딕 Neo는 한글 음절이 집합 밖, Menlo는 AAT `morx`라 해석하지 않는다.
            let times = CTFontCreateWithName("TimesNewRomanPSMT" as CFString, 12, nil)
            let gothic = CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, 12, nil)
            expect(HwpKerningCoverage.glyphs(of: times)?.contains(glyph(0x41, times))) == true
            expect(HwpKerningCoverage.glyphs(of: gothic)?.contains(glyph(0xAC00, gothic))) == false
            expect(HwpKerningCoverage.glyphs(of: gothic)?.contains(glyph(0x41, gothic))) == true
            let menlo = CTFontCreateWithName("Menlo-Regular" as CFString, 12, nil)
            expect(HwpKerningCoverage.glyphs(of: menlo)).to(beNil())
        }
    }
#endif
