import Foundation
import Testing
@testable import RecompSources

@Test func librariesFromBeforeGuidedSetupSkipTheWelcome() {
    #expect(LibrarySetup.migrate(hasSources: false, games: []) == LibrarySetup())
    // A connection but no games yet: every supported platform, so the home isn't empty.
    #expect(LibrarySetup.migrate(hasSources: true, games: []) ==
            LibrarySetup(complete: true, platforms: Set(SupportedPlatform.allCases)))
    #expect(LibrarySetup.migrate(hasSources: false, games: [.marioKart64]) ==
            LibrarySetup(complete: true, platforms: [.nintendo64]))
}
