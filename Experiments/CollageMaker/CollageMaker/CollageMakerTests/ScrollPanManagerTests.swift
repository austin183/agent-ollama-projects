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
        manager.accumulateDelta(CGSize(width: 10, height: 20), sensitivity: 1)

        manager.beginScrollPan(panelId: UUID()) { _ in }
        #expect(manager.accumulator == .zero)
    }

    // MARK: - Delta accumulation

    @Test func deltaAccumulatesWidth() {
        let manager = ScrollPanManager()
        manager.beginScrollPan(panelId: UUID()) { _ in }

        manager.accumulateDelta(CGSize(width: 10, height: 0), sensitivity: 1)

        #expect(manager.accumulator.width == 10)
    }

    @Test func deltaAccumulatesHeight() {
        let manager = ScrollPanManager()
        manager.beginScrollPan(panelId: UUID()) { _ in }

        manager.accumulateDelta(CGSize(width: 0, height: 20), sensitivity: 1)

        #expect(manager.accumulator.height == 20)
    }

    @Test func deltaAppliesSensitivity() {
        let manager = ScrollPanManager()
        manager.beginScrollPan(panelId: UUID()) { _ in }

        manager.accumulateDelta(CGSize(width: 10, height: 20), sensitivity: 2)

        #expect(manager.accumulator.width == 20)
        #expect(manager.accumulator.height == 40)
    }

    @Test func deltaAccumulatesAcrossCalls() {
        let manager = ScrollPanManager()
        manager.beginScrollPan(panelId: UUID()) { _ in }

        manager.accumulateDelta(CGSize(width: 10, height: 5), sensitivity: 1)
        manager.accumulateDelta(CGSize(width: 3, height: 7), sensitivity: 1)

        #expect(manager.accumulator.width == 13)
        #expect(manager.accumulator.height == 12)
    }

    // MARK: - Delta ignored without active pan

    @Test func deltaIgnoredWhenNoActivePan() {
        let manager = ScrollPanManager()

        manager.accumulateDelta(CGSize(width: 100, height: 100), sensitivity: 1)

        #expect(manager.accumulator == .zero)
    }

    // MARK: - End lifecycle

    @Test func endScrollPanClearsState() {
        let manager = ScrollPanManager()
        let panelId = UUID()
        manager.beginScrollPan(panelId: panelId) { _ in }
        manager.accumulateDelta(CGSize(width: 10, height: 20), sensitivity: 1)

        manager.endScrollPan()

        #expect(manager.hasActivePan == false)
        #expect(manager.activePanelId == nil)
        #expect(manager.accumulator == .zero)
    }

    // MARK: - Multiple begin/end cycles

    // MARK: - Multiple begin/end cycles

    @Test func multipleCyclesWorkIndependently() {
        let manager = ScrollPanManager()
        let firstId = UUID()
        let secondId = UUID()

        manager.beginScrollPan(panelId: firstId) { _ in }
        manager.accumulateDelta(CGSize(width: 10, height: 0), sensitivity: 1)
        manager.endScrollPan()

        manager.beginScrollPan(panelId: secondId) { _ in }
        manager.accumulateDelta(CGSize(width: 0, height: 20), sensitivity: 1)

        #expect(manager.activePanelId == secondId)
        #expect(manager.accumulator.width == 0)
        #expect(manager.accumulator.height == 20)
    }
}
