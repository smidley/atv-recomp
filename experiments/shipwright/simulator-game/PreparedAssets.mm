#import <Foundation/Foundation.h>
#include "NativecadeRuntime.h"

// A release or Torch update changes a game's folder name, and the earlier archives are never read
// again. Games call this before preparing, so the space is free for the new extraction.
void NativecadeRemoveOutdatedPreparations(const char *prepared, const char *current) {
    @autoreleasepool {
        NSString *folder = @(prepared), *key = @(current);
        NSRange hyphen = [key rangeOfString:@"-"];
        NSString *game = hyphen.location == NSNotFound ? nil : [key substringToIndex:NSMaxRange(hyphen)];
        auto files = NSFileManager.defaultManager;
        for (NSString *name in [files contentsOfDirectoryAtPath:folder error:nil]) {
            const bool sameGame = game ? [name hasPrefix:game] : ![name containsString:@"-"];
            if (sameGame && ![name isEqual:key]) [files removeItemAtPath:[folder stringByAppendingPathComponent:name] error:nil];
        }
    }
}

#ifdef NATIVECADE_PREPARED_ASSETS_TEST
// clang++ -fobjc-arc -DNATIVECADE_PREPARED_ASSETS_TEST PreparedAssets.mm -framework Foundation
#include <cstdio>
#include <cstdlib>
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #value); exit(1); } } while (0)

int main() {
    @autoreleasepool {
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *prepared = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSArray *names = @[@"9.3.0", @"9.3.1", @"SpaghettiKart-1.0.0-torch2ab12fe", @"SpaghettiKart-1.0.0-torch2ab12fe-legacy2",
                           @"SpaghettiKart-1.0.0-torch7f5d55f-legacy2", @"Ghostship-3.0.0-torch2ab12fe",
                           @"Ghostship-3.0.0-torch7f5d55f", @"Lighthouse-1.2.2-torch7f5d55f"];
        for (NSString *name in names)
            CHECK([files createDirectoryAtPath:[[prepared stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"rom"]
                   withIntermediateDirectories:YES attributes:nil error:nil]);
        auto remaining = [&] {
            return [[files contentsOfDirectoryAtPath:prepared error:nil] sortedArrayUsingSelector:@selector(compare:)];
        };
        // A game removes only its own earlier versions, and keeps the current one.
        NativecadeRemoveOutdatedPreparations(prepared.fileSystemRepresentation, "Ghostship-3.0.0-torch7f5d55f");
        CHECK(![remaining() containsObject:@"Ghostship-3.0.0-torch2ab12fe"]);
        CHECK([remaining() containsObject:@"Ghostship-3.0.0-torch7f5d55f"]);
        CHECK(remaining().count == names.count - 1);
        NativecadeRemoveOutdatedPreparations(prepared.fileSystemRepresentation, "SpaghettiKart-1.0.0-torch7f5d55f-legacy2");
        CHECK(remaining().count == names.count - 3);
        // Ocarina's folders are named by release alone.
        NativecadeRemoveOutdatedPreparations(prepared.fileSystemRepresentation, "9.3.1");
        CHECK([remaining() isEqual:(@[@"9.3.1", @"Ghostship-3.0.0-torch7f5d55f", @"Lighthouse-1.2.2-torch7f5d55f",
                                      @"SpaghettiKart-1.0.0-torch7f5d55f-legacy2"])]);
        // A missing folder is not an error.
        NativecadeRemoveOutdatedPreparations([prepared stringByAppendingPathComponent:@"missing"].fileSystemRepresentation, "9.3.1");
        [files removeItemAtPath:prepared error:nil];
        puts("Prepared-asset cleanup passed: each game removes only its own earlier versions.");
    }
    return 0;
}
#endif
