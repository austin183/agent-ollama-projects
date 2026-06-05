import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct ImageLibraryManagerTests {

    private var manager: ImageLibraryManager {
        ImageLibraryManager()
    }

    // MARK: - Initial state

    @Test func initialStateIsEmpty() {
        let mgr = manager
        #expect(mgr.images.isEmpty)
        #expect(mgr.customImageOrder.isEmpty)
    }

    // MARK: - Remove image

    @Test func removeImageReturnsRemovedItem() {
        let mgr = manager
        let item = createTestImageItem(filename: "test.jpg")
        mgr.images = [item]

        let result = mgr.removeImage(at: 0)
        #expect(result != nil)
        #expect(result?.item.id == item.id)
        #expect(result?.at == 0)
        #expect(mgr.images.isEmpty)
    }

    @Test func removeImageOutOfBoundsReturnsNil() {
        let mgr = manager
        let result = mgr.removeImage(at: 0)
        #expect(result == nil)
    }

    @Test func removeImageMiddleUpdatesArray() {
        let mgr = manager
        let items = (0..<3).map { i in
            createTestImageItem(filename: "\(i).jpg")
        }
        mgr.images = items

        _ = mgr.removeImage(at: 1)
        #expect(mgr.images.count == 2)
        #expect(mgr.images[0].id == items[0].id)
        #expect(mgr.images[1].id == items[2].id)
    }

    // MARK: - Move images

    @Test func moveImagesUpdatesCustomOrder() {
        let mgr = manager
        mgr.images = [
            createTestImageItem(filename: "a.jpg"),
            createTestImageItem(filename: "b.jpg"),
            createTestImageItem(filename: "c.jpg"),
        ]
        mgr.customImageOrder = [0, 1, 2]
        mgr.moveImages(from: IndexSet([0]), to: 2)
        #expect(mgr.customImageOrder == [1, 2, 0])
    }

    @Test func moveImagesToStart() {
        let mgr = manager
        mgr.images = (0..<5).map { _ in createTestImageItem() }
        mgr.customImageOrder = [0, 1, 2, 3, 4]
        mgr.moveImages(from: IndexSet([3]), to: 0)
        #expect(mgr.customImageOrder == [3, 0, 1, 2, 4])
    }

    @Test func moveImagesToEnd() {
        let mgr = manager
        mgr.images = (0..<5).map { _ in createTestImageItem() }
        mgr.customImageOrder = [0, 1, 2, 3, 4]
        mgr.moveImages(from: IndexSet([0]), to: 4)
        #expect(mgr.customImageOrder == [1, 2, 3, 4, 0])
    }

    @Test func moveImagesNoOpSkipsCustomOrder() {
        let mgr = manager
        mgr.images = (0..<3).map { _ in createTestImageItem() }
        mgr.customImageOrder = [0, 1, 2]
        mgr.moveImages(from: IndexSet([0]), to: 0)
        #expect(mgr.customImageOrder == [0, 1, 2])
    }

    @Test func moveImagesWithEmptyCustomOrderOnlyMovesArray() {
        let mgr = manager
        mgr.images = (0..<3).map { _ in createTestImageItem() }
        mgr.customImageOrder = []
        mgr.moveImages(from: IndexSet([0]), to: 2)
        #expect(mgr.images.count == 3)
        #expect(mgr.customImageOrder.isEmpty)
    }

    @Test func moveImagesMultipleSelection() {
        let mgr = manager
        mgr.images = (0..<5).map { _ in createTestImageItem() }
        mgr.customImageOrder = [0, 1, 2, 3, 4]
        mgr.moveImages(from: IndexSet([1, 2]), to: 4)
        #expect(mgr.images.count == 5)
        #expect(mgr.customImageOrder.count == 5)
    }

    // MARK: - Clear all

    @Test func clearAllResetsState() {
        let mgr = manager
        mgr.images = [
            createTestImageItem(filename: "a.jpg"),
            createTestImageItem(filename: "b.jpg"),
        ]
        mgr.customImageOrder = [0, 1]

        let oldImages = mgr.clearAll()
        #expect(oldImages.count == 2)
        #expect(mgr.images.isEmpty)
        #expect(mgr.customImageOrder.isEmpty)
    }

    @Test func clearAllOnEmptyManager() {
        let mgr = manager
        let oldImages = mgr.clearAll()
        #expect(oldImages.isEmpty)
        #expect(mgr.images.isEmpty)
        #expect(mgr.customImageOrder.isEmpty)
    }
}
