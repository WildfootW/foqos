import SwiftUI

/// The dimensions of a blocking method, one group per question, so the profile
/// editor and the guided flow ask them the same way - the editor stacking all
/// four, the guide taking one per step.

/// A grid of toggleable chips. Every checked option counts, which is the whole
/// point: a session can accept several ways in or out at once.
struct TriggerChipGrid<Option: Identifiable & Equatable>: View {
  @EnvironmentObject private var themeManager: ThemeManager

  let options: [Option]
  let title: (Option) -> String
  let isOn: (Option) -> Bool
  let toggle: (Option) -> Void

  private let columns = [GridItem(.flexible()), GridItem(.flexible())]

  var body: some View {
    LazyVGrid(columns: columns, spacing: 8) {
      ForEach(options) { option in
        Button {
          toggle(option)
        } label: {
          HStack(spacing: 6) {
            Image(systemName: isOn(option) ? "checkmark.circle.fill" : "circle")
              .font(.subheadline)
            Text(title(option))
              .font(.subheadline)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 9)
          .background(
            RoundedRectangle(cornerRadius: 10)
              .fill(isOn(option) ? themeManager.themeColor.opacity(0.16) : Color.secondary.opacity(0.08))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(
                isOn(option) ? themeManager.themeColor : Color.clear,
                lineWidth: 1.5
              )
          )
          .foregroundStyle(isOn(option) ? themeManager.themeColor : Color.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 2)
  }
}

// MARK: - Start

struct BlockingStartFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool = false

  @State private var showingSchedulePicker = false

  var body: some View {
    TriggerChipGrid(
      options: StartTrigger.allCases,
      title: \.chipTitle,
      isOn: { draft.method.start.contains($0) },
      toggle: { draft.toggleStart($0) }
    )

    if !draft.method.startScanTypes.isEmpty {
      ScanCodeListView(
        items: $draft.physicalUnblockItems,
        role: .start,
        allowedTypes: draft.method.startScanTypes,
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
    TriggerChipGrid(
      options: StopTrigger.allCases,
      title: \.chipTitle,
      isOn: { draft.method.stop.contains($0) },
      toggle: { draft.toggleStop($0) }
    )

    if !draft.method.stopScanTypes.isEmpty {
      ScanCodeListView(
        items: $draft.physicalUnblockItems,
        role: .stop,
        allowedTypes: draft.method.stopScanTypes,
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

    if draft.method.autoEnd == .whenScheduleEnds && !draft.method.start.contains(.schedule) {
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

extension StartTrigger {
  var chipTitle: String {
    switch self {
    case .manual: return "Tap"
    case .nfc: return "NFC tag"
    case .qr: return "QR code"
    case .schedule: return "Schedule"
    }
  }
}

extension StopTrigger {
  var chipTitle: String {
    switch self {
    case .manual: return "Tap"
    case .nfc: return "NFC tag"
    case .qr: return "QR code"
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
