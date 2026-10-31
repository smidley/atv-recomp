#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <GameController/GameController.h>
#include <SDL.h>
#include <SDL_main.h>
#include <zip.h>
#include <atomic>
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <map>
#include <chrono>
#include <thread>
#include <vector>
#include <unistd.h>
#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#if __has_feature(address_sanitizer)
#include <sanitizer/asan_interface.h>
#endif
#include <ship/Context.h>
#include <spdlog/spdlog.h>
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

static bool FolderFailure(char *error, size_t capacity, NSError *problem) {
    return Failure(error, capacity, [NSString stringWithFormat:@"Nativecade could not create a game folder: %@",
        problem.localizedDescription ?: @"unknown error"].UTF8String);
}

// Apple documents only Library/Caches and preferences as local storage for Apple TV apps, and tvOS
// may purge caches while the app isn't running. The simulator also allows Documents, which hid this.
static NSString *GameFolder(NSString *name) {
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:[@"Nativecade/Games" stringByAppendingPathComponent:name]];
}

// The last game's console output, in Library/Caches/Nativecade/Logs/last-game.log, which the
// Diagnostics tab shows. TestFlight builds run on the Apple TV without a debugger, so this is how a
// failure there can be read afterwards. The log stays stdout and stderr until the next game starts,
// so a crash on the way back to the library is caught too; a crash adds its signal and backtrace.
static struct sigaction GameLogPrevious[NSIG];
static constexpr int GameLogSignals[] = {SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP};

static void GameLogCrash(int signal) {
    static const char header[] = "\n[Nativecade] crashed with signal ";
    write(STDERR_FILENO, header, sizeof header - 1);
    const char number[] = {char('0' + signal / 10), char('0' + signal % 10), '\n'};
    write(STDERR_FILENO, number, sizeof number);
    void *frames[64];
    backtrace_symbols_fd(frames, backtrace(frames, 64), STDERR_FILENO);
    sigaction(signal, &GameLogPrevious[signal], nullptr);
    raise(signal);
}

