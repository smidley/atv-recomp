#import <Foundation/Foundation.h>
#include <SDL.h>
#include <SDL_main.h>
#include <cstdio>
#include <unistd.h>
#include <TargetConditionals.h>

#if !TARGET_OS_TV || !TARGET_OS_SIMULATOR
#error This development entry point is only for Apple TV Simulator.
#endif

extern "C" int RecompTVShipwrightMain(int argc, char **argv);

static int RunGame(int argc, char **argv) {
    @autoreleasepool {
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
        return RecompTVShipwrightMain(argc, argv);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        return SDL_UIKitRunApp(argc, argv, RunGame);
    }
}
