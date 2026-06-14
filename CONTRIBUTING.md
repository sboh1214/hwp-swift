# 기여

## 코딩 스타일

이 프로젝트는 코드 포맷과 스타일을 강제하기 위해 [SwiftLint](https://github.com/realm/SwiftLint),
[SwiftFormat](https://github.com/nicklockwood/SwiftFormat),
[pre-commit](https://pre-commit.com/)을 사용합니다.

```
brew install swiftlint swiftformat pre-commit
pre-commit install
```

SwiftFormat과 SwiftLint는 모든 PR에서 CI(`ci.yml`의 `lint` 잡)으로 확인됩니다.

## 명명법

파일 및 폴더명은 파스칼표기법을 따릅니다.
스위프트 코드는 일반적인 명명법을 따릅니다.

## 코드 퀄리티

커버리지는 [Codecov](https://codecov.io/gh/sboh1214/hwp-swift)에서 추적합니다.

## 문서

문서는 [Swift-DocC](https://www.swift.org/documentation/docc/)로 빌드되며,
`main` 브랜치에 푸시될 때 [GitHub Pages](https://sboh1214.github.io/hwp-swift/)에
배포됩니다. 배포 파이프라인은 `.github/workflows/cd.yml`을 참고하세요.

### 로컬에서 미리보기

DocC 미리보기 서버를 실행하면 변경 사항이 브라우저에 즉시 반영됩니다.

```sh
swift package --disable-sandbox preview-documentation --target CoreHwp
```

명령을 실행하면 `http://localhost:8080/documentation/corehwp` 같은 URL이
콘솔에 표시되며, 그 주소를 브라우저에서 열면 됩니다.

### 배포본과 동일한 정적 사이트 생성

GitHub Pages에 배포되는 결과물 그대로 확인하고 싶다면 정적 사이트를 직접
생성한 뒤 로컬 HTTP 서버로 띄웁니다. 루트 랜딩 페이지(`/hwp-swift/`)는
DocC 생성 후 `.github/pages/index.html`로 덮어쓰는 구조이므로, 마지막 두
단계로 이를 재현합니다.

```sh
rm -rf ./docs
swift package --allow-writing-to-directory ./docs \
  generate-documentation --target CoreHwp \
  --disable-indexing \
  --transform-for-static-hosting \
  --hosting-base-path hwp-swift \
  --output-path ./docs
cp .github/pages/index.html ./docs/index.html
python3 -m http.server 8000 --directory .
```

이후 `http://localhost:8000/hwp-swift/`에서 랜딩 페이지를,
`http://localhost:8000/hwp-swift/documentation/corehwp/`에서 모듈 문서를
확인할 수 있습니다.

## 배포

### Swift 버전이 새로 출시된 경우

아래 파일의 Swift matrix를 업데이트합니다.

- `.github/workflows/ci.yml` (`test-macos`, `test-linux`의 `matrix.swift`)

### Minimum Swift 버전이 변경된 경우

아래 파일을 모두 업데이트합니다.

- `.github/workflows/ci.yml` (matrix 최소 버전)
- `.swift-version`
- `.swiftformat` (`--swiftversion`)
- `Package.swift` (`// swift-tools-version:` 및 `platforms`)
