import SwiftUI

/// Shown when a profile accepts both kinds of scan for one action: the camera
/// is up and ready for a code, with NFC one tap away.
struct ScanChoiceView: View {
  let qrScanner: AnyView
  let onNFC: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      qrScanner

      Button(action: onNFC) {
        Label("Scan an NFC tag instead", systemImage: "wave.3.right")
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.bordered)
      .padding(.horizontal, 20)
      .padding(.bottom, 16)
    }
  }
}
