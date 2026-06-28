# legacy-common-control-property

- `document.hwp`: 로컬 Hwp-Swift 샘플 `대한민국헌법주석(최종보고서 초안-인쇄본).hwp`에서 이관.
- 포함 기능: HWP 5.0.2.2 문서의 44바이트 개체 공통 속성 payload를 가진
  `genShapeObject` 2개, 41개 section의 대형 body, preview streams, BinData,
  `atno`/`nwno`/`pghd`/`idxm`/`tdut` 계열 other controls.
- 재생성: 동일한 HWP 5.0.2.2 계열 문서에서 `genShapeObject` ctrl header payload가
  object description 길이 필드 없이 44바이트로 끝나는 파일을 확보하고, section/control
  count와 raw payload 길이 기대값을 갱신한다.
