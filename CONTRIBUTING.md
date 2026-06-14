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
생성한 뒤 로컬 HTTP 서버로 띄웁니다. 출력 위치(`./docs`)와 인자는
`cd.yml`의 `docs` job과 동일하며, 마지막의 랜딩 페이지 overlay까지 같은
순서로 재현합니다. `./docs`는 `.gitignore`에 포함되어 있어 작업 후
별도로 정리하지 않아도 됩니다.

`--hosting-base-path hwp-swift`로 DocC 내부 자산이 `/hwp-swift/...`
절대 경로로 굳어지므로, 로컬에서도 같은 URL 프리픽스가 필요합니다.
임시 디렉터리에 심볼릭 링크를 두어 repo는 깨끗하게 유지하면서 그
프리픽스만 만들어 줍니다.

```sh
rm -rf ./docs
swift package --allow-writing-to-directory ./docs \
  generate-documentation --target CoreHwp \
  --disable-indexing \
  --transform-for-static-hosting \
  --hosting-base-path hwp-swift \
  --output-path ./docs
cp .github/pages/index.html ./docs/index.html

rm -rf /tmp/hwp-preview && mkdir -p /tmp/hwp-preview
ln -s "$(pwd)/docs" /tmp/hwp-preview/hwp-swift
python3 -m http.server 8000 --directory /tmp/hwp-preview
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
