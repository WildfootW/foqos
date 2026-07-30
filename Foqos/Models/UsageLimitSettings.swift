import Foundation

/// Per-profile configuration for the daily usage limit feature.
/// When enabled, the profile's selected apps share a daily usage allowance.
/// Once the allowance is used up the apps are shielded until the user scans
/// one of the profile's physical unblock items (NFC tag or QR code), which
/// opens them for a short grant window before they lock again.
struct UsageLimitSettings: Codable, Equatable {
  static let defaultDailyLimitInMinutes = 30
  static let defaultUnlockDurationInMinutes = 5
  static let dailyLimitRange = 5...720
  static let unlockDurationRange = 1...60

  var isEnabled: Bool
  var dailyLimitInMinutes: Int
  var unlockDurationInMinutes: Int

  init(
    isEnabled: Bool = false,
    dailyLimitInMinutes: Int = UsageLimitSettings.defaultDailyLimitInMinutes,
    unlockDurationInMinutes: Int = UsageLimitSettings.defaultUnlockDurationInMinutes
  ) {
    self.isEnabled = isEnabled
    self.dailyLimitInMinutes = min(
      max(dailyLimitInMinutes, Self.dailyLimitRange.lowerBound),
      Self.dailyLimitRange.upperBound
    )
    self.unlockDurationInMinutes = min(
      max(unlockDurationInMinutes, Self.unlockDurationRange.lowerBound),
      Self.unlockDurationRange.upperBound
    )
  }
}