static void StartGameLog(NSString *game) {
    NSString *folder = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"Nativecade/Logs"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    int log = open([folder stringByAppendingPathComponent:@"last-game.log"].fileSystemRepresentation,
                   O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (log < 0) return;
    fflush(stdout);
    fflush(stderr);
    dup2(log, STDOUT_FILENO);
    dup2(log, STDERR_FILENO);
    close(log);
    setvbuf(stdout, nullptr, _IOLBF, 0);
    NSString *build = NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"?";
    fprintf(stderr, "[Nativecade] %s, build %s, %s\n", game.UTF8String, build.UTF8String, NSDate.date.description.UTF8String);
    static bool handlersInstalled;
    if (handlersInstalled) return;
    handlersInstalled = true;
    struct sigaction action = {};
    action.sa_handler = GameLogCrash;
    sigemptyset(&action.sa_mask);
    for (int signal : GameLogSignals) sigaction(signal, &action, &GameLogPrevious[signal]);
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
    // A hard link shares the prepared archive's storage; copy when linking isn't possible.
    if (link(source.fileSystemRepresentation, temporary.fileSystemRepresentation) != 0 &&
        ![files copyItemAtPath:source toPath:temporary error:nil]) return false;
    // rename atomically replaces an existing derived archive. Player save files are separate.
    // When both names already link to one file, rename does nothing, so the temporary name is always removed.
    bool ok = rename(temporary.fileSystemRepresentation, destination.fileSystemRepresentation) == 0;
    unlink(temporary.fileSystemRepresentation);
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
        NativecadeRemoveOutdatedPreparations([NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:@"Nativecade/Prepared"].fileSystemRepresentation, NATIVECADE_SHIPWRIGHT_RELEASE);
        NSString *cache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:[@"Nativecade/Prepared/" NATIVECADE_SHIPWRIGHT_RELEASE stringByAppendingPathComponent:hash]];
        NSError *problem = nil;
        if (![files createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:&problem])
            return FolderFailure(error, capacity, problem);
        NSString *archiveName = @"oot.o2r";
        if (!ValidArchive([cache stringByAppendingPathComponent:archiveName])) archiveName = @"oot-mq.o2r";
        if (!ValidArchive([cache stringByAppendingPathComponent:archiveName])) {
            NSString *staging = [cache stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            [files createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:nil];
            Total = std::max<size_t>(1, SohTorch::CountAssetFiles(definitions.fileSystemRepresentation));
            std::vector<uint8_t> rom(bytes, bytes + data.length);
            std::string result = SohTorch::Extract(std::move(rom), definitions.fileSystemRepresentation,
                staging.fileSystemRepresentation, NATIVECADE_SHIPWRIGHT_RELEASE, &Extracted);
            archiveName = result.empty() ? nil : @(result.c_str());
            bool valid = archiveName && [@[@"oot.o2r", @"oot-mq.o2r"] containsObject:archiveName] &&
                ValidArchive([staging stringByAppendingPathComponent:archiveName]);
            if (valid) valid = InstallArchive([staging stringByAppendingPathComponent:archiveName],
                                             [cache stringByAppendingPathComponent:archiveName]);
            [files removeItemAtPath:staging error:nil];
            if (!valid) return Failure(error, capacity, "Game preparation failed. Check available storage and try importing the ROM again.");
        }
        NSString *root = GameFolder(@"OcarinaOfTime");
        if (![files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&problem])
            return FolderFailure(error, capacity, problem);
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

// Zero-initialized game state is hundreds of megabytes. Map fresh zero pages over whole pages
// instead of writing zeros, so state a game never touched stays uncommitted.
static void ZeroGameState(uint8_t *start, size_t size) {
    uintptr_t begin = (uintptr_t)start, end = begin + size, mask = vm_page_size - 1;
    uintptr_t first = (begin + mask) & ~mask, last = end & ~mask;
    if (first >= last) { memset(start, 0, size); return; }
    memset(start, 0, first - begin);
    memset((void *)last, 0, end - last);
    vm_address_t pages = first;
    if (vm_allocate(mach_task_self(), &pages, last - first, VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE) != KERN_SUCCESS)
        memset((void *)first, 0, last - first);
}

// The ports keep the original game's state in C globals and expect a fresh process for each
// start. GameStateSection.h compiles those globals into __game_data and __game_bss. Before
// every start, put back their load-time values, as a console reset reloads memory.
static void ResetGameGlobals() {
    static std::map<const void *, std::vector<uint8_t>> loaded;
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        auto header = reinterpret_cast<const struct mach_header_64 *>(_dyld_get_image_header(i));
        unsigned long size = 0;
        if (uint8_t *data = getsectiondata(header, "__DATA", "__game_data", &size)) {
#if __has_feature(address_sanitizer)
            // Whole-section copies span the redzones Address Sanitizer places between globals.
            __asan_unpoison_memory_region(data, size);
#endif
            auto [values, first] = loaded.try_emplace(header, data, data + size);
            if (!first) memcpy(data, values->second.data(), size);
        }
        if (uint8_t *zeroed = getsectiondata(header, "__DATA", "__game_bss", &size)) {
#if __has_feature(address_sanitizer)
            __asan_unpoison_memory_region(zeroed, size);
#endif
            ZeroGameState(zeroed, size);
        }
    }
}

// Holding a controller's View button, or the Siri Remote's Play/Pause, for 1.5 seconds ends any
// game and returns to the library, as each game's own Quit does, whatever its menus offer. A press
// of View alone still opens the menus of the games that have one.
static id ControllerObserver;
static std::atomic<unsigned> QuitPresses{0};

static GCControllerButtonInput *QuitButton(GCController *controller) {
    return controller.extendedGamepad ? controller.extendedGamepad.buttonOptions : controller.microGamepad.buttonX;
}

static void ArmQuitButton(GCController *controller) {
    QuitButton(controller).pressedChangedHandler = ^(GCControllerButtonInput *button, float, BOOL pressed) {
        const unsigned press = ++QuitPresses;
        if (!pressed) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (press != QuitPresses.load() || !button.isPressed) return;
            SDL_Event quit = {};
            quit.type = SDL_QUIT;
            SDL_PushEvent(&quit);
        });
    };
}

static void ArmQuitButtons(bool armed) {
    if (armed) {
        for (GCController *controller in GCController.controllers) ArmQuitButton(controller);
        ControllerObserver = [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidConnectNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { ArmQuitButton(note.object); }];
    } else {
        if (ControllerObserver) [NSNotificationCenter.defaultCenter removeObserver:ControllerObserver];
        ControllerObserver = nil;
        for (GCController *controller in GCController.controllers) QuitButton(controller).pressedChangedHandler = nil;
    }
}

