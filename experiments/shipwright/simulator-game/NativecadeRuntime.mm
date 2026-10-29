#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#include <SDL.h>
#include <SDL_main.h>
#include <zip.h>
#include <atomic>
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <vector>
#include <unistd.h>
#include "NativecadeRuntime.h"
#include "AppleTVGameplay.h"
#include "soh/Extractor/TorchExtract.h"

extern "C" int RecompTVShipwrightMain(int argc, char **argv);
static void (*ShowLibrary)(void);
static void (*HideLibrary)(void);
static std::atomic<bool> Preparing{false}, Prepared{false}, LaunchRequested{false};
static std::atomic<size_t> Extracted{0}, Total{1};
static int (*GameRunner)(int, char **);
static NSString *GameDirectory;

static bool Failure(char *error, size_t capacity, const char *message) {
    if (error && capacity) snprintf(error, capacity, "%s", message);
    return false;
}

static NSString *ROMHash(NSData *data) {
    unsigned char bytes[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *hash = [NSMutableString string];
    for (auto byte : bytes) [hash appendFormat:@"%02x", byte];
    return hash;
}

static bool ValidArchive(NSString *path) {
    // Torch can emit repeated asset names. libzip's ZIP_CHECKCONS rejects these
    // valid archives with ZIP_ER_EXISTS; the game also opens them read-only.
    // Read every entry below to verify its CRC without rejecting duplicate names.
    zip_t *archive = zip_open(path.fileSystemRepresentation, ZIP_RDONLY, nullptr);
    if (!archive) return false;
    unsigned char version[7] = {};
    zip_file_t *entry = zip_fopen(archive, "portVersion", 0);
    bool valid = entry && zip_fread(entry, version, sizeof(version)) == sizeof(version);
    if (entry) zip_fclose(entry);
    // PortVersion stores an endianness byte followed by three uint16 values.
    auto component = [&](int offset) {
        return version[0] == 1 ? (version[offset] << 8) | version[offset + 1] :
                                version[offset] | (version[offset + 1] << 8);
    };
    valid = valid && version[0] <= 1 && component(1) == 9 && component(3) == 3 && component(5) == 1;
    // Check every entry's CRC before handing the archive to the game. A terminated
    // preparation or storage corruption must return to the library, not crash gameplay.
    std::array<char, 65536> buffer;
    for (zip_int64_t i = 0, count = zip_get_num_entries(archive, 0); valid && i < count; ++i) {
        zip_file_t *file = zip_fopen_index(archive, i, 0);
        if (!file) { valid = false; break; }
        zip_int64_t read;
        do { read = zip_fread(file, buffer.data(), buffer.size()); } while (read > 0);
        valid = read == 0;
        if (zip_fclose(file) != 0) valid = false;
    }
    zip_close(archive);
    return valid;
}

static bool InstallArchive(NSString *source, NSString *destination) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *temporary = [destination stringByAppendingFormat:@".%@.partial", NSUUID.UUID.UUIDString];
    if (![files copyItemAtPath:source toPath:temporary error:nil]) return false;
    // rename atomically replaces an existing derived archive. Player save files are separate.
    bool ok = rename(temporary.fileSystemRepresentation, destination.fileSystemRepresentation) == 0;
    if (!ok) [files removeItemAtPath:temporary error:nil];
    return ok;
}

