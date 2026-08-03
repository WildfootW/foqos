import SwiftUI

/// The dimensions of a blocking method, one group per question, so the profile
/// editor and the guided flow ask them the same way - the editor stacking all
/// four, the guide taking one per step.

// MARK: - Start

struct BlockingStartFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool = false

  @State private var showingSchedulePicker = false

  var body: some View {
    Picker("Start", selection: draft.methodBinding(\.start)) {
      ForEach(StartTrigger.allCases) { Text($0.title).tag($0) }
    }

    if draft.method.start.isScan {
      ScanCodeListView(
        items: $draft.physicalUnblockItems,
        role: .start,
        allowedTypes: [draft.method.start == .nfc ? .nfc : .qrCode],
        disabled: disabled
      )
    }

    if draft.method.needsSchedule {
      BlockedProfileScheduleSelector(
        schedule: draft.schedule,
        buttonAction: { showingSchedulePicker = true },
        disabled: disabled
      )
      .sheet(isPresented: $showingSchedulePicker) {
        SchedulePicker(schedule: $draft.schedule, isPresented: $showingSchedulePicker)
      }
    }
  }
}

// MARK: - Breaks

struct BlockingBreakFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool = false

  var body: some View {
    Picker("Breaks", selection: draft.interruptionKindBinding) {
      Text("None").tag(BlockedProfileDraft.InterruptionKind.none)
      Text("Timed break").tag(BlockedProfileDraft.InterruptionKind.timedBreak)
      Text("Tap for a break").tag(BlockedProfileDraft.InterruptionKind.grantByButton)
      Text("Scan for a break").tag(BlockedProfileDraft.InterruptionKind.grantByScan)
    }
    .pickerStyle(.inline)
    .labelsHidden()

    if draft.method.interruption != .none {
      Picker("Length", selection: draft.releaseMinutesBinding) {
        ForEach(InterruptionMode.durationOptions, id: \.self) {
          Text("\($0) minute\($0 == 1 ? "" : "s")").tag($0)
        }
      }
    }

    if case .grantByButton = draft.method.interruption {
      Picker("How many", selection: draft.releaseCountBinding) {
        ForEach(Array(InterruptionMode.countRange), id: \.self) { Text("\($0)").tag($0) }
      }
    }

    if case .timedBreak = draft.method.interruption {
      Toggle("Split across several breaks", isOn: draft.allowMultipleBreaksBinding)
    }

    if case .grantByScan(_, let maxCount) = draft.method.interruption {
      Toggle("Limit how many", isOn: draft.limitScansBinding)
      if maxCount != nil {
        Picker("How many", selection: draft.releaseCountBinding) {
          ForEach(Array(InterruptionMode.countRange), id: \.self) { Text("\($0)").tag($0) }
        }
      }

      ScanCodeListView(
        items: $draft.physicalUnblockItems,
        role: .breakTime,
        allowedTypes: [.nfc, .qrCode],
        disabled: disabled
      )
    }
  }
}

// MARK: - Stop

struct BlockingStopFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool = false

  @State private var showingSchedulePicker = false

  var body: some View {
    Picker("Stop", selection: draft.methodBinding(\.stop)) {
      ForEach(StopTrigger.allCases) { Text($0.title).tag($0) }
    }

    if draft.method.stop.isScan {
      ScanCodeListView(
        items: $draft.physicalUnblockItems,
        role: .stop,
        allowedTypes: [draft.method.stop == .nfc ? .nfc : .qrCode],
        disabled: disabled
      )
    }

    Picker("Ends on its own", selection: draft.autoEndKindBinding) {
      Text("Never").tag(BlockedProfileDraft.AutoEndKind.never)
      Text("After a set time").tag(BlockedProfileDraft.AutoEndKind.afterMinutes)
      Text("When the schedule ends").tag(BlockedProfileDraft.AutoEndKind.whenScheduleEnds)
    }

    if draft.method.autoEnd.minutes != nil {
      Picker("After", selection: draft.autoEndMinutesBinding) {
        ForEach(AutoEnd.minuteOptions, id: \.self) { Text("\($0) minutes").tag($0) }
      }

      Toggle("Allow stopping early", isOn: draft.methodBinding(\.allowsEarlyStop))
    }

    if draft.method.autoEnd == .whenScheduleEnds && draft.method.start != .schedule {
      BlockedProfileScheduleSelector(
        schedule: draft.schedule,
        buttonAction: { showingSchedulePicker = true },
        disabled: disabled
      )
      .sheet(isPresented: $showingSchedulePicker) {
        SchedulePicker(schedule: $draft.schedule, isPresented: $showingSchedulePicker)
      }
    }
  }
}

// MARK: - While running

struct BlockingEnforcementFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool = false

  var body: some View {
    Picker("Apps are", selection: draft.enforcementKindBinding) {
      Text("Blocked right away").tag(BlockedProfileDraft.EnforcementKind.blockImmediately)
      Text("Usable up to a limit").tag(BlockedProfileDraft.EnforcementKind.usageAllowance)
    }
    .pickerStyle(.inline)
    .labelsHidden()

    if draft.method.enforcement.allowanceMinutes != nil {
      Picker("Allowance", selection: draft.allowanceMinutesBinding) {
        ForEach(EnforcementMode.allowanceOptions, id: \.self) {
          Text(allowanceLabel($0)).tag($0)
        }
      }
    }
  }

  private func allowanceLabel(_ minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes) minutes" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours) hour\(hours == 1 ? "" : "s")" : "\(hours)h \(rest)m"
  }
}

// MARK: - Emergency

struct BlockingEmergencyFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool = false

  var body: some View {
    Toggle("Emergency releases", isOn: draft.emergencyEnabledBinding)

    if draft.method.emergency.isEnabled {
      Picker("Per session", selection: draft.emergencyCountBinding) {
        ForEach(1...EmergencyPolicy.countRange.upperBound, id: \.self) {
          Text("\($0)").tag($0)
        }
      }
    }
  }
}
