import Foundation

/// Something of the test bundle's own, to find its files by.
final class BundleAnchor {}

enum Fixture {
    /// A file from `Fixtures/`, by its name.
    static func data(_ name: String, _ ext: String = "json") throws -> Data {
        let bundle = Bundle(for: BundleAnchor.self)
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).\(ext)"])
        }
        return try Data(contentsOf: url)
    }
}
