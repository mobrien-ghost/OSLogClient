//
//  OSLogClientTests.swift
//  
//
//  Created by Michael O'Brien on 26/5/2024.
//

import XCTest
@preconcurrency import OSLog
@testable import OSLogClient

final class OSLogClientTests: XCTestCase {

    let subsystem = "com.cheekyghost.OSLogClient.tests"
    let logCategory = "tests"
    let dateStub = Date().addingTimeInterval(-3600)
    let logger = Logger(subsystem: "com.cheekyghost.OSLogClient", category: "unit-tests")
    let pollingInterval: PollingInterval = .custom(1)
    var logStore: OSLogStore!
    var lastProcessedStrategy: UserDefaultsLastProcessedStrategy!
    let lastProcessedDefaultsKey: String = "test-key"
    var logDriverSpy: LogDriverSpy!
    var logDriverSpyTwo: LogDriverSpy!
    var logClient: LogClient!
    var testProcessInfoProvider: TestProcessInfoProvider!

    override func setUp() async throws {
        try await super.setUp()
        logStore = try OSLogStore(scope: .currentProcessIdentifier)
        logDriverSpy = LogDriverSpy(id: "test")
        logDriverSpyTwo = LogDriverSpy(id: "test-two")
        testProcessInfoProvider = TestProcessInfoProvider()
        lastProcessedStrategy = .userDefaults(key: lastProcessedDefaultsKey)
        logClient = LogClient(
            pollingInterval: pollingInterval,
            lastProcessedStrategy: lastProcessedStrategy,
            logStore: logStore,
            logger: logger,
            processInfoEnvironmentProvider: testProcessInfoProvider
        )
        await OSLogClient._client.setLogClient(logClient)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        logClient = nil
        logDriverSpy = nil
        logDriverSpyTwo = nil
    }

    // MARK: - Helpers

    func test_pollingIntervalGetter_willReturnClientValue() async {
        await XCTAssertEqual_async(await OSLogClient.pollingInterval, pollingInterval)
    }

    // MARK: - Tests: Is Polling Helper

    func test_isPolling_true_willReturnClientValue() async {
        // Given
        await logClient.startPolling()

        // Then
        await XCTAssertTrue_async(await OSLogClient.isEnabled)
    }

    func test_isPolling_false_willReturnClientValue() async {
        // Given
        await logClient.stopPolling()

        // Then
        await XCTAssertFalse_async(await OSLogClient.isEnabled)
    }

    // MARK: - Tests: Last Processed Date Helpers

    func test_lastPolledDate_willInvokeUnderlyingClient() async {
        let date = Date().addingTimeInterval(-3600)
        await logClient.lastProcessedStrategy.setLastProcessedDate(date)
        await XCTAssertEqual_async(await OSLogClient.lastProcessedDate?.timeIntervalSince1970, date.timeIntervalSince1970)
    }

    // MARK: - Tests: Should Pause Flag Helper

    func test_shouldPauseIfNoRegisteredDrivers_false_willReturnClientValue() async {
        await logClient.setShouldPauseIfNoRegisteredDrivers(false)
        await XCTAssertFalse_async(await OSLogClient.shouldPauseIfNoRegisteredDrivers)
    }

    func test_shouldPauseIfNoRegisteredDrivers_true_willReturnClientValue() async {
        await logClient.setShouldPauseIfNoRegisteredDrivers(true)
        await XCTAssertTrue_async(await OSLogClient.shouldPauseIfNoRegisteredDrivers)
    }

    func test_setShouldPauseIfNoRegisteredDrivers_true_willSendToUnderlyingClient() async {
        await logClient.setShouldPauseIfNoRegisteredDrivers(false)
        await OSLogClient.setShouldPauseIfNoRegisteredDrivers(true)
        await XCTAssertTrue_async(await logClient.shouldPauseIfNoRegisteredDrivers)
    }

    func test_setShouldPauseIfNoRegisteredDrivers_false_willSendToUnderlyingClient() async {
        await logClient.setShouldPauseIfNoRegisteredDrivers(true)
        await OSLogClient.setShouldPauseIfNoRegisteredDrivers(false)
        await XCTAssertFalse_async(await logClient.shouldPauseIfNoRegisteredDrivers)
    }

    // MARK: - Tests: Is Initialized

    func test_isInitialized_validClient_willReturnTrue() async {
        await OSLogClient._client.setLogClient(logClient)
        await XCTAssertTrue_async(await OSLogClient.isInitialized)
    }

    func test_isInitialized_noClient_willReturnFalse() async {
        await OSLogClient._client.setLogClient(nil)
        await XCTAssertFalse_async(await OSLogClient.isInitialized)
    }

    // MARK: - Tests: Helpers

    func test_startPolling_willInvokeClient() async {
        await logClient.stopPolling()
        await XCTAssertFalse_async(await logClient.isEnabled)
        await OSLogClient.startPolling()
        await XCTAssertTrue_async(await logClient.isEnabled)
    }

