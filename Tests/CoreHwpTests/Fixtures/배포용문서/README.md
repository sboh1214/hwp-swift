# 배포용문서

- `document.hwp`: 기존 `Tests/CoreHwpTests/FileHeader/배포용문서.hwp`에서 이관.
- 재생성: 한컴오피스 한글에서 배포용 문서를 저장한다. 정상 파싱 대상이 아니며 `unsupportedFeature.deploymentDocument`를 기대한다.
- 재생성 후 `manifest.json`의 `expectedError.code`와 FileHeader deployment bit 기대값을
  `unsupportedFeature.deploymentDocument` 기준으로 갱신한다.
