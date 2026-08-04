import SwiftData
import SwiftUI
import WidgetKit

class StrategyManager: ObservableObject {
  static var shared = StrategyManager()


  @Published var elapsedTime: TimeInterval = 0
  @Published var sessionDisplayTime: TimeInterval = 0
  @Published var timer: Timer?
  @Published var activeSession: BlockedProfileSession?

  @Published var showCustomStrategyView: Bool = false
  @Published var customStrategyView: (any View)? = nil
  @Published var customStrategyViewPresentationDetents: Set<PresentationDetent> = [
    .medium, .large,
  ]

  @Published var errorMessage: String?


  private let liveActivityManager = LiveActivityManager.shared

  private let timersUtil = TimersUtil()
  private let appBlocker = AppBlockerUtil()

  var isBlocking: Bool {
    return activeSession?.isActive == true
  }

  var isBreakActive: Bool {
    return activeSession?.isBreakActive == true
  }

  var isBreakAvailable: Bool {
    return activeSession?.isBreakAvailable ?? false
  }

  var isPauseActive: Bool {
    return activeSession?.isPauseActive == true
  }

  func defaultReminderMessage(forProfile profile: BlockedProfiles?) -> String {
    let baseMessage = "Get back to productivity"
    guard let profile else {
      return baseMessage
    }
    return baseMessage + " by enabling \(profile.name)"
  }

  func loadActiveSession(context: ModelContext) {
    activeSession = getActiveSession(context: context)

    if activeSession?.isActive == true {
      startTimer()

      // Start live activity for existing session if one exists
      // live activities can only be started when the app is in the foreground
      if let session = activeSession {
        liveActivityManager.startSessionActivity(session: session)
      }
    } else {
      stopTimer()
      elapsedTime = 0
      sessionDisplayTime = 0

      // Close live activity if no session is active and a scheduled session might have ended
      liveActivityManager.endSessionActivity()
    }

    // Reload widget to reflect any changes from extension (e.g., timer expiration)
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")
  }

  func toggleBlocking(context: ModelContext, activeProfile: BlockedProfiles?) {
    if isBlocking {
      stopBlocking(context: context)
    } else {
      startBlocking(context: context, activeProfile: activeProfile)
    }
  }

  func toggleBreak(context: ModelContext) {
    guard let session = activeSession else {
      print("active session does not exist")
      return
    }

    if session.isBreakActive {
      stopBreak(context: context)
    } else {
      startBreak(context: context)
    }
  }

  func startTimer() {
    stopTimer()
    updateSessionTimes()

    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.updateSessionTimes()
    }
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func updateSessionTimes(at date: Date = Date()) {
    guard let session = activeSession else {
      elapsedTime = 0
      sessionDisplayTime = 0
      return
    }

    let focusTime = SessionTimeCalculator.elapsedFocusTime(for: session, at: date)
    elapsedTime = focusTime
    sessionDisplayTime = SessionTimeCalculator.displayedTime(
      for: session,
      elapsedFocusTime: focusTime,
      at: date
    )
  }

  func toggleSessionFromDeeplink(
    _ profileId: String,
    url: URL,
    context: ModelContext
  ) {
    guard let profileUUID = UUID(uuidString: profileId) else {
      self.errorMessage = "failed to parse profile in tag"
      return
    }

    do {
      guard
        let profile: BlockedProfiles = try BlockedProfiles.findProfile(
          byID: profileUUID,
          in: context
        )
      else {
        self.errorMessage =
          "Failed to find a profile stored locally that matches the tag"
        return
      }

      let manualStrategy = getStrategy(context: context)

      if let localActiveSession = getActiveSession(context: context) {
        if localActiveSession.blockedProfile.disableBackgroundStops {
          print(
            "profile: \(localActiveSession.blockedProfile.name) has disable background stops enabled, not stopping it"
          )
          self.errorMessage =
            "profile: \(localActiveSession.blockedProfile.name) has disable background stops enabled, not stopping it"
          return
        }

        _ =
          manualStrategy
          .stopBlocking(
            context: context,
            session: localActiveSession
          )

        if localActiveSession.blockedProfile.id != profile.id {
          print(
            "User is switching sessions from deep link"
          )

          _ = manualStrategy.startBlocking(
            context: context,
            profile: profile,
            forceStart: true
          )
        }
      } else {
        _ = manualStrategy.startBlocking(
          context: context,
          profile: profile,
          forceStart: true
        )
      }
    } catch {
      self.errorMessage = "Something went wrong fetching profile"
    }
  }

