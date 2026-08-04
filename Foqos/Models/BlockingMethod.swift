import SwiftUI

/// How a profile blocks, described as independent choices rather than as one
/// of a fixed list of strategies.
///
/// The twelve strategy classes this replaces were every useful combination of
/// four questions, spelled out one class at a time. Naming the questions makes
/// combinations that were never written available too: a schedule you can only
/// end early by scanning, a usage allowance with a temporary release, a session
/// started with a tag and ended by a timer.
struct BlockingMethod: Codable, Equatable {
  /// Every checked way of starting works; a profile with only `.schedule`
  /// simply cannot be started by hand, which is a legitimate hardcore setup.
  var start: [StartTrigger]
  /// How a person ends it. Independent of `autoEnd`: a session can run out on
  /// its own and still ask for a scan when you want out early. Empty is legal
  /// as long as something automatic ends the session.
  var stop: [StopTrigger]
  var autoEnd: AutoEnd
  /// Whether the stop controls work before `autoEnd` fires. Off makes a timed
  /// session impossible to abandon halfway.
  var allowsEarlyStop: Bool
  var enforcement: EnforcementMode
  var interruption: InterruptionMode
  var emergency: EmergencyPolicy

  init(
    start: [StartTrigger] = [.nfc],
    stop: [StopTrigger] = [.nfc],
    autoEnd: AutoEnd = .never,
    allowsEarlyStop: Bool = true,
    enforcement: EnforcementMode = .blockImmediately,
    interruption: InterruptionMode = .none,
    emergency: EmergencyPolicy = EmergencyPolicy()
  ) {
    self.start = start
    self.stop = stop
    self.autoEnd = autoEnd
    self.allowsEarlyStop = allowsEarlyStop
    self.enforcement = enforcement
    self.interruption = interruption
    self.emergency = emergency
  }

  // Rows written while these were single choices decode as such.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let many = try? container.decode([StartTrigger].self, forKey: .start) {
      start = many
    } else {
      start = [try container.decode(StartTrigger.self, forKey: .start)]
    }
    if let many = try? container.decode([StopTrigger].self, forKey: .stop) {
      stop = many
    } else {
      stop = [try container.decode(StopTrigger.self, forKey: .stop)]
    }
    autoEnd = try container.decodeIfPresent(AutoEnd.self, forKey: .autoEnd) ?? .never
    allowsEarlyStop =
      try container.decodeIfPresent(Bool.self, forKey: .allowsEarlyStop) ?? true
    enforcement =
      try container.decodeIfPresent(EnforcementMode.self, forKey: .enforcement)
      ?? .blockImmediately
    interruption =
      try container.decodeIfPresent(InterruptionMode.self, forKey: .interruption) ?? .none
    emergency =
      try container.decodeIfPresent(EmergencyPolicy.self, forKey: .emergency)
      ?? EmergencyPolicy()
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

  var id: String { rawValue }

  var title: String {
    switch self {
    case .manual: return "Tap to stop"
    case .nfc: return "Scan an NFC tag"
    case .qr: return "Scan a QR code"
    }
  }

  var isScan: Bool { self == .nfc || self == .qr }
}

/// When a session ends without anyone asking it to.
enum AutoEnd: Codable, Equatable {
  case never
  case afterMinutes(Int)
  case whenScheduleEnds

  static let minuteOptions = [
    5, 10, 15, 25, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720, 1440,
  ]

