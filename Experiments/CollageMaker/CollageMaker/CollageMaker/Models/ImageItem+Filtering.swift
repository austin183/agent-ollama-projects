import Foundation

extension Array where Element == ImageItem {
    func indexed(by query: String) -> [(index: Int, item: ImageItem)] {
        if query.isEmpty {
            return enumerated().map { ($0.offset, $0.element) }
        }
        return enumerated()
            .filter { $0.element.filename.localizedCaseInsensitiveContains(query) }
            .map { ($0.offset, $0.element) }
    }
}
