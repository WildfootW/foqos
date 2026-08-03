import SwiftUI

/// The blocking method in the profile editor: every dimension visible, grouped
/// by the question it answers, in the order a session lives through them.
struct BlockingMethodSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section {
      BlockingStartFields(draft: draft, disabled: disabled)
    } header: {
      Text("Start")
    }
    .disabled(disabled)

    Section {
      BlockingBreakFields(draft: draft, disabled: disabled)
    } header: {
      Text("Breaks")
    } footer: {
      Text(breaksFooter)
    }
    .disabled(disabled)

    Section {
      BlockingStopFields(draft: draft, disabled: disabled)
    } header: {
      Text("Stop")
    } footer: {
      Text(stopFooter)
    }
    .disabled(disabled)

    Section {
      BlockingEnforcementFields(draft: draft, disabled: disabled)
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
      BlockingEmergencyFields(draft: draft, disabled: disabled)
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

  private var stopFooter: String {
    guard draft.method.stopAndReleaseShareACredential else {
      return draft.method.autoEnd == .never
        ? "This profile runs until you stop it."
        : draft.method.autoEnd.title + "."
    }
    return "Stopping and taking a break both need a scan, so stopping asks for confirmation first."
  }

  private var breaksFooter: String {
    switch draft.method.interruption {
    case .none:
      return "Nothing lifts the block until the session ends."
    case .timedBreak:
      return "A pool of break time you can spend during the session."
    case .grantByButton:
      return "A button on the block screen opens one app for a while."
    case .grantByScan:
      return "A break costs a trip to one of the codes below."
    }
  }
}
