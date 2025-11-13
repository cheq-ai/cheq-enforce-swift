
# Implementation Guide

### Xcode

The SDK is provided as a [Swift Package](https://developer.apple.com/documentation/xcode/swift-packages) hosted at [cheq-enforce-swift](https://github.com/cheq-ai/cheq-enforce-swift). The following steps outline how to add a package dependency in Xcode.

1. Open your existing project in Xcode.

2. In the menu bar, go to `File` > `Add Package Dependencies...`.

3. In the search bar, enter the repository URL:
     ```
     https://github.com/cheq-ai/cheq-enforce-swift
     ```

4. Xcode will fetch the package information from the repository. Once it appears, select `cheq-enforce-swift`.

5. Select a library version and `Up to next major version` for the dependency rule.

6. Click the `Add Package` button.

7. You can now import the `Cheq` package:
     ```swift
     import CheqEnforce
     ```

For more information about maintaining package dependencies, see [Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app).