  func startSessionFromBackground(
    _ profileId: UUID,
    context: ModelContext,
    durationInMinutes: Int? = nil
  ) {
    do {
      guard
        let profile = try BlockedProfiles.findProfile(
          byID: profileId,
          in: context
        )
      else {
        self.errorMessage =
          "Failed to find a profile stored locally that matches the tag"
        return
      }

      if let localActiveSession = getActiveSession(context: context) {
        print(
          "session is already active for profile: \(localActiveSession.blockedProfile.name), not starting a new one"
        )
        return
      }

      if let duration = durationInMinutes {
        if duration < 15 || duration > 1440 {
          self.errorMessage = "Duration must be between 15 and 1440 minutes"
          return
        }

        profile.method.autoEnd = .afterMinutes(duration)
        profile.updatedAt = Date()
        BlockedProfiles.updateSnapshot(for: profile)
        try context.save()

        let shortcutTimerStrategy = getStrategy(context: context)
        _ = shortcutTimerStrategy.startBlocking(
          context: context,
          profile: profile,
          forceStart: true
        )
      } else {
        let manualStrategy = getStrategy(context: context)
        _ = manualStrategy.startBlocking(
          context: context,
          profile: profile,
          forceStart: true
        )
      }
    } catch {
      self.errorMessage = "Something went wrong fetching profile"
    }
  }

  func pauseActiveSessionFromBackground(
    context: ModelContext,
    schedulePause: (BlockedProfiles) throws -> Void =
      DeviceActivityCenterUtil.schedulePauseTimerActivity
  ) throws -> String {
    guard let session = getActiveSession(context: context) else {
      throw PauseActiveSessionError.noActiveSession
    }

    let profile = session.blockedProfile
    let profileName = profile.name
    guard profile.method.interruption != .none else {
      throw PauseActiveSessionError.unsupportedStrategy(profileName: profileName)
    }

    guard !session.isPauseActive else {
      throw PauseActiveSessionError.alreadyPaused(profileName: profileName)
    }

    guard !session.isBreakActive else {
      throw PauseActiveSessionError.breakActive(profileName: profileName)
    }

    do {
      try schedulePause(profile)
    } catch {
      throw PauseActiveSessionError.schedulingFailed(
        profileName: profileName,
        reason: error.localizedDescription
      )
    }

    return profileName
  }

  func stopSessionFromBackground(
    _ profileId: UUID,
    context: ModelContext
  ) {
    do {
      guard
        let profile = try BlockedProfiles.findProfile(
          byID: profileId,
          in: context
        )
      else {
        self.errorMessage =
          "Failed to find a profile stored locally that matches the tag"
        return
      }

      let manualStrategy = getStrategy(context: context)

      guard let localActiveSession = getActiveSession(context: context) else {
        print(
          "session is not active for profile: \(profile.name), not stopping it"
        )
        return
      }

      if localActiveSession.blockedProfile.id != profile.id {
        print(
          "session is not active for profile: \(profile.name), not stopping it"
        )
        self.errorMessage =
          "session is not active for profile: \(profile.name), not stopping it"
        return
      }

      if profile.disableBackgroundStops {
        print(
          "profile: \(profile.name) has disable background stops enabled, not stopping it"
        )
        self.errorMessage =
          "profile: \(profile.name) has disable background stops enabled, not stopping it"
        return
      }

      let _ = manualStrategy.stopBlocking(
        context: context,
        session: localActiveSession
      )
    } catch {
      self.errorMessage = "Something went wrong fetching profile"
    }
  }

  /// Emergency releases belong to the running session, so the allowance means
  /// "mistakes I can make during this stretch" and refills by starting again
  /// rather than by waiting out a calendar period.
  func getRemainingEmergencyUnblocks() -> Int {
    guard let session = activeSession else { return 0 }
    let policy = session.blockedProfile.method.emergency
    return max(policy.effectiveMaxUses - session.emergencyUsedCount, 0)
  }

