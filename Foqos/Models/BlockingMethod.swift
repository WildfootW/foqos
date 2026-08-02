import Foundation

/// How a profile blocks, described as independent choices rather than as one
/// of a fixed list of strategies.
///
/// The twelve strategy classes this replaces were every useful combination of
/// four questions, spelled out one class at a time. Naming the questions makes
/// combinations that were never written available too: a schedule you can only
/// end early by scanning, a usage allowance with a temporary release, a session
/// started with a tag and ended by a timer.
struct BlockingMethod: Codable, Equatable {
  var start: StartTrigger
  var stop: StopTrigger
  /// Only meaningful when `stop == .timer`.
  var stopTimerMinutes: Int
  /// Hides the stop control until a timer stop actually elapses, so a timed
  /// session cannot be abandoned halfway.
  var hideStopUntilTimerEnds: Bool = false
  var enforcement: EnforcementMode
  var interruption: InterruptionMode
  var emergency: EmergencyPolicy

  init(
    start: StartTrigger = .nfc,
    stop: StopTrigger = .nfc,
    stopTimerMinutes: Int = 25,
    hideStopUntilTimerEnds: Bool = false,
    enforcement: EnforcementMode = .blockImmediately,
    interruption: InterruptionMode = .none,
    emergency: EmergencyPolicy = EmergencyPolicy()
  ) {
    self.start = start
    self.stop = stop
    self.stopTimerMinutes = stopTimerMinutes
    self.hideStopUntilTimerEnds = hideStopUntilTimerEnds
    self.enforcement = enforcement
    self.interruption = interruption
    self.emergency = emergency
  }
}

// MARK: - Dimensions

enum StartTrigger: String, Codable, CaseIterable, Identifiable {
  case manual
  case nfc
  case qr
  case schedule

  var id: String { rawValue }

  var title: String {
    switch self {
    case .manual: return "Tap to start"
    case .nfc: return "Scan an NFC tag"
    case .qr: return "Scan a QR code"
    case .schedule: return "On a schedule"
    }
  }

  var isScan: Bool { self == .nfc || self == .qr }
}

enum StopTrigger: String, Codable, CaseIterable, Identifiable {
  case manual
  case nfc
  case qr
  case timer
  case schedule

  var id: String { rawValue }

  var title: String {
    switch self {
    case .manual: return "Tap to stop"
    case .nfc: return "Scan an NFC tag"
    case .qr: return "Scan a QR code"
    case .timer: return "After a set time"
    case .schedule: return "When the schedule ends"
    }
  }

  var isScan: Bool { self == .nfc || self == .qr }
}

/// What happens to the selected apps while a session is running.
enum EnforcementMode: Codable, Equatable {
  /// Everything selected is blocked for the whole session.
  case blockImmediately
  /// The apps stay usable until they have been used for `minutes` in total,
  /// then they lock. The allowance resets when the session's schedule window
  /// restarts (daily if no schedule is set).
  case usageAllowance(minutes: Int)

  static let allowanceRange = 5...720
  static let allowanceOptions = [10, 15, 20, 30, 45, 60, 90, 120, 180]

  var allowanceMinutes: Int? {
    guard case .usageAllowance(let minutes) = self else { return nil }
    return minutes
  }

  var title: String {
    switch self {
    case .blockImmediately: return "Block right away"
    case .usageAllowance(let minutes): return "Allow \(minutes) min per day"
    }
  }
}

/// How the block can be lifted for a short while without ending the session.
///
/// `timedBreak` covers what used to be two separate features, "breaks" and the
/// pause timer, which lifted and restored restrictions identically and differed
/// only in where they were configured.
enum InterruptionMode: Codable, Equatable {
  case none
  /// One shared pool of break time, taken in one go or across several breaks.
  case timedBreak(minutes: Int, allowMultiple: Bool)
  /// A button on the shield releases a single app for a while, a limited
  /// number of times.
  case grantByButton(minutes: Int, maxCount: Int)
  /// Same, but the release has to be earned by scanning one of the profile's
  /// physical unlock items. `maxCount == nil` means unlimited.
  case grantByScan(minutes: Int, maxCount: Int?)

  static let durationOptions = [1, 2, 5, 10, 15, 30]
  static let breakDurationOptions = [5, 10, 15, 30]
  static let countRange = 1...10

  var releaseMinutes: Int? {
    switch self {
    case .none: return nil
    case .timedBreak(let minutes, _): return minutes
    case .grantByButton(let minutes, _): return minutes
    case .grantByScan(let minutes, _): return minutes
    }
  }

  var requiresPhysicalUnlockItem: Bool {
    if case .grantByScan = self { return true }
    return false
  }

  var title: String {
    switch self {
    case .none:
      return "No releases"
    case .timedBreak(let minutes, let allowMultiple):
      return allowMultiple ? "\(minutes) min of breaks" : "One \(minutes) min break"
    case .grantByButton(let minutes, let maxCount):
      return "\(maxCount) × \(minutes) min, one tap"
    case .grantByScan(let minutes, let maxCount):
      guard let maxCount else { return "\(minutes) min per scan" }
      return "\(maxCount) × \(minutes) min per scan"
    }
  }
}

