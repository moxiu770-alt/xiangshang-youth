import Foundation

extension PostureMetricCalculator {
    static func standardDeviation(_ values: [Double]) -> Double? {
        let finite = values.filter(\.isFinite)
        guard finite.count >= 2 else { return nil }
        let mean = finite.reduce(0, +) / Double(finite.count)
        let variance = finite.reduce(0) { $0 + pow($1 - mean, 2) } / Double(finite.count - 1)
        return sqrt(max(0, variance))
    }

    /// Rejects completion when one capture still contains a visibly unstable
    /// metric series. This is a capture-quality check, not a health threshold.
    static func isStableSeries(_ values: [Double], minimumSamples: Int, maximumMedianAbsoluteDeviation: Double) -> Bool {
        let finite = values.filter(\.isFinite)
        guard finite.count >= minimumSamples,
              maximumMedianAbsoluteDeviation.isFinite,
              maximumMedianAbsoluteDeviation >= 0,
              let mad = medianAbsoluteDeviation(finite) else { return false }
        return mad <= maximumMedianAbsoluteDeviation
    }

    struct RepeatabilityResult: Equatable {
        let runCount: Int
        let range: Double?
        let standardDeviation: Double?
        let passed: Bool
    }

    /// Engineering acceptance helper for the requested same-person ten-run
    /// check. Passing this calculation is necessary but does not establish
    /// medical validity; real device/child runs still have to supply values.
    static func repeatability(_ values: [Double], minimumRuns: Int = 10, maximumRange: Double, maximumStandardDeviation: Double) -> RepeatabilityResult {
        let finite = values.filter(\.isFinite)
        let measuredRange = range(finite)
        let deviation = standardDeviation(finite)
        return RepeatabilityResult(
            runCount: finite.count,
            range: measuredRange,
            standardDeviation: deviation,
            passed: finite.count >= minimumRuns && (measuredRange ?? .infinity) <= maximumRange && (deviation ?? .infinity) <= maximumStandardDeviation
        )
    }

    /// Motion amplitude around the camera baseline. A range avoids treating
    /// a child who walks slightly off-centre as exaggerated trunk sway.
    static func range(_ values: [Double]) -> Double? {
        let finite = values.filter { $0.isFinite }
        guard let minimum = finite.min(), let maximum = finite.max() else { return nil }
        return max(0, maximum - minimum)
    }


    /// Range after trimming the same fraction from both tails. Gait amplitude
    /// must not be determined by one isolated landmark jump.
    static func robustRange(_ values: [Double], trimFraction: Double = 0.10) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard sorted.count >= 3, trimFraction.isFinite, trimFraction >= 0, trimFraction < 0.5 else { return nil }
        let trimCount = min((sorted.count - 2) / 2, Int(floor(Double(sorted.count) * trimFraction)))
        let retained = Array(sorted[trimCount..<(sorted.count - trimCount)])
        return range(retained)
    }
}
