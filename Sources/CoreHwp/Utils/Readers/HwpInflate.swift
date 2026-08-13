import Foundation
#if canImport(Compression)
    import Compression
#else
    import CHwpZlib
#endif

/// HWP OLE stream의 raw DEFLATE(zlib header 없음) 압축을 해제한다.
///
/// Apple 플랫폼에서는 `Compression.framework`의 `COMPRESSION_ZLIB` 스트리밍
/// 디코더를 쓴다 — 이 상수는 이름과 달리 zlib wrapper가 아니라 raw DEFLATE라
/// HWP stream과 형식이 일치한다. 그 외 플랫폼은 system zlib을 `CHwpZlib`
/// system library 타깃으로 링크해 `inflateInit2(-MAX_WBITS)`로 같은 형식을
/// 읽는다. 두 백엔드 모두 **스트리밍**이며 순수 Swift 디코더는 쓰지 않는다.
///
/// 스트리밍 경로의 목적은 속도만이 아니다. `limit`을 압축 해제 **도중**에
/// 적용해 decompression bomb이 상한을 넘는 순간 중단시킨다 — 다 풀고 나서
/// 크기를 보는 후처리 거부와 달리 실제 메모리 할당 상한이다. 두 플랫폼이
/// 같은 구조라 이 보장에 플랫폼 차이가 없다.
///
/// Apple 디코더는 stored block의 `NLEN` 검증을 생략해 zlib이 거부하는
/// 바이트열을 받아들이므로, 두 경로의 **판정**을 맞추기 위해
/// `validateLeadingStoredBlocks`를 앞단에 둔다 (부분 방어 — 그 함수 주석 참조).
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
        // 빈 입력은 유효한 raw DEFLATE stream이 아니다. 두 디코더 모두 이를
        // 거부하지만, 판정을 디코더에 맡기지 않고 앞단에서 통일한다.
        guard !data.isEmpty else {
            throw Failure.corrupted
        }
        try validateLeadingStoredBlocks(data)
        return try inflate(data, limit: max(0, limit))
    }

    /// 선행 stored block들의 `NLEN`이 `LEN`의 1의 보수인지 검사한다.
    ///
    /// Apple 디코더는 이 검사를 생략해 zlib이 거부하는 바이트열을 받아들인다.
    /// 압축으로 표시됐지만 실제로는 deflate가 아닌 입력이 대개 여기 걸린다 —
    /// 임의 바이트의 첫 3비트가 stored block으로 읽히는 경우다. 그 출력은
    /// BinData처럼 레코드 트리 검증을 거치지 않는 경로로도 흘러가므로
    /// (`HwpFile.init(fromOLE:)`), 판정을 디코더에만 맡기지 않는다.
    ///
    /// **부분 방어다.** stored block은 byte 경계에서 끝나 연속한 stored block은
    /// 디코딩 없이 따라갈 수 있지만, huffman block을 만나면 거기서 멈춘다 —
    /// 다음 블록 경계를 알려면 그 블록을 끝까지 디코딩해야 하고, 그것은 이
    /// 파일이 걷어낸 순수 Swift 디코더를 되살리는 일이다. 즉 huffman block 뒤에
    /// 오는 stored block의 `NLEN`은 여전히 검사되지 않는다 (zlib은 거기서도
    /// 거부하므로 남는 차이는 Apple 경로 한쪽이다).
    private static func validateLeadingStoredBlocks(_ data: Data) throws {
        var offset = data.startIndex
        while offset < data.endIndex {
            // 블록 헤더 (LSB first): bit 0 = BFINAL, bits 1-2 = BTYPE.
            let header = data[offset]
            guard (header >> 1) & 0b11 == 0 else {
                return
            }

            // stored block은 헤더 byte의 남은 5비트를 버리고 byte 경계에서
            // LEN·NLEN (각 2 byte LE) 을 읽는다.
            let lengthOffset = offset + 1
            guard lengthOffset + 4 <= data.endIndex else {
                throw Failure.corrupted
            }
            let length = UInt16(data[lengthOffset]) | (UInt16(data[lengthOffset + 1]) << 8)
            let complement = UInt16(data[lengthOffset + 2]) | (UInt16(data[lengthOffset + 3]) << 8)
            guard complement == ~length else {
                throw Failure.corrupted
            }

            let payloadEnd = lengthOffset + 4 + Int(length)
            guard payloadEnd <= data.endIndex else {
                throw Failure.corrupted
            }
            guard header & 0b1 == 0 else {
                return
            }
            offset = payloadEnd
        }
    }
}

private extension HwpInflate {
    /// 출력 버퍼 한 덩어리 크기. 디코더 한 번의 호출이 채우는 상한이다.
    static let chunkSize = 64 * 1024

    /// 초기 예약의 절대 상한. 이 위로는 `Data`의 기하급수 증가에 맡긴다.
    ///
    /// 추측이 **압축** 크기에서 나오므로 저팽창 입력(이미 압축된 BinData 등)은
    /// 쓰지 않는 여분을 붙인 채 모델에 남는다 — `Data`는 용량을 줄이지 않고,
    /// 집계 예산(`StreamReader.consumeAggregateBudget`)은 실제 byte만 센다.
    /// 상한이 없으면 그 여분이 입력 크기에 비례해 커져 **공격자가 정하게**
    /// 된다 (기본 한도에서 64 MiB 입력 → 256 MiB 예약). 상주 메모리는 쓴
    /// 만큼이라 집계 상한 안에 남지만, 예약을 상수로 끊어 두면 그 논증에
    /// 기대지 않아도 된다.
    static let maxInitialCapacity = 8 * 1024 * 1024

