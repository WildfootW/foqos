import FamilyControls
import SwiftData
import SwiftUI

private enum GuidedProfileStep: Int, CaseIterable, Identifiable {
  case apps
  case strategy
  case start
  case breaks
  case stop
  case whileRunning
  case strictSafeguards
  case sessionSafeguards
  case notifications
  case review

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .apps: return "Apps"
    case .strategy: return "Strategy"
    case .start: return "Start"
    case .breaks: return "Breaks"
    case .stop: return "Stop"
    case .whileRunning: return "Running"
    case .strictSafeguards: return "Protection"
    case .sessionSafeguards: return "Session"
    case .notifications: return "Notifications"
    case .review: return "Review"
    }
  }

  var introTitle: String {
    switch self {
    case .apps: return "Choose what to block"
    case .strategy: return "Pick a starting point"
    case .start: return "How does it start?"
    case .breaks: return "Can you take a break?"
    case .stop: return "How does it end?"
    case .whileRunning: return "What happens while it runs?"
    case .strictSafeguards: return "Choose session protection"
    case .sessionSafeguards: return "Choose session controls"
    case .notifications: return "Set notifications"
    case .review: return "Name it and review"
    }
  }

  var introDescription: String {
    switch self {
    case .apps:
      return "Pick the apps and websites this profile covers. They share one set of rules."
    case .strategy:
      return "These fill in everything at once. Adjust any of it in the next few steps."
    case .start:
      return "A session can begin with a tap, a scan, or on a schedule."
    case .breaks:
      return "Decide whether the block can lift for a few minutes without ending the session."
    case .stop:
      return "Decide how you get out, and whether it ends on its own."
    case .whileRunning:
      return "Block everything from the start, or allow a daily amount before locking."
    case .strictSafeguards:
      return "Stop apps being deleted or installed while a session runs."
    case .sessionSafeguards:
      return "Control what can end a session from outside the app."
    case .notifications:
      return "Show progress on the Lock Screen and get reminders."
    case .review:
      return "A name is filled in for you. Change it if you like."
    }
  }
}


