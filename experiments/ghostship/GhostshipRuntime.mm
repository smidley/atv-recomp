#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <atomic>
#include <array>
#include <cstring>
#include <cstdio>
#include <memory>
#include <vector>
#include <zip.h>
#include "Companion.h"
#include "NativecadeRuntime.h"
#include "GhostshipRuntime.h"

int NativecadeRunSuperMario(int argc, char **argv); // GhostshipRestart.cpp
static std::atomic<size_t> Extracted{0};
// Ghostship's game code is built for the US release, so only its assets are extracted (config.yml).
static constexpr const char *SupportedHash = "9bef1128717f958171a4afac3ed78ee2bb4e86ce";

static bool Fail(char *error, size_t capacity, const char *message) {
    if (error && capacity) snprintf(error, capacity, "%s", message);
    return false;
}

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
    auto files = NSFileManager.defaultManager;
    // A hard link shares the prepared archive's storage; copy when linking isn't possible.
    if (link(source.fileSystemRepresentation, temporary.fileSystemRepresentation) != 0 &&
        ![files copyItemAtPath:source toPath:temporary error:nil]) return false;
    // When both names already link to one file, rename does nothing, so the temporary name is always removed.
    const bool ok = rename(temporary.fileSystemRepresentation, destination.fileSystemRepresentation) == 0;
    unlink(temporary.fileSystemRepresentation);
    return ok;
}

bool NativecadePrepareSuperMario(const char *romPath, const char *expectedSHA1, char *error, size_t capacity) {
    Extracted = 0;
    @autoreleasepool {
        if (!romPath || !expectedSHA1 || strcmp(expectedSHA1, SupportedHash) != 0)
            return Fail(error, capacity, "Ghostship requires Super Mario 64 (USA). Import that ROM from your library.");
        auto files = NSFileManager.defaultManager;
        NSString *path = @(romPath);
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:nil];
        if ([attributes fileSize] == 0 || [attributes fileSize] > 64 * 1024 * 1024 ||
            ![attributes[NSFileType] isEqual:NSFileTypeRegular])
            return Fail(error, capacity, "The Super Mario 64 ROM is missing or invalid. Import it again.");
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
        char hash[41];
        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i) snprintf(hash + i * 2, 3, "%02x", digest[i]);
        if (data.length != [attributes fileSize] || strcmp(hash, expectedSHA1) != 0)
            return Fail(error, capacity, "The Super Mario 64 ROM changed after verification. Import it again.");
        NSString *support = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"NativecadeGame/Ghostship"];
        NSString *port = [support stringByAppendingPathComponent:@"ghostship.o2r"];
        if (!ValidArchive(port, 1) || ![files fileExistsAtPath:[support stringByAppendingPathComponent:@"config.yml"]])
            return Fail(error, capacity, "This app build is missing its Super Mario 64 support files.");
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *cache = [[caches stringByAppendingPathComponent:@"Nativecade/Prepared/" NATIVECADE_MARIO_PREPARED]
            stringByAppendingPathComponent:@(hash)];
        // Apple TV apps keep files in Library/Caches, like NativecadeRuntime.mm's game folders.
        NSString *root = [caches stringByAppendingPathComponent:@"Nativecade/Games/SuperMario64"];
        NSError *problem = nil;
        if (![files createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:&problem] ||
            ![files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&problem])
            return Fail(error, capacity, [NSString stringWithFormat:@"Nativecade could not create a game folder: %@",
                problem.localizedDescription ?: @"unknown error"].UTF8String);
        NSString *archive = [cache stringByAppendingPathComponent:@"sm64.o2r"];
        if (!ValidArchive(archive, 1000)) {
            NSString *stage = [cache stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            [files createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:nil];
            bool extracted = false;
            try {
                const auto *bytes = (const uint8_t *)data.bytes;
                auto extractor = std::make_unique<Companion>(std::vector<uint8_t>(bytes, bytes + data.length),
                    ArchiveType::O2R, false, std::string(support.fileSystemRepresentation), std::string(stage.fileSystemRepresentation));
                Companion::Instance = extractor.get();
                extractor->Init(ExportType::Binary, Extracted, true);
                extracted = ValidArchive([stage stringByAppendingPathComponent:@"sm64.o2r"], 1000) &&
                    Install([stage stringByAppendingPathComponent:@"sm64.o2r"], archive);
                Companion::Instance = nullptr;
            } catch (const std::exception& exception) {
                Companion::Instance = nullptr;
                NSLog(@"Nativecade Super Mario 64 preparation failed: %s", exception.what());
            }
            [files removeItemAtPath:stage error:nil];
            if (!extracted) return Fail(error, capacity, "Super Mario 64 preparation failed. Check available storage and try again.");
        }
        if (!Install(port, [root stringByAppendingPathComponent:@"ghostship.o2r"]) ||
            !Install(archive, [root stringByAppendingPathComponent:@"sm64.o2r"]))
            return Fail(error, capacity, "The prepared Super Mario 64 assets could not be installed.");
        if (!NativecadeSetPreparedGameRunner(NativecadeRunSuperMario, root.fileSystemRepresentation))
            return Fail(error, capacity, "Another game is already starting. Close and reopen Nativecade.");
        return true;
    }
}
