import Foundation

/// Represents a physical NFC tag or QR code that can unblock a profile
/// Supports having multiple NFC tags and/or QR codes per profile
/// What a scanned code is allowed to do. Stored on the code so deleting one
/// cannot leave an action pointing at something that is gone, but presented
/// the other way round: each action owns the set of codes that satisfy it.
enum PhysicalUnblockRole: String, Codable, CaseIterable, Sendable {
  case start
  case stop
  case breakTime

  var title: String {
    switch self {
    case .start: return "Start"
    case .stop: return "Stop"
    case .breakTime: return "Breaks"
    }
  }
}

struct PhysicalUnblockItem: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var type: PhysicalUnblockType
  var codeValue: String
  /// Absent on codes registered before roles existed, which stood for every
  /// action at the time. An array rather than a Set: SwiftData flattens this
  /// struct into its store, and Set is one of the types that flattening dies
  /// on at runtime.
  var roles: [PhysicalUnblockRole]? = nil

  var effectiveRoles: [PhysicalUnblockRole] {
    roles ?? PhysicalUnblockRole.allCases
  }

  func serves(_ role: PhysicalUnblockRole) -> Bool {
    effectiveRoles.contains(role)
  }

  enum PhysicalUnblockType: String, Codable, CaseIterable, Sendable {
    case nfc = "nfc"
    case qrCode = "qrCode"

    var displayName: String {
      switch self {
      case .nfc: return "NFC Tag"
      case .qrCode: return "QR Code"
      }
    }
  }

  init(
    id: UUID = UUID(),
    name: String,
    type: PhysicalUnblockType,
    codeValue: String,
    roles: [PhysicalUnblockRole]? = nil
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.codeValue = codeValue
    self.roles = roles
  }

  static func resolvedItems(
    physicalUnblockItems: [PhysicalUnblockItem]?,
    legacyNFCTagId: String? = nil,
    legacyQRCodeId: String? = nil
  ) -> [PhysicalUnblockItem]? {
    if let physicalUnblockItems {
      return normalizedItems(physicalUnblockItems)
    }

    var items: [PhysicalUnblockItem] = []

    if let legacyNFCTagId, !legacyNFCTagId.isEmpty {
      items.append(
        PhysicalUnblockItem(
          name: "NFC Tag",
          type: .nfc,
          codeValue: legacyNFCTagId
        )
      )
    }

    if let legacyQRCodeId, !legacyQRCodeId.isEmpty {
      items.append(
        PhysicalUnblockItem(
          name: "QR Code",
          type: .qrCode,
          codeValue: legacyQRCodeId
        )
      )
    }

    return normalizedItems(items)
  }

  static func normalizedItems(_ items: [PhysicalUnblockItem]?) -> [PhysicalUnblockItem]? {
    guard let items else { return nil }

    let normalizedItems = items.compactMap { item -> PhysicalUnblockItem? in
      let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalizedCodeValue = normalizedCodeValue(item.codeValue, type: item.type)

      guard !normalizedCodeValue.isEmpty else { return nil }

      return PhysicalUnblockItem(
        id: item.id,
        name: trimmedName.isEmpty ? item.type.displayName : trimmedName,
        type: item.type,
        codeValue: normalizedCodeValue,
        roles: item.roles
      )
    }

    return normalizedItems.isEmpty ? nil : normalizedItems
  }

  static func normalizedCodeValue(
    _ codeValue: String,
    type: PhysicalUnblockType
  ) -> String {
    let trimmedCodeValue = codeValue.trimmingCharacters(in: .whitespacesAndNewlines)

    guard type == .qrCode,
      var components = URLComponents(string: trimmedCodeValue),
      components.scheme != nil,
      components.host != nil
    else {
      return trimmedCodeValue
    }

    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()

    if components.path == "/" && components.query == nil && components.fragment == nil {
      components.path = ""
    }

    return components.string ?? trimmedCodeValue
  }
}
