import Foundation

/// Converts normalized landmark geometry into the report's explainable units.
/// `bodyHeightNormalized` is the detected subject height in the frame, not a
/// guessed camera distance, so a real measured height is required for cm.
enum PostureMetricCalculator {
    /// Removes global camera roll before comparing left/right heights. A
    /// tilted phone otherwise turns a perfectly level shoulder line into a
    /// false asymmetry signal.
    static func rollCorrectedX(_ x: Double, _ y: Double, axisDx: Double, axisDy: Double) -> Double {
        let angle = rollAngle(axisDx: axisDx, axisDy: axisDy)
        return x * cos(angle) + y * sin(angle)
    }

    static func rollCorrectedY(_ x: Double, _ y: Double, axisDx: Double, axisDy: Double) -> Double {
        let angle = rollAngle(axisDx: axisDx, axisDy: axisDy)
        return -x * sin(angle) + y * cos(angle)
    }

    private static func rollAngle(axisDx: Double, axisDy: Double) -> Double {
        guard axisDx.isFinite, axisDy.isFinite, hypot(axisDx, axisDy) > 0.0001 else { return 0 }
        return atan2(axisDy, axisDx)
    }

    static func rollCorrectedVerticalDifference(firstX: Double, firstY: Double, secondX: Double, secondY: Double, axisDx: Double, axisDy: Double) -> Double {
        abs(rollCorrectedY(firstX, firstY, axisDx: axisDx, axisDy: axisDy) - rollCorrectedY(secondX, secondY, axisDx: axisDx, axisDy: axisDy))
    }

    static func centimeters(_ normalizedDifference: Double, bodyHeightNormalized: Double, measuredHeightCm: Double) -> Double? {
        guard normalizedDifference.isFinite, bodyHeightNormalized.isFinite, measuredHeightCm.isFinite, bodyHeightNormalized > 0.05, measuredHeightCm > 0 else { return nil }
        return max(0, normalizedDifference / bodyHeightNormalized * measuredHeightCm)
    }
    static func degrees(_ radians: Double) -> Double? {
        guard radians.isFinite else { return nil }
        return abs(radians * 180 / .pi)
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Median after rejecting isolated landmark jumps with a MAD fence. This
    /// makes one low-confidence frame unable to move the reported value while
    /// preserving genuine, consistently observed asymmetry.
    static func robustMedian(_ values: [Double], madMultiplier: Double = 3.5) -> Double? {
        let finite = values.filter(\.isFinite)
        guard let center = median(finite) else { return nil }
        let deviations = finite.map { abs($0 - center) }
        guard let mad = median(deviations), mad > 0.000_001 else { return center }
        let fence = mad * max(2.5, madMultiplier)
        let retained = finite.filter { abs($0 - center) <= fence }
        return median(retained) ?? center
    }

    static func medianAbsoluteDeviation(_ values: [Double]) -> Double? {
        let finite = values.filter(\.isFinite)
        guard finite.count >= 2, let center = median(finite) else { return nil }
        return median(finite.map { abs($0 - center) })
    }
}
