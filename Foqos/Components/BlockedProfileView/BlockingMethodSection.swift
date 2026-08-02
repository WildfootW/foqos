import SwiftUI

/// One place to answer "how does this profile block", replacing a picker of
/// twelve prebuilt strategies. The presets cover what most profiles want;
/// Custom exposes the same choices the presets are made of.
struct BlockingMethodSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  @State private var showingCustom: Bool = false

  var body: some View {
    Section {
      ForEach(BlockingMethodPreset.all) { preset in
        presetRow(preset)
      }

      DisclosureGroup("Custom", isExpanded: $showingCustom) {
        customFields
      }
      .disabled(disabled)

      ForEach(draft.methodValidationIssues, id: \.self) { issue in
        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    } header: {
      Text("Blocking Method")
    } footer: {
      Text(draft.method.summary)
    }
    .onAppear {
      showingCustom = BlockingMethodPreset.matching(draft.method) == nil
    }
  }

  // MARK: - Presets

  private func presetRow(_ preset: BlockingMethodPreset) -> some View {
    let isSelected = draft.method == preset.method

    return Button {
      draft.method = preset.method
      showingCustom = false
    } label: {
      HStack(spacing: 12) {
        Image(systemName: preset.symbolName)
          .font(.title3)
          .frame(width: 28)
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)

        VStack(alignment: .leading, spacing: 2) {
          Text(preset.name)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
          Text(preset.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
        }
      }
      .padding(.vertical, 4)
    }
    .disabled(disabled)
  }

  // MARK: - Custom

  @ViewBuilder
  private var customFields: some View {
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

    Picker("While running", selection: enforcementBinding) {
      Text("Block right away").tag(EnforcementKind.blockImmediately)
      Text("Allow a daily amount").tag(EnforcementKind.usageAllowance)
    }

    if draft.method.enforcement.allowanceMinutes != nil {
      Picker("Daily allowance", selection: allowanceMinutesBinding) {
        ForEach(EnforcementMode.allowanceOptions, id: \.self) {
          Text($0 < 60 ? "\($0) minutes" : "\($0 / 60)h \($0 % 60 == 0 ? "" : "\($0 % 60)m")")
            .tag($0)
        }
      }
    }

    Picker("Releases", selection: interruptionBinding) {
      Text("None").tag(InterruptionKind.none)
      Text("Timed breaks").tag(InterruptionKind.timedBreak)
      Text("Tap to open briefly").tag(InterruptionKind.grantByButton)
      Text("Scan to open briefly").tag(InterruptionKind.grantByScan)
    }

    if draft.method.interruption != .none {
      Picker("Release length", selection: releaseMinutesBinding) {
        ForEach(InterruptionMode.durationOptions, id: \.self) {
          Text("\($0) minute\($0 == 1 ? "" : "s")").tag($0)
        }
      }
    }

    if case .grantByButton = draft.method.interruption {
      Picker("Releases allowed", selection: releaseCountBinding) {
        ForEach(Array(InterruptionMode.countRange), id: \.self) { Text("\($0)").tag($0) }
      }
    }

    if case .grantByScan(_, let maxCount) = draft.method.interruption {
      Toggle("Limit how many", isOn: limitScansBinding)
      if maxCount != nil {
        Picker("Scans allowed", selection: releaseCountBinding) {
          ForEach(Array(InterruptionMode.countRange), id: \.self) { Text("\($0)").tag($0) }
        }
      }
    }

    if case .timedBreak = draft.method.interruption {
      Toggle("Split across several breaks", isOn: allowMultipleBreaksBinding)
    }

    Toggle("Emergency releases", isOn: emergencyEnabledBinding)
    if draft.method.emergency.isEnabled {
      Picker("Per session", selection: emergencyCountBinding) {
        ForEach(1...EmergencyPolicy.countRange.upperBound, id: \.self) {
          Text("\($0)").tag($0)
        }
      }
    }

    if draft.method.stopAndReleaseShareACredential {
      Label(
        "Stopping and releasing both take one scan, so stopping will ask for "
          + "confirmation.",
        systemImage: "info.circle"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
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