bool NativecadePrepareGame(const char *romPath, const char *expectedSHA1, char *error, size_t capacity) {
    if (Preparing.exchange(true)) return Failure(error, capacity, "Another game is already being prepared.");
    struct Finish { ~Finish() { Preparing = false; } } finish;
    Prepared = false; Extracted = 0; Total = 1;
    GameRunner = nullptr; GameDirectory = nil;
    @autoreleasepool {
        if (!romPath || !expectedSHA1 || strlen(expectedSHA1) != 40)
            return Failure(error, capacity, "Import and verify a supported ROM first.");
        NSString *path = @(romPath), *hash = @(expectedSHA1);
        NSFileManager *files = NSFileManager.defaultManager;
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:nil];
        NSUInteger size = [attributes fileSize];
        if ((size != 32 * 1024 * 1024 && size != 64 * 1024 * 1024) ||
            ![attributes[NSFileType] isEqual:NSFileTypeRegular])
            return Failure(error, capacity, "The cached ROM is missing or invalid. Import it again.");
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
        const unsigned char *bytes = (const unsigned char *)data.bytes;
        if (data.length != size || ![ROMHash(data) isEqual:hash] ||
            bytes[0] != 0x80 || bytes[1] != 0x37 || bytes[2] != 0x12 || bytes[3] != 0x40)
            return Failure(error, capacity, "The ROM changed after verification. Import it again.");

        NSString *resources = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"NativecadeGame"];
        NSString *definitions = [resources stringByAppendingPathComponent:@"yml"];
        NSString *port = [resources stringByAppendingPathComponent:@"soh.o2r"];
        if (!ValidArchive(port) || ![files fileExistsAtPath:[definitions stringByAppendingPathComponent:@"config.yml"]])
            return Failure(error, capacity, "This app build is missing its game support files.");
        NSString *cache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:[@"Nativecade/Prepared/9.3.1" stringByAppendingPathComponent:hash]];
        if (![files createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil])
            return Failure(error, capacity, "There is not enough storage to prepare this game.");
        NSString *archiveName = @"oot.o2r";
        if (!ValidArchive([cache stringByAppendingPathComponent:archiveName])) archiveName = @"oot-mq.o2r";
        if (!ValidArchive([cache stringByAppendingPathComponent:archiveName])) {
            NSString *staging = [cache stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            [files createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:nil];
            Total = std::max<size_t>(1, SohTorch::CountAssetFiles(definitions.fileSystemRepresentation));
            std::vector<uint8_t> rom(bytes, bytes + data.length);
            std::string result = SohTorch::Extract(std::move(rom), definitions.fileSystemRepresentation,
                staging.fileSystemRepresentation, "9.3.1", &Extracted);
            archiveName = result.empty() ? nil : @(result.c_str());
            bool valid = archiveName && [@[@"oot.o2r", @"oot-mq.o2r"] containsObject:archiveName] &&
                ValidArchive([staging stringByAppendingPathComponent:archiveName]);
            if (valid) valid = InstallArchive([staging stringByAppendingPathComponent:archiveName],
                                             [cache stringByAppendingPathComponent:archiveName]);
            [files removeItemAtPath:staging error:nil];
            if (!valid) return Failure(error, capacity, "Game preparation failed. Check available storage and try importing the ROM again.");
        }
        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        [files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
        if (!InstallArchive(port, [root stringByAppendingPathComponent:@"soh.o2r"]) ||
            !InstallArchive([cache stringByAppendingPathComponent:archiveName], [root stringByAppendingPathComponent:archiveName]))
            return Failure(error, capacity, "The prepared game could not be installed. Check available storage and try again.");
        NSString *other = [archiveName isEqual:@"oot.o2r"] ? @"oot-mq.o2r" : @"oot.o2r";
        NSString *otherPath = [root stringByAppendingPathComponent:other];
        if ([files fileExistsAtPath:otherPath] && ![files removeItemAtPath:otherPath error:nil])
            return Failure(error, capacity, "The previous game archive could not be switched. Restart the app and try again.");
        Prepared = true; Extracted = Total.load();
        return true;
    }
}

double NativecadePreparationProgress(void) {
    return std::min(1.0, double(Extracted.load()) / double(std::max<size_t>(1, Total.load())));
}

bool NativecadeSetPreparedGameRunner(int (*runner)(int, char **), const char *directory) {
    if (!runner || !directory || LaunchRequested.load() || Preparing.exchange(true)) return false;
    Prepared = false;
    GameRunner = runner;
    GameDirectory = @(directory);
    Prepared = true;
    Preparing = false;
    return true;
}

bool NativecadeLaunchPreparedGame(void) {
    if (!NSThread.isMainThread || !Prepared.load() || Preparing.load()) return false;
    if (LaunchRequested.exchange(true)) return false;
    // The library uses UIKit's normal event loop. Start SDL only after Play;
    // nesting a run loop here interferes with tvOS focus and remote input.
    [(NSObject *)UIApplication.sharedApplication.delegate performSelector:@selector(postFinishLaunch)
                                                               withObject:nil afterDelay:0.0];
    return true;
}

extern "C" void NativecadeRuntimePresentLibrary(void) {
    if (ShowLibrary) ShowLibrary();
}

static int RunApplication(int argc, char **argv) {
    @autoreleasepool {
        if (!ShowLibrary || !HideLibrary) return 2;
        HideLibrary();
        NSString *root = GameDirectory ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        if (chdir(root.fileSystemRepresentation) != 0) return 2;
        if (GameRunner) {
            setenv("NATIVECADE_GAME_DIRECTORY", root.fileSystemRepresentation, 1);
            return GameRunner(argc, argv);
        }
        RecompTVInitializeSaveStorage(root.fileSystemRepresentation);
        return RecompTVShipwrightMain(argc, argv);
    }
}

int NativecadeRunApplication(int argc, char **argv, void (*showLibrary)(void), void (*hideLibrary)(void)) {
    ShowLibrary = showLibrary; HideLibrary = hideLibrary;
    return SDL_UIKitRunApp(argc, argv, RunApplication);
}