  func emergencyUnblock(context: ModelContext) {
    guard let activeSession = getActiveSession(context: context) else { return }

    let policy = activeSession.blockedProfile.method.emergency
    guard policy.effectiveMaxUses - activeSession.emergencyUsedCount > 0 else { return }

    activeSession.emergencyUsedCount += 1

    // End the session directly rather than through the profile's stop rule,
    // which is the whole point of an emergency release.
    SoftUnblockGrantScheduler.stopAll(sessionId: activeSession.id)
    SoftUnblockGrantStore.endSession(sessionId: activeSession.id)
    UsageLimitScheduler.end(profileId: activeSession.blockedProfile.id)
    activeSession.endSession()
    try? context.save()
    appBlocker.deactivateRestrictions()

    self.liveActivityManager.endSessionActivity()
    self.scheduleReminder(profile: activeSession.blockedProfile)
    self.stopTimer()
    self.activeSession = nil

    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")
  }

  static func strategy(for method: BlockingMethod) -> BlockingStrategy {
    return ConfigurableBlockingStrategy(method: method)
  }

  private func getStrategy(context: ModelContext) -> BlockingStrategy {
    var strategy: BlockingStrategy = ConfigurableBlockingStrategy()

    strategy.onSessionCreation = { session in
      switch session {
      case .paused:
        self.handlePauseStarted(context: context)
      case .started(let session):
        self.handleSessionStarted(session: session)
      case .ended(let endedProfile):
        self.handleSessionEnded(profile: endedProfile)
      }
    }

    strategy.onErrorMessage = { message in
      self.dismissView()

      self.errorMessage = message
    }

    return strategy
  }

  /// Whether the active session's profile trades scans for breaks, and how
  /// many are left. Unlimited when the method sets no cap.
  var scanBreaksRemaining: Int? {
    guard let session = activeSession,
      case .grantByScan(_, let maxCount) = session.blockedProfile.method.interruption
    else { return nil }
    guard let maxCount else { return Int.max }
    return max(maxCount - session.scanBreaksUsedCount, 0)
  }

  /// Starts a break that was just paid for with a valid scan. The scan itself
  /// is collected and checked by the caller; this is the payoff.
  func startScanBreak(context: ModelContext) {
    guard let session = activeSession,
      case .grantByScan(let minutes, _) = session.blockedProfile.method.interruption
    else { return }

    if let remaining = scanBreaksRemaining, remaining <= 0 {
      errorMessage = "No scan breaks left this session."
      return
    }

    session.scanBreaksUsedCount += 1
    session.startBreak()
    appBlocker.deactivateRestrictionsForBreak(
      for: BlockedProfiles.getSnapshot(for: session.blockedProfile))
    try? context.save()

    let durationInSeconds = TimeInterval(minutes * 60)
    DeviceActivityCenterUtil.startBreakTimerActivity(
      for: session.blockedProfile,
      durationInSeconds: durationInSeconds
    )
    scheduleBreakReminder(
      profile: session.blockedProfile,
      durationInSeconds: durationInSeconds
    )

    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")
    updateSessionTimes()
    liveActivityManager.updateBreakState(session: session)
  }

  private func startBreak(context: ModelContext) {
    guard let session = activeSession else {
      print("Breaks only available in active session")
      return
    }

    if !session.isBreakAvailable {
      print("Breaks is not availble")
      return
    }

    let remainingBreakAllowance = session.remainingBreakAllowance()
    guard remainingBreakAllowance > 0 else {
      print("No break allowance remaining")
      return
    }

    session.startBreak()
    appBlocker.deactivateRestrictionsForBreak(
      for: BlockedProfiles.getSnapshot(for: session.blockedProfile))
    try? context.save()

    // Start the break timer activity
    DeviceActivityCenterUtil.startBreakTimerActivity(
      for: session.blockedProfile,
      durationInSeconds: remainingBreakAllowance
    )

    // Schedule a reminder to get back to the profile after the break
    scheduleBreakReminder(
      profile: session.blockedProfile,
      durationInSeconds: remainingBreakAllowance
    )

    // Refresh widgets when break starts
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")

    updateSessionTimes()

    // Update live activity to show break state
    liveActivityManager.updateBreakState(session: session)
  }

