#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <atomic>
#include <array>
#include <algorithm>
#include <cstring>
#include <cstdio>
#include <memory>
#include <vector>
#include <zip.h>
#include "Companion.h"
#include "NativecadeRuntime.h"
#include "SpaghettiRuntime.h"

extern "C" int NativecadeSpaghettiMain(int argc, char **argv);
static std::atomic<size_t> Extracted{0};
static constexpr char SupportedHash[] = "579c48e211ae952530ffc8738709f078d5dd215e";

static bool Fail(char *error, size_t capacity, const char *message) {
    if (error && capacity) snprintf(error, capacity, "%s", message);
    return false;
}

static bool ValidArchive(NSString *path, const char *required, bool game = false) {
    zip_t *archive = zip_open(path.fileSystemRepresentation, ZIP_RDONLY, nullptr);
    if (!archive) return false;
    bool valid = zip_name_locate(archive, required, 0) >= 0;
    if (game) {
        // CRC alone cannot detect an incomplete extraction built without audio support.
        for (const char *entry : {"sound/sequences/title_screen", "sound/sequences/luigi_raceway",
                                 "sound/banks/bank_0", "sound/root/audio_seq_font_table"})
            valid = valid && zip_name_locate(archive, entry, 0) >= 0;
        zip_stat_t background;
        valid = valid && zip_stat(archive, "textures/texture_tkmk00/background_blue_sky", 0, &background) == 0 &&
                background.size >= 320 * 240 * 2;
    }
    const auto count = zip_get_num_entries(archive, 0);
    valid = valid && count > 0 && count < 150000;
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

bool NativecadePrepareMarioKart(const char *romPath, const char *expectedSHA1, char *error, size_t capacity) {
    Extracted = 0;
    @autoreleasepool {
        if (!romPath || !expectedSHA1 || strcmp(expectedSHA1, SupportedHash) != 0)
            return Fail(error, capacity, "SpaghettiKart requires Mario Kart 64 (USA). Import that ROM from your library.");
        auto files = NSFileManager.defaultManager;
        NSString *path = @(romPath);
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:nil];
        if ([attributes fileSize] != 12 * 1024 * 1024 || ![attributes[NSFileType] isEqual:NSFileTypeRegular])
            return Fail(error, capacity, "The Mario Kart ROM is missing or invalid. Import it again.");
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
        char hash[41];
        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i) snprintf(hash + i * 2, 3, "%02x", digest[i]);
        if (data.length != 12 * 1024 * 1024 || strcmp(hash, SupportedHash) != 0)
            return Fail(error, capacity, "The Mario Kart ROM changed after verification. Import it again.");
        NSString *support = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"NativecadeGame/SpaghettiKart"];
        NSString *port = [support stringByAppendingPathComponent:@"spaghetti.o2r"];
        if (!ValidArchive(port, "mods.toml") || ![files fileExistsAtPath:[support stringByAppendingPathComponent:@"config.yml"]])
            return Fail(error, capacity, "This app build is missing its Mario Kart support files.");
        NSString *cache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:@"Nativecade/Prepared/SpaghettiKart-1.0.0-torch2ab12fe-legacy2"];
        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/MarioKart64"];
        if (![files createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil] ||
            ![files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil])
            return Fail(error, capacity, "There is not enough storage to prepare Mario Kart.");
        NSString *archive = [cache stringByAppendingPathComponent:@"mk64.o2r"];
        if (!ValidArchive(archive, "mods.toml", true)) {
            NSString *stage = [cache stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            [files createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:nil];
            bool extracted = false;
            try {
                const auto *bytes = (const uint8_t *)data.bytes;
                auto extractor = std::make_unique<Companion>(std::vector<uint8_t>(bytes, bytes + data.length),
                    ArchiveType::O2R, false, std::string(support.fileSystemRepresentation), std::string(stage.fileSystemRepresentation));
                Companion::Instance = extractor.get();
                extractor->SetAdditionalFiles({"meta/mods.toml"});
                extractor->Init(ExportType::Binary, Extracted, true);
                extracted = ValidArchive([stage stringByAppendingPathComponent:@"mk64.o2r"], "mods.toml", true) &&
                    Install([stage stringByAppendingPathComponent:@"mk64.o2r"], archive);
                Companion::Instance = nullptr;
            } catch (const std::exception& exception) {
                Companion::Instance = nullptr;
                NSLog(@"Nativecade Mario Kart preparation failed: %s", exception.what());
            }
            [files removeItemAtPath:stage error:nil];
            if (!extracted) return Fail(error, capacity, "Mario Kart preparation failed. Check available storage and try again.");
        }
        if (!Install(port, [root stringByAppendingPathComponent:@"spaghetti.o2r"]) ||
            !Install(archive, [root stringByAppendingPathComponent:@"mk64.o2r"]))
            return Fail(error, capacity, "The prepared Mario Kart assets could not be installed.");
        if (!NativecadeSetPreparedGameRunner(NativecadeSpaghettiMain, root.fileSystemRepresentation))
            return Fail(error, capacity, "Another game is already starting. Close and reopen Nativecade.");
        return true;
    }
}
