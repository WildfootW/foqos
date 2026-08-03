import SwiftUI

/// The five choices that make up a blocking method, laid out as themselves.
///
/// They used to be twelve prebuilt strategies behind one picker; naming each
/// question and showing them all is the point of the change, so none of this
/// hides behind a disclosure. Presets still exist, but as starting points in
/// the guided creation flow rather than as the vocabulary here.
struct BlockingMethodSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section {
      Picker("Start", selection: startBinding) {
        ForEach(StartTrigger.allCases) { Text($0.title).tag($0) }
      }

      Picker("Stop", selection: stopBinding) {
        ForEach(StopTrigger.allCases) { Text($0.title).tag($0) }
      }

      if draft.method.stop == .timer {
        Picker("Length", selection: timerMinutesBinding) {
          ForEach([5, 10, 15, 25, 30, 45, 60, 90], id: \.self) {
            Text("\($0) minutes").tag($0)
          }
        }

        Toggle("Hide stop until it ends", isOn: hideStopBinding)
      }
    } header: {
      Text("Start & Stop")
    } footer: {
      Text(startStopFooter)
    }
    .disabled(disabled)

    Section {
      Picker("Apps are", selection: enforcementBinding) {
        Text("Blocked right away").tag(EnforcementKind.blockImmediately)
        Text("Usable up to a limit").tag(EnforcementKind.usageAllowance)
      }
      .pickerStyle(.inline)
      .labelsHidden()

      if draft.method.enforcement.allowanceMinutes != nil {
        Picker("Allowance", selection: allowanceMinutesBinding) {
          ForEach(EnforcementMode.allowanceOptions, id: \.self) {
            Text(allowanceLabel($0)).tag($0)
          }
        }
      }
    } header: {
      Text("While Running")
    } footer: {
      Text(
        draft.method.enforcement.allowanceMinutes == nil
          ? "Everything selected is blocked for the whole session."
          : "The apps stay usable until the allowance runs out, then they lock. "
            + "It refills when the window starts again."
      )
    }
    .disabled(disabled)

    Section {
      Picker("Releases", selection: interruptionBinding) {
        Text("None").tag(InterruptionKind.none)
        Text("Timed breaks").tag(InterruptionKind.timedBreak)
        Text("Tap to open briefly").tag(InterruptionKind.grantByButton)
        Text("Scan to open briefly").tag(InterruptionKind.grantByScan)
      }
      .pickerStyle(.inline)
      .labelsHidden()

      if draft.method.interruption != .none {
        Picker("Length", selection: releaseMinutesBinding) {
          ForEach(InterruptionMode.durationOptions, id: \.self) {
            Text("\($0) minute\($0 == 1 ? "" : "s")").tag($0)
          }
        }
      }

      if case .grantByButton = draft.method.interruption {
        Picker("How many", selection: releaseCountBinding) {
          ForEach(Array(InterruptionMode.countRange), id: \.self) { Text("\($0)").tag($0) }
        }
      }

      if case .grantByScan(_, let maxCount) = draft.method.interruption {
        Toggle("Limit how many", isOn: limitScansBinding)
        if maxCount != nil {
          Picker("How many", selection: releaseCountBinding) {
            ForEach(Array(InterruptionMode.countRange), id: \.self) { Text("\($0)").tag($0) }
          }
        }
      }

      if case .timedBreak = draft.method.interruption {
        Toggle("Split across several breaks", isOn: allowMultipleBreaksBinding)
      }
    } header: {
      Text("Releases")
    } footer: {
      Text(releasesFooter)
    }
    .disabled(disabled)

    Section {
      Toggle("Emergency releases", isOn: emergencyEnabledBinding)

      if draft.method.emergency.isEnabled {
        Picker("Per session", selection: emergencyCountBinding) {
          ForEach(1...EmergencyPolicy.countRange.upperBound, id: \.self) {
            Text("\($0)").tag($0)
          }
        }
      }
    } header: {
      Text("Emergency")
    } footer: {
      Text("Breaking the glass ends the session outright. The count refills when you start again.")
    }
    .disabled(disabled)

    if !draft.methodValidationIssues.isEmpty {
      Section {
        ForEach(draft.methodValidationIssues, id: \.self) { issue in
          Label(issue.message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
    }
  }

  private var startStopFooter: String {
    guard draft.method.stopAndReleaseShareACredential else {
      return draft.method.summary
    }
    return "Stopping and releasing both take one scan, so stopping asks for confirmation first."
  }

  private var releasesFooter: String {
    switch draft.method.interruption {
    case .none:
      return "Nothing lifts the block until the session ends."
    case .timedBreak:
      return "A pool of break time you can spend during the session."
    case .grantByButton:
      return "A button on the block screen opens one app for a while."
    case .grantByScan:
      return "Opening an app costs a trip to one of this profile's Physical Unlocks."
    }
  }

  private func allowanceLabel(_ minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes) minutes" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours) hour\(hours == 1 ? "" : "s")" : "\(hours)h \(rest)m"
  }

  // MARK: - Bindings

  private enum EnforcementKind: Hashable { case blockImmediately, usageAllowance }
  private enum InterruptionKind: Hashable {
    case none, timedBreak, grantByButton, grantByScan
  }

  private func binding<Value>(
    _ keyPath: WritableKeyPath<BlockingMethod, Value>
  ) -> Binding<Value> {
    Binding(
      get: { draft.method[keyPath: keyPath] },
      set: { draft.method[keyPath: keyPath] = $0 }
    )
  }

  private var startBinding: Binding<StartTrigger> { binding(\.start) }
  private var stopBinding: Binding<StopTrigger> { binding(\.stop) }
  private var timerMinutesBinding: Binding<Int> { binding(\.stopTimerMinutes) }
  private var hideStopBinding: Binding<Bool> { binding(\.hideStopUntilTimerEnds) }

  private var enforcementBinding: Binding<EnforcementKind> {
    Binding(
      get: { draft.method.enforcement.allowanceMinutes == nil ? .blockImmediately : .usageAllowance },
      set: { kind in
        draft.method.enforcement =
          kind == .blockImmediately ? .blockImmediately : .usageAllowance(minutes: 30)
      }
    )
  }

  private var allowanceMinutesBinding: Binding<Int> {
    Binding(
      get: { draft.method.enforcement.allowanceMinutes ?? 30 },
      set: { draft.method.enforcement = .usageAllowance(minutes: $0) }
    )
  }

  private var interruptionBinding: Binding<InterruptionKind> {
    Binding(
      get: {
        switch draft.method.interruption {
        case .none: return .none
        case .timedBreak: return .timedBreak
        case .grantByButton: return .grantByButton
        case .grantByScan: return .grantByScan
        }
      },
      set: { kind in
        let minutes = draft.method.interruption.releaseMinutes ?? 5
        switch kind {
        case .none:
          draft.method.interruption = .none
        case .timedBreak:
          draft.method.interruption = .timedBreak(minutes: 15, allowMultiple: false)
        case .grantByButton:
          draft.method.interruption = .grantByButton(minutes: minutes, maxCount: 3)
        case .grantByScan:
          draft.method.interruption = .grantByScan(minutes: minutes, maxCount: nil)
        }
      }
    )
  }

  private var releaseMinutesBinding: Binding<Int> {
    Binding(
      get: { draft.method.interruption.releaseMinutes ?? 5 },
      set: { minutes in
        switch draft.method.interruption {
        case .none:
          break
        case .timedBreak(_, let allowMultiple):
          draft.method.interruption = .timedBreak(minutes: minutes, allowMultiple: allowMultiple)
        case .grantByButton(_, let maxCount):
          draft.method.interruption = .grantByButton(minutes: minutes, maxCount: maxCount)
        case .grantByScan(_, let maxCount):
          draft.method.interruption = .grantByScan(minutes: minutes, maxCount: maxCount)
        }
      }
    )
  }

  private var releaseCountBinding: Binding<Int> {
    Binding(
      get: {
        switch draft.method.interruption {
        case .grantByButton(_, let maxCount): return maxCount
        case .grantByScan(_, let maxCount): return maxCount ?? 3
        default: return 3
        }
      },
      set: { count in
        let minutes = draft.method.interruption.releaseMinutes ?? 5
        switch draft.method.interruption {
        case .grantByButton:
          draft.method.interruption = .grantByButton(minutes: minutes, maxCount: count)
        case .grantByScan:
          draft.method.interruption = .grantByScan(minutes: minutes, maxCount: count)
        default:
          break
        }
      }
    )
  }

  private var limitScansBinding: Binding<Bool> {
    Binding(
      get: {
        if case .grantByScan(_, let maxCount) = draft.method.interruption { return maxCount != nil }
        return false
      },
      set: { isLimited in
        let minutes = draft.method.interruption.releaseMinutes ?? 5
        draft.method.interruption = .grantByScan(
          minutes: minutes, maxCount: isLimited ? 3 : nil)
      }
    )
  }

  private var allowMultipleBreaksBinding: Binding<Bool> {
    Binding(
      get: {
        if case .timedBreak(_, let allowMultiple) = draft.method.interruption {
          return allowMultiple
        }
        return false
      },
      set: { allowMultiple in
        let minutes = draft.method.interruption.releaseMinutes ?? 15
        draft.method.interruption = .timedBreak(minutes: minutes, allowMultiple: allowMultiple)
      }
    )
  }

  private var emergencyEnabledBinding: Binding<Bool> {
    Binding(
      get: { draft.method.emergency.isEnabled },
      set: { draft.method.emergency.isEnabled = $0 }
    )
  }

  private var emergencyCountBinding: Binding<Int> {
    Binding(
      get: { draft.method.emergency.maxUsesPerSession },
      set: { draft.method.emergency.maxUsesPerSession = $0 }
    )
  }
}
