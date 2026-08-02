import DeviceActivity
import FamilyControls
import Foundation
import OSLog

private let log = Logger(
  subsystem: "dev.ambitionsoftware.foqos",
  category: "UsageLimitScheduler"
)

/// Drives `EnforcementMode.usageAllowance`: the apps stay usable until they
/// have been used for the allowance, then they lock until the window restarts
/// or someone earns a release.
///
/// Monitoring is tied to the session, not to saving the profile, so an
/// allowance only counts while the profile is actually running.
enum UsageLimitScheduler {
  // MARK: - Session lifecycle

  /// Starts (or refreshes) threshold monitoring for a session that just began.
  /// Does nothing for profiles that block immediately.
  static func begin(for snapshot: SharedData.ProfileSnapshot) {
    guard let allowance = snapshot.method.enforcement.allowanceMinutes,
      !snapshot.enableAllowMode
    else {
      end(profileId: snapshot.id)
      return
    }

    let center = DeviceActivityCenter()
    let activityName = UsageLimitDailyTimerActivity()
      .getDeviceActivityName(from: snapshot.id.uuidString)

    let selection = snapshot.selectedActivity
    let event = DeviceActivityEvent(
      applications: selection.applicationTokens,
      categories: selection.categoryTokens,
      webDomains: [],
      threshold: DateComponents(minute: allowance),
      includesPastActivity: true
    )

    center.stopMonitoring([activityName])
    do {
      try center.startMonitoring(
        activityName,
        during: measurementWindow(for: snapshot),
        events: [UsageLimitDailyTimerActivity.thresholdEventName: event]
      )
      UsageLimitState.clearLock(profileId: snapshot.id)
      UsageLimitState.clearGrant(profileId: snapshot.id)
      UsageLimitState.clearShield(profileId: snapshot.id)
      log.info("Watching a \(allowance)m allowance for \(snapshot.id.uuidString)")
    } catch {
      log.error("Could not watch the allowance: \(error.localizedDescription)")
    }
  }

  /// Stops monitoring and lifts anything this profile was holding.
  static func end(profileId: UUID) {
    let center = DeviceActivityCenter()
    let names = [
      UsageLimitDailyTimerActivity().getDeviceActivityName(from: profileId.uuidString),
      UsageLimitRelockTimerActivity().getDeviceActivityName(from: profileId.uuidString),
    ]
    let running = center.activities.filter { names.contains($0) }
    if !running.isEmpty {
      center.stopMonitoring(running)
    }

    UsageLimitState.clearLock(profileId: profileId)
    UsageLimitState.clearGrant(profileId: profileId)
    UsageLimitState.clearShield(profileId: profileId)
  }

  /// The window the allowance is measured over, and therefore when it resets.
  /// A profile with a schedule reuses that window - an 8 PM to 6 AM schedule
  /// gives an overnight allowance that refills at 6 AM - and everything else
  /// falls back to a plain day.
  private static func measurementWindow(
    for snapshot: SharedData.ProfileSnapshot
  ) -> DeviceActivitySchedule {
    if let schedule = snapshot.schedule, schedule.isActive {
      return DeviceActivitySchedule(
        intervalStart: DateComponents(
          hour: schedule.startHour, minute: schedule.startMinute),
        intervalEnd: DateComponents(hour: schedule.endHour, minute: schedule.endMinute),
        repeats: true
      )
    }

    return DeviceActivitySchedule(
      intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
      intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
      repeats: true
    )
  }

  // MARK: - Releases

  /// Lifts the shield for the profile's release duration and schedules the
  /// automatic re-lock. Returns when access expires.
  @discardableResult
  static func grantTemporaryUnlock(
    for snapshot: SharedData.ProfileSnapshot
  ) throws -> Date {
    let minutes = snapshot.method.interruption.releaseMinutes ?? 5
    let now = Date()
    let expiry = now.addingTimeInterval(TimeInterval(minutes * 60))

    let center = DeviceActivityCenter()
    let activityName = UsageLimitRelockTimerActivity()
      .getDeviceActivityName(from: snapshot.id.uuidString)

    // Anchoring the interval at midnight keeps it comfortably longer than the
    // fifteen minute minimum a schedule has to span; the end is what matters.
    let calendar = Calendar.current
    let components: Set<Calendar.Component> = [
      .year, .month, .day, .hour, .minute, .second,
    ]
    let schedule = DeviceActivitySchedule(
      intervalStart: calendar.dateComponents(
        components, from: calendar.startOfDay(for: now)),
      intervalEnd: calendar.dateComponents(
        components, from: max(expiry, now.addingTimeInterval(60))),
      repeats: false
    )

    center.stopMonitoring([activityName])
    try center.startMonitoring(activityName, during: schedule)

    UsageLimitState.setGrantExpiry(expiry, profileId: snapshot.id)
    UsageLimitState.clearShield(profileId: snapshot.id)

    log.info("Released \(snapshot.id.uuidString) until \(expiry)")
    return expiry
  }
}
