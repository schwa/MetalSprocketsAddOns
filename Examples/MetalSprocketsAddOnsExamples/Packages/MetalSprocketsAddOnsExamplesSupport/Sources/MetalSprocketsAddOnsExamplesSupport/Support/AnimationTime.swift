import Foundation

extension Date {
    /// Seconds since the reference date, wrapped to `period` before converting to `Float`.
    ///
    /// The raw value is about 8e8, where a `Float` can only step in 64-second increments, so
    /// converting first freezes any animation. Pick a `period` that is a whole number of cycles
    /// for every rate the caller uses, so the wrap is seamless.
    func animationTime(wrappingEvery period: Double) -> Float {
        Float(timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period))
    }
}
