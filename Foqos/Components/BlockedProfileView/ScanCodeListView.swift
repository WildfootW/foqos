import SwiftUI

/// The codes that satisfy one action, shown directly beneath it.
///
/// A code is stored once and remembers which actions it serves, but nobody has
/// to think about it that way: each action simply owns a list, and a code that
/// appears under two of them is shared by coincidence rather than by being a
/// special kind of code.
struct ScanCodeListView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  @Binding var items: [PhysicalUnblockItem]
  let role: PhysicalUnblockRole
  let allowedTypes: [PhysicalUnblockItem.PhysicalUnblockType]
  var disabled: Bool = false

  @State private var showingQRScanner = false
  @State private var errorMessage: String?
  @State private var renamingItemID: UUID?
  @State private var renameText: String = ""

  private let reader = PhysicalReader()

  private var assigned: [PhysicalUnblockItem] {
    items.filter { $0.serves(role) && allowedTypes.contains($0.type) }
  }

  /// Codes this profile already knows about that this action could also
  /// accept - the raw material for sharing one across two actions. Codes
  /// holding a conflicting role are not offered.
  private var shareable: [PhysicalUnblockItem] {
    items.filter { item in
      !item.serves(role) && allowedTypes.contains(item.type)
        && !item.effectiveRoles.contains(where: { $0.conflicts(with: role) })
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if assigned.isEmpty {
        Text("Any \(typeNoun) works until you add one.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(assigned) { item in
          assignedRow(item)
        }
      }

      HStack(spacing: 12) {
        ForEach(allowedTypes, id: \.self) { type in
          Button {
            add(type: type)
          } label: {
            Label(
              allowedTypes.count == 1 ? "Add" : type.displayName,
              systemImage: type == .nfc ? "wave.3.right" : "qrcode"
            )
            .font(.caption)
          }
          .buttonStyle(.bordered)
          .disabled(disabled)
        }

        if !shareable.isEmpty {
          Menu {
            ForEach(shareable) { item in
              Button(item.name) { grantRole(to: item) }
            }
          } label: {
            Label("Also allow", systemImage: "plus.circle")
              .font(.caption)
          }
          .disabled(disabled)
        }
      }
    }
    .padding(.vertical, 2)
    .sheet(isPresented: $showingQRScanner) {
      LabeledCodeScannerView(
        heading: "Scan to register",
        subtitle: "Point your camera at the code you want to use."
      ) { result in
        showingQRScanner = false
        switch result {
        case .success(let scan):
          register(code: scan.string, type: .qrCode)
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
    .alert(
      "Whoops",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
    .alert("Rename", isPresented: renamingBinding) {
      TextField("Name", text: $renameText)
      Button("Cancel", role: .cancel) { renamingItemID = nil }
      Button("Save") { commitRename() }
    }
  }

  private func assignedRow(_ item: PhysicalUnblockItem) -> some View {
    HStack(spacing: 8) {
      Image(systemName: item.type == .nfc ? "wave.3.right" : "qrcode")
        .font(.caption)
        .foregroundStyle(themeManager.themeColor)

      Text(item.name)
        .font(.subheadline)

      if item.effectiveRoles.count > 1 {
        Text("shared")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.secondary.opacity(0.12))
          .clipShape(Capsule())
      }

      Spacer()

      Menu {
        Button {
          renameText = item.name
          renamingItemID = item.id
        } label: {
          Label("Rename", systemImage: "pencil")
        }
        Button(role: .destructive) {
          revokeRole(from: item)
        } label: {
          Label(
            item.effectiveRoles.count > 1 ? "Remove from \(role.title)" : "Delete",
            systemImage: "trash"
          )
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .foregroundStyle(.secondary)
      }
      .disabled(disabled)
    }
  }

  // MARK: - Editing

  private var typeNoun: String {
    guard allowedTypes.count == 1 else { return "tag or code" }
    return allowedTypes[0] == .nfc ? "NFC tag" : "code"
  }

  private func add(type: PhysicalUnblockItem.PhysicalUnblockType) {
    switch type {
    case .nfc:
      reader.readNFCTag(
        onSuccess: { code in register(code: code, type: .nfc) },
        onFailure: { errorMessage = $0 }
      )
    case .qrCode:
      showingQRScanner = true
    }
  }

  private func register(code: String, type: PhysicalUnblockItem.PhysicalUnblockType) {
    let normalized = PhysicalUnblockItem.normalizedCodeValue(code, type: type)
    guard !normalized.isEmpty else {
      errorMessage = "That scan came back empty."
      return
    }

    // Scanning something already known adds this action to it rather than
    // creating a duplicate entry.
    if let index = items.firstIndex(where: {
      $0.type == type
        && PhysicalUnblockItem.normalizedCodeValue($0.codeValue, type: $0.type) == normalized
    }) {
      if let conflict = items[index].effectiveRoles.first(where: { $0.conflicts(with: role) }) {
        errorMessage =
          "\(items[index].name) already \(conflict == .stop ? "stops" : "takes a break for")"
          + " this profile. One code can't do both, or a scan wouldn't know which you meant."
        return
      }
      if !items[index].serves(role) {
        items[index].roles = items[index].effectiveRoles + [role]
      }
      return
    }

    items.append(
      PhysicalUnblockItem(
        name: defaultName(for: type),
        type: type,
        codeValue: normalized,
        roles: [role]
      )
    )
  }

  private func defaultName(for type: PhysicalUnblockItem.PhysicalUnblockType) -> String {
    let existing = items.filter { $0.type == type }.count
    let base = type == .nfc ? "Tag" : "Code"
    return existing == 0 ? base : "\(base) \(existing + 1)"
  }

  private func grantRole(to item: PhysicalUnblockItem) {
    guard let index = items.firstIndex(where: { $0.id == item.id }),
      !items[index].serves(role)
    else { return }
    items[index].roles = items[index].effectiveRoles + [role]
  }

  private func revokeRole(from item: PhysicalUnblockItem) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    let roles = items[index].effectiveRoles.filter { $0 != role }

    if roles.isEmpty {
      items.remove(at: index)
    } else {
      items[index].roles = roles
    }
  }

  private var renamingBinding: Binding<Bool> {
    Binding(
      get: { renamingItemID != nil },
      set: { if !$0 { renamingItemID = nil } }
    )
  }

  private func commitRename() {
    defer { renamingItemID = nil }
    guard let id = renamingItemID,
      let index = items.firstIndex(where: { $0.id == id })
    else { return }

    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    items[index].name = trimmed
  }
}
