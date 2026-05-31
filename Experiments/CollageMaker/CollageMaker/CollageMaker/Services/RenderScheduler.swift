import Foundation

/// Serializes CoreGraphics rendering operations to protect NSGraphicsContext.current
/// from concurrent corruption, while yielding non-blockingly to the caller.
actor RenderScheduler {
    private let queue = DispatchQueue(label: "austin183.indie.CollageMaker.render")

    /// Submit rendering work to the serial queue. Returns non-blockingly.
    /// The caller's thread is freed immediately; work executes on the queue.
    func render<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.async {
                let result = work()
                cont.resume(returning: result)
            }
        }
    }
}
