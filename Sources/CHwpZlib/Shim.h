// system zlib 을 Swift 로 들여오는 shim. 비-Apple 플랫폼의 raw DEFLATE 해제
// (`HwpInflate`)만 사용한다. Apple 플랫폼은 `Compression` 을 쓰므로 이 타깃에
// 의존하지 않고, 따라서 이 헤더도 읽히지 않는다 — 의존 간선은 `Package.swift`
// 에서 `.when(platforms:)` 로 타깃 기준으로 걸린다.
//
// zlib.h 를 직접 module map 의 header 로 지정하지 않는 이유는 경로가
// 배포판마다 달라서다. `#include <zlib.h>` 는 컴파일러의 기본 헤더 검색
// 경로를 그대로 쓴다.
#ifndef CHWPZLIB_SHIM_H
#define CHWPZLIB_SHIM_H

#include <zlib.h>

#endif