/// Emergency releases are counted per session and refill whenever a new session
/// starts, so the allowance means "mistakes I can make during this stretch of
/// focus" rather than a running monthly balance.
struct EmergencyPolicy: Codable, Equatable {
  static let countRange = 0...10

  var isEnabled: Bool
  var maxUsesPerSession: Int

  init(isEnabled: Bool = true, maxUsesPerSession: Int = 3) {
    self.isEnabled = isEnabled
    self.maxUsesPerSession = maxUsesPerSession
  }

  var effectiveMaxUses: Int { isEnabled ? maxUsesPerSession : 0 }
}

// MARK: - Derived capabilities

extension BlockingMethod {
  var usesNFC: Bool { start == .nfc || stop == .nfc }
  var usesQRCode: Bool { start == .qr || stop == .qr }
  var hasTimer: Bool { stop == .timer }
  var needsSchedule: Bool { start == .schedule || stop == .schedule }
  var startsManually: Bool { start == .manual }

  /// Whether ending the session and taking a release both cost the same
  /// physical act. When they do, the release is the strictly worse deal and the
  /// stop needs a confirmation step to stay meaningful.
  var stopAndReleaseShareACredential: Bool {
    guard case .grantByScan = interruption else { return false }
    return stop.isScan
  }

  var summary: String {
    var parts = ["Start: \(start.title)", "Stop: \(stop.title)"]
    if case .usageAllowance = enforcement {
      parts.append(enforcement.title)
    }
    if interruption != .none {
      parts.append(interruption.title)
    }
    return parts.joined(separator: " · ")
  }
}

// MARK: - Validation

extension BlockingMethod {
  enum ValidationIssue: Hashable {
    case scheduleRequired
    case physicalUnlockItemRequired
    case allowanceNeedsBlocklistMode

    var message: String {
      switch self {
      case .scheduleRequired:
        return "Set a schedule below, or pick a different way to start and stop."
      case .physicalUnlockItemRequired:
        return "Add an NFC tag or QR code under Physical Unlocks first."
      case .allowanceNeedsBlocklistMode:
        return "A daily allowance needs a blocked-app profile, not Allow Mode."
      }
    }
  }

  func validate(
    hasActiveSchedule: Bool,
    hasPhysicalUnlockItems: Bool,
    isAllowMode: Bool
  ) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []

    if needsSchedule && !hasActiveSchedule {
      issues.append(.scheduleRequired)
    }
    if interruption.requiresPhysicalUnlockItem && !hasPhysicalUnlockItems {
      issues.append(.physicalUnlockItemRequired)
    }
    if enforcement.allowanceMinutes != nil && isAllowMode {
      issues.append(.allowanceNeedsBlocklistMode)
    }

    return issues
  }
}

// MARK: - Presets

/// The combinations worth putting in front of someone who does not want to
/// think about the dimensions. Everything else is reachable through Custom.
struct BlockingMethodPreset: Identifiable, Equatable {
  let id: String
  let name: String
  let detail: String
  let symbolName: String
  let method: BlockingMethod

  static let all: [BlockingMethodPreset] = [
    BlockingMethodPreset(
      id: "nfc",
      name: "NFC Tag",
      detail: "Scan a tag to start, scan again to stop.",
      symbolName: "wave.3.right",
      method: BlockingMethod(start: .nfc, stop: .nfc)
    ),
    BlockingMethodPreset(
      id: "qr",
      name: "QR Code",
      detail: "Scan a code to start, scan again to stop.",
      symbolName: "qrcode",
      method: BlockingMethod(start: .qr, stop: .qr)
    ),
    BlockingMethodPreset(
      id: "timer",
      name: "Focus Timer",
      detail: "Tap to start, unlocks itself when the time is up.",
      symbolName: "timer",
      method: BlockingMethod(start: .manual, stop: .timer, stopTimerMinutes: 25)
    ),
    BlockingMethodPreset(
      id: "dailyAllowance",
      name: "Daily Allowance",
      detail: "Use the apps freely up to a daily limit, then scan for more.",
      symbolName: "hourglass",
      method: BlockingMethod(
        start: .schedule,
        stop: .schedule,
        enforcement: .usageAllowance(minutes: 30),
        interruption: .grantByScan(minutes: 5, maxCount: nil)
      )
    ),
    BlockingMethodPreset(
      id: "schedule",
      name: "Scheduled Hours",
      detail: "Blocks itself during the hours you set.",
      symbolName: "calendar",
      method: BlockingMethod(start: .schedule, stop: .schedule)
    ),
    BlockingMethodPreset(
      id: "temporaryAccess",
      name: "Temporary Access",
      detail: "Always on, with a few short openings you can tap for.",
      symbolName: "lock.open",
      method: BlockingMethod(
        start: .manual,
        stop: .nfc,
        interruption: .grantByButton(minutes: 15, maxCount: 3)
      )
    ),
  ]

  static func matching(_ method: BlockingMethod) -> BlockingMethodPreset? {
    all.first { $0.method == method }
  }
}
