import CoreML
import Vision
import CoreImage
import CryptoKit
import Security
import CommonCrypto

/// On-device NSFW detector. Create one instance and hold it for the lifetime of your session.
@available(iOS 14.0, macOS 10.15, *)
public class XpungeDetector {

    /// The tier associated with the current API key (`"free"`, `"indie"`, etc.).
    /// Available after a successful call to ``initialize(apiKey:)``.
    public private(set) var tier: String = "free"

    /// `true` after a successful call to ``initialize(apiKey:)``.
    public var isInitialized: Bool { visionRequest != nil }

    private var vnModel: VNCoreMLModel?
    private var visionRequest: VNCoreMLRequest?

    private let classNames = ["anus", "breast", "penis", "rear", "vagina"]
    private let confidenceThreshold: Double = 0.15

    private static let partBMasked: [UInt8] = [
        0x6E, 0xE6, 0xB2, 0x6C, 0x57, 0x31, 0xA7, 0x09,
    ]
    private static let partBMask: [UInt8] = [
        0xC7, 0x3B, 0x1A, 0x2B, 0x32, 0x0B, 0x18, 0xA7,
    ]
    private static let partC: [UInt8] = [
        0x46, 0x6F, 0x8F, 0xBE, 0xC9, 0x9D, 0xBC, 0xFD,
    ]

    public init() {}

    // MARK: – Public API

    /// Validates the API key and loads the on-device model.
    /// Call once before any detection. Throws ``XpungeError`` on failure.
    public func initialize(apiKey: String) throws {
        tier = try validateKey(apiKey)
        try loadModel()
    }

    /// Runs detection on raw image bytes (JPEG, PNG, HEIF, WebP).
    /// Returns an empty array if not initialized or the image cannot be decoded.
    public func analyzeImage(_ data: Data) -> [Detection] {
        guard let cgImage = cgImage(from: data) else { return [] }
        return runVision(on: cgImage)
    }

    /// Runs detection on an image file at the given path.
    /// Returns an empty array if not initialized or the file cannot be decoded.
    public func analyzeFile(path: String) -> [Detection] {
        guard let cgImage = cgImage(fromFile: path) else { return [] }
        return runVision(on: cgImage)
    }

    /// Releases Vision/CoreML resources.
    public func dispose() {
        visionRequest = nil
        vnModel = nil
    }

    // MARK: – Key validation

    private static func buildSecret() -> [UInt8] {
        let partB = zip(partBMasked, partBMask).map { $0 ^ $1 }
        return XpungeKeyMaterial.partA + partB + partC + XpungeKeyMaterial.partD
    }

    private static func loadOrStoreSecret() -> [UInt8] {
        let service = "com.xpunge.ios.sdk"
        let account = "hmac_secret_v3"
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String:         true,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, data.count == 32 {
            return Array(data)
        }
        var secret = buildSecret()
        let addQuery: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecValueData as String:          Data(secret),
            kSecAttrAccessible as String:     kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        let result = secret
        let secretLen = secret.count
        _ = secret.withUnsafeMutableBufferPointer { $0.baseAddress.map { memset($0, 0, secretLen) } }
        return result
    }

    private func validateKey(_ apiKey: String) throws -> String {
        let parts = apiKey.split(separator: ".").map(String.init)
        guard parts.count == 3, parts[0] == "xp1" else {
            throw XpungeError.invalidKey("Invalid API key format")
        }
        guard let payloadData = base64UrlDecode(parts[1]),
              let sigData     = base64UrlDecode(parts[2]) else {
            throw XpungeError.invalidKey("Could not decode API key")
        }

        var secretBytes = Self.loadOrStoreSecret()
        let key = SymmetricKey(data: Data(secretBytes))
        let secretLen = secretBytes.count
        _ = secretBytes.withUnsafeMutableBufferPointer { $0.baseAddress.map { memset($0, 0, secretLen) } }
        let mac = HMAC<SHA256>.authenticationCode(for: payloadData, using: key)
        guard Data(mac.prefix(16)) == sigData else {
            throw XpungeError.invalidKey("API key signature invalid")
        }

        guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw XpungeError.invalidKey("Could not decode payload")
        }

        if let exp = (payload["exp"] as? NSNumber)?.doubleValue, exp > 0 {
            guard Date().timeIntervalSince1970 < exp else {
                throw XpungeError.invalidKey("API key expired")
            }
        }

        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let allowed: [String] = ((payload["pkgs"] as? [String])
            ?? (payload["pkg"] as? String).map { [$0] } ?? [])
            .filter { !$0.isEmpty }
        if !allowed.isEmpty && !allowed.contains(bundleId) {
            throw XpungeError.invalidKey("API key is not registered for bundle '\(bundleId)'")
        }

