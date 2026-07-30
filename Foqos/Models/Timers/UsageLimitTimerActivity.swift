import DeviceActivity
import OSLog

private let dailyLog = Logger(
  subsystem: "com.foqos.monitor",
  category: UsageLimitDailyTimerActivity.id
)

/// Daily repeating activity (midnight to midnight) that carries the usage
/// threshold event for a usage-limited profile.
///
/// - intervalDidStart (midnight, or the moment monitoring begins): a fresh
///   daily allowance — clear any lock/grant and lift the shield.
/// - eventDidReachThreshold (routed here via `lock(for:)`): the allowance is
///   used up — shield the profile's apps until a scan grants temporary access.
class UsageLimitDailyTimerActivity: TimerActivity {
  static var id: String = "UsageLimitDailyActivity"
  static let thresholdEventName = DeviceActivityEvent.Name("usageLimitReached")

  func getDeviceActivityName(from profileId: String) -> DeviceActivityName {
    DeviceActivityName(rawValue: "\(Self.id):\(profileId)")
  }

  func start(for profile: SharedData.ProfileSnapshot) {
    dailyLog.info("Usage limit day started for \(profile.id.uuidString)")
    resetDay(for: profile)
  }

  func stop(for profile: SharedData.ProfileSnapshot) {
    dailyLog.info("Usage limit day ended for \(profile.id.uuidString)")
    resetDay(for: profile)
  }

  func lock(for profile: SharedData.ProfileSnapshot) {
    guard profile.usageLimit?.isEnabled == true else {
      dailyLog.info(
        "Ignoring usage limit threshold for \(profile.id.uuidString), feature disabled"
      )
      return
    }

    dailyLog.info("Usage limit reached for \(profile.id.uuidString), locking")
    UsageLimitState.setLockedToday(profileId: profile.id)
    UsageLimitState.clearGrant(profileId: profile.id)
    UsageLimitState.applyShield(for: profile)
  }

  private func resetDay(for profile: SharedData.ProfileSnapshot) {
    UsageLimitState.clearLock(profileId: profile.id)
    UsageLimitState.clearGrant(profileId: profile.id)
    UsageLimitState.clearShield(profileId: profile.id)
  }
}

private let relockLog = Logger(
  subsystem: "com.foqos.monitor",
  category: UsageLimitRelockTimerActivity.id
)

/// One-shot activity scheduled when the user scans to unlock. Its interval
/// ends at the grant expiry; intervalDidEnd re-applies the shield.
class UsageLimitRelockTimerActivity: TimerActivity {
  static var id: String = "UsageLimitRelockActivity"

  func getDeviceActivityName(from profileId: String) -> DeviceActivityName {
    DeviceActivityName(rawValue: "\(Self.id):\(profileId)")
  }

  func start(for profile: SharedData.ProfileSnapshot) {
    // The main app already lifted the shield when it issued the grant.
  }

  func stop(for profile: SharedData.ProfileSnapshot) {
    guard UsageLimitState.isLockedToday(profileId: profile.id) else {
      relockLog.info(
        "Relock fired for \(profile.id.uuidString) but profile is not locked today"
      )
      UsageLimitState.clearGrant(profileId: profile.id)
      return
    }

    if let expiry = UsageLimitState.grantExpiry(profileId: profile.id), expiry > Date() {
      relockLog.info(
        "Relock fired for \(profile.id.uuidString) but a newer grant is still active"
      )
      return
    }

    relockLog.info("Grant expired for \(profile.id.uuidString), re-locking")
    UsageLimitState.clearGrant(profileId: profile.id)
    UsageLimitState.applyShield(for: profile)
  }
}
