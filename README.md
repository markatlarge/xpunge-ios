# XpungeSDK for iOS

On-device NSFW detection for iOS. No uploads. No cloud. Pure margin.

**[Get a free API key →](https://xpunge.markatlarge.com)**

---

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies** and enter:

```
https://github.com/markatlarge/xpunge-ios
```

Or in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/markatlarge/xpunge-ios", from: "0.1.0"),
],
targets: [
    .target(name: "YourTarget", dependencies: [
        .product(name: "XpungeSDK", package: "xpunge-ios"),
    ]),
]
```

---

## Quick Start

```swift
import XpungeSDK

let detector = XpungeDetector()

// Initialize once (validates API key and loads the model)
do {
    try detector.initialize(apiKey: "xp1.YOUR_API_KEY")
} catch {
    print("Init failed: \(error.localizedDescription)")
}

// Analyze image data (JPEG, PNG, HEIF, WebP)
let detections = detector.analyzeImage(imageData)
for d in detections {
    print("\(d.label) \(Int(d.confidence * 100))% at (\(d.x), \(d.y))")
}

// Or from a file path
let detections = detector.analyzeFile(path: "/path/to/image.jpg")
```

---

## API Reference

### `XpungeDetector`

```swift
@available(iOS 14.0, *)
public class XpungeDetector {
    public init()

    // Validates the API key and loads the on-device model.
    // Throws XpungeError on failure.
    public func initialize(apiKey: String) throws

    // Analyze from raw image bytes. Returns [] if not initialized.
    public func analyzeImage(_ data: Data) -> [Detection]

    // Analyze from a file path. Returns [] if not initialized.
    public func analyzeFile(path: String) -> [Detection]

    // Tier encoded in the API key ("free", "indie", etc.)
    public var tier: String { get }

    // true after successful initialize()
    public var isInitialized: Bool { get }

    // Release CoreML/Vision resources
    public func dispose()
}
```

### `Detection`

```swift
public struct Detection {
    let label: String      // "breast" | "penis" | "anus" | "rear" | "vagina"
    let confidence: Double // 0.0–1.0
    let x: Double          // bounding box left edge, normalized 0–1 (0 on free tier)
    let y: Double          // bounding box top edge,  normalized 0–1 (0 on free tier)
    let width: Double      // normalized 0–1                         (0 on free tier)
    let height: Double     // normalized 0–1                         (0 on free tier)
}
```

### `XpungeError`

```swift
public enum XpungeError: Error {
    case invalidKey(String)          // bad format, wrong signature, expired, wrong bundle
    case modelNotFound(String)       // model.mlenc missing or corrupt
    case initializationFailed(String)
}
```

---

## Requirements

- iOS 14.0+
- Xcode 15+

---

## Pricing

| Tier | Price | Images/month |
|---|---|---|
| Free | $0 | 1,000 |
| Basic | $29/mo | 50,000 |
| Pro | $79/mo | 200,000 |
| Growth | $149/mo | 500,000 |
| Scale | $499/mo | 5,000,000 |
| Enterprise | Custom | 5M+ |

[Sign up and get a free key →](https://xpunge.markatlarge.com)

---

## License

Usage is subject to your xPunge subscription agreement.
See [terms](https://xpunge.markatlarge.com/terms/) for details.
