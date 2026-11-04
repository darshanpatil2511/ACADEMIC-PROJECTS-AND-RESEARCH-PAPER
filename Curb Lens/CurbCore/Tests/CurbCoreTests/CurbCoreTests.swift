import Foundation
import Testing
@testable import CurbCore

@Suite("CurbCore package")
struct CurbCoreTests {
    @Test func versionIsSet() {
        #expect(!CurbCore.version.isEmpty)
    }

    @Test func fixturesBundleIsAvailable() {
        #expect(Bundle.module.url(forResource: "Fixtures", withExtension: nil) != nil)
    }
}
