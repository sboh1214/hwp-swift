import Foundation
import SWCompression

/// 테스트 전용 ZIP 아카이브 합성기.
///
/// `HwpxArchive`의 malformed/경계 입력 테스트를 위해 local file header +
/// central directory + EOCD를 바이트 단위로 직접 쓴다. SWCompression은 ZIP
/// 컨테이너 **작성**을 지원하지 않으므로 (`Deflate.compress`는 raw DEFLATE
/// payload만 만든다) 여기서 손으로 조립한다. 필드 오버라이드로 손상
/// 아카이브를 만들 수 있다.
struct ZipBuilder {
    struct Entry {
        var name: String
        var content: Data
        var method: UInt16
        /// nil이면 method에 따라 자동 산출 (0 = content 그대로, 8 = deflate).
        var storedPayload: Data?
        var flags: UInt16
        /// nil이면 실제 값. central directory에만 반영되는 오버라이드다.
        var declaredCompressedSize: UInt32?
        var declaredUncompressedSize: UInt32?

        init(
            name: String,
            content: Data,
            method: UInt16 = 8,
            storedPayload: Data? = nil,
            flags: UInt16 = 0,
            declaredCompressedSize: UInt32? = nil,
            declaredUncompressedSize: UInt32? = nil
        ) {
            self.name = name
            self.content = content
            self.method = method
            self.storedPayload = storedPayload
            self.flags = flags
            self.declaredCompressedSize = declaredCompressedSize
            self.declaredUncompressedSize = declaredUncompressedSize
        }

        var payload: Data {
            if let storedPayload {
                return storedPayload
            }
            return method == 8 ? Deflate.compress(data: content) : content
        }
    }

    var entries: [Entry] = []
    var comment: Data = .init()
    /// nil이면 실제 엔트리 수를 쓴다.
    var declaredEntryCount: UInt16?

    func build() -> Data {
        var archive = Data()
        var directory = Data()

        for entry in entries {
            let headerOffset = UInt32(archive.count)
            appendLocalRecord(of: entry, to: &archive)
            appendDirectoryRecord(of: entry, headerOffset: headerOffset, to: &directory)
        }

        let directoryOffset = UInt32(archive.count)
        archive.append(directory)

        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0)) // disk
        archive.appendLittleEndian(UInt16(0)) // CD disk
        let entryCount = declaredEntryCount ?? UInt16(entries.count)
        archive.appendLittleEndian(entryCount)
        archive.appendLittleEndian(entryCount)
        archive.appendLittleEndian(UInt32(directory.count))
        archive.appendLittleEndian(directoryOffset)
        archive.appendLittleEndian(UInt16(comment.count))
        archive.append(comment)
        return archive
    }

    /// local file header + payload — data descriptor(비트 3) 흉내를 위해 CD와
    /// 별개로 크기 0을 적을 수 있게 flags로 가른다.
    private func appendLocalRecord(of entry: Entry, to archive: inout Data) {
        let payload = entry.payload
        let nameBytes = Data(entry.name.utf8)
        let crc = ZipBuilder.crc32(of: entry.content)
        let compressedSize = entry.declaredCompressedSize ?? UInt32(payload.count)
        let uncompressedSize = entry.declaredUncompressedSize ?? UInt32(entry.content.count)

        archive.appendLittleEndian(UInt32(0x0403_4B50))
        archive.appendLittleEndian(UInt16(20))
        archive.appendLittleEndian(entry.flags)
        archive.appendLittleEndian(entry.method)
        archive.appendLittleEndian(UInt32(0)) // 시각
        let usesDataDescriptor = entry.flags & 0b1000 != 0
        archive.appendLittleEndian(usesDataDescriptor ? 0 : crc)
        archive.appendLittleEndian(usesDataDescriptor ? 0 : compressedSize)
        archive.appendLittleEndian(usesDataDescriptor ? 0 : uncompressedSize)
        archive.appendLittleEndian(UInt16(nameBytes.count))
        archive.appendLittleEndian(UInt16(0)) // extra 없음
        archive.append(nameBytes)
        archive.append(payload)
        if usesDataDescriptor {
            archive.appendLittleEndian(UInt32(0x0807_4B50))
            archive.appendLittleEndian(crc)
            archive.appendLittleEndian(compressedSize)
            archive.appendLittleEndian(uncompressedSize)
        }
    }

    private func appendDirectoryRecord(
        of entry: Entry,
        headerOffset: UInt32,
        to directory: inout Data
    ) {
        let nameBytes = Data(entry.name.utf8)
        let crc = ZipBuilder.crc32(of: entry.content)
        let compressedSize = entry.declaredCompressedSize ?? UInt32(entry.payload.count)
        let uncompressedSize = entry.declaredUncompressedSize ?? UInt32(entry.content.count)

        directory.appendLittleEndian(UInt32(0x0201_4B50))
        directory.appendLittleEndian(UInt16(20)) // made by
        directory.appendLittleEndian(UInt16(20)) // needed
        directory.appendLittleEndian(entry.flags)
        directory.appendLittleEndian(entry.method)
        directory.appendLittleEndian(UInt32(0)) // 시각
        directory.appendLittleEndian(crc)
        directory.appendLittleEndian(compressedSize)
        directory.appendLittleEndian(uncompressedSize)
        directory.appendLittleEndian(UInt16(nameBytes.count))
        directory.appendLittleEndian(UInt16(0)) // extra
        directory.appendLittleEndian(UInt16(0)) // comment
        directory.appendLittleEndian(UInt16(0)) // disk
        directory.appendLittleEndian(UInt16(0)) // internal attrs
        directory.appendLittleEndian(UInt32(0)) // external attrs
        directory.appendLittleEndian(headerOffset)
        directory.append(nameBytes)
    }

    static func crc32(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0)
            }
        }
        return ~crc
    }
}

extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
