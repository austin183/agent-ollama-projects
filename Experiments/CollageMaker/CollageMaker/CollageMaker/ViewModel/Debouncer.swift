import Foundation

@MainActor
final class Debouncer {
    private var tasks: [String: Task<Void, Never>] = [:]

    func debounce(id: String, delay: Duration, work: @escaping @MainActor () -> Void) {
        tasks[id]?.cancel()
        tasks[id] = Task { [work] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            work()
        }
    }

    func cancel(id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }
}
