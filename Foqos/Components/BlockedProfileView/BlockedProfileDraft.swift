import FamilyControls
import Foundation
import SwiftData
import SwiftUI

final class BlockedProfileDraft: ObservableObject {
  @Published var name: String
  @Published var enableLiveActivity: Bool
  @Published var enableReminder: Bool
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
  @Published var method: BlockingMethod

  init(profile: BlockedProfiles? = nil) {
    name = profile?.name ?? ""
    selectedActivity = profile?.selectedActivity ?? FamilyActivitySelection()
    enableLiveActivity = profile?.enableLiveActivity ?? false
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

  }

  var isValid: Bool {
    return !name.isEmpty
  }

  /// A name built from what has been chosen, so nobody has to invent one.
  /// App names are unavailable by design - the tokens are opaque outside a
  /// Label - so this counts them instead.
  var suggestedName: String {
    let count = selectedActivity.applicationTokens.count
      + selectedActivity.categoryTokens.count
    let subject = count == 0 ? "Profile" : "\(count) app\(count == 1 ? "" : "s")"

    if let minutes = method.enforcement.allowanceMinutes {
      return "\(subject) · \(minutes) min/day"
    }
    if let preset = BlockingMethodPreset.matching(method) {
      return "\(subject) · \(preset.name)"
    }
    if method.needsSchedule, schedule.isActive {
      return "\(subject) · scheduled"
    }
    return subject
  }

  var methodValidationIssues: [BlockingMethod.ValidationIssue] {
    method.validate(
      hasActiveSchedule: schedule.isActive,
      hasPhysicalUnlockItems: !physicalUnblockItems.isEmpty,
      isAllowMode: enableAllowMode
    )
  }

  // MARK: - Method bindings
  //
  // The enums carry associated values, which pickers cannot select over, so
  // each dimension gets a plain tag type here and rebuilds the case on set.

  enum EnforcementKind: Hashable { case blockImmediately, usageAllowance }
  enum InterruptionKind: Hashable { case none, timedBreak, grantByButton, grantByScan }
  enum AutoEndKind: Hashable { case never, afterMinutes, whenScheduleEnds }

  func methodBinding<Value>(
    _ keyPath: WritableKeyPath<BlockingMethod, Value>
  ) -> Binding<Value> {
    Binding(
      get: { self.method[keyPath: keyPath] },
      set: { self.method[keyPath: keyPath] = $0 }
    )
  }

  var autoEndKindBinding: Binding<AutoEndKind> {
    Binding(
      get: {
        switch self.method.autoEnd {
        case .never: return .never
        case .afterMinutes: return .afterMinutes
        case .whenScheduleEnds: return .whenScheduleEnds
        }
      },
      set: { kind in
        switch kind {
        case .never: self.method.autoEnd = .never
        case .afterMinutes: self.method.autoEnd = .afterMinutes(self.method.autoEnd.minutes ?? 25)
        case .whenScheduleEnds: self.method.autoEnd = .whenScheduleEnds
        }
      }
    )
  }

  var autoEndMinutesBinding: Binding<Int> {
    Binding(
      get: { self.method.autoEnd.minutes ?? 25 },
      set: { self.method.autoEnd = .afterMinutes($0) }
    )
  }

  var enforcementKindBinding: Binding<EnforcementKind> {
    Binding(
      get: { self.method.enforcement.allowanceMinutes == nil ? .blockImmediately : .usageAllowance },
      set: { kind in
        self.method.enforcement =
          kind == .blockImmediately ? .blockImmediately : .usageAllowance(minutes: 30)
      }
    )
  }

  var allowanceMinutesBinding: Binding<Int> {
    Binding(
      get: { self.method.enforcement.allowanceMinutes ?? 30 },
      set: { self.method.enforcement = .usageAllowance(minutes: $0) }
    )
  }

  var interruptionKindBinding: Binding<InterruptionKind> {
    Binding(
      get: {
        switch self.method.interruption {
        case .none: return .none
        case .timedBreak: return .timedBreak
        case .grantByButton: return .grantByButton
        case .grantByScan: return .grantByScan
        }
      },
      set: { kind in
        let minutes = self.method.interruption.releaseMinutes ?? 5
        switch kind {
        case .none: self.method.interruption = .none
        case .timedBreak: self.method.interruption = .timedBreak(minutes: 15, allowMultiple: false)
        case .grantByButton:
          self.method.interruption = .grantByButton(minutes: minutes, maxCount: 3)
        case .grantByScan:
          self.method.interruption = .grantByScan(minutes: minutes, maxCount: nil)
        }
      }
    )
  }

  var releaseMinutesBinding: Binding<Int> {
    Binding(
      get: { self.method.interruption.releaseMinutes ?? 5 },
      set: { minutes in
        switch self.method.interruption {
        case .none: break
        case .timedBreak(_, let allowMultiple):
          self.method.interruption = .timedBreak(minutes: minutes, allowMultiple: allowMultiple)
        case .grantByButton(_, let maxCount):
          self.method.interruption = .grantByButton(minutes: minutes, maxCount: maxCount)
        case .grantByScan(_, let maxCount):
          self.method.interruption = .grantByScan(minutes: minutes, maxCount: maxCount)
        }
      }
    )
  }

  var releaseCountBinding: Binding<Int> {
    Binding(
      get: {
        switch self.method.interruption {
        case .grantByButton(_, let maxCount): return maxCount
        case .grantByScan(_, let maxCount): return maxCount ?? 3
        default: return 3
        }
      },
      set: { count in
        let minutes = self.method.interruption.releaseMinutes ?? 5
        switch self.method.interruption {
        case .grantByButton:
          self.method.interruption = .grantByButton(minutes: minutes, maxCount: count)
        case .grantByScan:
          self.method.interruption = .grantByScan(minutes: minutes, maxCount: count)
        default: break
        }
      }
    )
  }

  var limitScansBinding: Binding<Bool> {
    Binding(
      get: {
        if case .grantByScan(_, let maxCount) = self.method.interruption { return maxCount != nil }
        return false
      },
      set: { isLimited in
        let minutes = self.method.interruption.releaseMinutes ?? 5
        self.method.interruption = .grantByScan(minutes: minutes, maxCount: isLimited ? 3 : nil)
      }
    )
  }

  var allowMultipleBreaksBinding: Binding<Bool> {
    Binding(
      get: {
        if case .timedBreak(_, let allowMultiple) = self.method.interruption { return allowMultiple }
        return false
      },
      set: { allowMultiple in
        let minutes = self.method.interruption.releaseMinutes ?? 15
        self.method.interruption = .timedBreak(minutes: minutes, allowMultiple: allowMultiple)
      }
    )
  }

  var emergencyEnabledBinding: Binding<Bool> {
    Binding(
      get: { self.method.emergency.isEnabled },
      set: { self.method.emergency.isEnabled = $0 }
    )
  }

  var emergencyCountBinding: Binding<Int> {
    Binding(
      get: { self.method.emergency.maxUsesPerSession },
      set: { self.method.emergency.maxUsesPerSession = $0 }
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


}
