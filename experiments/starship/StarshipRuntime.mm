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
#include "StarshipRuntime.h"

int NativecadeRunStarFox(int argc, char **argv); // StarshipRestart.cpp
static std::atomic<size_t> Extracted{0};
// Starship extracts its base assets from the US ROMs only (config.yml).
static constexpr const char *SupportedHashes[] = {"d8b1088520f7c5f81433292a9258c1184afa1457",
                                                  "09f0d105f476b00efa5303a3ebc42e60a7753b7a"};

static bool Fail(char *error, size_t capacity, const char *message) {
    if (error && capacity) snprintf(error, capacity, "%s", message);
    return false;
}

static bool Supported(const char *hash) {
    for (const char *supported : SupportedHashes)
        if (hash && strcmp(hash, supported) == 0) return true;
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
    if (![files copyItemAtPath:source toPath:temporary error:nil]) return false;
    const bool ok = rename(temporary.fileSystemRepresentation, destination.fileSystemRepresentation) == 0;
    if (!ok) [files removeItemAtPath:temporary error:nil];
    return ok;
}

bool NativecadePrepareStarFox(const char *romPath, const char *expectedSHA1, char *error, size_t capacity) {
    Extracted = 0;
    @autoreleasepool {
        if (!romPath || !Supported(expectedSHA1))
            return Fail(error, capacity, "Starship requires Star Fox 64 (USA) 1.0 or 1.1. Import that ROM from your library.");
        auto files = NSFileManager.defaultManager;
        NSString *path = @(romPath);
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:nil];
        if ([attributes fileSize] == 0 || [attributes fileSize] > 64 * 1024 * 1024 ||
            ![attributes[NSFileType] isEqual:NSFileTypeRegular])
            return Fail(error, capacity, "The Star Fox ROM is missing or invalid. Import it again.");
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
        char hash[41];
        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i) snprintf(hash + i * 2, 3, "%02x", digest[i]);
        if (data.length != [attributes fileSize] || strcmp(hash, expectedSHA1) != 0)
            return Fail(error, capacity, "The Star Fox ROM changed after verification. Import it again.");
        NSString *support = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"NativecadeGame/Starship"];
        NSString *port = [support stringByAppendingPathComponent:@"starship.o2r"];
        if (!ValidArchive(port, 1) || ![files fileExistsAtPath:[support stringByAppendingPathComponent:@"config.yml"]])
            return Fail(error, capacity, "This app build is missing its Star Fox support files.");
        // Each ROM revision extracts its own assets.
        NSString *cache = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:@"Nativecade/Prepared/" NATIVECADE_FOX_PREPARED]
            stringByAppendingPathComponent:@(hash)];
        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/StarFox64"];
        if (![files createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil] ||
            ![files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil])
            return Fail(error, capacity, "There is not enough storage to prepare Star Fox.");
        NSString *archive = [cache stringByAppendingPathComponent:@"sf64.o2r"];
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
                extracted = ValidArchive([stage stringByAppendingPathComponent:@"sf64.o2r"], 1000) &&
                    Install([stage stringByAppendingPathComponent:@"sf64.o2r"], archive);
                Companion::Instance = nullptr;
            } catch (const std::exception& exception) {
                Companion::Instance = nullptr;
                NSLog(@"Nativecade Star Fox preparation failed: %s", exception.what());
            }
            [files removeItemAtPath:stage error:nil];
            if (!extracted) return Fail(error, capacity, "Star Fox preparation failed. Check available storage and try again.");
        }
        if (!Install(port, [root stringByAppendingPathComponent:@"starship.o2r"]) ||
            !Install(archive, [root stringByAppendingPathComponent:@"sf64.o2r"]))
            return Fail(error, capacity, "The prepared Star Fox assets could not be installed.");
        if (!NativecadeSetPreparedGameRunner(NativecadeRunStarFox, root.fileSystemRepresentation))
            return Fail(error, capacity, "Another game is already starting. Close and reopen Nativecade.");
        return true;
    }
}
