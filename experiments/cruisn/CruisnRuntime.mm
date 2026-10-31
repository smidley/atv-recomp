#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <cstdio>
#include <cstring>
#include "NativecadeRuntime.h"
#include "CruisnRuntime.h"

int NativecadeRunCruisnUSA(int argc, char **argv);   // CruisnGame.cpp
int NativecadeRunCruisnWorld(int argc, char **argv);

namespace {

struct Release {
    const char *title;
    const char *sha1;      // the release navjack's configuration describes (its splat.yaml)
    NSString *folder;      // in Library/Caches/Nativecade/Games
    NSString *romName;     // the frontend's GameInfo.rom_names
    int (*run)(int, char **);
};

bool Fail(char *error, size_t capacity, NSString *message) {
    if (error && capacity) snprintf(error, capacity, "%s", message.UTF8String);
    return false;
}

// As RacerRuntime.mm: nothing is extracted, because the game's code and data are read from the
// cartridge while it runs.
bool Prepare(const Release &game, const char *romPath, const char *expectedSHA1, char *error, size_t capacity) {
    @autoreleasepool {
        if (!romPath || !expectedSHA1 || strcmp(expectedSHA1, game.sha1) != 0)
            return Fail(error, capacity, [NSString stringWithFormat:@"%s requires its USA release. Import it from your library.", game.title]);
        auto files = NSFileManager.defaultManager;
        NSString *path = @(romPath);
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:nil];
        // N64 cartridges hold at most 64 MB.
        if (!attributes || [attributes fileSize] > 64 * 1024 * 1024 || ![attributes[NSFileType] isEqual:NSFileTypeRegular])
            return Fail(error, capacity, [NSString stringWithFormat:@"The %s ROM is missing or invalid. Import it again.", game.title]);
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
        char hash[41];
        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i) snprintf(hash + i * 2, 3, "%02x", digest[i]);
        if (data.length != [attributes fileSize] || strcmp(hash, expectedSHA1) != 0)
            return Fail(error, capacity, [NSString stringWithFormat:@"The %s ROM changed after verification. Import it again.", game.title]);
        // The runtime keeps its settings, saves and the ROM it accepted in its working folder, which
        // on Apple TV is the game folder.
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *root = [caches stringByAppendingPathComponent:[@"Nativecade/Games" stringByAppendingPathComponent:game.folder]];
        NSError *problem = nil;
        if (![files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&problem])
            return Fail(error, capacity, [NSString stringWithFormat:@"Nativecade could not create a game folder: %@",
                problem.localizedDescription ?: @"unknown error"]);
        NSString *rom = [root stringByAppendingPathComponent:game.romName];
        NSString *temporary = [rom stringByAppendingFormat:@".%@.partial", NSUUID.UUID.UUIDString];
        // A hard link shares the verified ROM's storage; copy when linking isn't possible.
        bool installed = (link(path.fileSystemRepresentation, temporary.fileSystemRepresentation) == 0 ||
            [files copyItemAtPath:path toPath:temporary error:nil]) &&
            rename(temporary.fileSystemRepresentation, rom.fileSystemRepresentation) == 0;
        unlink(temporary.fileSystemRepresentation);
        if (!installed) return Fail(error, capacity, [NSString stringWithFormat:@"The %s ROM could not be installed.", game.title]);
        if (!NativecadeSetPreparedGameRunner(game.run, root.fileSystemRepresentation))
            return Fail(error, capacity, @"Another game is already starting. Close and reopen Nativecade.");
        return true;
    }
}

} // namespace

bool NativecadePrepareCruisnUSA(const char *romPath, const char *expectedSHA1, char *error, size_t capacity) {
    return Prepare({"Cruis'n USA", "54a875ee0b482036fa401a6bc2b242699f0259f7", @"CruisnUSA", @"cruisnusa.z64",
        NativecadeRunCruisnUSA}, romPath, expectedSHA1, error, capacity);
}

bool NativecadePrepareCruisnWorld(const char *romPath, const char *expectedSHA1, char *error, size_t capacity) {
    return Prepare({"Cruis'n World", "6da1a6a2bda687d50e798d80c342948ad1738202", @"CruisnWorld", @"cruisnworld.z64",
        NativecadeRunCruisnWorld}, romPath, expectedSHA1, error, capacity);
}
