import SwiftData
import SwiftUI

/// The one strategy. Everything the twelve hand-written strategies used to
/// decide by class is read from the profile's `BlockingMethod` instead.
final class ConfigurableBlockingStrategy: BlockingStrategy {
  static var id: String = "ConfigurableBlockingStrategy"

  var name: String = "Blocking Method"
  var description: String = "Start, stop and release rules configured per profile."
  var iconAssetName: String = "Manual"
  var color: Color = .blue
  var pickerCategory: BlockingStrategyPickerCategory = .mostPopular

  var usesNFC: Bool = false
  var usesQRCode: Bool = false
  var hasTimer: Bool = false
  var hasPauseMode: Bool = false
  var startsManually: Bool = true
  var requiresSameCodeToStop: Bool = false
  var allowsTimedBreaks: Bool = true
  var isBeta: Bool = false
  var startViewPresentationDetents: Set<PresentationDetent> = [.medium, .large]

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?

  private let nfcScanner = NFCScannerUtil()
  private let appBlocker = AppBlockerUtil()

  init() {}

  /// Describes a specific profile's method, so views asking a strategy how to
  /// label itself get answers about that profile rather than about the class.
  init(method: BlockingMethod) {
    name = BlockingMethodPreset.matching(method)?.name ?? "Focus Session"
    description = method.summary
    usesNFC = method.usesNFC
    usesQRCode = method.usesQRCode
    hasTimer = method.hasTimer
    // Breaks flow through the break button; the main control always stops.
    // The old pause-labelled main button quietly ended the session, which is
    // the opposite of what its label promised.
    hasPauseMode = false
    startsManually = method.startsManually
    allowsTimedBreaks = {
      if case .timedBreak = method.interruption { return true }
      return method.interruption == .none
    }()

    switch method.enforcement {
    case .usageAllowance:
      iconAssetName = "Manual"
      color = .orange
    case .blockImmediately:
      color = method.usesNFC ? .blue : (method.usesQRCode ? .purple : .green)
    }
  }

  func getIdentifier() -> String { Self.id }

