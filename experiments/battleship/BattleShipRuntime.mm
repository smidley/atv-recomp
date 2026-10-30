#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <array>
#include <cstdio>
#include <cstring>
#include <exception>
#include <memory>
#include <vector>
#include <unistd.h>
#include <zip.h>
#include "Companion.h"
#include "NativecadeRuntime.h"
#include "BattleShipRuntime.h"

int NativecadeBattleShipMain(int argc, char **argv); // BattleShip's main, renamed in CMakeLists.txt
extern "C" void portRelocResetPointerTable(void);    // port/resource/RelocPointerTable.cpp
// Added to BattleShip's gameloop.cpp and Menu.cpp by scripts/prepare-battleship.py.
extern "C" void NativecadeBattleShipResetLoop(void);
extern "C" void NativecadeBattleShipResetMenu(void);

// BattleShip builds one region at a time; this build is Super Smash Bros. (USA), NALE 1.0.
static constexpr const char *SupportedHash = "e2929e10fccc0aa84e5776227e798abc07cedabf";

static bool Fail(char *error, size_t capacity, const char *message) {
    if (error && capacity) snprintf(error, capacity, "%s", message);
    return false;
}

// Reads every entry, so a terminated preparation or damaged storage returns to the library
// instead of crashing the game.
static bool ValidArchive(NSString *path, size_t minimumEntries) {
    zip_t *archive = zip_open(path.fileSystemRepresentation, ZIP_RDONLY, nullptr);
    if (!archive) return false;
    const auto count = zip_get_num_entries(archive, 0);
    bool valid = count >= (zip_int64_t)minimumEntries && count < 150000;
    std::array<char, 65536> bytes;
    uint64_t total = 0;
    for (zip_int64_t index = 0; valid && index < count; ++index) {
        zip_stat_t info;
        if (zip_stat_index(archive, index, 0, &info) != 0 || info.size > 128 * 1024 * 1024 ||
            (total += info.size) > 1024ull * 1024 * 1024) { valid = false; break; }
        zip_file_t *file = zip_fopen_index(archive, index, 0);
        if (!file) { valid = false; break; }
        zip_int64_t read;
        do { read = zip_fread(file, bytes.data(), bytes.size()); } while (read > 0);
        valid = read == 0;
        if (zip_fclose(file) != 0) valid = false;
    }
    zip_close(archive);
    return valid;
}

static bool Install(NSString *source, NSString *destination) {
    NSString *temporary = [destination stringByAppendingFormat:@".%@.partial", NSUUID.UUID.UUIDString];
    // A hard link shares the prepared file's storage; copy when linking isn't possible.
    if (link(source.fileSystemRepresentation, temporary.fileSystemRepresentation) != 0 &&
        ![NSFileManager.defaultManager copyItemAtPath:source toPath:temporary error:nil]) return false;
    // When both names already link to one file, rename does nothing, so the temporary name is always removed.
    const bool ok = rename(temporary.fileSystemRepresentation, destination.fileSystemRepresentation) == 0;
    unlink(temporary.fileSystemRepresentation);
    return ok;
}

// Runs Super Smash Bros. for one start. BattleShip expects a new process for each start; state that
// its own startup does not rebuild is reset here when a game ends (docs/GAME_SWITCHING.md).
static int NativecadeRunSuperSmashBros(int argc, char **argv) {
    const int result = NativecadeBattleShipMain(argc, argv);
    portRelocResetPointerTable(); // its tokens point into the ended game's resources
    NativecadeBattleShipResetLoop();
    NativecadeBattleShipResetMenu();
    return result;
}

