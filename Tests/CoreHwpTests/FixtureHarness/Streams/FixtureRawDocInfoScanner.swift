@testable import CoreHwp
import Foundation
import OLEKit

enum FixtureRawDocInfoScanner {
    struct RecordTag: Equatable {
        let tagId: UInt32
        let level: UInt32
    }

    static func topLevelStreamNames(in fixture: LoadedFixture) throws -> Set<String> {
        let streams = try rootStreams(in: fixture)
        return Set(streams.keys)
    }

    static func storageChildNames(
        in fixture: LoadedFixture,
        streamName: HwpStreamName
    ) throws -> [String] {
        let streams = try rootStreams(in: fixture)
        guard let storage = streams[streamName.rawValue] else {
            return []
        }
        return StreamReader.sortedStorageChildNames(
            storage.children.map { (name: $0.name, type: $0.type) },
            for: streamName
        )
    }

    static func topLevelTagIds(in fixture: LoadedFixture) throws -> [UInt32] {
        try docInfoRootRecord(in: fixture).children.map(\.tagId)
    }

    static func recordTags(in fixture: LoadedFixture) throws -> [RecordTag] {
        flattenedRecordTags(from: try docInfoRootRecord(in: fixture).children)
    }

    private static func docInfoRootRecord(in fixture: LoadedFixture) throws -> HwpRecord {
        let fileHeader = try HwpFileHeader.load(fromPath: fixture.documentURL.path)
        let ole = try oleFile(for: fixture)
        let streams = try StreamReader.rootStreams(from: ole.root.children)
        let reader = StreamReader(ole, streams)
        guard let docInfoData = try reader.getOptionalDataFromStream(
            .docInfo,
            fileHeader.fileProperty.isCompressed
        ) else {
            return HwpRecord(tagId: 0, level: 0, payload: Data())
        }
        return try parseTreeRecord(data: docInfoData)
    }

    private static func flattenedRecordTags(from records: [HwpRecord]) -> [RecordTag] {
        records.flatMap { record in
            [RecordTag(tagId: record.tagId, level: record.level)] +
                flattenedRecordTags(from: record.children)
        }
    }

    private static func oleFile(for fixture: LoadedFixture) throws -> OLEFile {
        do {
            return try OLEFile(fixture.documentURL.path)
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
    }

    private static func rootStreams(in fixture: LoadedFixture) throws -> [String: DirectoryEntry] {
        let ole = try oleFile(for: fixture)
        return try StreamReader.rootStreams(from: ole.root.children)
    }
}
