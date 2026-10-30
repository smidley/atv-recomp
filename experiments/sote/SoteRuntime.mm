#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <cstdio>
#include <cstring>
#include "NativecadeRuntime.h"
#include "SoteRuntime.h"

int NativecadeRunShadowsOfTheEmpire(int argc, char **argv); // SoteRestart.cpp
// Star Wars - Shadows of the Empire (USA) (Rev 2), the dump SotE-Recomp accepts (CRC32 E8727549).
static constexpr const char *SupportedHash = "9ab85626c27372ee614b7c5301c2c4eb187fd9f6";

static bool Fail(char *error, size_t capacity, const char *message) {
    if (error && capacity) snprintf(error, capacity, "%s", message);
    return false;
}

bool NativecadePrepareShadowsOfTheEmpire(const char *romPath, const char *expectedSHA1, char *error, size_t capacity) {
    @autoreleasepool {
        if (!romPath || !expectedSHA1 || strcmp(expectedSHA1, SupportedHash) != 0)
            return Fail(error, capacity, "SotE-Recomp requires the USA Rev 2 Shadows of the Empire ROM. Import it from your library.");
        auto files = NSFileManager.defaultManager;
        NSString *path = @(romPath);
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:nil];
        if ([attributes fileSize] != 12582912 || ![attributes[NSFileType] isEqual:NSFileTypeRegular])
            return Fail(error, capacity, "The Shadows of the Empire ROM is missing or invalid. Import it again.");
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
        char hash[41];
        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i) snprintf(hash + i * 2, 3, "%02x", digest[i]);
        if (data.length != [attributes fileSize] || strcmp(hash, expectedSHA1) != 0)
            return Fail(error, capacity, "The Shadows of the Empire ROM changed after verification. Import it again.");
        // The recompilation reads the cartridge at run time; nothing is extracted. SotE looks for the
        // ROM, its settings and saves beside its executable, which on Apple TV is the game folder.
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *root = [caches stringByAppendingPathComponent:@"Nativecade/Games/ShadowsOfTheEmpire"];
        NSError *problem = nil;
        if (![files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&problem])
            return Fail(error, capacity, [NSString stringWithFormat:@"Nativecade could not create a game folder: %@",
                problem.localizedDescription ?: @"unknown error"].UTF8String);
        NSString *rom = [root stringByAppendingPathComponent:@"sote.us.v1.2.z64"];
        NSString *temporary = [rom stringByAppendingFormat:@".%@.partial", NSUUID.UUID.UUIDString];
        // A hard link shares the verified ROM's storage; copy when linking isn't possible.
        bool installed = (link(path.fileSystemRepresentation, temporary.fileSystemRepresentation) == 0 ||
            [files copyItemAtPath:path toPath:temporary error:nil]) &&
            rename(temporary.fileSystemRepresentation, rom.fileSystemRepresentation) == 0;
        unlink(temporary.fileSystemRepresentation);
        if (!installed) return Fail(error, capacity, "The Shadows of the Empire ROM could not be installed.");
        if (!NativecadeSetPreparedGameRunner(NativecadeRunShadowsOfTheEmpire, root.fileSystemRepresentation))
            return Fail(error, capacity, "Another game is already starting. Close and reopen Nativecade.");
        return true;
    }
}
