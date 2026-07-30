import FamilyControls
import Foundation
import ManagedSettings

/// Shared (app-group) state for the daily usage limit feature, readable and
/// writable from the main app and the DeviceActivity/Shield extensions.
///
/// Each usage-limited profile gets its own named ManagedSettingsStore so that
/// several profiles can be locked/unlocked independently of each other and of
/// the regular Foqos blocking session (which uses "foqosAppRestrictions").
enum UsageLimitState {
  private static let suite = UserDefaults(
    suiteName: "group.dev.ambitionsoftware.foqos"
  )!

  private static let lockedDayKeyPrefix = "usageLimit.lockedDay."
  private static let grantExpiryKeyPrefix = "usageLimit.grantExpiry."
  private static let configKeyPrefix = "usageLimit.config."
  private static let storeNamePrefix = "foqosUsageLimit_"

  // MARK: - Day key

  static func dayKey(for date: Date = Date()) -> String {
    let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
  }

  // MARK: - Locked state (limit reached today)

  static func isLockedToday(profileId: UUID, at date: Date = Date()) -> Bool {
    suite.string(forKey: lockedDayKeyPrefix + profileId.uuidString) == dayKey(for: date)
  }

  static func setLockedToday(profileId: UUID, at date: Date = Date()) {
    suite.set(dayKey(for: date), forKey: lockedDayKeyPrefix + profileId.uuidString)
  }

  static func clearLock(profileId: UUID) {
    suite.removeObject(forKey: lockedDayKeyPrefix + profileId.uuidString)
  }

  // MARK: - Temporary unlock grant

  static func grantExpiry(profileId: UUID) -> Date? {
    let value = suite.double(forKey: grantExpiryKeyPrefix + profileId.uuidString)
    guard value > 0 else { return nil }
    return Date(timeIntervalSince1970: value)
  }

  static func hasActiveGrant(profileId: UUID, at date: Date = Date()) -> Bool {
    guard let expiry = grantExpiry(profileId: profileId) else { return false }
    return expiry > date
  }

  static func setGrantExpiry(_ expiry: Date, profileId: UUID) {
    suite.set(
      expiry.timeIntervalSince1970,
      forKey: grantExpiryKeyPrefix + profileId.uuidString
    )
  }

  static func clearGrant(profileId: UUID) {
    suite.removeObject(forKey: grantExpiryKeyPrefix + profileId.uuidString)
  }

  // MARK: - Monitoring config fingerprint (used to avoid restart churn)

  static func storedConfigFingerprint(profileId: UUID) -> Data? {
    suite.data(forKey: configKeyPrefix + profileId.uuidString)
  }

  static func setConfigFingerprint(_ fingerprint: Data, profileId: UUID) {
    suite.set(fingerprint, forKey: configKeyPrefix + profileId.uuidString)
  }

  static func clearConfigFingerprint(profileId: UUID) {
    suite.removeObject(forKey: configKeyPrefix + profileId.uuidString)
  }

  // MARK: - Shielding

  private static func store(for profileId: UUID) -> ManagedSettingsStore {
    ManagedSettingsStore(
      named: ManagedSettingsStore.Name(storeNamePrefix + profileId.uuidString)
    )
  }

  static func applyShield(for profile: SharedData.ProfileSnapshot) {
    let selection = profile.selectedActivity
    let store = store(for: profile.id)

    store.shield.applications =
      selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
    store.shield.applicationCategories =
      selection.categoryTokens.isEmpty
      ? nil
      : .specific(selection.categoryTokens)
    store.shield.webDomains =
      selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
  }

  static func clearShield(profileId: UUID) {
    let store = store(for: profileId)
    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomains = nil
    store.shield.webDomainCategories = nil
    store.clearAllSettings()
  }
}
