import Foundation
import Testing
@testable import RecompSources

private let address = try! RomMAddress("https://example.test", allowHTTP: false)
private func media(_ json: String) throws -> RomMMedia { try JSONDecoder().decode(RomMMedia.self, from: Data(json.utf8)) }

@Test func decodesBoxFacesScreenScraperFirst() throws {
    let art = RomMProvider.artwork(id: 3, title: "Fixture", media: try media(#"""
        {"path_cover_small": "/assets/romm/resources/roms/1/3/cover/small.png", "summary": "Race karts",
         "ss_metadata": {"box2d_back_path": "roms/1/3/box2d_back/box2d_back.png",
                         "box2d_side_path": "roms/1/3/box2d_side/box2d_side.png",
                         "physical_path": "roms/1/3/physical/physical.png"},
         "launchbox_metadata": {"box2d_path": "roms/1/3/box2d/box2d.png", "box2d_back_path": "roms/1/3/lb/back.png"}}
        """#), address: address)
    #expect(art.boxBack == "/assets/romm/resources/roms/1/3/box2d_back/box2d_back.png")
    #expect(art.boxSpine == "/assets/romm/resources/roms/1/3/box2d_side/box2d_side.png")
    #expect(art.media == "/assets/romm/resources/roms/1/3/physical/physical.png")
    #expect(art.boxFront == "/assets/romm/resources/roms/1/3/box2d/box2d.png")
    #expect(art.summary == "Race karts")
}

@Test func dropsUnsafeAndMissingFacePaths() throws {
    let art = RomMProvider.artwork(id: 3, title: "Fixture", media: try media(#"""
        {"ss_metadata": {"box2d_back_path": "roms/../../api/users/me", "box2d_side_path": ""}, "launchbox_metadata": null}
        """#), address: address)
    #expect(art.boxBack == nil && art.boxSpine == nil && art.boxFront == nil && art.media == nil)
}

@Test func oldCachedArtworkStillDecodes() throws {
    let old = #"{"romID": 3, "server": "https://example.test/", "title": "Fixture", "screenshots": []}"#
    let art = try JSONDecoder().decode(RomMArtwork.self, from: Data(old.utf8))
    #expect(art.boxBack == nil && art.summary == nil)
}

@Test func facesAreDrawnWithoutArtwork() {
    #expect(BoxFaces(nil) == BoxFaces(front: .drawn, back: .drawn, spine: .drawn, label: .drawn))
}

@Test func mixesRemoteAndDrawnFaces() {
    var art = RomMArtwork(romID: 3, server: "https://example.test/", title: "Fixture", coverSmall: "/assets/romm/resources/s.png",
                          coverLarge: "/assets/romm/resources/l.png", screenshots: [])
    art.boxSpine = "/assets/romm/resources/side.png"
    let faces = BoxFaces(art)
    #expect(faces.front == .remote("/assets/romm/resources/l.png"))
    #expect(faces.spine == .remote("/assets/romm/resources/side.png"))
    #expect(faces.back == .drawn && faces.label == .drawn)
}