    /// 할당 재조정 횟수를 줄이기 위한 초기 용량. deflate 평균 압축률을
    /// 감안해 입력의 4배를 잡되 `limit`·`maxInitialCapacity`와 overflow를
    /// 넘지 않는다.
    static func initialCapacity(inputCount: Int, limit: Int) -> Int {
        let (guess, overflow) = inputCount.multipliedReportingOverflow(by: 4)
        return min(overflow ? limit : guess, limit, maxInitialCapacity)
    }
}

#if canImport(Compression)
    private extension HwpInflate {
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
    }

#else
    private extension HwpInflate {
        /// 비-Apple 플랫폼은 system zlib으로 raw DEFLATE를 스트리밍 해제한다.
        ///
        /// Apple 경로와 구조가 같다 — 출력 한 덩어리마다 `limit`을 확인해
        /// 상한을 넘는 순간 중단하고, 판정도 같은 두 `Failure`로 좁힌다.
        /// 순수 Swift 디코더 폴백은 손상 입력에서 typed error 대신 배열 범위
        /// 초과 트랩으로 프로세스를 중단시켜 걷어냈다 (#101).
        static func inflate(_ data: Data, limit: Int) throws -> Data {
            var stream = z_stream()
            // `inflateInit2`는 C 매크로라 Swift로 들어오지 않으므로, 그 매크로가
            // 채우던 ABI 인자(버전 문자열·구조체 크기)를 직접 넘긴다.
            // windowBits가 음수면 zlib/gzip wrapper 없이 raw DEFLATE로 읽는다 —
            // Apple 쪽 `COMPRESSION_ZLIB`과 같은 해석이다.
            guard inflateInit2_(
                &stream,
                -MAX_WBITS,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            ) == Z_OK else {
                throw Failure.corrupted
            }
            defer { inflateEnd(&stream) }

            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { destination.deallocate() }

            var output = Data()
            output.reserveCapacity(initialCapacity(inputCount: data.count, limit: limit))

            return try data.withUnsafeBytes { raw -> Data in
                guard let source = raw.bindMemory(to: UInt8.self).baseAddress else {
                    throw Failure.corrupted
                }

                var fed = 0

                while true {
                    feedNextSlab(&stream, from: source, count: raw.count, fed: &fed)
                    stream.next_out = destination
                    stream.avail_out = uInt(chunkSize)

                    let consumedBefore = stream.total_in
                    let status = CHwpZlib.inflate(
                        &stream, fed == raw.count ? Z_FINISH : Z_NO_FLUSH
                    )
                    // 출력 공간은 매 호출 새로 주므로 `Z_BUF_ERROR`는 "더
                    // 진전할 수 없음", 즉 절단된 입력이다 — 아래 진전 검사가
                    // 받는다. 나머지 음수 status는 손상이다.
                    guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR
                    else {
                        throw Failure.corrupted
                    }

                    let produced = chunkSize - Int(stream.avail_out)
                    guard output.count + produced <= limit else {
                        throw Failure.limitExceeded(produced: output.count + produced)
                    }
                    if produced > 0 {
                        output.append(destination, count: produced)
                    }

                    // 완결된 stream 뒤에 남은 입력은 보지 않는다. Apple 디코더가
                    // 종료 후 `src_size`를 0으로 보고해(실측: 코퍼스 100개 전부)
                    // 잉여 바이트를 알아낼 방법이 없으므로, zlib에서만 거부하면
                    // macOS에서 열리는 문서가 Linux에서 거부된다.
                    if status == Z_STREAM_END {
                        return output
                    }
                    // 진전이 없는데 END도 아니면 입력이 끊긴 것이다. 이 검사를
                    // 빼면 절단된 stream이 부분 출력으로 조용히 "성공"한다 —
                    // 성능 회귀가 아니라 무성 데이터 손상이므로 반드시 남긴다.
                    // **출력만으로 판정하면 안 된다**: 입력이 `Int32.max`를 넘어
                    // 여러 덩어리로 물릴 때, 한 덩어리를 다 소비하고도 출력이
                    // 0인 호출(빈 non-final block 연쇄)은 진전한 것이고 다음
                    // 덩어리는 아직 물리지도 않았다.
                    if produced == 0, stream.total_in == consumedBefore {
                        throw Failure.corrupted
                    }
                }
            }
        }

        /// 남은 입력이 없을 때만 다음 덩어리를 물린다.
        ///
        /// `avail_in`이 32비트라 입력을 한 번에 다 넘긴다고 가정할 수 없다.
        /// 마지막 덩어리를 물린 뒤에야 호출부가 `Z_FINISH`를 세운다.
        static func feedNextSlab(
            _ stream: inout z_stream,
            from source: UnsafePointer<UInt8>,
            count: Int,
            fed: inout Int
        ) {
            guard stream.avail_in == 0, fed < count else {
                return
            }
            let slab = min(count - fed, Int(Int32.max))
            stream.next_in = UnsafeMutablePointer(mutating: source + fed)
            stream.avail_in = uInt(slab)
            fed += slab
        }
    }
#endif
