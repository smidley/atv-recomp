#import "AppleTVSaveStore.h"
#include <cstdio>
#include <cstdlib>
#include <TargetConditionals.h>

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #value); exit(1); } } while (0)
@interface TestCredentials : NSObject <RTVSaveCredentials>
@property NSString *token;
@end
@implementation TestCredentials
- (NSString *)readToken { return self.token; }
- (BOOL)writeToken:(NSString *)token { self.token = token; return YES; }
@end
static NSData *Save(int progress) {
    return [NSJSONSerialization dataWithJSONObject:@{@"version":@1, @"fileType":@0,
        @"sections":@{@"base":@{@"version":@4, @"data":@{@"progress":@(progress)}}}} options:0 error:nil];
}
static id Control(NSString *server, NSString *path) {
    NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:[server stringByAppendingString:path]]];
    CHECK(data);
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}
static void Pump(BOOL (^finished)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!finished() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(finished());
}
static NSArray *List(RTVSaveStore *store) {
    __block BOOL done = NO; __block NSArray *items;
    [store listBackups:^(NSArray *values, NSError *error) { CHECK(!error); items = values; done = YES; }];
    Pump(^BOOL { return done; });
    return items;
}
static NSError *Restore(RTVSaveStore *store, NSDictionary *backup) {
    __block BOOL done = NO; __block NSError *problem;
    [store stageRestore:backup completion:^(NSError *error) { problem = error; done = YES; }];
    Pump(^BOOL { return done; });
    return problem;
}
int RecompTVRunKeychainProbe(const char *accountName) {
    @autoreleasepool {
        NSString *account = @(accountName);
        CHECK([account hasPrefix:@"test-"] && account.length > 20);
        RTVKeychainSaveCredentials *keys = [[RTVKeychainSaveCredentials alloc] initWithAccount:account];
        NSString *saved = [keys readToken];
        if (!saved) {
            CHECK([keys writeToken:@"synthetic-save-probe"]);
            CHECK([[keys readToken] isEqual:@"synthetic-save-probe"]);
            puts("[RecompTVKeychainTest] PASS: stored isolated test credential; relaunch to verify persistence.");
        } else {
            CHECK([saved isEqual:@"synthetic-save-probe"]);
            CHECK([keys writeToken:@""]);
            CHECK(![keys readToken]);
            puts("[RecompTVKeychainTest] PASS: credential survived relaunch; isolated test credential removed.");
        }
    }
    return 0;
}
int RecompTVRunSaveStoreTests(const char *serverAddress) {
    @autoreleasepool {
        NSString *server = @(serverAddress);
        NSString *suite = [@"RecompTV.SaveTests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:suite];
        TestCredentials *keys = [TestCredentials new];
        RTVSaveStore *(^makeStore)(void) = ^{ return [[RTVSaveStore alloc] initWithRoot:root defaults:defaults credentials:keys]; };
        RTVSaveStore *store = makeStore();
        NSError *error = nil;
        CHECK([store prepareLocalFiles:&error]);
        NSString *path = [root stringByAppendingPathComponent:@"Save/file1.sav"];
        NSData *first = Save(1), *second = Save(2);
        CHECK(RTVValidSave(@"file1.sav", first));
        CHECK(!RTVValidSave(@"../file1.sav", first));
        CHECK(!RTVValidSave(@"file1.sav", [@"{}" dataUsingEncoding:NSUTF8StringEncoding]));
        CHECK(!RTVValidSave(@"global.sav", first));
        NSMutableDictionary *format = [[NSJSONSerialization JSONObjectWithData:first options:NSJSONReadingMutableContainers error:nil] mutableCopy];
        format[@"fileType"] = @4; // Shipwright speedrun, not the preset enum value 2.
        CHECK(RTVValidSave(@"file1.sav", [NSJSONSerialization dataWithJSONObject:format options:0 error:nil]));
        format[@"fileType"] = @2;
        CHECK(!RTVValidSave(@"file1.sav", [NSJSONSerialization dataWithJSONObject:format options:0 error:nil]));
        CHECK([first writeToFile:path atomically:YES]);
        CHECK([store recordSave:@"file1.sav" data:first error:&error]);
        CHECK([NSFileManager.defaultManager removeItemAtPath:path error:&error]);
        store = makeStore();
        CHECK([store prepareLocalFiles:&error]);
        CHECK([[NSData dataWithContentsOfFile:path] isEqual:first]);
        CHECK([store deleteSave:@"file1.sav" error:&error]);
        CHECK([first writeToFile:path atomically:YES]); // Model interruption after tombstone, before unlink.
        store = makeStore();
        CHECK([store prepareLocalFiles:&error]);
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:path]);
        CHECK([first writeToFile:path atomically:YES]);
        CHECK([store recordSave:@"file1.sav" data:first error:&error]);

        NSString *url = [server stringByAppendingString:@"/romm/rom/42"];
        CHECK(![store configureGameURL:url token:@"test-token" allowHTTP:NO error:&error]);
        CHECK(![store configureGameURL:@"https://user:password@example.com/rom/42" token:@"test-token" allowHTTP:NO error:&error]);
        CHECK(![store configureGameURL:@"https://example.com/rom/nope" token:@"test-token" allowHTTP:NO error:&error]);
        CHECK(![store configureGameURL:url token:@"bad\r\ntoken" allowHTTP:YES error:&error]);
        CHECK([store configureGameURL:url token:@"test-token" allowHTTP:YES error:&error]);
        [store waitForBackups];
        CHECK([[store status] containsString:@"backed up"]);
        CHECK([Control(server,@"/stats")[@"uploads"] intValue] == 1);
        [store backupNow]; [store waitForBackups];
        CHECK([Control(server,@"/stats")[@"uploads"] intValue] == 1);
        CHECK(![[defaults persistentDomainForName:suite].description containsString:@"test-token"]);
        NSArray *initial = List(store);
        CHECK(initial.count == 1); // Fixture also returns saves for other games/emulators and unsafe slots.

        Control(server, @"/mode?value=offline");
        CHECK([second writeToFile:path atomically:YES]);
        CHECK([store recordSave:@"file1.sav" data:second error:&error]);
        [store waitForBackups];
        CHECK(![[store status] containsString:@"backed up"]);
        CHECK([[NSData dataWithContentsOfFile:path] isEqual:second]);
        Control(server, @"/mode?value=normal");
        [store backupNow]; [store waitForBackups];
        CHECK([Control(server,@"/stats")[@"uploads"] intValue] == 2);
        CHECK(List(store).count == 2);
        CHECK(!Restore(store, initial.firstObject));
        CHECK([[NSData dataWithContentsOfFile:path] isEqual:second]); // Never replace a running game's file.
        NSString *blockedRecovery = [root stringByAppendingPathComponent:@"Save/Recovery"];
        CHECK([first writeToFile:blockedRecovery atomically:YES]);
        CHECK(![store prepareLocalFiles:&error]); // Cannot preserve current save: postpone restoration.
        CHECK([[NSData dataWithContentsOfFile:path] isEqual:second]);
        CHECK([NSFileManager.defaultManager removeItemAtPath:blockedRecovery error:&error]);
        store = makeStore();
        CHECK([store prepareLocalFiles:&error]);
        CHECK([[NSData dataWithContentsOfFile:path] isEqual:first]);
        NSArray *recoveryDirs = [NSFileManager.defaultManager contentsOfDirectoryAtPath:[root stringByAppendingPathComponent:@"Save/Recovery"] error:&error];
        CHECK(recoveryDirs.count == 1);
        NSString *recovered = [[[root stringByAppendingPathComponent:@"Save/Recovery"] stringByAppendingPathComponent:recoveryDirs.firstObject] stringByAppendingPathComponent:@"file1.sav"];
        CHECK([[NSData dataWithContentsOfFile:recovered] isEqual:second]);
        CHECK([store stageUndo:@"file1.sav" error:&error]);
        store = makeStore(); CHECK([store prepareLocalFiles:&error]);
        CHECK([[NSData dataWithContentsOfFile:path] isEqual:second]);

        Control(server, @"/mode?value=bad-save");
        CHECK(Restore(store, initial.firstObject));
        CHECK([[NSData dataWithContentsOfFile:path] isEqual:second]);
        Control(server, @"/mode?value=oversize");
        CHECK(Restore(store, initial.firstObject));
        Control(server, @"/mode?value=redirect");
        CHECK(Restore(store, initial.firstObject));
        CHECK([Control(server,@"/stats")[@"redirected"] intValue] == 0);
        Control(server, @"/mode?value=denied");
        NSError *denied = Restore(store, initial.firstObject);
        CHECK([denied.localizedDescription containsString:@"assets.read"]);
        Control(server, @"/mode?value=normal");
        CHECK(!Restore(store, initial.firstObject));
        CHECK([store deleteSave:@"file1.sav" error:&error]);
        store = makeStore(); CHECK([store prepareLocalFiles:&error]);
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:path]);

        [store disconnect];
        CHECK(!keys.token.length);
        CHECK([Control(server,@"/stats")[@"deletes"] intValue] == 0);
        // Failed local writes and future/invalid formats must leave the current safety copy unchanged.
        CHECK(![store recordSave:@"file1.sav" data:[@"broken" dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
        CHECK(![store deleteSave:@"../../other" error:&error]);
        NSMutableData *noise = [NSMutableData dataWithLength:512 * 1024];
        arc4random_buf(noise.mutableBytes, noise.length);
        format[@"fileType"] = @0;
        format[@"sections"][@"base"][@"data"][@"testNoise"] = [noise base64EncodedStringWithOptions:0];
        NSData *largeSave = [NSJSONSerialization dataWithJSONObject:format options:0 error:nil];
        CHECK([largeSave writeToFile:path atomically:YES]);
        CHECK(![store recordSave:@"file1.sav" data:largeSave error:&error]);
        CHECK([error.localizedDescription containsString:@"full"]);
        CHECK([[NSData dataWithContentsOfFile:path] isEqual:largeSave]);
        [defaults removePersistentDomainForName:suite];
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
        puts("Save tests passed: offline recovery, erase, versioned uploads, retry, restore/undo, format isolation, credentials, redirects, response limits and denied access.");
    }
    return 0;
}
#ifdef RECOMPTV_SAVE_TEST_MAIN
int main(int argc, char **argv) { CHECK(argc == 2); return RecompTVRunSaveStoreTests(argv[1]); }
#endif
