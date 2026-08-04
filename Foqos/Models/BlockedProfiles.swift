import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import SwiftData

@Model
class BlockedProfiles {
  @Attribute(.unique) var id: UUID
  var name: String
  var selectedActivity: FamilyActivitySelection
  var createdAt: Date
  var updatedAt: Date
  var order: Int = 0

  var enableLiveActivity: Bool = false
  var reminderTimeInSeconds: UInt32?
  var enableStrictMode: Bool = false
  var enableBlockAppInstallation: Bool = false
  var enableAllowMode: Bool = false
  var enableAllowModeDomains: Bool = false
  var enableSafariBlocking: Bool = true
  var enableAdultContentBlocking: Bool = false

  @available(
    *, deprecated, message: "Use physicalUnblockItems instead - supports multiple NFC/QR codes"
  )
  var physicalUnblockNFCTagId: String?

  @available(
    *, deprecated, message: "Use physicalUnblockItems instead - supports multiple NFC/QR codes"
  )
  var physicalUnblockQRCodeId: String?

  /// Array of physical unblock items (NFC tags and QR codes) that can unblock this profile
  /// Supports multiple NFC tags and/or QR codes per profile
  var physicalUnblockItems: [PhysicalUnblockItem]?

  var domains: [String]? = nil

  var schedule: BlockedProfileSchedule? = nil

  var disableBackgroundStops: Bool = false


  var customReminderMessage: String?

  /// The method as JSON rather than as a nested value type. SwiftData tries
  /// to flatten Codable properties into columns, and the enums with
  /// associated values inside BlockingMethod crash that machinery at runtime;
  /// a Data blob goes through untouched.
  private var blockingMethodData: Data? = nil

  var method: BlockingMethod {
    get {
      guard let blockingMethodData,
        let method = try? JSONDecoder().decode(BlockingMethod.self, from: blockingMethodData)
      else { return BlockingMethod() }
      return method
    }
    set { blockingMethodData = try? JSONEncoder().encode(newValue) }
  }

  @Relationship var sessions: [BlockedProfileSession] = []

  var activeScheduleTimerActivity: DeviceActivityName? {
    return DeviceActivityCenterUtil.getActiveScheduleTimerActivity(for: self)
  }

  var scheduleIsOutOfSync: Bool {
    return self.schedule?.isActive == true
      && DeviceActivityCenterUtil.getActiveScheduleTimerActivity(for: self) == nil
  }

  var allowsTimedBreaks: Bool {
    if case .timedBreak = method.interruption { return true }
    return method.interruption == .none
  }

  // Breaks used to be three stored flags edited in their own screen while the
  // method separately claimed to describe them. The method is the only source
  // now; these read through so the session machinery is untouched.
  var enableBreaks: Bool {
    if case .timedBreak = method.interruption { return true }
    return false
  }

  var breakTimeInMinutes: Int {
    if case .timedBreak(let minutes, _) = method.interruption { return minutes }
    return 15
  }

  var allowMultipleBreaks: Bool {
    if case .timedBreak(_, let allowMultiple) = method.interruption { return allowMultiple }
    return false
  }

  var enableEmergencyUnblock: Bool { method.emergency.isEnabled }

  // MARK: - Physical Unblock Helpers

  /// Checks if a specific NFC tag or QR code can unblock this profile
  /// - Parameters:
  ///   - codeValue: The NFC tag ID or QR code value to check
  ///   - type: The type of code (NFC or QR)
  /// - Returns: True if the code is in the allowed list, false otherwise
  /// Codes registered for an action. An empty set means the action has not
  /// been narrowed down, and any code of the right kind will do.
  func codes(for role: PhysicalUnblockRole) -> [PhysicalUnblockItem] {
    (physicalUnblockItems ?? []).filter { $0.serves(role) }
  }

  func accepts(
    code codeValue: String,
    type: PhysicalUnblockItem.PhysicalUnblockType,
    for role: PhysicalUnblockRole
  ) -> Bool {
    let candidates = codes(for: role).filter { $0.type == type }
    guard !candidates.isEmpty else { return true }

    let normalized = PhysicalUnblockItem.normalizedCodeValue(codeValue, type: type)
    return candidates.contains {
      PhysicalUnblockItem.normalizedCodeValue($0.codeValue, type: $0.type) == normalized
    }
  }

