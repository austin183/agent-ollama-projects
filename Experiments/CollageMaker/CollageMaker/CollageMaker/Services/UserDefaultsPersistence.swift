import AppKit
import Foundation

/// Protocol that abstracts ViewModel persistence so CollageViewModel
/// depends on an interface rather than the concrete UserDefaults implementation.
@MainActor
protocol ViewModelPersistence {
    func save(_ viewModel: CollageViewModel)
    func load() -> PersistenceBundle
}

/// Bundle of persisted values loaded from UserDefaults, used to initialize CollageViewModel.
struct PersistenceBundle {
    var layoutStyle: LayoutStyle
    var titleAttrString: NSAttributedString
    var titleStyle: TitleStyle
    var gutter: CGFloat
    var backgroundColor: NSColor
    var exportQuality: Double
    var backgroundStyle: BackgroundStyle
    var gradientStartColor: NSColor
    var gradientEndColor: NSColor
    var gradientAngle: Double
    var backgroundImagePath: String?
    var backgroundOpacity: Double
    var customImageOrder: [Int]
    var doubleExposureMaskOpacity: CGFloat
    var doubleExposureMaskImagePath: String?
    var diagonalSliceAngle: CGFloat
    var hexagonalSpacing: CGFloat
    var rightDrawerWidth: CGFloat
}

/// Centralized UserDefaults persistence for CollageViewModel.
/// Consolidates all UserDefaults keys and handles type-specific archiving
/// (NSKeyedArchiver for colors/attr strings, JSON for [Int]).
@MainActor
final class UserDefaultsPersistence {

    /// All UserDefaults keys used by the application.
    enum Keys {
        // Persisted ViewModel properties
        static let layoutStyle = "layoutStyle"
        static let titleAttrString = "titleAttrString"
        static let titleStyle = "titleStyle"
        static let gutter = "gutter"
        static let backgroundColor = "backgroundColor"
        static let exportQuality = "exportQuality"
        static let backgroundStyle = "backgroundStyle"
        static let gradientStartColor = "gradientStartColor"
        static let gradientEndColor = "gradientEndColor"
        static let gradientAngle = "gradientAngle"
        static let backgroundOpacity = "backgroundOpacity"
        static let customImageOrder = "customImageOrder"
        static let backgroundImagePath = "backgroundImagePath"
        static let doubleExposureMaskOpacity = "doubleExposureMaskOpacity"
        static let doubleExposureMaskImagePath = "doubleExposureMaskImagePath"
        static let diagonalSliceAngle = "diagonalSliceAngle"
        static let hexagonalSpacing = "hexagonalSpacing"
        static let rightDrawerWidth = "rightDrawerWidth"

        // Export
        static let defaultExportFolder = "defaultExportFolder"

        // Legacy (migration only)
        static let title = "title"
        static let defaultTitle = "defaultTitle"
        static let defaultFontFamily = "defaultFontFamily"
        static let defaultFontSize = "defaultFontSize"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Save

    /// Persists all 13 ViewModel properties to UserDefaults.
    func save(_ viewModel: CollageViewModel) {
        defaults.set(viewModel.layoutStyle.rawValue, forKey: Keys.layoutStyle)
        saveTitleAttrString(viewModel.titleAttrString)
        if let data = try? JSONEncoder().encode(viewModel.titleStyle) {
            defaults.set(data, forKey: Keys.titleStyle)
        }
        defaults.set(Double(viewModel.gutter), forKey: Keys.gutter)
        saveColor(viewModel.backgroundColor, key: Keys.backgroundColor)
        defaults.set(viewModel.exportQuality, forKey: Keys.exportQuality)
        defaults.set(viewModel.backgroundStyle.rawValue, forKey: Keys.backgroundStyle)
        saveColor(viewModel.gradientStartColor, key: Keys.gradientStartColor)
        saveColor(viewModel.gradientEndColor, key: Keys.gradientEndColor)
        defaults.set(viewModel.gradientAngle, forKey: Keys.gradientAngle)
        defaults.set(viewModel.backgroundOpacity, forKey: Keys.backgroundOpacity)
        saveCustomImageOrder(viewModel.customImageOrder)
        defaults.set(Double(viewModel.doubleExposureMaskOpacity), forKey: Keys.doubleExposureMaskOpacity)
        defaults.set(Double(viewModel.diagonalSliceAngle), forKey: Keys.diagonalSliceAngle)
        defaults.set(Double(viewModel.hexagonalSpacing), forKey: Keys.hexagonalSpacing)
        defaults.set(Double(viewModel.rightDrawerWidth), forKey: Keys.rightDrawerWidth)

        if let path = viewModel.backgroundImagePath {
            defaults.set(path, forKey: Keys.backgroundImagePath)
        } else {
            defaults.removeObject(forKey: Keys.backgroundImagePath)
        }

        if let path = viewModel.doubleExposureMaskImagePath {
            defaults.set(path, forKey: Keys.doubleExposureMaskImagePath)
        } else {
            defaults.removeObject(forKey: Keys.doubleExposureMaskImagePath)
        }
    }

    // MARK: - Load