  private func stopBreak(context: ModelContext) {
    guard let session = activeSession else {
      print("Breaks only available in active session")
      return
    }

    if !session.isBreakActive {
      print("Breaks is not availble")
      return
    }

    session.endBreak()
    appBlocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: session.blockedProfile))
    try? context.save()

    // Remove the break timer activity
    DeviceActivityCenterUtil.removeBreakTimerActivity(for: session.blockedProfile)

    // Cancel all notifications that were scheduled during break
    timersUtil.cancelAllNotifications()

    // Refresh widgets when break ends
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")

    updateSessionTimes()

    // Update live activity to show break has ended
    liveActivityManager.updateBreakState(session: session)
  }

  private func handlePauseStarted(context: ModelContext) {
    self.dismissView()

    // load the active session since the pause start time was set in a different thread
    loadActiveSession(context: context)

    // Refresh widgets when pause starts
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")

    // Update live activity to show pause state
    if let session = activeSession {
      liveActivityManager.updatePauseState(session: session)
    }
  }

  private func handleSessionStarted(session: BlockedProfileSession) {
    self.dismissView()

    if SoftUnblockGrantStore.activeSession?.sessionId != session.id {
      SoftUnblockGrantScheduler.stopAll()
      SoftUnblockGrantStore.clearAll()
    }

    // Remove any timers and notifications that were scheduled
    self.timersUtil.cancelAll()
    // Update the snapshot of the profile in case some settings were changed
    BlockedProfiles.updateSnapshot(for: session.blockedProfile)

    self.errorMessage = nil

    self.activeSession = session
    self.startTimer()
    self.liveActivityManager
      .startSessionActivity(session: session)

    // Refresh widgets when session starts
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")
  }

  private func handleSessionEnded(profile: BlockedProfiles) {
    self.dismissView()

    SoftUnblockGrantScheduler.stopAll()
    SoftUnblockGrantStore.clearAll()

    // Remove any timers and notifications that were scheduled
    self.timersUtil.cancelAll()
    self.activeSession = nil
    self.liveActivityManager.endSessionActivity()
    self.scheduleReminder(profile: profile)

    self.stopTimer()
    self.elapsedTime = 0
    self.sessionDisplayTime = 0

    // Refresh widgets when session ends
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")

    // Remove all break timer activities
    DeviceActivityCenterUtil.removeAllBreakTimerActivities()

    // Remove all strategy timer activities
    DeviceActivityCenterUtil.removeAllStrategyTimerActivities()

    // Remove all pause timer activities
    DeviceActivityCenterUtil.removeAllPauseTimerActivities()
  }

  private func dismissView() {
    showCustomStrategyView = false
    customStrategyView = nil
    customStrategyViewPresentationDetents = [.medium, .large]
  }

  private func presentCustomStrategyView(
    _ view: any View,
    presentationDetents: Set<PresentationDetent>
  ) {
    customStrategyView = view
    customStrategyViewPresentationDetents = presentationDetents
    showCustomStrategyView = true
  }

  private func getActiveSession(context: ModelContext)
    -> BlockedProfileSession?
  {
    // Before fetching the active session, sync any schedule sessions
    syncScheduleSessions(context: context)

    return
      BlockedProfileSession
      .mostRecentActiveSession(in: context)
  }

  private func syncScheduleSessions(context: ModelContext) {
    // Process any active scheduled sessions
    if let activeScheduledSession = SharedData.getActiveSharedSession() {
      BlockedProfileSession.upsertSessionFromSnapshot(
        in: context,
        withSnapshot: activeScheduledSession
      )
    }

    // Process any completed scheduled sessions
    let completedScheduleSessions = SharedData.getCompletedSessionsForSchedular()
    for completedScheduleSession in completedScheduleSessions {
      BlockedProfileSession.upsertSessionFromSnapshot(
        in: context,
        withSnapshot: completedScheduleSession
      )
    }

    // Flush completed scheduled sessions
    SharedData.flushCompletedSessionsForSchedular()
  }

  private func resultFromURL(_ url: String) -> NFCResult {
    return NFCResult(id: url, url: url, DateScanned: Date())
  }

  private func startBlocking(
    context: ModelContext,
    activeProfile: BlockedProfiles?
  ) {
    guard let definedProfile = activeProfile else {
      print(
        "No active profile found, calling stop blocking with no session"
      )
      return
    }

    let strategy = getStrategy(context: context)
    let view = strategy.startBlocking(
      context: context,
      profile: definedProfile,
      forceStart: false
    )

    if let customView = view {
      presentCustomStrategyView(
        customView,
        presentationDetents: strategy.startViewPresentationDetents
      )
    }
  }

  private func stopBlocking(context: ModelContext) {
    guard let session = activeSession else {
      print(
        "No active session found, calling stop blocking with no session"
      )
      return
    }

    let strategy = getStrategy(context: context)
    let view = strategy.stopBlocking(context: context, session: session)

    if let customView = view {
      presentCustomStrategyView(
        customView,
        presentationDetents: [.medium, .large]
      )
    }
  }

  private func scheduleReminder(profile: BlockedProfiles) {
    guard let reminderTimeInSeconds = profile.reminderTimeInSeconds else {
      return
    }

    let profileName = profile.name
    let message = profile.customReminderMessage ?? defaultReminderMessage(forProfile: profile)
    timersUtil
      .scheduleNotification(
        title: profileName + " time!",
        message: message,
        seconds: TimeInterval(reminderTimeInSeconds)
      )
  }

  private func scheduleBreakReminder(
    profile: BlockedProfiles,
    durationInSeconds: TimeInterval? = nil
  ) {
    let profileName = profile.name

    // Schedule a reminder to let the user know that the break is about to end
    let breakDurationInSeconds = durationInSeconds ?? TimeInterval(profile.breakTimeInMinutes * 60)
    let breakNotificationTimeInSeconds = breakDurationInSeconds - 60
    if breakNotificationTimeInSeconds > 0 {
      timersUtil.scheduleNotification(
        title: "Break almost over!",
        message: "Hope you enjoyed your break, starting " + profileName + " in 1 minute.",
        seconds: breakNotificationTimeInSeconds
      )
    }
  }

  func cleanUpGhostSchedules(context: ModelContext) {
    let allActivities = DeviceActivityCenterUtil.getDeviceActivities()
    let scheduleTimerActivity = ScheduleTimerActivity()
    let scheduleActivities = scheduleTimerActivity.getAllScheduleTimerActivities(
      from: allActivities)

    print(
      "Found \(scheduleActivities.count) schedule timer activities out of \(allActivities.count) total activities"
    )

    for activity in scheduleActivities {
      let rawValue = activity.rawValue
      guard let profileId = UUID(uuidString: rawValue) else {
        // This shouldn't happen since we filtered above, but print just in case
        print("Unexpected: failed to parse profile id from filtered activity: \(rawValue)")
        continue
      }

      do {
        if let profile = try BlockedProfiles.findProfile(byID: profileId, in: context) {
          if profile.schedule == nil {
            print(
              "Profile '\(profile.name)' has no schedule but has device activity registered. Removing ghost schedule..."
            )
            DeviceActivityCenterUtil.removeScheduleTimerActivities(for: profile)
          } else {
            print("Profile '\(profile.name)' has schedule - activity is valid ✅")
          }
        } else {
          // Profile truly doesn't exist in database
          print("No profile found for activity \(rawValue). Removing orphaned schedule...")
          DeviceActivityCenterUtil.removeScheduleTimerActivities(for: activity)
        }
      } catch {
        // Database error occurred - do NOT delete the schedule since we don't know the true state
        print(
          "Error fetching profile \(rawValue): \(error.localizedDescription). Skipping cleanup for safety."
        )
      }
    }
  }

  func resetBlockingState(context: ModelContext) {
    guard !isBlocking else {
      print("Cannot reset blocking state while a profile is active")
      return
    }

    print("Resetting blocking state...")

    // Clean up ghost schedules
    cleanUpGhostSchedules(context: context)

    // Clear all restrictions
    appBlocker.deactivateRestrictions()
    SoftUnblockGrantScheduler.stopAll()
    SoftUnblockGrantStore.clearAll()

    // Remove all break timer activities
    DeviceActivityCenterUtil.removeAllBreakTimerActivities()

    // Remove all strategy timer activities
    DeviceActivityCenterUtil.removeAllStrategyTimerActivities()

    print("Blocking state reset complete")
  }
}