        return payload["tier"] as? String ?? "free"
    }

    // MARK: – Model loading

    private func loadModel() throws {
        // Bundle.module resolves to the SPM resource bundle; falls back to the
        // framework bundle when integrated via CocoaPods or direct Xcode embed.
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: XpungeDetector.self)
        #endif
        guard let encURL = bundle.url(forResource: "model", withExtension: "mlenc") else {
            throw XpungeError.modelNotFound("model.mlenc not found in XpungeSDK bundle")
        }
        let encData = try Data(contentsOf: encURL)
        let tempDir = try decryptModelToTemp(encData)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        let mlModel = try MLModel(contentsOf: tempDir, configuration: config)
        let vn = try VNCoreMLModel(for: mlModel)
        let req = VNCoreMLRequest(model: vn, completionHandler: nil)
        req.imageCropAndScaleOption = .scaleFit
        self.vnModel = vn
        self.visionRequest = req
    }

    private func decryptModelToTemp(_ data: Data) throws -> URL {
        guard data.count > 16 else {
            throw XpungeError.modelNotFound("Encrypted model data too short")
        }
        var secretBytes = Self.loadOrStoreSecret()
        let rawKey = Data(SHA256.hash(data: Data(secretBytes)))
        let secretLen = secretBytes.count
        _ = secretBytes.withUnsafeMutableBufferPointer { $0.baseAddress.map { memset($0, 0, secretLen) } }

        let iv = Data(data.prefix(16))
        let ciphertext = Data(data.dropFirst(16))
        let plaintextCapacity = ciphertext.count + kCCBlockSizeAES128
        var plaintext = Data(count: plaintextCapacity)
        var outLen = 0
        let status = rawKey.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                ciphertext.withUnsafeBytes { inPtr in
                    plaintext.withUnsafeMutableBytes { outPtr in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyPtr.baseAddress, rawKey.count, ivPtr.baseAddress,
                                inPtr.baseAddress, ciphertext.count,
                                outPtr.baseAddress, plaintextCapacity, &outLen)
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw XpungeError.modelNotFound("Model decryption failed: \(status)")
        }
        plaintext = Data(plaintext.prefix(outLen))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xpunge_\(UUID().uuidString).mlmodelc")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var offset = plaintext.startIndex
        func readUInt32() -> UInt32 {
            let b0 = UInt32(plaintext[plaintext.index(offset, offsetBy: 0)])
            let b1 = UInt32(plaintext[plaintext.index(offset, offsetBy: 1)])
            let b2 = UInt32(plaintext[plaintext.index(offset, offsetBy: 2)])
            let b3 = UInt32(plaintext[plaintext.index(offset, offsetBy: 3)])
            offset = plaintext.index(offset, offsetBy: 4)
            return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }
        func readUInt64() -> UInt64 {
            let b0 = UInt64(plaintext[plaintext.index(offset, offsetBy: 0)])
            let b1 = UInt64(plaintext[plaintext.index(offset, offsetBy: 1)])
            let b2 = UInt64(plaintext[plaintext.index(offset, offsetBy: 2)])
            let b3 = UInt64(plaintext[plaintext.index(offset, offsetBy: 3)])
            let b4 = UInt64(plaintext[plaintext.index(offset, offsetBy: 4)])
            let b5 = UInt64(plaintext[plaintext.index(offset, offsetBy: 5)])
            let b6 = UInt64(plaintext[plaintext.index(offset, offsetBy: 6)])
            let b7 = UInt64(plaintext[plaintext.index(offset, offsetBy: 7)])
            offset = plaintext.index(offset, offsetBy: 8)
            return (b0 << 56) | (b1 << 48) | (b2 << 40) | (b3 << 32) | (b4 << 24) | (b5 << 16) | (b6 << 8) | b7
        }
        guard readUInt32() == 0x58504D4C else {
            throw XpungeError.modelNotFound("Invalid model archive magic")
        }
        let numFiles = Int(readUInt32())
        for _ in 0..<numFiles {
            let pathLen = Int(readUInt32())
            let pathEnd = plaintext.index(offset, offsetBy: pathLen)
            guard let relPath = String(data: plaintext[offset..<pathEnd], encoding: .utf8) else {
                throw XpungeError.modelNotFound("Invalid path in model archive")
            }
            offset = pathEnd
            let dataLen = Int(readUInt64())
            let dataEnd = plaintext.index(offset, offsetBy: dataLen)
            let fileData = plaintext[offset..<dataEnd]
            offset = dataEnd
            let fileURL = tempDir.appendingPathComponent(relPath)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try fileData.write(to: fileURL)
        }
        return tempDir
    }

    // MARK: – Detection

    private func runVision(on cgImage: CGImage) -> [Detection] {
        guard let req = visionRequest else { return [] }
        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([req])
            return parseResults(req.results)
        } catch {
            return []
        }
    }

    private func parseResults(_ results: [VNObservation]?) -> [Detection] {
        guard let results = results,
              let obs = results.first as? VNCoreMLFeatureValueObservation,
              let arr = obs.featureValue.multiArrayValue else { return [] }

        let shape = arr.shape.map { $0.intValue }
        guard shape.count == 3, shape[2] == 6 else { return [] }

        let n   = shape[1]
        let ptr = arr.dataPointer.bindMemory(to: Float.self, capacity: n * 6)
        var out: [Detection] = []

        for i in 0..<n {
            let o    = i * 6
            let conf = Double(ptr[o + 4])
            guard conf >= confidenceThreshold else { continue }
            let x1      = Double(ptr[o + 0]); let y1 = Double(ptr[o + 1])
            let x2      = Double(ptr[o + 2]); let y2 = Double(ptr[o + 3])
            let classId = Int(ptr[o + 5])
            let label   = classId >= 0 && classId < classNames.count ? classNames[classId] : "unknown"
            out.append(Detection(
                label:      label,
                confidence: conf,
                x:          max(0, min(1, x1 / 640.0)),
                y:          max(0, min(1, y1 / 640.0)),
                width:      max(0, min(1, (x2 - x1) / 640.0)),
                height:     max(0, min(1, (y2 - y1) / 640.0))
            ))
        }
        return out
    }

    // MARK: – Image helpers

    private func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return img
    }

    private func cgImage(fromFile path: String) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return img
    }

    private func base64UrlDecode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        return Data(base64Encoded: b64)
    }
}