  static func label(forMinutes minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes) minutes" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours) hour\(hours == 1 ? "" : "s")" : "\(hours)h \(rest)m"
  }

  var minutes: Int? {
    guard case .afterMinutes(let minutes) = self else { return nil }
    return minutes
  }

  var title: String {
    switch self {
    case .never: return "Runs until stopped"
    case .afterMinutes(let minutes): return "After \(Self.label(forMinutes: minutes))"
    case .whenScheduleEnds: return "When the schedule ends"
    }
  }
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
  var usesNFC: Bool { start.contains(.nfc) || stop.contains(.nfc) }
  var usesQRCode: Bool { start.contains(.qr) || stop.contains(.qr) }
  var hasTimer: Bool { autoEnd.minutes != nil }
  var needsSchedule: Bool { start.contains(.schedule) || autoEnd == .whenScheduleEnds }
  var startsManually: Bool { start.contains(.manual) }
  var startsByScan: Bool { start.contains(.nfc) || start.contains(.qr) }
  var stopsByScan: Bool { stop.contains(.nfc) || stop.contains(.qr) }
  var canStartByHand: Bool { startsManually || startsByScan }

  var startScanTypes: [PhysicalUnblockItem.PhysicalUnblockType] {
    var types: [PhysicalUnblockItem.PhysicalUnblockType] = []
    if start.contains(.nfc) { types.append(.nfc) }
    if start.contains(.qr) { types.append(.qrCode) }
    return types
  }

  var stopScanTypes: [PhysicalUnblockItem.PhysicalUnblockType] {
    var types: [PhysicalUnblockItem.PhysicalUnblockType] = []
    if stop.contains(.nfc) { types.append(.nfc) }
    if stop.contains(.qr) { types.append(.qrCode) }
    return types
  }

  var summary: String {
    let startTitles = start.map(\.title).joined(separator: " / ")
    let stopTitles = stop.isEmpty ? "-" : stop.map(\.title).joined(separator: " / ")
    var parts = ["Start: \(startTitles)", "Stop: \(stopTitles)"]
    if autoEnd != .never {
      parts.append(autoEnd.title)
    }
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
    case noWayToStart
    case noWayToEnd
    case scheduleRequired
    case physicalUnlockItemRequired
    case allowanceNeedsBlocklistMode

    var message: String {
      switch self {
      case .noWayToStart:
        return "Pick at least one way to start."
      case .noWayToEnd:
        return "Nothing can end this session. Add a stop method or an automatic end."
      case .scheduleRequired:
        return "Set a schedule below, or pick a different way to start and stop."
      case .physicalUnlockItemRequired:
        return "Register an NFC tag or QR code for breaks first."
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

    if start.isEmpty {
      issues.append(.noWayToStart)
    }
    if stop.isEmpty && autoEnd == .never {
      issues.append(.noWayToEnd)
    }
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

/// The strategies this app shipped before the dimensions existed, kept intact
/// as starting points. Picking one fills in every dimension; anything can then
/// be adjusted, including into combinations that were never on this list.
struct BlockingMethodPreset: Identifiable, Equatable {
  let id: String
  let name: String
  let detail: String
  let iconAssetName: String
  let color: Color
  let category: Category
  let method: BlockingMethod

  enum Category: String, CaseIterable, Identifiable {
    case mostPopular
    case easyToStart
    case timers
    case forever

    var id: String { rawValue }

    var title: String {
      switch self {
      case .mostPopular: return "Most popular"
      case .easyToStart: return "Easy to start"
      case .timers: return "Timers"
      case .forever: return "No end time"
      }
    }
  }

  static let all: [BlockingMethodPreset] = [
    BlockingMethodPreset(
      id: "nfc", name: "NFC Tags",
      detail: "Scan a tag to start, scan again to stop.",
      iconAssetName: "NFCStickerLogo", color: .yellow, category: .mostPopular,
      method: BlockingMethod(start: [.nfc], stop: [.nfc])
    ),
    BlockingMethodPreset(
      id: "qr", name: "QR Code/Barcode",
      detail: "Scan a code to start, scan again to stop.",
      iconAssetName: "QRStickerLogo", color: .pink, category: .mostPopular,
      method: BlockingMethod(start: [.qr], stop: [.qr])
    ),
    BlockingMethodPreset(
      id: "manual", name: "Manual",
      detail: "Start and stop it yourself, with nothing in the way.",
      iconAssetName: "ManualLogoSticker", color: .blue, category: .easyToStart,
      method: BlockingMethod(start: [.manual], stop: [.manual])
    ),
    BlockingMethodPreset(
      id: "nfcManual", name: "NFC + Manual",
      detail: "Start with a tap, but scan a tag to stop.",
      iconAssetName: "Manual+NFCSticker", color: .yellow, category: .easyToStart,
      method: BlockingMethod(start: [.manual], stop: [.nfc])
    ),
    BlockingMethodPreset(
      id: "qrManual", name: "QR/Barcode + Manual",
      detail: "Start with a tap, but scan a code to stop.",
      iconAssetName: "Manual+QRSticker", color: .pink, category: .easyToStart,
      method: BlockingMethod(start: [.manual], stop: [.qr])
    ),
    BlockingMethodPreset(
      id: "timerManual", name: "Timer + Manual",
      detail: "Runs out on its own after the time you set.",
      iconAssetName: "Manual + Timer", color: .mint, category: .timers,
      method: BlockingMethod(
        start: [.manual], stop: [.manual], autoEnd: .afterMinutes(25))
    ),
    BlockingMethodPreset(
      id: "nfcTimer", name: "NFC + Timer",
      detail: "Runs out on its own; scan a tag to get out early.",
      iconAssetName: "NFC+TimerSticker", color: .mint, category: .timers,
      method: BlockingMethod(
        start: [.manual], stop: [.nfc], autoEnd: .afterMinutes(25))
    ),
    BlockingMethodPreset(
      id: "qrTimer", name: "QR/Barcode + Timer",
      detail: "Runs out on its own; scan a code to get out early.",
      iconAssetName: "QR+TimerSticker", color: .mint, category: .timers,
      method: BlockingMethod(
        start: [.manual], stop: [.qr], autoEnd: .afterMinutes(25))
    ),
    BlockingMethodPreset(
      id: "nfcPause", name: "NFC + Breaks",
      detail: "No end time, with break time you can spend as you like.",
      iconAssetName: "NFCPauseSticker", color: .orange, category: .forever,
      method: BlockingMethod(
        start: [.manual], stop: [.nfc],
        interruption: .timedBreak(minutes: 15, allowMultiple: false))
    ),
    BlockingMethodPreset(
      id: "qrPause", name: "QR/Barcode + Breaks",
      detail: "No end time, with break time you can spend as you like.",
      iconAssetName: "QRPauseSticker", color: .indigo, category: .forever,
      method: BlockingMethod(
        start: [.manual], stop: [.qr],
        interruption: .timedBreak(minutes: 15, allowMultiple: false))
    ),
    BlockingMethodPreset(
      id: "softUnblockNFC", name: "Temporary Access + NFC",
      detail: "Always on, with a few short openings you can tap for.",
      iconAssetName: "Soft Unblock + NFC", color: .purple, category: .forever,
      method: BlockingMethod(
        start: [.manual], stop: [.nfc],
        interruption: .grantByButton(minutes: 15, maxCount: 3))
    ),
    BlockingMethodPreset(
      id: "softUnblockQR", name: "Temporary Access + QR",
      detail: "Always on, with a few short openings you can tap for.",
      iconAssetName: "Soft Unblock + QR", color: .purple, category: .forever,
      method: BlockingMethod(
        start: [.manual], stop: [.qr],
        interruption: .grantByButton(minutes: 15, maxCount: 3))
    ),
    BlockingMethodPreset(
      id: "schedule", name: "Scheduled Hours",
      detail: "Blocks itself during the hours you set.",
      iconAssetName: "ManualLogoSticker", color: .teal, category: .forever,
      method: BlockingMethod(
        start: [.schedule], stop: [.manual], autoEnd: .whenScheduleEnds)
    ),
    BlockingMethodPreset(
      id: "dailyAllowance", name: "Daily Allowance",
      detail: "Use the apps freely up to a daily limit, then scan for more.",
      iconAssetName: "NFCStickerLogo", color: .orange, category: .forever,
      method: BlockingMethod(
        start: [.schedule], stop: [.manual], autoEnd: .whenScheduleEnds,
        enforcement: .usageAllowance(minutes: 30),
        interruption: .grantByScan(minutes: 5, maxCount: nil))
    ),
  ]

  static func matching(_ method: BlockingMethod) -> BlockingMethodPreset? {
    all.first { $0.method == method }
  }

  static func inCategory(_ category: Category) -> [BlockingMethodPreset] {
    all.filter { $0.category == category }
  }
}
