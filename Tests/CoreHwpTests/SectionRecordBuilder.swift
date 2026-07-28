import Foundation

/// 테스트용 레코드 스트림 프레이밍 빌더.
///
/// 레코드 헤더는 `tagId(10) | level(10) | size(12)` little-endian UInt32이고,
/// size가 0xFFF이면 뒤따르는 UInt32가 실제 크기다. 이 프레이밍이 여러 테스트
/// 파일에 private 사본으로 흩어져 있었고, 사본 대부분이 확장 크기 분기를
/// 빠뜨려 payload가 0xFFF 이상이면 size 비트가 level로 넘쳐 헤더가 깨졌다.
/// 손상·적대 입력 스위트가 공유하는 단일 출처로 여기에 모은다.
enum SectionRecordBuilder {
    /// 값을 little-endian 바이트로 만든다.
    static func littleEndian(_ value: some FixedWidthInteger) -> Data {
        var littleEndian = value.littleEndian
        return withUnsafeBytes(of: &littleEndian) { Data($0) }
    }

    /// 레코드 헤더 4바이트를 **size 필드 그대로** 만든다.
    /// 확장 크기 sentinel(0xFFF)을 손으로 심는 적대 입력 케이스용이다 —
    /// 정상 레코드는 `record(tagId:level:payload:)`를 쓴다.
    static func header(tagId: UInt32, level: UInt32, size: UInt32) -> Data {
        littleEndian(tagId | (level << 10) | (size << 20))
    }

    /// 레코드 하나를 만든다. payload가 0xFFF 이상이면 확장 크기 형식을 쓴다.
    static func record(tagId: UInt32, level: UInt32, payload: Data) -> Data {
        let size = UInt32(payload.count)
        var data: Data
        if size < 0xFFF {
            data = header(tagId: tagId, level: level, size: size)
        } else {
            data = header(tagId: tagId, level: level, size: 0xFFF)
            data.append(littleEndian(size))
        }
        data.append(payload)
        return data
    }

    /// level 0 ..< `depth`인 레코드를 이어 붙인 중첩 체인을 만든다.
    /// 깊이 한도 경계 테스트용 — 결과 스트림의 최대 level은 `depth - 1`이다.
    static func nestedChain(
        depth: Int,
        tagId: UInt32 = 0x10,
        payload: Data = Data()
    ) -> Data {
        var data = Data()
        for level in 0 ..< depth {
            data.append(record(tagId: tagId, level: UInt32(level), payload: payload))
        }
        return data
    }
}
