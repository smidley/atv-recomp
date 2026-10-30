#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <cstdio>
#include <cstring>
#include "NativecadeRuntime.h"
#include "RacerRuntime.h"

int NativecadeRunEpisodeOneRacer(int argc, char **argv); // RacerGame.cpp
// Star Wars Episode I - Racer (USA), the release whose header CRC Racer checks (72F70398).
static constexpr const char *SupportedHash = "3542d5597c8a56ea8f5c63bceae97a24c4c08d58";

static bool Fail(char *error, size_t capacity, const char *message) {
    if (error && capacity) snprintf(error, capacity, "%s", message);
    return false;
}

// As SoteRuntime.mm: nothing is extracted, because the game's code and data are read from the
// cartridge while it runs.
bool NativecadePrepareEpisodeOneRacer(const char *romPath, const char *expectedSHA1, char *error, size_t capacity) {
    @autoreleasepool {
        if (!romPath || !expectedSHA1 || strcmp(expectedSHA1, SupportedHash) != 0)
            return Fail(error, capacity, "Racer requires the USA release of Star Wars Episode I: Racer. Import it from your library.");
        auto files = NSFileManager.defaultManager;
        NSString *path = @(romPath);
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:nil];
        if ([attributes fileSize] != 33554432 || ![attributes[NSFileType] isEqual:NSFileTypeRegular])
            return Fail(error, capacity, "The Racer ROM is missing or invalid. Import it again.");
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
        char hash[41];
        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i) snprintf(hash + i * 2, 3, "%02x", digest[i]);
        if (data.length != [attributes fileSize] || strcmp(hash, expectedSHA1) != 0)
            return Fail(error, capacity, "The Racer ROM changed after verification. Import it again.");
        // Racer's runtime keeps its settings, saves and the ROM it accepted in its working folder,
        // which on Apple TV is the game folder; swe1racer.z64 is the name it keeps the ROM under.
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *root = [caches stringByAppendingPathComponent:@"Nativecade/Games/EpisodeOneRacer"];
        NSError *problem = nil;
        if (![files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&problem])
            return Fail(error, capacity, [NSString stringWithFormat:@"Nativecade could not create a game folder: %@",
                problem.localizedDescription ?: @"unknown error"].UTF8String);
        NSString *rom = [root stringByAppendingPathComponent:@"swe1racer.z64"];
        NSString *temporary = [rom stringByAppendingFormat:@".%@.partial", NSUUID.UUID.UUIDString];
        // A hard link shares the verified ROM's storage; copy when linking isn't possible.
        bool installed = (link(path.fileSystemRepresentation, temporary.fileSystemRepresentation) == 0 ||
            [files copyItemAtPath:path toPath:temporary error:nil]) &&
            rename(temporary.fileSystemRepresentation, rom.fileSystemRepresentation) == 0;
        unlink(temporary.fileSystemRepresentation);
        if (!installed) return Fail(error, capacity, "The Racer ROM could not be installed.");
        if (!NativecadeSetPreparedGameRunner(NativecadeRunEpisodeOneRacer, root.fileSystemRepresentation))
            return Fail(error, capacity, "Another game is already starting. Close and reopen Nativecade.");
        return true;
    }
}
