#import <Foundation/Foundation.h>
#include <SDL.h>
#include <SDL_main.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <TargetConditionals.h>
#include "AppleTVGameplay.h"

#if !TARGET_OS_TV || !TARGET_OS_SIMULATOR
#error This development entry point is only for Apple TV Simulator.
#endif

extern "C" int RecompTVShipwrightMain(int argc, char **argv);
int RecompTVRunSaveStoreTests(const char* serverAddress);
int RecompTVRunKeychainProbe(const char* accountName);
bool RecompTVRunControllerProbe();

static int RunGame(int argc, char **argv) {
    @autoreleasepool {
        // Explicit simulator diagnostics use isolated synthetic files and never
        // touch the player's save slots or RomM credentials.
        if (const char* account = std::getenv("RECOMPTV_KEYCHAIN_PROBE_ACCOUNT")) {
            if (RecompTVRunKeychainProbe(account) != 0) return 3;
        }
        if (const char* testServer = std::getenv("RECOMPTV_SAVE_TEST_SERVER")) {
            if (std::strncmp(testServer, "http://127.0.0.1:", 17) != 0) return 3;
            if (RecompTVRunSaveStoreTests(testServer) != 0) return 3;
        }
        if (const char* probe = std::getenv("RECOMPTV_CONTROLLER_SELF_TEST")) {
            if (std::strcmp(probe, "1") == 0 && !RecompTVRunControllerProbe()) return 3;
        }
        // Match libultraship's mobile data root. Private development bundles
        // contain the host-prepared archives and are never distribution builds.
        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        NSFileManager *files = NSFileManager.defaultManager;
        NSError *error = nil;
        if (![files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&error]) {
            fprintf(stderr, "Could not create the simulator's game data directory.\n");
            return 2;
        }
        for (NSString *name in @[@"oot.o2r", @"soh.o2r"]) {
            NSString *destination = [root stringByAppendingPathComponent:name];
            if ([files fileExistsAtPath:destination]) continue;
            NSString *source = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:name];
            if (![files copyItemAtPath:source toPath:destination error:&error]) {
                fprintf(stderr, "Missing prepared Shipwright assets. Add the verified ROM's archives before launch.\n");
                return 2;
            }
        }
        if (chdir(root.fileSystemRepresentation) != 0) return 2;
        RecompTVInitializeSaveStorage(root.fileSystemRepresentation);
        return RecompTVShipwrightMain(argc, argv);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        return SDL_UIKitRunApp(argc, argv, RunGame);
    }
}