bool NativecadePrepareSuperSmashBros(const char *romPath, const char *expectedSHA1, char *error, size_t capacity) {
    @autoreleasepool {
        if (!romPath || !expectedSHA1 || strcmp(expectedSHA1, SupportedHash) != 0)
            return Fail(error, capacity, "BattleShip requires Super Smash Bros. (USA). Import it from your library.");
        auto files = NSFileManager.defaultManager;
        NSString *path = @(romPath);
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:nil];
        if ([attributes fileSize] == 0 || [attributes fileSize] > 64 * 1024 * 1024 ||
            ![attributes[NSFileType] isEqual:NSFileTypeRegular])
            return Fail(error, capacity, "The Super Smash Bros. ROM is missing or invalid. Import it again.");
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
        char hash[41];
        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i) snprintf(hash + i * 2, 3, "%02x", digest[i]);
        if (data.length != [attributes fileSize] || strcmp(hash, expectedSHA1) != 0)
            return Fail(error, capacity, "The Super Smash Bros. ROM changed after verification. Import it again.");
        // Packed by scripts/prepare-battleship.py: Torch's extraction definitions, the shaders, fonts.
        NSString *support = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"NativecadeGame/BattleShip"];
        NSString *shaders = [support stringByAppendingPathComponent:@"f3d.o2r"];
        if (!ValidArchive(shaders, 1) || ![files fileExistsAtPath:[support stringByAppendingPathComponent:@"config.yml"]])
            return Fail(error, capacity, "This app build is missing its Super Smash Bros. support files.");
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NativecadeRemoveOutdatedPreparations([caches stringByAppendingPathComponent:@"Nativecade/Prepared"].fileSystemRepresentation,
            NATIVECADE_BATTLESHIP_PREPARED);
        NSString *cache = [[caches stringByAppendingPathComponent:@"Nativecade/Prepared/" NATIVECADE_BATTLESHIP_PREPARED]
            stringByAppendingPathComponent:@(hash)];
        // Apple TV apps keep files in Library/Caches, like NativecadeRuntime.mm's game folders.
        NSString *root = [caches stringByAppendingPathComponent:@"Nativecade/Games/SuperSmashBros"];
        NSString *fonts = [root stringByAppendingPathComponent:@"assets/custom/fonts"];
        NSError *problem = nil;
        if (![files createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:&problem] ||
            ![files createDirectoryAtPath:fonts withIntermediateDirectories:YES attributes:nil error:&problem])
            return Fail(error, capacity, [NSString stringWithFormat:@"Nativecade could not create a game folder: %@",
                problem.localizedDescription ?: @"unknown error"].UTF8String);
        // About 2,150 assets: one per relocatable file, plus audio and particles (yamls/us).
        constexpr size_t MinimumAssets = 2000;
        NSString *archive = [cache stringByAppendingPathComponent:@"BattleShip.o2r"];
        if (!ValidArchive(archive, MinimumAssets)) {
            NSString *stage = [cache stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            [files createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:nil];
            bool extracted = false;
            // As BattleShip's Android build extracts on the device (port/android_torch_bridge.cpp).
            try {
                const auto *bytes = (const uint8_t *)data.bytes;
                auto extractor = std::make_unique<Companion>(std::vector<uint8_t>(bytes, bytes + data.length),
                    ArchiveType::O2R, false, std::string(support.fileSystemRepresentation), std::string(stage.fileSystemRepresentation));
                Companion::Instance = extractor.get();
                extractor->Init(ExportType::Binary);
                Companion::Instance = nullptr;
                NSString *output = [stage stringByAppendingPathComponent:@"BattleShip.o2r"];
                extracted = ValidArchive(output, MinimumAssets) && Install(output, archive);
            } catch (const std::exception& exception) {
                Companion::Instance = nullptr;
                NSLog(@"Nativecade Super Smash Bros. preparation failed: %s", exception.what());
            }
            [files removeItemAtPath:stage error:nil];
            if (!extracted) return Fail(error, capacity, "Super Smash Bros. preparation failed. Check available storage and try again.");
        }
        bool installed = Install(shaders, [root stringByAppendingPathComponent:@"f3d.o2r"]) &&
            Install(archive, [root stringByAppendingPathComponent:@"BattleShip.o2r"]);
        NSString *bundledFonts = [support stringByAppendingPathComponent:@"assets/custom/fonts"];
        for (NSString *font in [files contentsOfDirectoryAtPath:bundledFonts error:nil])
            if ([font.pathExtension isEqualToString:@"ttf"])
                installed = installed && Install([bundledFonts stringByAppendingPathComponent:font], [fonts stringByAppendingPathComponent:font]);
        if (!installed) return Fail(error, capacity, "The prepared Super Smash Bros. assets could not be installed.");
        if (!NativecadeSetPreparedGameRunner(NativecadeRunSuperSmashBros, root.fileSystemRepresentation))
            return Fail(error, capacity, "Another game is already starting. Close and reopen Nativecade.");
        return true;
    }
}
