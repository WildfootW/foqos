import DeviceActivity
import FamilyControls
import Foundation
import OSLog

private let log = Logger(
  subsystem: "dev.ambitionsoftware.foqos",
  category: "UsageLimitScheduler"
)

/// Main-app side of the daily usage limit feature: keeps the DeviceActivity
/// threshold monitoring in sync with each profile's settings, and issues the
/// short unlock grants after a successful NFC/QR scan.
enum UsageLimitScheduler {
  /// Everything monitoring depends on; when this changes the daily activity
  /// is restarted with fresh parameters.
  private struct ConfigFingerprint: Codable, Equatable {
    let settings: UsageLimitSettings
    let selection: FamilyActivitySelection
  }

  // MARK: - Sync

  static func syncAll(profiles: [BlockedProfiles]) {
    for profile in profiles {
      if profile.usageLimit?.isEnabled == true {
        BlockedProfiles.updateSnapshot(for: profile)
        sync(snapshot: BlockedProfiles.getSnapshot(for: profile))
      } else if UsageLimitState.storedConfigFingerprint(profileId: profile.id) != nil {
        teardown(profileId: profile.id)
      }
    }
  }

  static func sync(for profile: BlockedProfiles) {
    if profile.usageLimit?.isEnabled == true {
      sync(snapshot: BlockedProfiles.getSnapshot(for: profile))
    } else {
      teardown(profileId: profile.id)
    }
  }

  static func sync(snapshot: SharedData.ProfileSnapshot) {
    guard let settings = snapshot.usageLimit,
      settings.isEnabled,
      !snapshot.enableAllowMode
    else {
      teardown(profileId: snapshot.id)
      return
    }

    let fingerprint = try? JSONEncoder().encode(
      ConfigFingerprint(settings: settings, selection: snapshot.selectedActivity)
    )

    let center = DeviceActivityCenter()
    let activityName = UsageLimitDailyTimerActivity()
      .getDeviceActivityName(from: snapshot.id.uuidString)

    if center.activities.contains(activityName),
      let fingerprint,
      UsageLimitState.storedConfigFingerprint(profileId: snapshot.id) == fingerprint
    {
      return
    }

    let selection = snapshot.selectedActivity
    let event = DeviceActivityEvent(
      applications: selection.applicationTokens,
      categories: selection.categoryTokens,
      webDomains: [],
      threshold: DateComponents(minute: settings.dailyLimitInMinutes),
      includesPastActivity: true
    )
    let schedule = DeviceActivitySchedule(
      intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
      intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
      repeats: true
    )

    center.stopMonitoring([activityName])
    do {
      try center.startMonitoring(
        activityName,
        during: schedule,
        events: [UsageLimitDailyTimerActivity.thresholdEventName: event]
      )
      if let fingerprint {
        UsageLimitState.setConfigFingerprint(fingerprint, profileId: snapshot.id)
      }
      log.info(
        "Monitoring daily usage limit of \(settings.dailyLimitInMinutes)m for \(snapshot.id.uuidString)"
      )
    } catch {
      log.error(
        "Failed to start usage limit monitoring: \(error.localizedDescription)"
      )
    }
  }

  static func teardown(profileId: UUID) {
    let center = DeviceActivityCenter()
    let names = [
      UsageLimitDailyTimerActivity().getDeviceActivityName(from: profileId.uuidString),
      UsageLimitRelockTimerActivity().getDeviceActivityName(from: profileId.uuidString),
    ]
    let toStop = center.activities.filter { names.contains($0) }
    if !toStop.isEmpty {
      center.stopMonitoring(toStop)
    }

    UsageLimitState.clearLock(profileId: profileId)
    UsageLimitState.clearGrant(profileId: profileId)
    UsageLimitState.clearShield(profileId: profileId)
    UsageLimitState.clearConfigFingerprint(profileId: profileId)
  }

  // MARK: - Temporary unlock

  /// Lifts the shield for the profile's grant duration and schedules the
  /// automatic re-lock. Returns the expiry date on success.
  @discardableResult
  static func grantTemporaryUnlock(
    for snapshot: SharedData.ProfileSnapshot
  ) throws -> Date {
    let settings = snapshot.usageLimit ?? UsageLimitSettings()
    let now = Date()
    let expiry = now.addingTimeInterval(
      TimeInterval(settings.unlockDurationInMinutes * 60)
    )

    let center = DeviceActivityCenter()
    let activityName = UsageLimitRelockTimerActivity()
      .getDeviceActivityName(from: snapshot.id.uuidString)

    // Same trick as the soft-unblock scheduler: anchor the interval start at
    // midnight so the schedule is comfortably longer than the 15 minute
    // minimum, and let intervalDidEnd fire at the grant expiry.
    let calendar = Calendar.current
    let components: Set<Calendar.Component> = [
      .year, .month, .day, .hour, .minute, .second,
    ]
    let intervalStart = calendar.dateComponents(
      components,
      from: calendar.startOfDay(for: now)
    )
    let intervalEnd = calendar.dateComponents(
      components,
      from: max(expiry, now.addingTimeInterval(60))
    )
    let schedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: false
    )

    center.stopMonitoring([activityName])
    try center.startMonitoring(activityName, during: schedule)

    UsageLimitState.setGrantExpiry(expiry, profileId: snapshot.id)
    UsageLimitState.clearShield(profileId: snapshot.id)

    log.info(
      "Granted usage limit unlock for \(snapshot.id.uuidString) until \(expiry)"
    )
    return expiry
  }
}
