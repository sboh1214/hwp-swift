# 문서암호설정-보안수준보통

- `document.hwp`: 기존 `Tests/CoreHwpTests/FileHeader/문서암호설정-보안수준보통.hwp`에서 이관.
- 재생성: 한컴오피스 한글에서 보안 수준 보통 암호 문서를 저장한다. 정상 파싱 대상이 아니며 `unsupportedFeature.encryptedDocument`를 기대한다.
- 재생성 후 `manifest.json`의 `expectedError.code`와 FileHeader encryption bit 기대값을
  `unsupportedFeature.encryptedDocument` 기준으로 갱신한다.
