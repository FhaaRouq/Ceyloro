# PomeloCore

PomeloCore is the open-source, platform-focused foundation for Pomelo: a radial drag converter for macOS.

The package contains reusable conversion logic and file-operation primitives:

- file-format detection and conversion target matrices;
- common-target calculation for multi-file selections;
- radial hit-testing geometry;
- cancellable job execution with progress snapshots;
- collision-safe output naming.

The Pomelo macOS application, user interface, brand, distribution, and future premium features are maintained separately and are not part of this repository.

## Use as a Swift Package

Add the package dependency:

```swift
dependencies: [
    .package(url: "https://github.com/neuraldigital/Pomelo.git", from: "0.1.0")
]
```

Then add `PomeloCore` to the target that needs it.

## Development

Requires macOS 13 or later and Swift 5.9 or later.

```sh
swift test
```

## License

PomeloCore is available under the MIT License. See [LICENSE](LICENSE).

The Pomelo name, logo, application UI, and proprietary application code are not licensed under this repository's MIT License.
