import SwiftData
import XCTest

@testable import foqos

@MainActor
final class PauseActiveSessionTests: XCTestCase {
  private enum SchedulerError: LocalizedError {
    case unavailable

    var errorDescription: String? {
      return "Device Activity is unavailable"
    }
  }

  override func setUp() {
    super.setUp()
    SharedData.flushActiveSession()
  }

  override func tearDown() {
    SharedData.flushActiveSession()
    super.tearDown()
  }

  func testNFCPauseStrategySchedulesPause() throws {
    let context = try makeContext()
    let profile = try makeActiveSession(
      strategyId: "session-tag",
      context: context
    ).blockedProfile
    var scheduledProfileId: UUID?

    let profileName = try StrategyManager().pauseActiveSessionFromBackground(
      context: context,
      schedulePause: { scheduledProfileId = $0.id }
    )

    XCTAssertEqual(profileName, profile.name)
    XCTAssertEqual(scheduledProfileId, profile.id)
  }

  func testQRPauseStrategySchedulesPause() throws {
    let context = try makeContext()
    let profile = try makeActiveSession(
      strategyId: "session-tag",
      context: context
    ).blockedProfile
    var scheduledProfileId: UUID?

    let profileName = try StrategyManager().pauseActiveSessionFromBackground(
      context: context,
      schedulePause: { scheduledProfileId = $0.id }
    )

    XCTAssertEqual(profileName, profile.name)
    XCTAssertEqual(scheduledProfileId, profile.id)
  }

  func testNoActiveSessionThrows() throws {
    let context = try makeContext()
    var didSchedule = false

    XCTAssertThrowsError(
      try StrategyManager().pauseActiveSessionFromBackground(
        context: context,
        schedulePause: { _ in didSchedule = true }
      )
    ) { error in
      XCTAssertEqual(error as? PauseActiveSessionError, .noActiveSession)
    }
    XCTAssertFalse(didSchedule)
  }

  func testProfilesWithoutReleasesThrow() throws {
    for strategyId in ["session-tag", UUID().uuidString] {
      SharedData.flushActiveSession()
      let context = try makeContext()
      _ = try makeActiveSession(
        strategyId: strategyId,
        includePauseConfiguration: false,
        context: context
      )

      XCTAssertThrowsError(
        try StrategyManager().pauseActiveSessionFromBackground(
          context: context,
          schedulePause: { _ in XCTFail("Pause should not be scheduled") }
        )
      ) { error in
        XCTAssertEqual(
          error as? PauseActiveSessionError,
          .unsupportedStrategy(profileName: "Focus")
        )
      }
    }
  }

  func testAlreadyPausedSessionThrows() throws {
    let context = try makeContext()
    let session = try makeActiveSession(
      strategyId: "session-tag",
      context: context
    )
    session.startPause()
    try context.save()

    XCTAssertThrowsError(
      try StrategyManager().pauseActiveSessionFromBackground(
        context: context,
        schedulePause: { _ in XCTFail("Pause should not be scheduled") }
      )
    ) { error in
      XCTAssertEqual(
        error as? PauseActiveSessionError,
        .alreadyPaused(profileName: "Focus")
      )
    }
  }

  func testActiveBreakThrows() throws {
    let context = try makeContext()
    let session = try makeActiveSession(
      strategyId: "session-tag",
      enableBreaks: true,
      context: context
    )
    session.startBreak()
    try context.save()

    XCTAssertThrowsError(
      try StrategyManager().pauseActiveSessionFromBackground(
        context: context,
        schedulePause: { _ in XCTFail("Pause should not be scheduled") }
      )
    ) { error in
      XCTAssertEqual(
        error as? PauseActiveSessionError,
        .breakActive(profileName: "Focus")
      )
    }
  }

  func testReleaseLengthDefaultsToFifteenMinutes() throws {
    let context = try makeContext()
    let profile = try makeActiveSession(
      strategyId: "session-tag",
      context: context
    ).blockedProfile
    var scheduledProfileId: UUID?

    let profileName = try StrategyManager().pauseActiveSessionFromBackground(
      context: context,
      schedulePause: { scheduledProfileId = $0.id }
    )
    XCTAssertEqual(profileName, profile.name)
    XCTAssertEqual(scheduledProfileId, profile.id)
    XCTAssertEqual(profile.method.interruption.releaseMinutes, 15)
  }

  func testSchedulerFailureThrowsLocalizedError() throws {
    let context = try makeContext()
    _ = try makeActiveSession(
      strategyId: "session-tag",
      context: context
    )

    XCTAssertThrowsError(
      try StrategyManager().pauseActiveSessionFromBackground(
        context: context,
        schedulePause: { _ in throw SchedulerError.unavailable }
      )
    ) { error in
      XCTAssertEqual(
        error as? PauseActiveSessionError,
        .schedulingFailed(
          profileName: "Focus",
          reason: "Device Activity is unavailable"
        )
      )
    }
  }

  private func makeContext() throws -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: BlockedProfileSession.self,
      BlockedProfiles.self,
      configurations: configuration
    )
    return ModelContext(container)
  }

  private func makeActiveSession(
    strategyId: String,
    includePauseConfiguration: Bool = true,
    enableBreaks: Bool = false,
    context: ModelContext
  ) throws -> BlockedProfileSession {
    let profile = BlockedProfiles(
      name: "Focus",
      enableBreaks: enableBreaks,
      blockingMethod: BlockingMethod(
        interruption: includePauseConfiguration
          ? .timedBreak(minutes: 15, allowMultiple: false)
          : .none
      )
    )
    context.insert(profile)

    let session = BlockedProfileSession.createSession(
      in: context,
      withTag: strategyId,
      withProfile: profile
    )
    try context.save()
    return session
  }
}
