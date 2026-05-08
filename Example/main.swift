import Foundation
import XpungeSDK

// Dev key — no bundle restriction, no expiry
let apiKey = "xp1.eyJ2IjoxLCJ0aWVyIjoiZnJlZSIsInBrZyI6IiIsImV4cCI6MH0.GHucbTqHCoMglMHhk682sw"

let detector = XpungeDetector()

// 1. Initialize
do {
    try detector.initialize(apiKey: apiKey)
    print("✓ Initialized  tier=\(detector.tier)")
} catch {
    print("✗ Init failed: \(error.localizedDescription)")
    exit(1)
}

// 2. Load test image and analyze
guard let imageURL = Bundle.module.url(forResource: "test", withExtension: "jpg") else {
    print("✗ test.jpg not found in bundle")
    exit(1)
}

guard let imageData = try? Data(contentsOf: imageURL) else {
    print("✗ Could not load test.jpg")
    exit(1)
}
print("✓ Image loaded  \(imageData.count) bytes")

let detections = detector.analyzeImage(imageData)
print("✓ Analysis done  \(detections.count) detection(s)\n")

if detections.isEmpty {
    print("No detections.")
} else {
    for d in detections {
        let pct = Int(d.confidence * 100)
        let box = String(format: "(%.3f, %.3f) %.3f×%.3f", d.x, d.y, d.width, d.height)
        print("\(d.label)  conf=\(pct)%  box=\(box)")
    }
}

detector.dispose()
