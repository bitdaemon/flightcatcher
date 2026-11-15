import XCTest
@testable import SimCore

enum TestSupport {
    static func airport(_ name: String) throws -> AirportPackage {
        try AirportPackage.loadBundled(name)
    }
}