  // MARK: - Start

  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)? {
    let method = profile.method

    // Tapping start satisfies a manual trigger directly; a schedule-only
    // profile has no by-hand path at all, on purpose.
    if method.startsManually || (method.start.contains(.schedule) && !method.startsByScan) {
      guard method.canStartByHand || method.start.contains(.schedule) else {
        onErrorMessage?("This profile has no way to start.")
        return nil
      }
      if method.startsManually {
        begin(context: context, profile: profile, tag: Self.id, forceStart: forceStart ?? false)
        return nil
      }
      onErrorMessage?("This profile starts on its schedule.")
      return nil
    }

    let scanTypes = method.startScanTypes
    if scanTypes.contains(.nfc) && scanTypes.count == 1 {
      beginNFCStartScan(context: context, profile: profile, forceStart: forceStart ?? false)
      return nil
    }
    if scanTypes == [.qrCode] {
      return qrStartScanner(context: context, profile: profile, forceStart: forceStart ?? false)
    }
    if scanTypes.count > 1 {
      // Both kinds accepted: show the camera, offer NFC as the alternative.
      return ScanChoiceView(
        qrScanner: qrStartScanner(
          context: context, profile: profile, forceStart: forceStart ?? false),
        onNFC: { [weak self] in
          self?.beginNFCStartScan(
            context: context, profile: profile, forceStart: forceStart ?? false)
        }
      )
    }

    onErrorMessage?("This profile has no way to start.")
    return nil
  }

  private func beginNFCStartScan(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool
  ) {
    nfcScanner.onTagScanned = { [weak self] tag in
      guard let self else { return }
      let code = tag.url ?? tag.id
      guard profile.accepts(code: code, type: .nfc, for: .start) else {
        self.onErrorMessage?("This NFC tag can't start this profile.")
        return
      }
      self.begin(context: context, profile: profile, tag: code, forceStart: forceStart)
    }
    nfcScanner.onError = { [weak self] message in
      self?.onErrorMessage?(message)
    }
    nfcScanner.scan(profileName: profile.name)
  }

  private func qrStartScanner(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool
  ) -> AnyView {
    AnyView(
      LabeledCodeScannerView(
        heading: "Scan to start",
        subtitle: "Point your camera at the code for \(profile.name)."
      ) { [weak self] result in
        guard let self else { return }
        switch result {
        case .success(let scan):
          guard profile.accepts(code: scan.string, type: .qrCode, for: .start) else {
            self.onErrorMessage?("This code can't start this profile.")
            return
          }
          self.begin(
            context: context, profile: profile, tag: scan.string, forceStart: forceStart)
        case .failure(let error):
          self.onErrorMessage?(error.localizedDescription)
        }
      }
    )
  }

  private func begin(
    context: ModelContext,
    profile: BlockedProfiles,
    tag: String,
    forceStart: Bool
  ) {
    let method = profile.method
    let session = BlockedProfileSession.createSession(
      in: context,
      withTag: tag,
      withProfile: profile,
      forceStart: forceStart
    )

    let snapshot = BlockedProfiles.getSnapshot(for: profile)

    switch method.enforcement {
    case .blockImmediately:
      appBlocker.activateRestrictions(for: snapshot)
    case .usageAllowance:
      // Nothing is blocked yet; the monitor shields the apps once the
      // allowance runs out.
      UsageLimitScheduler.begin(for: snapshot)
    }

    if case .grantByButton(_, let maxCount) = method.interruption {
      SoftUnblockGrantScheduler.stopAll()
      SoftUnblockGrantStore.beginSession(
        sessionId: session.id,
        profileId: profile.id,
        maximumUnblockCount: maxCount,
        allowanceResetIntervalInHours: nil,
        startedAt: session.startTime
      )
    }

    onSessionCreation?(.started(session))
  }

  // MARK: - Stop

  func stopBlocking(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> (any View)? {
    let profile = session.blockedProfile
    let method = profile.method

    if method.stop.contains(.manual) {
      end(context: context, session: session)
      return nil
    }

    let scanTypes = method.stopScanTypes
    if scanTypes.contains(.nfc) && scanTypes.count == 1 {
      beginNFCStopScan(context: context, session: session)
      return nil
    }
    if scanTypes == [.qrCode] {
      return qrStopScanner(context: context, session: session)
    }
    if scanTypes.count > 1 {
      return ScanChoiceView(
        qrScanner: qrStopScanner(context: context, session: session) ?? AnyView(SwiftUI.EmptyView()),
        onNFC: { [weak self] in
          self?.beginNFCStopScan(context: context, session: session)
        }
      )
    }

    // No by-hand stop; the session runs out on its own.
    onErrorMessage?(
      method.autoEnd == .never
        ? "This profile has no way to stop."
        : "This session ends on its own: \(method.autoEnd.title.lowercased())."
    )
    return nil
  }

  private func qrStopScanner(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> AnyView? {
    guard session.blockedProfile.method.stop.contains(.qr) else { return nil }

    return AnyView(
      LabeledCodeScannerView(
        heading: "Scan to stop",
        subtitle: "Point your camera at the code for \(session.blockedProfile.name)."
      ) { [weak self] result in
        guard let self else { return }
        switch result {
        case .success(let scan):
          guard self.codeCanStop(scan.string, type: .qrCode, session: session) else {
            self.onErrorMessage?("This code can't stop this profile.")
            return
          }
          self.end(context: context, session: session)
        case .failure(let error):
          self.onErrorMessage?(error.localizedDescription)
        }
      }
    )
  }

  private func beginNFCStopScan(
    context: ModelContext,
    session: BlockedProfileSession
  ) {
    guard session.blockedProfile.method.stop.contains(.nfc) else { return }

    nfcScanner.onTagScanned = { [weak self] tag in
      guard let self else { return }
      let code = tag.url ?? tag.id
      guard self.codeCanStop(code, type: .nfc, session: session) else {
        self.onErrorMessage?("This NFC tag can't stop this profile.")
        return
      }
      self.end(context: context, session: session)
    }
    nfcScanner.onError = { [weak self] message in
      self?.onErrorMessage?(message)
    }
    nfcScanner.scan(profileName: session.blockedProfile.name)
  }

  /// Codes registered for stopping are the answer whenever there are any.
  /// Without them, a session started by scanning still demands the same code
  /// back, which is the only guarantee left.
  private func codeCanStop(
    _ code: String,
    type: PhysicalUnblockItem.PhysicalUnblockType,
    session: BlockedProfileSession
  ) -> Bool {
    let profile = session.blockedProfile

    if profile.hasCode(ofType: type, for: .stop) {
      return profile.accepts(code: code, type: type, for: .stop)
    }

    if profile.method.startsByScan && !session.forceStarted {
      return code == session.tag
    }

    return true
  }

  private func end(context: ModelContext, session: BlockedProfileSession) {
    let profile = session.blockedProfile

    SoftUnblockGrantScheduler.stopAll(sessionId: session.id)
    SoftUnblockGrantStore.endSession(sessionId: session.id)
    UsageLimitScheduler.end(profileId: profile.id)

    session.endSession()
    do {
      try context.save()
    } catch {
      onErrorMessage?("Failed to save the completed session.")
    }

    appBlocker.deactivateRestrictions()
    onSessionCreation?(.ended(profile))
  }
}
