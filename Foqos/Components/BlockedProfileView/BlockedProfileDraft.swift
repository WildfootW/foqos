import FamilyControls
import Foundation
import SwiftData
import SwiftUI

final class BlockedProfileDraft: ObservableObject {
  @Published var name: String
  @Published var enableLiveActivity: Bool
  @Published var enableReminder: Bool
  @Published var enableBreaks: Bool
  @Published var breakTimeInMinutes: Int
  @Published var allowMultipleBreaks: Bool
  @Published var enableStrictMode: Bool
  @Published var enableBlockAppInstallation: Bool
  @Published var reminderTimeInMinutes: Int
  @Published var customReminderMessage: String
  @Published var enableAllowMode: Bool
  @Published var enableAllowModeDomain: Bool
  @Published var enableSafariBlocking: Bool
  @Published var enableAdultContentBlocking: Bool
  @Published var disableBackgroundStops: Bool
  @Published var enableEmergencyUnblock: Bool
  @Published var domains: [String]
  @Published var physicalUnblockItems: [PhysicalUnblockItem]
  @Published var schedule: BlockedProfileSchedule
  @Published var selectedActivity: FamilyActivitySelection
  @Published var method: BlockingMethod {
    didSet {
      enforceStrategyBreaksPolicy()
    }
  }

  init(profile: BlockedProfiles? = nil) {
    name = profile?.name ?? ""
    selectedActivity = profile?.selectedActivity ?? FamilyActivitySelection()
    enableLiveActivity = profile?.enableLiveActivity ?? false
    enableBreaks = profile?.enableBreaks ?? false
    breakTimeInMinutes = profile?.breakTimeInMinutes ?? 15
    allowMultipleBreaks = profile?.allowMultipleBreaks ?? false
    enableStrictMode = profile?.enableStrictMode ?? false
    enableBlockAppInstallation = profile?.enableBlockAppInstallation ?? false
    enableAllowMode = profile?.enableAllowMode ?? false
    enableAllowModeDomain = profile?.enableAllowModeDomains ?? false
    enableSafariBlocking = profile?.enableSafariBlocking ?? true
    enableAdultContentBlocking = profile?.enableAdultContentBlocking ?? false
    enableReminder = profile?.reminderTimeInSeconds != nil
    disableBackgroundStops = profile?.disableBackgroundStops ?? false
    enableEmergencyUnblock = profile?.enableEmergencyUnblock ?? true
    reminderTimeInMinutes = Int(profile?.reminderTimeInSeconds ?? 900) / 60
    customReminderMessage = profile?.customReminderMessage ?? ""
    domains = profile?.domains ?? []
    physicalUnblockItems = profile?.physicalUnblockItems ?? []
    schedule =
      profile?.schedule
      ?? BlockedProfileSchedule(
        days: [],
        startHour: 9,
        startMinute: 0,
        endHour: 17,
        endMinute: 0,
        updatedAt: Date()
      )

    method = profile?.method ?? BlockingMethod()

    enforceStrategyBreaksPolicy()
  }

  var isValid: Bool {
    return !name.isEmpty
  }

  var selectedStrategyAllowsTimedBreaks: Bool {
    if case .timedBreak = method.interruption { return true }
    return method.interruption == .none
  }

  var methodValidationIssues: [BlockingMethod.ValidationIssue] {
    method.validate(
      hasActiveSchedule: schedule.isActive,
      hasPhysicalUnlockItems: !physicalUnblockItems.isEmpty,
      isAllowMode: enableAllowMode
    )
  }

  func save(
    existingProfile: BlockedProfiles?,
    in context: ModelContext
  ) throws -> BlockedProfiles {
    schedule.updatedAt = Date()

    let reminderTimeSeconds: UInt32? =
      enableReminder ? UInt32(reminderTimeInMinutes * 60) : nil
    let physicalUnblockItemsToSave: [PhysicalUnblockItem]? =
      physicalUnblockItems.isEmpty ? nil : physicalUnblockItems
    let enableTimedBreaksToSave = selectedStrategyAllowsTimedBreaks && enableBreaks
    var methodToSave = method
    if enableAllowMode, methodToSave.enforcement.allowanceMinutes != nil {
      // An allowance counts usage of blocked apps; there are none in Allow Mode.
      methodToSave.enforcement = .blockImmediately
    }

    if let existingProfile {
      let updatedProfile = try BlockedProfiles.updateProfile(
        existingProfile,
        in: context,
        name: name,
        selection: selectedActivity,
        enableLiveActivity: enableLiveActivity,
        reminderTime: reminderTimeSeconds,
        customReminderMessage: customReminderMessage,
        enableBreaks: enableTimedBreaksToSave,
        breakTimeInMinutes: breakTimeInMinutes,
        allowMultipleBreaks: enableTimedBreaksToSave && allowMultipleBreaks,
        enableStrictMode: enableStrictMode,
        enableBlockAppInstallation: enableBlockAppInstallation,
        enableAllowMode: enableAllowMode,
        enableAllowModeDomains: enableAllowModeDomain,
        enableSafariBlocking: enableSafariBlocking,
        enableAdultContentBlocking: enableAdultContentBlocking,
        domains: domains,
        physicalUnblockItems: .some(physicalUnblockItemsToSave),
        schedule: schedule,
        disableBackgroundStops: disableBackgroundStops,
        enableEmergencyUnblock: enableEmergencyUnblock,
        blockingMethod: methodToSave
      )

      DeviceActivityCenterUtil.scheduleTimerActivity(for: updatedProfile)
      return updatedProfile
    }

    let newProfile = try BlockedProfiles.createProfile(
      in: context,
      name: name,
      selection: selectedActivity,
      enableLiveActivity: enableLiveActivity,
      reminderTimeInSeconds: reminderTimeSeconds,
      customReminderMessage: customReminderMessage,
      enableBreaks: enableTimedBreaksToSave,
      breakTimeInMinutes: breakTimeInMinutes,
      allowMultipleBreaks: enableTimedBreaksToSave && allowMultipleBreaks,
      enableStrictMode: enableStrictMode,
      enableBlockAppInstallation: enableBlockAppInstallation,
      enableAllowMode: enableAllowMode,
      enableAllowModeDomains: enableAllowModeDomain,
      enableSafariBlocking: enableSafariBlocking,
      enableAdultContentBlocking: enableAdultContentBlocking,
      domains: domains,
      physicalUnblockItems: physicalUnblockItemsToSave,
      schedule: schedule,
      disableBackgroundStops: disableBackgroundStops,
      enableEmergencyUnblock: enableEmergencyUnblock,
      blockingMethod: methodToSave
    )

    DeviceActivityCenterUtil.scheduleTimerActivity(for: newProfile)
    return newProfile
  }

  private func enforceStrategyBreaksPolicy() {
    guard !selectedStrategyAllowsTimedBreaks else { return }
    enableBreaks = false
    allowMultipleBreaks = false
  }
}
