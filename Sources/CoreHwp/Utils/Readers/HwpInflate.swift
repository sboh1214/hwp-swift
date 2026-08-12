import Foundation
#if canImport(Compression)
    import Compression
#else
    import SWCompression
#endif

/// HWP OLE stream의 raw DEFLATE(zlib header 없음) 압축을 해제한다.
///
/// Apple 플랫폼에서는 `Compression.framework`의 `COMPRESSION_ZLIB` 스트리밍
/// 디코더를 쓴다 — 이 상수는 이름과 달리 zlib wrapper가 아니라 raw DEFLATE라
/// HWP stream과 형식이 일치한다. 그 외 플랫폼은 `SWCompression`으로 폴백한다.
/// 폴백은 **코드 경로만**이며 SWCompression 의존성 자체는 전 플랫폼에 남는다
/// (테스트가 `Deflate.compress`로 입력을 합성한다).
///
/// 스트리밍 경로의 목적은 속도만이 아니다. `limit`을 압축 해제 **도중**에
/// 적용해 decompression bomb이 상한을 넘는 순간 중단시킨다 — 다 풀고 나서
/// 크기를 보는 후처리 거부와 달리 실제 메모리 할당 상한이다.
enum HwpInflate {
    enum Failure: Error, Equatable {
        /// 입력이 유효한 raw DEFLATE stream이 아니거나 도중에 끊겼다.
        case corrupted

        /// 출력이 `limit`을 넘었다.
        ///
        /// `produced`는 중단 시점까지 만들어진 byte 수, 즉 실제 압축 해제
        /// 크기의 **하한**이다. 도중에 멈추는 것이 이 API의 목적이므로
        /// 정확한 전체 크기는 정의상 알 수 없다.
        case limitExceeded(produced: Int)
    }

    /// `data`를 압축 해제하되 출력이 `limit` byte를 넘으면 중단한다.
    static func decompress(_ data: Data, limit: Int) throws -> Data {
        // 빈 입력은 유효한 raw DEFLATE stream이 아니다. SWCompression 폴백이
        // 이미 throw하므로, 두 경로의 판정을 맞추기 위해 앞단에서 통일한다.
        guard !data.isEmpty else {
            throw Failure.corrupted
        }
        return try inflate(data, limit: max(0, limit))
    }
}

#if canImport(Compression)
    private extension HwpInflate {
        /// 출력 버퍼 한 덩어리 크기. 한 번의 `process` 호출이 채우는 상한이다.
        static let chunkSize = 64 * 1024

        static func inflate(_ data: Data, limit: Int) throws -> Data {
            let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            defer { stream.deallocate() }

            guard compression_stream_init(
                stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB
            ) == COMPRESSION_STATUS_OK else {
                throw Failure.corrupted
            }
            defer { compression_stream_destroy(stream) }

            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { destination.deallocate() }

            var output = Data()
            output.reserveCapacity(initialCapacity(inputCount: data.count, limit: limit))

            return try data.withUnsafeBytes { raw -> Data in
                guard let source = raw.bindMemory(to: UInt8.self).baseAddress else {
                    throw Failure.corrupted
                }
                stream.pointee.src_ptr = source
                stream.pointee.src_size = raw.count

                // 입력 전체를 한 번에 넘기므로 첫 호출부터 FINALIZE를 세운다.
                let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                var status = COMPRESSION_STATUS_OK

                while status == COMPRESSION_STATUS_OK {
                    stream.pointee.dst_ptr = destination
                    stream.pointee.dst_size = chunkSize

                    status = compression_stream_process(stream, flags)
                    guard status != COMPRESSION_STATUS_ERROR else {
                        throw Failure.corrupted
                    }

                    let produced = chunkSize - stream.pointee.dst_size
                    guard output.count + produced <= limit else {
                        throw Failure.limitExceeded(produced: output.count + produced)
                    }
                    if produced > 0 {
                        output.append(destination, count: produced)
                    }

                    // 진전이 없는데 END도 아니면 입력이 끊긴 것이다. 이 검사를
                    // 빼면 절단된 stream이 부분 출력으로 조용히 "성공"한다 —
                    // 성능 회귀가 아니라 무성 데이터 손상이므로 반드시 남긴다.
                    if status == COMPRESSION_STATUS_OK, produced == 0 {
                        throw Failure.corrupted
                    }
                }

                // 위 루프는 END 또는 throw로만 빠져나온다. 방어적으로 한 번 더
                // 확인해 END 미도달 상태가 성공으로 새지 않게 한다.
                guard status == COMPRESSION_STATUS_END else {
                    throw Failure.corrupted
                }
                return output
            }
        }

        /// 할당 재조정 횟수를 줄이기 위한 초기 용량. deflate 평균 압축률을
        /// 감안해 입력의 4배를 잡되 `limit`과 overflow를 넘지 않는다.
        static func initialCapacity(inputCount: Int, limit: Int) -> Int {
            let (guess, overflow) = inputCount.multipliedReportingOverflow(by: 4)
            return min(overflow ? limit : guess, limit)
        }
    }

#else
    private extension HwpInflate {
        /// 비-Apple 플랫폼 폴백. `SWCompression`은 bounded streaming inflate를
        /// 제공하지 않으므로 `limit` 판정은 압축 해제가 끝난 뒤에 이뤄진다 —
        /// 이 경로에서는 typed error 반환만 보장되고 메모리 할당 상한은
        /// 보장되지 않는다.
        static func inflate(_ data: Data, limit: Int) throws -> Data {
            let output: Data
            do {
                output = try Deflate.decompress(data: data)
            } catch {
                throw Failure.corrupted
            }

            guard output.count <= limit else {
                throw Failure.limitExceeded(produced: output.count)
            }
            return output
        }
    }
#endif
