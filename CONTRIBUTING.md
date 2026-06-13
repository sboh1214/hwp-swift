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
