# ``CoreHwp``

한글 문서 파일(.hwp) 5.0 바이너리를 읽는 순수 Swift 파서입니다.

## Overview

CoreHwp는 OLE 컨테이너 안의 FileHeader·DocInfo·BodyText 스트림을 해석해
한글 문서 파일 형식 5.0 공개 문서의 record 구조를 그대로 본뜬 모델 트리로
돌려주는 읽기 전용 reader입니다. Apple 플랫폼뿐 아니라 Linux에서도
동작하므로 CLI·서버에서도 쓸 수 있습니다. 쓰기/저장은 지원하지 않습니다.

모든 읽기는 ``HwpFile``에서 시작합니다. 파싱 실패는 ``HwpError``로
던져지고, 아직 완전히 해석하지 못한 record는 raw payload를 보존합니다.

```swift
import CoreHwp

let hwp = try HwpFile(fromPath: "sample.hwp")
print(hwp.fileHeader.version)      // 파일 버전
print(hwp.docInfo.idMappings)      // 글꼴·글자/문단 모양 정의
for section in hwp.displaySectionArray {
    for paragraph in section.paragraph {
        // 구역(HwpSection) → 문단(HwpParagraph) 순회
    }
}
```

메모리 사용을 줄이려면 ``HwpLoadOptions``의 `.viewer` 프리셋을, 적대적
입력에 대한 한도는 ``HwpReadLimits``를 사용합니다. 화면 렌더가 필요하면
뷰어 타깃 `HwpKit`을 참고하십시오.

## Topics

### 시작하기

- ``HwpFile``
- ``HwpError``
- ``HwpUnsupportedFeature``
- ``HwpLoadOptions``
- ``HwpReadLimits``
- ``HwpParseDiagnostic``

### 문서 스트림

- ``HwpFileHeader``
- ``HwpDocInfo``
- ``HwpSection``
- ``HwpSummary``
- ``HwpPreviewText``
- ``HwpPreviewImage``
- ``HwpBinaryData``

### DocInfo — 문서 공통 속성

- ``HwpDocumentProperties``
- ``HwpIdMappings``
- ``HwpCompatibleDocument``
- ``HwpLayoutCompatibility``

### DocInfo — 글꼴·모양·스타일 정의

- ``HwpFaceName``
- ``HwpCharShape``
- ``HwpParaShape``
- ``HwpStyle``
- ``HwpBorderFill``
- ``HwpBullet``
- ``HwpNumbering``
- ``HwpTabDef``
- ``HwpBinData``

### 본문 — 문단

- ``HwpParagraph``
- ``HwpParaHeader``
- ``HwpParaText``
- ``HwpChar``
- ``HwpParaCharShape``
- ``HwpParaLineSeg``
- ``HwpListHeader``

### 본문 — 컨트롤

- ``HwpCtrlHeader``
- ``HwpSectionDef``
- ``HwpPageDef``
- ``HwpTable``
- ``HwpShapeControl``
- ``HwpListControl``
- ``HwpFieldControl``
- ``HwpHyperlink``
- ``HwpColumn``
- ``HwpOtherControl``

### 스트림·컨트롤 식별자

- ``HwpStreamName``
- ``HwpCtrlId``

### 공통 값 타입

- ``HwpVersion``
- ``HwpColor``