struct GuidedBlockedProfileCreationView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var themeManager: ThemeManager

  let onBackFromFirst: (() -> Void)?

  @StateObject private var draft = BlockedProfileDraft()

  @State private var currentStep: GuidedProfileStep = .apps
  @State private var showingActivityPicker = false
  @State private var showingDomainPicker = false
  @State private var alertIdentifier: AlertIdentifier?
  @State private var navigationDirection: CGFloat = 1

  private let steps = GuidedProfileStep.allCases

  private var currentStepIndex: Int {
    return steps.firstIndex(of: currentStep) ?? 0
  }

  private var isFirstStep: Bool {
    return currentStepIndex == 0
  }

  private var isLastStep: Bool {
    return currentStepIndex == steps.count - 1
  }

  private var canContinue: Bool {
    return currentStep != .review || draft.isValid
  }

  private var stepAnimation: Animation {
    .spring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.04)
  }

  private var stepTransition: AnyTransition {
    let insertionEdge: Edge = navigationDirection > 0 ? .bottom : .top
    let removalEdge: Edge = navigationDirection > 0 ? .top : .bottom

    return .asymmetric(
      insertion: .move(edge: insertionEdge)
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0.985, anchor: .top)),
      removal: .move(edge: removalEdge)
        .combined(with: .opacity)
    )
  }

  init(onBackFromFirst: (() -> Void)? = nil) {
    self.onBackFromFirst = onBackFromFirst
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            stepIntroHeader
              .id("header-\(currentStep.id)")
              .transition(stepTransition)

            stepContent
              .id("content-\(currentStep.id)")
              .transition(stepTransition)
          }
        }
        .animation(stepAnimation, value: currentStep)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))

        stepControls
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: handleBackAction) {
            Label("Back", systemImage: "chevron.left")
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Cancel")
        }
      }
      .sheet(isPresented: $showingActivityPicker) {
        AppPicker(
          selection: $draft.selectedActivity,
          isPresented: $showingActivityPicker,
          allowMode: draft.enableAllowMode
        )
      }
      .sheet(isPresented: $showingDomainPicker) {
        DomainPicker(
          domains: $draft.domains,
          isPresented: $showingDomainPicker,
          allowMode: draft.enableAllowModeDomain
        )
      }
      .alert(item: $alertIdentifier) { alert in
        Alert(
          title: Text("Error"),
          message: Text(alert.errorMessage ?? "An unknown error occurred"),
          dismissButton: .default(Text("OK"))
        )
      }
    }
  }

  private var stepIntroHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Step \(currentStepIndex + 1) of \(steps.count)")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.primary)
        .padding(.leading, 1)
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.16), value: currentStepIndex)

      Text(currentStepIntroTitle)
        .font(.largeTitle)
        .fontWeight(.bold)
        .foregroundStyle(.primary)
        .contentTransition(.interpolate)

      Text(currentStepIntroDescription)
        .font(.body)
        .foregroundStyle(.secondary)
        .lineSpacing(3)
        .contentTransition(.interpolate)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, 28)
  }

  private var currentStepIntroTitle: String {

    return currentStep.introTitle
  }

  private var currentStepIntroDescription: String {

    return currentStep.introDescription
  }

  @ViewBuilder
  private var stepContent: some View {
    switch currentStep {
    case .apps:
      guidedCard(title: (draft.enableAllowMode ? "Allowed" : "Blocked") + " Apps") {
        BlockedProfileAppsFields(
          draft: draft,
          showingActivityPicker: $showingActivityPicker,
          disabled: false,
          showsSeparators: true
        )

        Divider()

        BlockedProfileDomainsFields(
          draft: draft,
          showingDomainPicker: $showingDomainPicker,
          disabled: false,
          showsSeparators: true
        )
      }

    case .strategy:
      guidedCard(title: "Strategy") {
        ForEach(BlockingMethodPreset.Category.allCases) { category in
          Text(category.title)
            .font(.caption)
            .foregroundStyle(.secondary)

          ForEach(BlockingMethodPreset.inCategory(category)) { preset in
            presetRow(preset)
          }
        }
      }

    case .start:
      guidedCard(title: "Start") {
        BlockingStartFields(draft: draft)
      }

    case .breaks:
      guidedCard(title: "Breaks") {
        BlockingBreakFields(draft: draft)
      }

    case .stop:
      guidedCard(title: "Stop") {
        BlockingStopFields(draft: draft)
      }

    case .whileRunning:
      guidedCard(title: "While Running") {
        BlockingEnforcementFields(draft: draft)
      }

    case .strictSafeguards:
      guidedCard(title: "Session Protection") {
        BlockedProfileStrictSafeguardsFields(
          draft: draft,
          disabled: false,
          showsSeparators: true
        )
      }

    case .sessionSafeguards:
      guidedCard(title: "Stop Options") {
        BlockedProfileSessionSafeguardsFields(
          draft: draft,
          disabled: false,
          showsSeparators: true
        )

        Divider()

        BlockingEmergencyFields(draft: draft)
      }

    case .notifications:
      guidedCard(title: "Notifications") {
        BlockedProfileNotificationsFields(
          draft: draft,
          profile: nil,
          disabled: false,
          showsSeparators: true
        )
      }

    case .review:
      guidedCard(title: "Name") {
        BlockedProfileNameFields(
          draft: draft,
          disabled: false,
          showsFieldLabels: false
        )
        .onAppear {
          if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.name = draft.suggestedName
          }
        }
      }

      guidedCard(title: "Summary") {
        GuidedProfileReviewContent(draft: draft)
      }
    }
  }

  private func presetRow(_ preset: BlockingMethodPreset) -> some View {
    let isSelected = draft.method == preset.method

    return Button {
      draft.method = preset.method
    } label: {
      HStack(spacing: 12) {
        Image(preset.iconAssetName)
          .resizable()
          .scaledToFit()
          .frame(width: 34, height: 34)

        VStack(alignment: .leading, spacing: 2) {
          Text(preset.name)
            .font(.subheadline).fontWeight(.semibold)
            .foregroundStyle(.primary)
          Text(preset.detail)
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(preset.color)
        }
      }
      .padding(.vertical, 6)
    }
  }

  private func guidedCard<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 16) {
        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.vertical, 18)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 28)
  }

  private var stepControls: some View {
    ActionButton(
      title: isLastStep ? "Create Profile" : "Next",
      backgroundColor: themeManager.themeColor,
      isDisabled: !canContinue
    ) {
      handlePrimaryAction()
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 16)
  }

  private func handlePrimaryAction() {
    if isLastStep {
      createProfile()
    } else {
      goNext()
    }
  }

  private func goNext() {
    guard currentStepIndex < steps.count - 1 else { return }
    navigationDirection = 1
    withAnimation(stepAnimation) {
      currentStep = steps[currentStepIndex + 1]
    }
  }

  private func goBack() {
    guard currentStepIndex > 0 else { return }
    navigationDirection = -1
    withAnimation(stepAnimation) {
      currentStep = steps[currentStepIndex - 1]
    }
  }

  private func handleBackAction() {
    if isFirstStep {
      onBackFromFirst?() ?? dismiss()
    } else {
      goBack()
    }
  }

  private func createProfile() {
    do {
      _ = try draft.save(existingProfile: nil, in: modelContext)
      dismiss()
    } catch {
      alertIdentifier = AlertIdentifier(id: .error, errorMessage: error.localizedDescription)
    }
  }
}

