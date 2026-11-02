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

private struct ScanFixture: LibraryProvider {
    let result: Result<PlatformScan, LibraryError>
    func list(_ location: LibraryLocation, search: String, offset: Int) async throws -> LibraryPage {
        throw LibraryError.message("Not listed")
    }
    func download(_ entry: LibraryEntry, to destination: URL, progress: @escaping ProgressHandler) async throws {}
    func scan(_ platform: SupportedPlatform) async throws -> PlatformScan { try result.get() }
}

private func candidate(_ game: SupportedGame, _ sourceID: UUID) -> ScanCandidate {
    ScanCandidate(game: game, sourceID: sourceID, entries: [
        LibraryEntry(id: game.rawValue, name: game.title, detail: "", size: nil, target: .smbFile(game.rawValue))])
}

@Test func scanningSeveralConnectionsCountsEachGameOnceAndSurvivesAFailure() async {
    let den = UUID(), share = UUID()
    let report = await PlatformScanner.scan(.nintendo64, connections: [
        ScanConnection(name: "Den", provider: ScanFixture(result: .success(PlatformScan(
            candidates: [candidate(.marioKart64, den), candidate(.ocarinaOfTime, den)], unsupportedCount: 5)))),
        ScanConnection(name: "Attic", provider: ScanFixture(result: .failure(.httpStatus(503)))),
        ScanConnection(name: "Share", provider: ScanFixture(result: .success(PlatformScan(
            candidates: [candidate(.marioKart64, share), candidate(.starFox64, share)], unsupportedCount: nil)))),
    ])
    #expect(report.scan.candidates.map(\.game) == [.marioKart64, .starFox64, .ocarinaOfTime])
    #expect(report.scan.candidates.first?.sourceID == den)
    #expect(report.scan.unsupportedCount == 5)
    #expect(report.failures == ["Couldn't scan Attic. RomM returned HTTP 503. Try again after checking the server."])
}

@Test func scanPageAlwaysOffersAWayOutOfSetup() {
    let den = UUID()
    let scan = PlatformScan(candidates: [candidate(.marioKart64, den), candidate(.ocarinaOfTime, den)], unsupportedCount: nil)
    let none = PlatformScan(candidates: [], unsupportedCount: nil)
    // A fresh setup: add the games, or skip into the library.
    #expect(scan.actions(owned: [], setup: true, importFinished: false, added: 0) == [.addAll(2), .scanAgain, .goToLibrary])
    // Nothing Nativecade plays was found, or every connection failed.
    #expect(none.actions(owned: [], setup: true, importFinished: false, added: 0) == [.scanAgain, .goToLibrary])
    // Every dump was a different version: nothing was added, and Add all again wouldn't help.
    #expect(scan.actions(owned: [], setup: true, importFinished: true, added: 0) == [.scanAgain, .goToLibrary])
    // Some games were added, or were already there after going back a step.
    #expect(scan.actions(owned: [.marioKart64], setup: true, importFinished: true, added: 1) == [.startPlaying, .scanAgain])
    #expect(scan.actions(owned: [.marioKart64, .ocarinaOfTime], setup: true, importFinished: false, added: 0) == [.startPlaying, .scanAgain])
    // A platform's page after setup: Done once games were added; Back leaves otherwise.
    #expect(scan.actions(owned: [.ocarinaOfTime], setup: false, importFinished: false, added: 0) == [.addAll(1), .scanAgain])
    #expect(scan.actions(owned: [.marioKart64, .ocarinaOfTime], setup: false, importFinished: true, added: 1) == [.done, .scanAgain])
}
