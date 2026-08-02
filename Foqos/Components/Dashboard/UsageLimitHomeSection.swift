import SwiftUI

/// Home screen card for profiles with a daily usage limit. Shows each
/// profile's current state and offers the NFC/QR scan that grants a short
/// unlock once the daily allowance is used up.
struct UsageLimitHomeSection: View {
  @EnvironmentObject private var themeManager: ThemeManager

  let profiles: [BlockedProfiles]

  @State private var nfcScanner = NFCScannerUtil()
  @State private var qrScanProfile: BlockedProfiles? = nil
  @State private var methodChoiceProfile: BlockedProfiles? = nil
  @State private var alertTitle: String? = nil
  @State private var alertMessage: String = ""
  @State private var refreshToken = Date()

  private let refreshTimer = Timer.publish(
    every: 15, on: .main, in: .common
  ).autoconnect()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionTitle(
        "Daily Limits",
        buttonText: nil,
        buttonAction: nil
      )

      VStack(spacing: 0) {
        ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
          profileRow(for: profile)

          if index < profiles.count - 1 {
            Divider()
          }
        }
      }
      .padding(16)
      .background(CardBackground())
    }
    .onReceive(refreshTimer) { _ in
      refreshToken = Date()
    }
    .confirmationDialog(
      "Scan to unlock",
      isPresented: Binding(
        get: { methodChoiceProfile != nil },
        set: { if !$0 { methodChoiceProfile = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Scan NFC Tag") {
        if let profile = methodChoiceProfile {
          methodChoiceProfile = nil
          scanNFC(for: profile)
        }
      }
      Button("Scan QR Code") {
        if let profile = methodChoiceProfile {
          methodChoiceProfile = nil
          qrScanProfile = profile
        }
      }
      Button("Cancel", role: .cancel) {
        methodChoiceProfile = nil
      }
    }
    .sheet(item: $qrScanProfile) { profile in
      LabeledCodeScannerView(
        heading: "Scan to unlock",
        subtitle:
          "Point your camera at one of \(profile.name)'s unlock QR codes."
      ) { result in
        qrScanProfile = nil
        switch result {
        case .success(let scanResult):
          handleScannedCode(scanResult.string, type: .qrCode, profile: profile)
        case .failure(let error):
          showAlert(title: "Whoops", message: error.localizedDescription)
        }
      }
    }
    .alert(
      alertTitle ?? "",
      isPresented: Binding(
        get: { alertTitle != nil },
        set: { if !$0 { alertTitle = nil } }
      )
    ) {
      Button("OK", role: .cancel) { alertTitle = nil }
    } message: {
      Text(alertMessage)
    }
  }

  @ViewBuilder
  private func profileRow(for profile: BlockedProfiles) -> some View {
    let _ = refreshToken
    let state = rowState(for: profile)

    HStack(spacing: 12) {
      Image(systemName: state.iconName)
        .font(.title3)
        .foregroundStyle(state.iconColor)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(profile.name)
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(state.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if state.showsScanButton {
        Button {
          startUnlockScan(for: profile)
        } label: {
          Label("Scan", systemImage: "wave.3.right.circle.fill")
            .font(.subheadline)
            .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .tint(themeManager.themeColor)
      }
    }
    .padding(.vertical, 10)
  }

  private struct RowState {
    let iconName: String
    let iconColor: Color
    let statusText: String
    let showsScanButton: Bool
  }

  private func rowState(for profile: BlockedProfiles) -> RowState {
    let allowance = profile.method.enforcement.allowanceMinutes ?? 0
    let locked = UsageLimitState.isLockedToday(profileId: profile.id)
    let grantExpiry = UsageLimitState.grantExpiry(profileId: profile.id)

    if locked, let expiry = grantExpiry, expiry > Date() {
      return RowState(
        iconName: "lock.open.fill",
        iconColor: .green,
        statusText: "Unlocked until \(expiry.formatted(date: .omitted, time: .shortened))",
        showsScanButton: true
      )
    }

    if locked {
      return RowState(
        iconName: "lock.fill",
        iconColor: .red,
        statusText: "Daily limit reached — scan to unlock",
        showsScanButton: true
      )
    }

    return RowState(
      iconName: "hourglass",
      iconColor: .secondary,
      statusText: "\(allowance) min allowance, resets with the schedule",
      showsScanButton: false
    )
  }

  private func startUnlockScan(for profile: BlockedProfiles) {
    let hasNFC = profile.hasPhysicalUnblockItem(ofType: .nfc)
    let hasQR = profile.hasPhysicalUnblockItem(ofType: .qrCode)

    switch (hasNFC, hasQR) {
    case (true, true):
      methodChoiceProfile = profile
    case (true, false):
      scanNFC(for: profile)
    case (false, true):
      qrScanProfile = profile
    case (false, false):
      showAlert(
        title: "No unlock items",
        message:
          "Add a Physical Unlock (NFC tag or QR code) to this profile first. "
          + "Edit the profile and use the Physical Unlocks section."
      )
    }
  }

  private func scanNFC(for profile: BlockedProfiles) {
    nfcScanner.onTagScanned = { result in
      let code = result.url ?? result.id
      DispatchQueue.main.async {
        handleScannedCode(code, type: .nfc, profile: profile)
      }
    }
    nfcScanner.onError = { message in
      DispatchQueue.main.async {
        showAlert(title: "Whoops", message: message)
      }
    }
    nfcScanner.scan(profileName: profile.name)
  }

  private func handleScannedCode(
    _ code: String,
    type: PhysicalUnblockItem.PhysicalUnblockType,
    profile: BlockedProfiles
  ) {
    guard profile.canUnblock(withCode: code, type: type) else {
      showAlert(
        title: "Wrong code",
        message: "This \(type.displayName.lowercased()) can't unlock \(profile.name)."
      )
      return
    }

    do {
      let snapshot = BlockedProfiles.getSnapshot(for: profile)
      let expiry = try UsageLimitScheduler.grantTemporaryUnlock(for: snapshot)
      refreshToken = Date()
      let minutes = profile.method.interruption.releaseMinutes ?? 5
      showAlert(
        title: "Unlocked",
        message:
          "\(profile.name) is open for \(minutes) minute\(minutes == 1 ? "" : "s"), "
          + "until \(expiry.formatted(date: .omitted, time: .shortened))."
      )
    } catch {
      showAlert(
        title: "Whoops",
        message: "Couldn't schedule the re-lock: \(error.localizedDescription)"
      )
    }
  }

  private func showAlert(title: String, message: String) {
    alertTitle = title
    alertMessage = message
  }
}