#if TARGET_OS_SIMULATOR
// Simulator-only menu check: with NATIVECADE_MENU_PROBE set, a virtual controller presses View 12
// seconds into the game, then moves through its menu with the D-pad (docs/GAME_SWITCHING.md).
static void StartMenuProbe() {
    if (!getenv("NATIVECADE_MENU_PROBE") || SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) != 0) return;
    SDL_VirtualJoystickDesc desc{};
    desc.version = SDL_VIRTUAL_JOYSTICK_DESC_VERSION;
    desc.type = SDL_JOYSTICK_TYPE_GAMECONTROLLER;
    desc.naxes = SDL_CONTROLLER_AXIS_MAX;
    desc.nbuttons = SDL_CONTROLLER_BUTTON_MAX;
    desc.axis_mask = (1u << SDL_CONTROLLER_AXIS_MAX) - 1;
    desc.button_mask = (1u << SDL_CONTROLLER_BUTTON_MAX) - 1;
    desc.name = "Nativecade menu probe";
    const int index = SDL_JoystickAttachVirtualEx(&desc);
    SDL_Joystick *pad = index >= 0 ? SDL_JoystickOpen(index) : nullptr;
    if (!pad) return;
    std::thread([pad] {
        const auto start = std::chrono::steady_clock::now();
        auto press = [&](SDL_GameControllerButton button, int at) {
            std::this_thread::sleep_until(start + std::chrono::milliseconds(at));
            SDL_JoystickSetVirtualButton(pad, button, 1);
            std::this_thread::sleep_for(std::chrono::milliseconds(150));
            SDL_JoystickSetVirtualButton(pad, button, 0);
            NSLog(@"[MenuProbe] pressed %s", SDL_GameControllerGetStringForButton(button));
        };
        press(SDL_CONTROLLER_BUTTON_BACK, 12000);
        for (int i = 0; i < 3; ++i) press(SDL_CONTROLLER_BUTTON_DPAD_DOWN, 15000 + i * 1000);
        press(SDL_CONTROLLER_BUTTON_DPAD_RIGHT, 18000);
        press(SDL_CONTROLLER_BUTTON_DPAD_DOWN, 19000);
    }).detach();
}
#endif

static int RunApplication(int argc, char **argv) {
    @autoreleasepool {
        if (!ShowLibrary || !HideLibrary) return 2;
        HideLibrary();
        NSString *root = GameDirectory ?: GameFolder(@"OcarinaOfTime");
        int status = 2;
        if (chdir(root.fileSystemRepresentation) == 0) {
            StartGameLog(root.lastPathComponent);
            ResetGameGlobals();
#if TARGET_OS_SIMULATOR
            // Simulator-only restart check: end the game after 30 seconds, as its Quit button does.
            if (getenv("NATIVECADE_RESTART_PROBE")) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    SDL_Event quit = {};
                    quit.type = SDL_QUIT;
                    SDL_PushEvent(&quit);
                });
            }
#endif
            // libultraship otherwise uses Documents; Apple TV apps keep files in Caches (GameFolder).
            setenv("NATIVECADE_GAME_DIRECTORY", root.fileSystemRepresentation, 1);
            ArmQuitButtons(true);
#if TARGET_OS_SIMULATOR
            StartMenuProbe();
#endif
            if (GameRunner) {
                status = GameRunner(argc, argv);
            } else {
                RecompTVInitializeSaveStorage(root.fileSystemRepresentation);
                status = RecompTVShipwrightMain(argc, argv);
            }
        }
        ArmQuitButtons(false);
        // A game's main loop ends when its menu's Quit button closes the window. The ports
        // expect the process to exit next, so release libultraship's process-wide context
        // before another game creates one. SDL keeps UIKit running for the library.
        RecompTVClearGameHooks();
        std::string logger = Ship::Context::GetRawInstance() ? Ship::Context::GetRawInstance()->GetName() : "";
        Ship::Context::DestroyInstance();
        // libultraship registers its logger under the game's name; let the next start register it again.
        spdlog::drop(logger);
        spdlog::set_default_logger(std::make_shared<spdlog::logger>("nativecade"));
        // Quit SDL only now; libultraship's window no longer does (metal/restart.patch).
        SDL_Quit();
        // libultraship reads this as the game's data folder; it must not leak into the next game.
        unsetenv("NATIVECADE_GAME_DIRECTORY");
        Prepared = false;
        LaunchRequested = false;
        ShowLibrary();
        return status;
    }
}

int NativecadeRunApplication(int argc, char **argv, void (*showLibrary)(void), void (*hideLibrary)(void)) {
    ShowLibrary = showLibrary; HideLibrary = hideLibrary;
    return SDL_UIKitRunApp(argc, argv, RunApplication);
}
