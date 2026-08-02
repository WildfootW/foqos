import SwiftUI

/// Asks before a scan ends the whole session, for profiles where a release and
/// a stop cost the same walk to the same tag.
///
/// Without this the release is never worth taking: both actions are one scan,
/// but one buys a few minutes and the other buys the rest of the day. The
/// pause is the point - it is the moment to notice which one is being chosen.
///
/// Confirming swaps this view for whatever actually collects the scan, so the
/// sheet that presented the question also carries the answer.
struct StopConfirmationView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  let profileName: String
  let releaseDescription: String
  let onCancel: () -> Void
  /// Present when the scan needs a view of its own; nil for NFC, where the
  /// system sheet takes over.
  let scannerView: AnyView?
  let onConfirm: () -> Void

  @State private var confirmed = false

  var body: some View {
    if confirmed {
      if let scannerView {
        scannerView
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .onAppear(perform: onConfirm)
      }
    } else {
      confirmation
    }
  }

  private var confirmation: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.largeTitle)
          .foregroundStyle(.orange)

        Text("End \(profileName) completely?")
          .font(.title2)
          .fontWeight(.bold)

        Text(
          "Scanning here stops the session for good. The same scan taken from "
            + "the home screen gives you \(releaseDescription) and leaves the "
            + "profile running."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()

      VStack(spacing: 12) {
        Button(action: onCancel) {
          Text("Keep it running")
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(themeManager.themeColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }

        Button {
          confirmed = true
        } label: {
          Text("Scan to end the session")
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundStyle(.red)
        }
      }
    }
    .padding(24)
  }
}
