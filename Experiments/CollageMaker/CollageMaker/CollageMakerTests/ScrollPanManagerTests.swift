import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@Suite struct ScrollPanManagerTests {

    // MARK: - Initial state

    @Test func initialHasNoActivePan() {
        let manager = ScrollPanManager()
        #expect(manager.hasActivePan == false)
        #expect(manager.activePanelId == nil)
        #expect(manager.accumulator == .zero)
    }

    // MARK: - Begin lifecycle

    @Test func beginScrollPanSetsPanelId() {
        let manager = ScrollPanManager()
        let panelId = UUID()

        var beganCropId: UUID?
        manager.beginScrollPan(panelId: panelId) { id in
            beganCropId = id
        }

        #expect(manager.hasActivePan == true)
        #expect(manager.activePanelId == panelId)
        #expect(beganCropId == panelId)
    }

    @Test func beginScrollPanResetsAccumulator() {
        let manager = ScrollPanManager()

        manager.beginScrollPan(panelId: UUID()) { _ in }
        manager.scrollPanDelta(CGSize(width: 10, height: 20), sensitivity: 1) {
        } commit: {}

        manager.beginScrollPan(panelId: UUID()) { _ in }
        #expect(manager.accumulator == .zero)
    }

    // MARK: - Delta accumulation

    @Test func deltaAccumulatesWidth() {
        let manager = ScrollPanManager()
        manager.beginScrollPan(panelId: UUID()) { _ in }

        manager.scrollPanDelta(CGSize(width: 10, height: 0), sensitivity: 1) {
        } commit: {}

        #expect(manager.accumulator.width == 10)
    }

    @Test func deltaAccumulatesHeight() {
        let manager = ScrollPanManager()
        manager.beginScrollPan(panelId: UUID()) { _ in }

        manager.scrollPanDelta(CGSize(width: 0, height: 20), sensitivity: 1) {
        } commit: {}

        #expect(manager.accumulator.height == 20)
    }

    @Test func deltaAppliesSensitivity() {
        let manager = ScrollPanManager()
        manager.beginScrollPan(panelId: UUID()) { _ in }

        manager.scrollPanDelta(CGSize(width: 10, height: 20), sensitivity: 2) {
        } commit: {}

        #expect(manager.accumulator.width == 20)
        #expect(manager.accumulator.height == 40)
    }

    @Test func deltaAccumulatesAcrossCalls() {
        let manager = ScrollPanManager()
        manager.beginScrollPan(panelId: UUID()) { _ in }

        manager.scrollPanDelta(CGSize(width: 10, height: 5), sensitivity: 1) {
        } commit: {}
        manager.scrollPanDelta(CGSize(width: 3, height: 7), sensitivity: 1) {
        } commit: {}

        #expect(manager.accumulator.width == 13)
        #expect(manager.accumulator.height == 12)
    }

    @Test func deltaCallsApplyLive() {
        let manager = ScrollPanManager()
        manager.beginScrollPan(panelId: UUID()) { _ in }

        var applyCalled = false
        manager.scrollPanDelta(CGSize(width: 5, height: 5), sensitivity: 1) {
            applyCalled = true
        } commit: {}

        #expect(applyCalled == true)
    }

    // MARK: - Delta ignored without active pan

    @Test func deltaIgnoredWhenNoActivePan() {
        let manager = ScrollPanManager()

        manager.scrollPanDelta(CGSize(width: 100, height: 100), sensitivity: 1) {
        } commit: {}

        #expect(manager.accumulator == .zero)
    }

    // MARK: - End lifecycle

    @Test func endScrollPanClearsState() {
        let manager = ScrollPanManager()
        let panelId = UUID()
        manager.beginScrollPan(panelId: panelId) { _ in }
        manager.scrollPanDelta(CGSize(width: 10, height: 20), sensitivity: 1) {
        } commit: {}

        manager.endScrollPan()

        #expect(manager.hasActivePan == false)
        #expect(manager.activePanelId == nil)
        #expect(manager.accumulator == .zero)
    }

    // MARK: - Commit scheduling

    @Test func scheduledCommitFires() async throws {
        let manager = ScrollPanManager()
        manager.beginScrollPan(panelId: UUID()) { _ in }

        var commitCalled = false
        manager.scrollPanDelta(CGSize(width: 5, height: 5), sensitivity: 1) {
        } commit: {
            commitCalled = true
        }

        try await Task.sleep(for: .milliseconds(200))
        #expect(commitCalled == true)
    }

    // MARK: - Multiple begin/end cycles

    @Test func multipleCyclesWorkIndependently() {
        let manager = ScrollPanManager()
        let firstId = UUID()
        let secondId = UUID()

        manager.beginScrollPan(panelId: firstId) { _ in }
        manager.scrollPanDelta(CGSize(width: 10, height: 0), sensitivity: 1) {
        } commit: {}
        manager.endScrollPan()

        manager.beginScrollPan(panelId: secondId) { _ in }
        manager.scrollPanDelta(CGSize(width: 0, height: 20), sensitivity: 1) {
        } commit: {}

        #expect(manager.activePanelId == secondId)
        #expect(manager.accumulator.width == 0)
        #expect(manager.accumulator.height == 20)
    }
}
