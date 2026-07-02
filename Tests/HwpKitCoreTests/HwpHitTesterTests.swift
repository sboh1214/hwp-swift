import CoreGraphics
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpHitTesterTests: XCTestCase {
    private let tester = HwpHitTester()
    private let defaultMargins = HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0)
    private let pageSize = CGSize(width: 595, height: 842)

    func testTextBlockHit() {
        let block = AnyHwpBlock(frame: CGRect(x: 10, y: 10, width: 90, height: 40), kind: .text)
        let page = HwpPage(size: pageSize, margins: defaultMargins, blocks: [block], pageNumber: 1)
        let result = tester.hit(page: page, point: CGPoint(x: 50, y: 30))
        expect(result) == .text(blockIndex: 0, characterIndex: nil)
    }

    func testMissReturnsNil() {
        let block = AnyHwpBlock(frame: CGRect(x: 10, y: 10, width: 90, height: 40), kind: .text)
        let page = HwpPage(size: pageSize, margins: defaultMargins, blocks: [block], pageNumber: 1)
        let result = tester.hit(page: page, point: CGPoint(x: 200, y: 200))
        expect(result).to(beNil())
    }

    func testTableBlockHit() {
        let block = AnyHwpBlock(frame: CGRect(x: 20, y: 60, width: 200, height: 100), kind: .table)
        let page = HwpPage(size: pageSize, margins: defaultMargins, blocks: [block], pageNumber: 1)
        let result = tester.hit(page: page, point: CGPoint(x: 100, y: 110))
        expect(result) == .table(blockIndex: 0, row: 0, col: 0)
    }

    func testImageBlockHit() {
        let block = AnyHwpBlock(frame: CGRect(x: 0, y: 0, width: 150, height: 150), kind: .image)
        let page = HwpPage(size: pageSize, margins: defaultMargins, blocks: [block], pageNumber: 1)
        let result = tester.hit(page: page, point: CGPoint(x: 75, y: 75))
        expect(result) == .image(blockIndex: 0)
    }

    func testOverlappingBlocksLastWins() {
        let bottom = AnyHwpBlock(frame: CGRect(x: 0, y: 0, width: 100, height: 100), kind: .image)
        let top = AnyHwpBlock(frame: CGRect(x: 50, y: 50, width: 100, height: 100), kind: .text)
        let page = HwpPage(size: pageSize, margins: defaultMargins, blocks: [bottom, top], pageNumber: 1)
        let result = tester.hit(page: page, point: CGPoint(x: 60, y: 60))
        expect(result) == .text(blockIndex: 1, characterIndex: nil)
    }

    func testPlaceholderBlockHit() {
        let block = AnyHwpBlock(frame: CGRect(x: 10, y: 10, width: 80, height: 80), kind: .placeholder)
        let page = HwpPage(size: pageSize, margins: defaultMargins, blocks: [block], pageNumber: 1)
        let result = tester.hit(page: page, point: CGPoint(x: 50, y: 50))
        expect(result) == .placeholder(blockIndex: 0, kind: .placeholder)
    }

    func testEmptyPageReturnsNil() {
        let page = HwpPage(size: pageSize, margins: defaultMargins, blocks: [], pageNumber: 1)
        let result = tester.hit(page: page, point: CGPoint(x: 50, y: 50))
        expect(result).to(beNil())
    }
}