  func hasCode(
    ofType type: PhysicalUnblockItem.PhysicalUnblockType,
    for role: PhysicalUnblockRole
  ) -> Bool {
    codes(for: role).contains { $0.type == type }
  }

  init(
    id: UUID = UUID(),
    name: String,
    selectedActivity: FamilyActivitySelection = FamilyActivitySelection(),
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    enableLiveActivity: Bool = false,
    reminderTimeInSeconds: UInt32? = nil,
    customReminderMessage: String? = nil,
    enableStrictMode: Bool = false,
    enableBlockAppInstallation: Bool = false,
    enableAllowMode: Bool = false,
    enableAllowModeDomains: Bool = false,
    enableSafariBlocking: Bool = true,
    enableAdultContentBlocking: Bool = false,
    order: Int = 0,
    domains: [String]? = nil,
    physicalUnblockItems: [PhysicalUnblockItem]? = nil,
    schedule: BlockedProfileSchedule? = nil,
    disableBackgroundStops: Bool = false,
    blockingMethod: BlockingMethod? = nil
  ) {
    self.id = id
    self.name = name
    self.selectedActivity = selectedActivity
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.order = order

    self.enableLiveActivity = enableLiveActivity
    self.reminderTimeInSeconds = reminderTimeInSeconds
    self.customReminderMessage = customReminderMessage
    self.enableLiveActivity = enableLiveActivity
    self.enableStrictMode = enableStrictMode
    self.enableBlockAppInstallation = enableBlockAppInstallation
    self.enableAllowMode = enableAllowMode
    self.enableAllowModeDomains = enableAllowModeDomains
    self.enableSafariBlocking = enableSafariBlocking
    self.enableAdultContentBlocking = enableAdultContentBlocking
    self.domains = domains

    self.physicalUnblockItems = PhysicalUnblockItem.normalizedItems(physicalUnblockItems)
    self.schedule = schedule

    self.disableBackgroundStops = disableBackgroundStops
    if let blockingMethod {
      self.method = blockingMethod
    }
  }

  func showStopButton(elapsedTime: TimeInterval) -> Bool {
    guard !method.allowsEarlyStop, let minutes = method.autoEnd.minutes else { return true }
    return elapsedTime >= Double(minutes * 60)
  }