    /// Loads all persisted values from UserDefaults, returning defaults for missing keys.
    func load() -> PersistenceBundle {
        let layoutStyle = LayoutStyle.migrate(
            rawValue: defaults.string(forKey: Keys.layoutStyle)
        )

        let titleAttrString = loadTitleAttrString()
        let titleStyle: TitleStyle
        if let data = defaults.data(forKey: Keys.titleStyle),
           let decoded = try? JSONDecoder().decode(TitleStyle.self, from: data) {
            titleStyle = decoded
        } else {
            titleStyle = .defaultStyle()
        }
        let gutter = CGFloat(defaults.double(forKey: Keys.gutter))
        let backgroundColor = loadColor(key: Keys.backgroundColor, default: .black)
        let exportQuality: Double
        if defaults.object(forKey: Keys.exportQuality) != nil {
            exportQuality = defaults.double(forKey: Keys.exportQuality)
        } else {
            exportQuality = 0.92
        }
        let backgroundStyle = BackgroundStyle(
            rawValue: defaults.string(forKey: Keys.backgroundStyle) ?? "solid"
        ) ?? .solid
        let gradientStartColor = loadColor(key: Keys.gradientStartColor, default: .black)
        let gradientEndColor = loadColor(key: Keys.gradientEndColor, default: .darkGray)
        let gradientAngle = defaults.double(forKey: Keys.gradientAngle)
        let backgroundImagePath = loadBackgroundImagePath()
        let backgroundOpacity = loadBackgroundOpacity()
        let customImageOrder = loadCustomImageOrder()
        let doubleExposureMaskOpacity = CGFloat(defaults.double(forKey: Keys.doubleExposureMaskOpacity))
        let doubleExposureMaskImagePath = loadDoubleExposureMaskImagePath()
        let diagonalSliceAngle = CGFloat(defaults.double(forKey: Keys.diagonalSliceAngle))
        let hexagonalSpacing = CGFloat(defaults.double(forKey: Keys.hexagonalSpacing))
        let rightDrawerWidth: CGFloat
        if defaults.object(forKey: Keys.rightDrawerWidth) != nil {
            rightDrawerWidth = CGFloat(defaults.double(forKey: Keys.rightDrawerWidth))
        } else {
            rightDrawerWidth = 300
        }

        return PersistenceBundle(
            layoutStyle: layoutStyle,
            titleAttrString: titleAttrString,
            titleStyle: titleStyle,
            gutter: gutter,
            backgroundColor: backgroundColor,
            exportQuality: exportQuality,
            backgroundStyle: backgroundStyle,
            gradientStartColor: gradientStartColor,
            gradientEndColor: gradientEndColor,
            gradientAngle: gradientAngle,
            backgroundImagePath: backgroundImagePath,
            backgroundOpacity: backgroundOpacity,
            customImageOrder: customImageOrder,
            doubleExposureMaskOpacity: doubleExposureMaskOpacity,
            doubleExposureMaskImagePath: doubleExposureMaskImagePath,
            diagonalSliceAngle: diagonalSliceAngle,
            hexagonalSpacing: hexagonalSpacing,
            rightDrawerWidth: rightDrawerWidth
        )
    }

    // MARK: - Color Helpers

    private func saveColor(_ color: NSColor, key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            defaults.set(data, forKey: key)
        }
    }

    private func loadColor(key: String, default def: NSColor) -> NSColor {
        if let data = defaults.data(forKey: key),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return def
    }

    // MARK: - Title Attr String

    private func saveTitleAttrString(_ attr: NSAttributedString) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: attr, requiringSecureCoding: false) {
            defaults.set(data, forKey: Keys.titleAttrString)
        }
    }

    private func loadTitleAttrString() -> NSAttributedString {
        // Primary: archived NSAttributedString
        if let data = defaults.data(forKey: Keys.titleAttrString),
           let attr = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
            return attr
        }
        // Legacy migration: plain string
        if let oldTitle = defaults.string(forKey: Keys.title), !oldTitle.isEmpty {
            return NSAttributedString(string: oldTitle)
        }
        // Legacy migration: default title + font
        if let defaultTitle = defaults.string(forKey: Keys.defaultTitle), !defaultTitle.isEmpty {
            let fontFamily = defaults.string(forKey: Keys.defaultFontFamily) ?? ""
            let fontSize = defaults.double(forKey: Keys.defaultFontSize)
            let font: NSFont
            if !fontFamily.isEmpty, let f = NSFont(name: fontFamily, size: fontSize) {
                font = f
            } else {
                font = NSFont.boldSystemFont(ofSize: fontSize)
            }
            return NSAttributedString(string: defaultTitle, attributes: [.font: font])
        }
        return NSAttributedString(string: "")
    }

    // MARK: - Custom Image Order

    private func saveCustomImageOrder(_ order: [Int]) {
        if let data = try? JSONEncoder().encode(order) {
            defaults.set(data, forKey: Keys.customImageOrder)
        }
    }

    private func loadCustomImageOrder() -> [Int] {
        if let data = defaults.data(forKey: Keys.customImageOrder),
           let order = try? JSONDecoder().decode([Int].self, from: data) {
            return order
        }
        return []
    }

    // MARK: - Background Image

    private func loadBackgroundImagePath() -> String? {
        guard let path = defaults.string(forKey: Keys.backgroundImagePath),
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    // MARK: - Double Exposure Mask Image

    private func loadDoubleExposureMaskImagePath() -> String? {
        guard let path = defaults.string(forKey: Keys.doubleExposureMaskImagePath),
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    // MARK: - Background Opacity

    private func loadBackgroundOpacity() -> Double {
        if defaults.object(forKey: Keys.backgroundOpacity) != nil {
            return defaults.double(forKey: Keys.backgroundOpacity)
        }
        return 1.0
    }
}

extension UserDefaultsPersistence: ViewModelPersistence {}
