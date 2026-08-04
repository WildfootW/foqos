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
    if draft.method.stop.isEmpty {
      return draft.method.autoEnd == .never
        ? "Nothing can end this session - add a stop method or an automatic end."
        : "No stopping by hand; it only ends on its own."
    }
    return draft.method.autoEnd == .never
      ? "Any checked method stops it. It never ends on its own."
      : "Any checked method stops it early. " + draft.method.autoEnd.title + "."
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
