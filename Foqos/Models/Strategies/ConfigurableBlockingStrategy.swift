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
    name = BlockingMethodPreset.matching(method)?.name ?? "Custom"
    description = method.summary
    usesNFC = method.usesNFC
    usesQRCode = method.usesQRCode
    hasTimer = method.hasTimer
    hasPauseMode = method.interruption != .none
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

    switch method.start {
    case .manual, .schedule:
      // A scheduled profile can still be started by hand; the schedule just
      // means it also starts on its own.
      begin(context: context, profile: profile, tag: Self.id, forceStart: forceStart ?? false)
      return nil

    case .nfc:
      nfcScanner.onTagScanned = { [weak self] tag in
        guard let self else { return }
        self.begin(
          context: context,
          profile: profile,
          tag: tag.url ?? tag.id,
          forceStart: forceStart ?? false
        )
      }
      nfcScanner.onError = { [weak self] message in
        self?.onErrorMessage?(message)
      }
      nfcScanner.scan(profileName: profile.name)
      return nil

    case .qr:
      return LabeledCodeScannerView(
        heading: "Scan to start",
        subtitle: "Point your camera at the code for \(profile.name)."
      ) { [weak self] result in
        guard let self else { return }
        switch result {
        case .success(let scan):
          self.begin(
            context: context,
            profile: profile,
            tag: scan.string,
            forceStart: forceStart ?? false
          )
        case .failure(let error):
          self.onErrorMessage?(error.localizedDescription)
        }
      }
    }
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

    // When a release and a stop are both one scan of the same tag, ending the
    // session is the strictly better deal and would always win. Make the
    // difference explicit before the scanner opens.
    guard method.stopAndReleaseShareACredential else {
      return openStopScanner(context: context, session: session)
    }

    let minutes = method.interruption.releaseMinutes ?? 5
    return StopConfirmationView(
      profileName: profile.name,
      releaseDescription: "\(minutes) more minute\(minutes == 1 ? "" : "s")",
      onCancel: { StrategyManager.shared.showCustomStrategyView = false },
      // Built now but not shown until the question is answered; a QR scanner is
      // inert until it appears, and an NFC scan only starts from onConfirm.
      scannerView: qrStopScanner(context: context, session: session),
      onConfirm: { [weak self] in
        self?.beginNFCStopScan(context: context, session: session)
      }
    )
  }

  /// Starts whichever stop mechanism the profile uses. Returns a view when the
  /// mechanism needs one, nil when it runs on its own.
  private func openStopScanner(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> (any View)? {
    switch session.blockedProfile.method.stop {
    case .manual, .timer, .schedule:
      // Timer and schedule stops also fire on their own; this is the early exit.
      end(context: context, session: session)
      return nil
    case .nfc:
      beginNFCStopScan(context: context, session: session)
      return nil
    case .qr:
      return qrStopScanner(context: context, session: session)
    }
  }

  private func qrStopScanner(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> AnyView? {
    guard session.blockedProfile.method.stop == .qr else { return nil }

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
    guard session.blockedProfile.method.stop == .nfc else { return }

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

  /// Registered unlock items are the answer whenever the profile has any.
  /// Without them, a session started by scanning still demands the same code
  /// back, which is the only guarantee left.
  private func codeCanStop(
    _ code: String,
    type: PhysicalUnblockItem.PhysicalUnblockType,
    session: BlockedProfileSession
  ) -> Bool {
    let profile = session.blockedProfile

    if profile.hasPhysicalUnblockItem(ofType: type) {
      return profile.canUnblock(withCode: code, type: type)
    }

    if profile.method.start.isScan && !session.forceStarted {
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
