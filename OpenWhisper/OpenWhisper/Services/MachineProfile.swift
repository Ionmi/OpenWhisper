import Foundation
import IOKit

struct MachineProfile: Sendable {

    // MARK: - BandwidthTier

    enum BandwidthTier: Sendable, Comparable {
        case low        // ≤68 GB/s  (M1 base)
        case medium     // ~100 GB/s (M2/M3/M4 base)
        case high       // ~150-200 GB/s (Pro chips)
        case veryHigh   // 273+ GB/s (M4 Pro)
        case extreme    // 400+ GB/s (Max, Ultra)

        var estimatedBandwidthGBs: Double {
            switch self {
            case .low:      return 68
            case .medium:   return 100
            case .high:     return 200
            case .veryHigh: return 273
            case .extreme:  return 400
            }
        }
    }

    // MARK: - Properties

    let chipName: String
    let gpuCoreCount: Int
    let cpuCoreCount: Int
    let totalRAMBytes: UInt64
    let bandwidthTier: BandwidthTier

    // MARK: - Singleton

    static let current = MachineProfile()

    // MARK: - Init

    init() {
        self.chipName = Self.detectChipName()
        self.gpuCoreCount = Self.detectGPUCoreCount()
        self.cpuCoreCount = ProcessInfo.processInfo.processorCount
        self.totalRAMBytes = ProcessInfo.processInfo.physicalMemory
        self.bandwidthTier = Self.classifyBandwidth(chipName: self.chipName)
    }

    // MARK: - Computed Properties

    var totalRAMGB: Int {
        Int(totalRAMBytes / (1024 * 1024 * 1024))
    }

    var recommendedModelID: String {
        switch bandwidthTier {
        case .low:
            return "gemma3n-e2b"
        case .medium:
            return totalRAMGB < 16 ? "gemma3n-e2b" : "qwen3.5-2b"
        case .high:
            return totalRAMGB < 16 ? "qwen3.5-2b" : "qwen3.5-4b"
        case .veryHigh, .extreme:
            return "qwen3.5-4b"
        }
    }

    var summary: String {
        "\(chipName) · \(gpuCoreCount) GPU cores · \(totalRAMGB) GB RAM"
    }

    // MARK: - Token Estimation

    /// Estimates tokens per second based on memory bandwidth and model size.
    func estimatedTokensPerSec(modelSizeGB: Double) -> Int {
        guard modelSizeGB > 0 else { return 0 }
        let bandwidth = bandwidthTier.estimatedBandwidthGBs
        return Int(bandwidth / modelSizeGB)
    }

    // MARK: - Hardware Detection

    private static func detectChipName() -> String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }

        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detectGPUCoreCount() -> Int {
        let matching = IOServiceMatching("AGXAccelerator")
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }

        guard let prop = IORegistryEntryCreateCFProperty(
            service,
            "gpu-core-count" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return 0
        }

        if let number = prop as? NSNumber {
            return number.intValue
        }
        return 0
    }

    // MARK: - Bandwidth Classification

    private static func classifyBandwidth(chipName: String) -> BandwidthTier {
        let lower = chipName.lowercased()

        // Ultra / Max have massive bandwidth (400-800+ GB/s)
        if lower.contains("ultra") { return .extreme }
        if lower.contains("max") { return .extreme }

        let generation = extractGeneration(from: lower)
        let isPro = lower.contains("pro")

        // M4 Pro or any M5+ Pro → veryHigh
        if isPro {
            if let gen = generation, gen >= 4 {
                return .veryHigh
            }
            // Older Pro chips (M1 Pro, M2 Pro, M3 Pro) → high
            return .high
        }

        // Base chips (no Pro/Max/Ultra suffix)
        if let gen = generation {
            if gen >= 2 {
                // M2, M3, M4, M5+ base → medium
                return .medium
            }
            // M1 base → low
            return .low
        }

        // Unknown or Intel → low
        return .low
    }

    /// Extracts the Apple Silicon generation number from the chip name.
    /// e.g. "apple m2 pro" → 2, "apple m4" → 4
    private static func extractGeneration(from chipName: String) -> Int? {
        // Match patterns like "m1", "m2", "m3", "m4", "m5", etc.
        guard let match = chipName.range(of: #"m(\d+)"#, options: .regularExpression) else {
            return nil
        }
        let matched = String(chipName[match])
        // Drop the leading "m" and parse the number
        let digits = String(matched.dropFirst())
        return Int(digits)
    }
}