    func test_stopPolling_willInvokeClient() async {
        await logClient.startPolling()
        await XCTAssertTrue_async(await logClient.isEnabled)
        await OSLogClient.stopPolling()
        await XCTAssertFalse_async(await logClient.isEnabled)
    }

    // MARK: - Tests: Polling Interval Update

    func test_setPollingInterval_willInvokeClient() async {
        // Given
        await logClient.startPolling()
        await logClient.registerDriver(logDriverSpy)
        await logClient.setShouldPauseIfNoRegisteredDrivers(false)
        let lastClient = logClient

        // When
        await OSLogClient.setPollingInterval(.custom(123))

        // Then
        await XCTAssertFalse_async(await OSLogClient._client.logClient === lastClient)
        await XCTAssertEqual_async(await OSLogClient.pollingInterval, .custom(123))
        await XCTAssertEqual_async(
            await OSLogClient.lastProcessedStrategy as? InMemoryLastProcessedStrategy,
            await lastClient?.lastProcessedStrategy as? InMemoryLastProcessedStrategy
        )
        await XCTAssertEqual_async(
            await OSLogClient.lastProcessedDate?.timeIntervalSince1970,
            await lastClient?.lastProcessedDate?.timeIntervalSince1970
        )
        await XCTAssertEqual_async(await OSLogClient.isEnabled, await lastClient?.isEnabled)
        await XCTAssertEqual_async(await OSLogClient.shouldPauseIfNoRegisteredDrivers, await lastClient?.shouldPauseIfNoRegisteredDrivers)
        await XCTAssertTrue_async(await OSLogClient._client.logClient.logStore === lastClient?.logStore)
        await XCTAssertTrue_async(await OSLogClient._client.logClient.processInfoEnvironmentProvider === lastClient?.processInfoEnvironmentProvider)
    }

    // MARK: - Tests: Polling Immediately

    func test_pollImmediately_nilDate_willInvokeClientWithExpectedValues() async {
        await OSLogClient.pollImmediately(from: nil)
        await XCTAssertEqual_async(await logClient._testPollLatestLogsCallCount, 1)
        await XCTAssertNil_async(await logClient._testPollLatestLogsParametersAtIndex(0)?.date)
    }

    func test_pollImmediately_withDate_willInvokeClientWithExpectedValues() async {
        let date = Date().addingTimeInterval(-3600)
        await OSLogClient.pollImmediately(from: date)
        await XCTAssertEqual_async(await logClient._testPollLatestLogsCallCount, 1)
        await XCTAssertEqual_async(
            await logClient._testPollLatestLogsParametersAtIndex(0)?.date?.timeIntervalSince1970,
            date.timeIntervalSince1970
        )
    }

    // MARK: - Tests: Register Driver/s

    func test_registerDriver_willUpdateClientWithProvidedValues() async {
        print(await logClient.drivers.count)
        await OSLogClient.registerDriver(logDriverSpy)
        await XCTAssertEqual_async(await logClient.drivers.count, 1)
        await XCTAssertTrue_async(await logClient.drivers.contains(logDriverSpy))
    }

    func test_registerDrivers_willUpdateClientWithProvidedValues() async {
        await OSLogClient.registerDrivers([logDriverSpy, logDriverSpyTwo])
        await XCTAssertEqual_async(await logClient.drivers.count, 2)
        await XCTAssertTrue_async(await logClient.drivers.contains(where: { $0 === logDriverSpy }))
        await XCTAssertTrue_async(await logClient.drivers.contains(where: { $0 === logDriverSpyTwo }))
    }

    // MARK: - Tests: DeRegister Driver

    func test_deregisterDriver_willUpdateClientWithProvidedValues() async {
        // Given
        await OSLogClient.registerDriver(logDriverSpy)
        await XCTAssertTrue_async(await logClient.isDriverRegistered(withId: logDriverSpy.id))
        await XCTAssertEqual_async(await logClient.drivers.count, 1)

        // When
        await OSLogClient.deregisterDriver(withId: logDriverSpy.id)

        // Then
        await XCTAssertEqual_async(await logClient.drivers.count, 0)
    }

    // MARK: - Tests: Is Driver Registered

    // Note: This is a soft check as not spying the actual invoked method

    func test_isDriverRegistered_willReturnClientValue() async {
        // Given
        await OSLogClient.registerDriver(logDriverSpy)
        await XCTAssertEqual_async(await logClient.drivers.count, 1)
        await XCTAssertTrue_async(await logClient.drivers[0] === logDriverSpy)

        // Then
        await XCTAssertTrue_async(await OSLogClient.isDriverRegistered(withId: logDriverSpy.id))
        await XCTAssertFalse_async(await OSLogClient.isDriverRegistered(withId: logDriverSpyTwo.id))
        await XCTAssertFalse_async(await OSLogClient.isDriverRegistered(withId: "missing"))
    }
}
