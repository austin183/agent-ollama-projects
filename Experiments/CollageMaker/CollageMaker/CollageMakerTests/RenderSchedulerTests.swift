import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

// Thread-safe array for collecting results from synchronous closures on dispatch queues
final class ThreadSafeArray<Element: Sendable>: @unchecked Sendable {
    private var items: [Element] = []
    private let lock = NSLock()

    func append(_ item: Element) {
        lock.lock()
        defer { lock.unlock() }
        items.append(item)
    }

    func getItems() -> [Element] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

@Suite(.serialized) struct RenderSchedulerTests {

    @Test func concurrentRendersComplete() async {
        let scheduler = RenderScheduler()
        let completionCount = await withTaskGroup(of: Int.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let result = await scheduler.render {
                        i
                    }
                    return result
                }
            }

            var count = 0
            for await value in group {
                #expect(value >= 0)
                count += 1
            }
            return count
        }
        #expect(completionCount == 10)
    }

    @Test func rendersExecuteSerially() async {
        let scheduler = RenderScheduler()
        let tracker = ThreadSafeArray<String>()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    await scheduler.render {
                        tracker.append("\(i)-enter")
                        Thread.sleep(forTimeInterval: 0.001)
                        tracker.append("\(i)-exit")
                        return ()
                    }
                }
            }
            for await _ in group {}
        }

        let order = tracker.getItems()

        // Verify serial execution: each pair should be adjacent
        for i in stride(from: 0, to: order.count, by: 2) {
            #expect(order[i].hasSuffix("-enter"))
            #expect(order[i + 1].hasSuffix("-exit"))
            #expect(order[i].prefix(1) == order[i + 1].prefix(1))
        }
    }

    @Test func renderReturnsCorrectValue() async {
        let scheduler = RenderScheduler()
        let value = await scheduler.render { 42 }
        #expect(value == 42)
    }

    @Test func renderWithSendableType() async {
        let scheduler = RenderScheduler()
        let str = await scheduler.render { "hello" }
        #expect(str == "hello")
    }

    @Test func multipleRendersReturnIndependentResults() async {
        let scheduler = RenderScheduler()

        let results = await withTaskGroup(of: Int.self) { group in
            for i in 0..<20 {
                group.addTask {
                    await scheduler.render { i * 2 }
                }
            }

            var collected: [Int] = []
            for await value in group {
                collected.append(value)
            }
            return collected.sorted()
        }

        #expect(results == (0..<20).map { $0 * 2 })
    }

    @Test func schedulerHandlesHighConcurrency() async {
        let scheduler = RenderScheduler()
        let count = await withTaskGroup(of: Int.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await scheduler.render { i }
                }
            }

            var count = 0
            for await _ in group {
                count += 1
            }
            return count
        }
        #expect(count == 50)
    }
}
