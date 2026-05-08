/// A single detection result from the xPunge model.
public struct Detection {
    /// Detected class: `"breast"`, `"penis"`, `"anus"`, `"rear"`, or `"vagina"`.
    public let label: String
    /// Confidence score in the range 0.0–1.0.
    public let confidence: Double
    /// Bounding box left edge, normalized 0–1. Always `0` on the free tier.
    public let x: Double
    /// Bounding box top edge, normalized 0–1. Always `0` on the free tier.
    public let y: Double
    /// Bounding box width, normalized 0–1. Always `0` on the free tier.
    public let width: Double
    /// Bounding box height, normalized 0–1. Always `0` on the free tier.
    public let height: Double
}