  static func fetchProfiles(in context: ModelContext) throws
    -> [BlockedProfiles]
  {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      sortBy: [
        SortDescriptor(\.order, order: .forward), SortDescriptor(\.createdAt, order: .reverse),
      ]
    )
    return try context.fetch(descriptor)
  }

  static func findProfile(byID id: UUID, in context: ModelContext) throws
    -> BlockedProfiles?
  {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      predicate: #Predicate { $0.id == id }
    )
    return try context.fetch(descriptor).first
  }

  static func fetchMostRecentlyUpdatedProfile(in context: ModelContext) throws
    -> BlockedProfiles?
  {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
    )
    return try context.fetch(descriptor).first
  }

  static func updateProfile(
    _ profile: BlockedProfiles,
    in context: ModelContext,
    name: String? = nil,
    selection: FamilyActivitySelection? = nil,
    enableLiveActivity: Bool? = nil,
    reminderTime: UInt32? = nil,
    customReminderMessage: String? = nil,
    enableStrictMode: Bool? = nil,
    enableBlockAppInstallation: Bool? = nil,
    enableAllowMode: Bool? = nil,
    enableAllowModeDomains: Bool? = nil,
    enableSafariBlocking: Bool? = nil,
    enableAdultContentBlocking: Bool? = nil,
    order: Int? = nil,
    domains: [String]? = nil,
    physicalUnblockItems: [PhysicalUnblockItem]?? = nil,
    schedule: BlockedProfileSchedule? = nil,
    disableBackgroundStops: Bool? = nil,
    blockingMethod: BlockingMethod? = nil
  ) throws -> BlockedProfiles {
    if let newName = name {
      profile.name = newName
    }

    if let newSelection = selection {
      profile.selectedActivity = newSelection
    }

    if let newEnableLiveActivity = enableLiveActivity {
      profile.enableLiveActivity = newEnableLiveActivity
    }




    if let newEnableStrictMode = enableStrictMode {
      profile.enableStrictMode = newEnableStrictMode
    }

    if let newEnableBlockAppInstallation = enableBlockAppInstallation {
      profile.enableBlockAppInstallation = newEnableBlockAppInstallation
    }

    if let newEnableAllowMode = enableAllowMode {
      profile.enableAllowMode = newEnableAllowMode
    }

    if let newEnableAllowModeDomains = enableAllowModeDomains {
      profile.enableAllowModeDomains = newEnableAllowModeDomains
    }

    if let newEnableSafariBlocking = enableSafariBlocking {
      profile.enableSafariBlocking = newEnableSafariBlocking
    }

    if let newEnableAdultContentBlocking = enableAdultContentBlocking {
      profile.enableAdultContentBlocking = newEnableAdultContentBlocking
    }

    if let newOrder = order {
      profile.order = newOrder
    }

    if let newDomains = domains {
      profile.domains = newDomains
    }

    if let newSchedule = schedule {
      profile.schedule = newSchedule
    }

    if let newDisableBackgroundStops = disableBackgroundStops {
      profile.disableBackgroundStops = newDisableBackgroundStops
    }


    if let physicalUnblockItems {
      profile.physicalUnblockItems = PhysicalUnblockItem.normalizedItems(physicalUnblockItems)
    }

    if let blockingMethod {
      profile.method = blockingMethod
    }

    profile.reminderTimeInSeconds = reminderTime
    profile.customReminderMessage = customReminderMessage
    profile.updatedAt = Date()

    // Update the snapshot
    updateSnapshot(for: profile)

    try context.save()

    return profile
  }

  static func deleteProfile(
    _ profile: BlockedProfiles,
    in context: ModelContext
  ) throws {
    // First end any active sessions
    for session in profile.sessions {
      if session.endTime == nil {
        session.endSession()
      }
    }

    // Remove all sessions first
    for session in profile.sessions {
      context.delete(session)
    }

    // Delete the snapshot
    deleteSnapshot(for: profile)

    // Remove the schedule restrictions
    DeviceActivityCenterUtil.removeScheduleTimerActivities(for: profile)

    // Remove any usage limit monitoring and shields
    UsageLimitScheduler.end(profileId: profile.id)

    // Then delete the profile
    context.delete(profile)
    // Defer context saving as the reference to the profile might be used
  }

  static func getProfileDeepLink(_ profile: BlockedProfiles) -> String {
    return "https://foqos.app/profile/" + profile.id.uuidString
  }

  static func getSnapshot(for profile: BlockedProfiles) -> SharedData.ProfileSnapshot {
    return SharedData.ProfileSnapshot(
      id: profile.id,
      name: profile.name,
      selectedActivity: profile.selectedActivity,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt,
      order: profile.order,
      enableLiveActivity: profile.enableLiveActivity,
      reminderTimeInSeconds: profile.reminderTimeInSeconds,
      customReminderMessage: profile.customReminderMessage,
      enableStrictMode: profile.enableStrictMode,
      enableBlockAppInstallation: profile.enableBlockAppInstallation,
      enableAllowMode: profile.enableAllowMode,
      enableAllowModeDomains: profile.enableAllowModeDomains,
      enableSafariBlocking: profile.enableSafariBlocking,
      enableAdultContentBlocking: profile.enableAdultContentBlocking,
      domains: profile.domains,
      physicalUnblockNFCTagId: nil,
      physicalUnblockQRCodeId: nil,
      physicalUnblockItems: profile.physicalUnblockItems,
      schedule: profile.schedule,
      disableBackgroundStops: profile.disableBackgroundStops,
      blockingMethod: profile.method
    )
  }

  // Create a codable/equatable snapshot suitable for UserDefaults
  static func updateSnapshot(for profile: BlockedProfiles) {
    let snapshot = getSnapshot(for: profile)
    SharedData.setSnapshot(snapshot, for: profile.id.uuidString)
  }

  static func deleteSnapshot(for profile: BlockedProfiles) {
    SharedData.removeSnapshot(for: profile.id.uuidString)
  }

  static func reorderProfiles(
    _ profiles: [BlockedProfiles],
    in context: ModelContext
  ) throws {
    for (index, profile) in profiles.enumerated() {
      profile.order = index
    }
    try context.save()
  }

  static func getNextOrder(in context: ModelContext) -> Int {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      sortBy: [SortDescriptor(\.order, order: .reverse)]
    )
    guard let lastProfile = try? context.fetch(descriptor).first else {
      return 0
    }
    return lastProfile.order + 1
  }

  static func createProfile(
    in context: ModelContext,
    name: String,
    selection: FamilyActivitySelection = FamilyActivitySelection(),
    enableLiveActivity: Bool = false,
    reminderTimeInSeconds: UInt32? = nil,
    customReminderMessage: String = "",
    enableStrictMode: Bool = false,
    enableBlockAppInstallation: Bool = false,
    enableAllowMode: Bool = false,
    enableAllowModeDomains: Bool = false,
    enableSafariBlocking: Bool = true,
    enableAdultContentBlocking: Bool = false,
    domains: [String]? = nil,
    physicalUnblockItems: [PhysicalUnblockItem]? = nil,
    schedule: BlockedProfileSchedule? = nil,
    disableBackgroundStops: Bool = false,
    blockingMethod: BlockingMethod? = nil
  ) throws -> BlockedProfiles {
    let profileOrder = getNextOrder(in: context)

    let profile = BlockedProfiles(
      name: name,
      selectedActivity: selection,
      enableLiveActivity: enableLiveActivity,
      reminderTimeInSeconds: reminderTimeInSeconds,
      customReminderMessage: customReminderMessage,
      enableStrictMode: enableStrictMode,
      enableBlockAppInstallation: enableBlockAppInstallation,
      enableAllowMode: enableAllowMode,
      enableAllowModeDomains: enableAllowModeDomains,
      enableSafariBlocking: enableSafariBlocking,
      enableAdultContentBlocking: enableAdultContentBlocking,
      order: profileOrder,
      domains: domains,
      physicalUnblockItems: physicalUnblockItems,
      disableBackgroundStops: disableBackgroundStops,
      blockingMethod: blockingMethod
    )

    if let schedule = schedule {
      profile.schedule = schedule
    }

    // Create the snapshot so extensions can read it immediately
    updateSnapshot(for: profile)

    context.insert(profile)
    try context.save()
    return profile
  }

  static func cloneProfile(
    _ source: BlockedProfiles,
    in context: ModelContext,
    newName: String
  ) throws -> BlockedProfiles {
    let nextOrder = getNextOrder(in: context)
    let cloned = BlockedProfiles(
      name: newName,
      selectedActivity: source.selectedActivity,
      enableLiveActivity: source.enableLiveActivity,
      reminderTimeInSeconds: source.reminderTimeInSeconds,
      customReminderMessage: source.customReminderMessage,
      enableStrictMode: source.enableStrictMode,
      enableBlockAppInstallation: source.enableBlockAppInstallation,
      enableAllowMode: source.enableAllowMode,
      enableAllowModeDomains: source.enableAllowModeDomains,
      enableSafariBlocking: source.enableSafariBlocking,
      enableAdultContentBlocking: source.enableAdultContentBlocking,
      order: nextOrder,
      domains: source.domains,
      physicalUnblockItems: source.physicalUnblockItems,
      schedule: source.schedule,
      blockingMethod: source.method
    )

    context.insert(cloned)
    try context.save()
    return cloned
  }

  static func addDomain(to profile: BlockedProfiles, context: ModelContext, domain: String) throws {
    guard let domains = profile.domains else {
      return
    }

    if domains.contains(domain) {
      return
    }

    let newDomains = domains + [domain]
    try updateProfile(profile, in: context, domains: newDomains)
  }

  static func removeDomain(from profile: BlockedProfiles, context: ModelContext, domain: String)
    throws
  {
    guard let domains = profile.domains else {
      return
    }

    let newDomains = domains.filter { $0 != domain }
    try updateProfile(profile, in: context, domains: newDomains)
  }
}
