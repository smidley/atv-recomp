import Foundation
import Testing
@testable import RecompSources

@Test func runtimeSelectionUsesROMIdentityAndPreservesOlderRecords() throws {
    let mario = "579c48e211ae952530ffc8738709f078d5dd215e"
    let zelda = "ad69c91157f6705e8ab06c79fe08aad47bb57ba7"
    #expect(SupportedGame.identify(sha1: mario) == .marioKart64)
    #expect(SupportedGame.identify(sha1: mario.uppercased()) == .marioKart64)
    #expect(SupportedGame.identify(sha1: zelda) == .ocarinaOfTime)
    // Star Fox 64 (U) 1.0 and 1.1, as listed in upstream/starship-baseline.json.
    #expect(SupportedGame.identify(sha1: "d8b1088520f7c5f81433292a9258c1184afa1457") == .starFox64)
    #expect(SupportedGame.identify(sha1: "09f0d105f476b00efa5303a3ebc42e60a7753b7a") == .starFox64)
    #expect(SupportedGame.identify(sha1: String(repeating: "0", count: 40)) == nil)
    let record = ImportedROM(name: "Mario Kart 64.z64", revision: "NTSC 1.0 US", sha1: zelda,
        sha256: String(repeating: "a", count: 64), size: 33554432, sourceID: UUID())
    let restored = try JSONDecoder().decode(ImportedROM.self, from: JSONEncoder().encode(record))
    #expect(restored.game == .ocarinaOfTime)
    let entries = try SupportedGame.allCases.flatMap { try $0.revisions() }
    #expect(Set(entries.map(\.sha1)).count == entries.count)
    #expect(try SupportedGame.marioKart64.revisions().count == 1)
}