private struct GuidedProfileReviewContent: View {
  @ObservedObject var draft: BlockedProfileDraft

  var body: some View {
    VStack(spacing: 0) {
      reviewRow(title: "Name", value: draft.name)
      reviewDivider
      reviewRow(title: "Method", value: draft.method.summary)
      reviewDivider
      reviewRow(
        title: "Apps", value: FamilyActivityUtil.getCountDisplayText(draft.selectedActivity))
      reviewDivider
      reviewRow(title: "Domains", value: domainSummary)
      reviewDivider
      reviewRow(title: "Schedule", value: scheduleSummary)
      reviewDivider
      reviewRow(title: "Breaks", value: breaksSummary)
      reviewDivider
      reviewRow(title: "Safeguards", value: safeguardsSummary)
      reviewDivider
      reviewRow(title: "Notifications", value: notificationsSummary)
    }
  }

  private func reviewRow(title: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      Text(title)
        .font(.body)
        .fontWeight(.medium)
        .foregroundStyle(.primary)
        .frame(width: 118, alignment: .leading)

      Text(value)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.vertical, 12)
  }

  private var reviewDivider: some View {
    Divider()
      .padding(.leading, 118)
  }

  private var domainSummary: String {
    if draft.domains.isEmpty {
      return "No domains selected"
    }

    return "\(draft.domains.count) \(draft.domains.count == 1 ? "domain" : "domains")"
  }

  private var scheduleSummary: String {
    guard draft.method.needsSchedule else { return "Not used" }
    return draft.schedule.isActive ? draft.schedule.summaryText : "Not set"
  }

  private var breaksSummary: String {
    draft.method.interruption.title
  }

  private var safeguardsSummary: String {
    var enabled: [String] = []

    if draft.enableStrictMode {
      enabled.append("App deletion blocked")
    }

    if draft.enableBlockAppInstallation {
      enabled.append("New app installs blocked")
    }

    if draft.disableBackgroundStops {
      enabled.append("Foqos required to stop")
    }

    if !draft.method.emergency.isEnabled {
      enabled.append("Emergency unblock disabled")
    }

    return enabled.isEmpty ? "Default" : enabled.joined(separator: ", ")
  }

  private var notificationsSummary: String {
    var enabled: [String] = []

    if draft.enableLiveActivity {
      enabled.append("Live Activity")
    }

    if draft.enableReminder {
      enabled.append("Reminder")
    }

    return enabled.isEmpty ? "Disabled" : enabled.joined(separator: ", ")
  }
}

#Preview {
  GuidedBlockedProfileCreationView()
    .environmentObject(NFCWriter())
    .environmentObject(StrategyManager())
    .modelContainer(for: BlockedProfiles.self, inMemory: true)
}
