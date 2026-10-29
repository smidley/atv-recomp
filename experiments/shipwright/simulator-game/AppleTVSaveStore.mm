#import "AppleTVSaveStore.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include <zlib.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static const NSUInteger MaxSaveBytes = 4 * 1024 * 1024;
// tvOS preferences are limited. Leave room for settings and other app preferences.
static const NSUInteger MaxArchiveBytes = 256 * 1024;
static NSString *const ArchiveKey = @"RecompTV.SaveArchive.v1";
static NSString *const Emulator = @"recomptv-shipwright-9.3.1";

static NSError *SaveError(NSString *message) {
    return [NSError errorWithDomain:@"RecompTV.Saves" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL Fail(NSError **error, NSString *message) {
    if (error) *error = SaveError(message);
    return NO;
}
static BOOL JSONInteger(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
           [value doubleValue] == [value longLongValue];
}
NSArray<NSString *> *RTVSaveNames(void) {
    return @[@"file1.sav", @"file2.sav", @"file3.sav", @"global.sav"];
}
BOOL RTVValidSave(NSString *name, NSData *data) {
    if (![RTVSaveNames() containsObject:name] || !data.length || data.length > MaxSaveBytes) return NO;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![value isKindOfClass:NSDictionary.class] || !JSONInteger(value[@"version"]) || ![value[@"version"] isEqual:@1]) return NO;
    if ([name isEqual:@"global.sav"]) {
        for (NSString *key in @[@"audioSetting", @"zTargetSetting", @"language"])
            if (!JSONInteger(value[key]) || [value[key] intValue] < 0 || [value[key] intValue] > 3) return NO;
        return YES;
    }
    // Pinned Shipwright FileType: vanilla=0, randomizer=1, speedrun=4.
    if (!JSONInteger(value[@"fileType"]) || ![@[@0, @1, @4] containsObject:value[@"fileType"]] ||
        ![value[@"sections"] isKindOfClass:NSDictionary.class]) return NO;
    for (id section in [value[@"sections"] allValues]) {
        if (![section isKindOfClass:NSDictionary.class] || !JSONInteger(section[@"version"]) ||
            ![section[@"data"] isKindOfClass:NSDictionary.class]) return NO;
    }
    NSDictionary *base = value[@"sections"][@"base"];
    return [base isKindOfClass:NSDictionary.class] && [base[@"version"] isEqual:@4];
}
static NSString *Hash(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *result = [NSMutableString stringWithCapacity:64];
    for (unsigned char byte : bytes) [result appendFormat:@"%02x", byte];
    return result;
}
static NSData *Pack(NSData *data) {
    uLongf count = compressBound(data.length);
    NSMutableData *packed = [NSMutableData dataWithLength:count];
    if (compress2((Bytef *)packed.mutableBytes, &count, (const Bytef *)data.bytes, data.length, Z_BEST_SPEED) != Z_OK) return nil;
    packed.length = count;
    return packed;
}
static NSData *Unpack(id packed) {
    if (![packed isKindOfClass:NSData.class] || [packed length] > MaxArchiveBytes) return nil;
    uLongf count = MaxSaveBytes;
    NSMutableData *data = [NSMutableData dataWithLength:count];
    if (uncompress((Bytef *)data.mutableBytes, &count, (const Bytef *)[packed bytes], [packed length]) != Z_OK) return nil;
    data.length = count;
    return data;
}
static BOOL AtomicWrite(NSString *path, NSData *data) {
    // Same-directory atomic replacement, with the bytes flushed before rename.
    NSString *temp = [path stringByAppendingFormat:@".%@.tmp", NSUUID.UUID.UUIDString];
    int fd = open(temp.fileSystemRepresentation, O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (fd < 0) return NO;
    const char *bytes = (const char *)data.bytes;
    NSUInteger left = data.length;
    while (left) {
        ssize_t written = write(fd, bytes, left);
        if (written <= 0) break;
        bytes += written;
        left -= written;
    }
    BOOL ok = !left && fsync(fd) == 0;
    ok = close(fd) == 0 && ok;
    if (ok) ok = rename(temp.fileSystemRepresentation, path.fileSystemRepresentation) == 0;
    if (!ok) unlink(temp.fileSystemRepresentation);
    return ok;
}

@interface RTVKeychainSaveCredentials ()
@property NSString *account;
@end
@implementation RTVKeychainSaveCredentials
- (instancetype)init { return [self initWithAccount:@"save-backups"]; }
- (instancetype)initWithAccount:(NSString *)account {
    if ((self = [super init])) _account = [account copy];
    return self;
}
- (NSMutableDictionary *)query {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:@"com.smidley.RecompTVShipwrightExperiment.RomM",
              (__bridge id)kSecAttrAccount:self.account} mutableCopy];
}
- (NSString *)readToken {
    NSMutableDictionary *query = [self query];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = nil;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return nil;
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
- (BOOL)writeToken:(NSString *)token {
    NSMutableDictionary *query = [self query];
    if (!token.length) {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        return status == errSecSuccess || status == errSecItemNotFound;
    }
    NSDictionary *attributes = @{(__bridge id)kSecValueData:[token dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    if (status == errSecItemNotFound) {
        [query addEntriesFromDictionary:attributes];
        status = SecItemAdd((__bridge CFDictionaryRef)query, nil);
    }
    return status == errSecSuccess;
}
@end

// A private session per bounded request. Redirects never receive an API token,
// and oversized/error bodies cannot fill memory or enter user-facing messages.
@interface RTVSaveRequest : NSObject <NSURLSessionDataDelegate>
@property NSMutableData *data;
@property NSError *error;
@property NSInteger status;
@property dispatch_semaphore_t done;
@end
@implementation RTVSaveRequest
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    self.error = SaveError(@"RomM redirected the request. Use its final server address.");
    completionHandler(nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    self.status = [(NSHTTPURLResponse *)response statusCode];
    if (response.expectedContentLength > (long long)MaxSaveBytes) {
        self.error = SaveError(@"RomM returned a backup or list that is too large.");
        completion(NSURLSessionResponseCancel);
    } else completion(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (self.data.length + data.length > MaxSaveBytes) {
        self.error = SaveError(@"RomM returned a backup or list that is too large.");
        [task cancel];
    } else [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
#ifdef RECOMPTV_SAVE_TEST_MAIN
    // Numeric diagnostics for the isolated host fixture; never log URLs, tokens or response bodies.
    if (error) fprintf(stderr, "Save fixture transport error: %s %ld; underlying %ld\n",
                       error.domain.UTF8String, (long)error.code,
                       (long)[error.userInfo[NSUnderlyingErrorKey] code]);
#endif
    if (!self.error && error) self.error = SaveError(@"RomM is unavailable. Local saves are safe; backups will retry.");
    dispatch_semaphore_signal(self.done);
}
@end

static NSData *Request(NSDictionary *config, NSString *token, NSString *method, NSString *path,
                       NSDictionary *query, NSData *body, NSString *contentType, NSError **error) {
    NSURL *base = [NSURL URLWithString:config[@"server"]];
    NSURLComponents *url = [NSURLComponents componentsWithURL:[base URLByAppendingPathComponent:path] resolvingAgainstBaseURL:NO];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *key in query) [items addObject:[NSURLQueryItem queryItemWithName:key value:[query[key] description]]];
    url.queryItems = items;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL];
    request.HTTPMethod = method;
    request.timeoutInterval = 20;
    request.HTTPBody = body;
    [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (contentType) [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    NSURLSessionConfiguration *options = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    options.HTTPCookieStorage = nil;
    options.URLCredentialStorage = nil;
    options.URLCache = nil;
    options.timeoutIntervalForResource = 25;
    RTVSaveRequest *delegate = [RTVSaveRequest new];
    delegate.data = [NSMutableData data];
    delegate.done = dispatch_semaphore_create(0);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:options delegate:delegate delegateQueue:nil];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request];
    [task resume];
    // This function runs exclusively on the store's background operation queue.
    if (dispatch_semaphore_wait(delegate.done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC))) {
        [session invalidateAndCancel];
        if (error) *error = SaveError(@"RomM timed out. Local saves are safe; backups will retry.");
        return nil;
    }
    [session finishTasksAndInvalidate];
    NSString *message = nil;
    if (delegate.status == 401 || delegate.status == 403)
        message = @"RomM denied save access. Use a token with assets.read and assets.write permissions.";
    else if (delegate.status < 200 || delegate.status >= 300)
        message = @"RomM could not complete the backup request. Local saves are safe.";
    if (delegate.error || message) {
        if (error) *error = delegate.error ?: SaveError(message);
        return nil;
    }
    return delegate.data;
}

@interface RTVSaveStore ()
@property NSString *root;
@property NSUserDefaults *defaults;
@property id<RTVSaveCredentials> credentials;
@property NSMutableDictionary *state;
@property NSOperationQueue *queue;
@property NSString *message;
@property BOOL backupQueued;
@end
@implementation RTVSaveStore
- (instancetype)initWithRoot:(NSString *)root defaults:(NSUserDefaults *)defaults credentials:(id<RTVSaveCredentials>)credentials {
    if ((self = [super init])) {
        _root = [root copy]; _defaults = defaults; _credentials = credentials;
        id saved = [defaults dictionaryForKey:ArchiveKey];
        _state = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
        for (NSString *key in @[@"current", @"deleted", @"uploaded", @"pending", @"beforeRestore"])
            _state[key] = [_state[key] isKindOfClass:NSDictionary.class] ? [_state[key] mutableCopy] : [NSMutableDictionary dictionary];
        _queue = [NSOperationQueue new];
        _queue.maxConcurrentOperationCount = 1;
        _queue.qualityOfService = NSQualityOfServiceUtility;
        _message = @"Local saves ready. Set up RomM to back them up.";
    }
    return self;
}
- (BOOL)persist:(NSError **)error {
    NSData *encoded = [NSPropertyListSerialization dataWithPropertyList:self.state format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!encoded || encoded.length > MaxArchiveBytes)
        return Fail(error, @"The local safety copy is full. The game save remains on disk; back it up to RomM.");
    [self.defaults setObject:self.state forKey:ArchiveKey];
    if (![self.defaults synchronize]) return Fail(error, @"Could not persist the local safety copy. The game save remains on disk.");
    return YES;
}
- (NSString *)path:(NSString *)name { return [[self.root stringByAppendingPathComponent:@"Save"] stringByAppendingPathComponent:name]; }
- (NSString *)status { @synchronized(self) { return self.message; } }
- (NSString *)gameURL { @synchronized(self) { return self.state[@"config"][@"gameURL"] ?: @""; } }
- (void)setStatusError:(NSError *)error { @synchronized(self) { self.message = error.localizedDescription; } }
- (BOOL)recordSave:(NSString *)name data:(NSData *)data error:(NSError **)error {
    if (!RTVValidSave(name, data)) return Fail(error, @"This save format cannot be backed up by this version of the game.");
    @synchronized(self) {
        self.state[@"current"][name] = Pack(data);
        [self.state[@"deleted"] removeObjectForKey:name];
        NSError *problem = nil;
        BOOL persisted = [self persist:&problem];
        if (!persisted) { self.message = problem.localizedDescription; if (error) *error = problem; }
        [self backupNow];
        return persisted;
    }
}
- (BOOL)deleteSave:(NSString *)name error:(NSError **)error {
    if (![RTVSaveNames() containsObject:name]) return Fail(error, @"Unknown save slot.");
    @synchronized(self) {
        // Persist intent before unlink so a crash cannot resurrect an erased slot.
        self.state[@"deleted"][name] = @YES;
        if (![self persist:error]) return NO;
        NSString *path = [self path:name];
        if (unlink(path.fileSystemRepresentation) && errno != ENOENT) {
            [self.state[@"deleted"] removeObjectForKey:name];
            [self persist:nil];
            return Fail(error, @"The save could not be erased. Its previous copy is retained.");
        }
        [self.state[@"pending"] removeObjectForKey:name];
        return [self persist:error];
    }
}
- (BOOL)prepareLocalFiles:(NSError **)error {
    @synchronized(self) {
        NSFileManager *files = NSFileManager.defaultManager;
        if (![files createDirectoryAtPath:[self.root stringByAppendingPathComponent:@"Save"] withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        for (NSString *name in RTVSaveNames()) {
            NSString *path = [self path:name];
            NSData *local = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
            NSData *pending = Unpack(self.state[@"pending"][name]);
            if (pending) {
                if (!RTVValidSave(name, pending)) return Fail(error, @"The downloaded backup is invalid. Local saves were kept.");
                if (local) {
                    // Keep an independent, unmodified file even if it is corrupt or a future format.
                    NSString *recovery = [[self.root stringByAppendingPathComponent:@"Save/Recovery"] stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
                    if (![files createDirectoryAtPath:recovery withIntermediateDirectories:YES attributes:nil error:error] ||
                        !AtomicWrite([recovery stringByAppendingPathComponent:name], local))
                        return Fail(error, @"Could not preserve the current save. Restore was postponed.");
                    if (RTVValidSave(name, local)) {
                        self.state[@"beforeRestore"][name] = Pack(local);
                        if (![self persist:error]) return NO;
                    }
                }
                if (!AtomicWrite(path, pending)) return Fail(error, @"Could not restore the backup. The current save is retained.");
                self.state[@"current"][name] = Pack(pending);
                [self.state[@"pending"] removeObjectForKey:name];
                [self.state[@"deleted"] removeObjectForKey:name];
                [self.state[@"uploaded"] removeObjectForKey:name];
                if (![self persist:error]) return NO;
                local = pending;
            } else if ([self.state[@"deleted"][name] boolValue]) {
                // Complete an erase interrupted after persisting its tombstone.
                if (unlink(path.fileSystemRepresentation) && errno != ENOENT)
                    return Fail(error, @"Could not finish erasing a save. Its recovery copy is retained.");
                local = nil;
            } else if (!local) {
                NSData *backup = Unpack(self.state[@"current"][name]);
                if (backup && RTVValidSave(name, backup)) {
                    if (!AtomicWrite(path, backup)) return Fail(error, @"Could not recover the local safety copy.");
                    local = backup;
                }
            }
            if (local && RTVValidSave(name, local) && ![self.state[@"deleted"][name] boolValue])
                self.state[@"current"][name] = Pack(local);
        }
        return [self persist:error];
    }
}
- (BOOL)configureGameURL:(NSString *)address token:(NSString *)token allowHTTP:(BOOL)allowHTTP error:(NSError **)error {
    NSURLComponents *url = [NSURLComponents componentsWithString:[address stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    NSString *scheme = url.scheme.lowercaseString;
    NSArray *parts = url.path.pathComponents;
    if (!url.host.length || url.user || url.password || url.query || url.fragment ||
        !([scheme isEqual:@"https"] || ([scheme isEqual:@"http"] && allowHTTP)) || parts.count < 3 ||
        ![parts[parts.count - 2] isEqual:@"rom"])
        return Fail(error, @"Paste the game's RomM page address, ending in /rom/123. HTTP requires the local-network option.");
    NSString *rom = parts.lastObject;
    if (!rom.length || [rom rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound || rom.longLongValue <= 0)
        return Fail(error, @"The RomM page address needs a valid game number.");
    token = [token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!token.length || token.length > 8192 || [token rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound)
        return Fail(error, @"Enter a valid RomM client API token.");
    NSString *gameURL = url.string;
    url.path = [[url.path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    @synchronized(self) {
        if (![self.credentials writeToken:token]) return Fail(error, @"Could not store the token securely in Keychain.");
        self.state[@"config"] = @{ @"server":url.string, @"gameURL":gameURL, @"rom":@(rom.longLongValue), @"id":NSUUID.UUID.UUIDString };
        [self.state[@"uploaded"] removeAllObjects];
        [self.state[@"pending"] removeAllObjects];
        if (![self persist:error]) return NO;
        self.message = @"RomM configured. Backups will run in the background.";
    }
    [self backupNow];
    return YES;
}
- (void)disconnect {
    @synchronized(self) {
        [self.state removeObjectForKey:@"config"];
        [self.state[@"uploaded"] removeAllObjects];
        [self.credentials writeToken:@""];
        [self persist:nil];
        self.message = @"RomM disconnected. Local saves and existing server backups are retained.";
    }
}
- (BOOL)isCurrent:(NSDictionary *)config { return [self.state[@"config"][@"id"] isEqual:config[@"id"]]; }
- (void)backupNow {
    @synchronized(self) {
        if (self.backupQueued || !self.state[@"config"]) return;
        self.backupQueued = YES;
    }
    [self.queue addOperationWithBlock:^{
        @autoreleasepool {
            NSDictionary *config; NSDictionary *current; NSDictionary *deleted; NSDictionary *uploaded; NSString *token;
            @synchronized(self) {
                config = [self.state[@"config"] copy]; current = [self.state[@"current"] copy];
                deleted = [self.state[@"deleted"] copy]; uploaded = [self.state[@"uploaded"] copy];
                token = [self.credentials readToken];
            }
            NSError *error = nil;
            NSUInteger savedCount = 0;
            if (config && !token.length) error = SaveError(@"RomM needs a token. Open backup setup to reconnect.");
            // A fresh setup verifies read permission as well as upload permission.
            if (config && !error && !uploaded.count) {
                NSData *listing = Request(config, token, @"GET", @"api/saves", @{@"rom_id":config[@"rom"]}, nil, nil, &error);
                id items = listing ? [NSJSONSerialization JSONObjectWithData:listing options:0 error:nil] : nil;
                if (listing && ![items isKindOfClass:NSArray.class]) error = SaveError(@"RomM returned an unreadable backup list.");
            }
            for (NSString *name in RTVSaveNames()) {
                if (!config || error) break;
                @synchronized(self) { if (![self isCurrent:config]) break; }
                if ([deleted[name] boolValue]) continue;
                NSData *data = Unpack(current[name]);
                if (!data || !RTVValidSave(name, data)) continue;
                ++savedCount;
                NSString *hash = Hash(data);
                if ([uploaded[name] isEqual:hash]) continue;
                // Always create a new version. No update/delete endpoint is used.
                NSString *boundary = [@"RecompTV-" stringByAppendingString:NSUUID.UUID.UUIDString];
                NSString *filename = [NSString stringWithFormat:@"%@-%@.sav", name.stringByDeletingPathExtension, NSUUID.UUID.UUIDString];
                NSMutableData *body = [NSMutableData data];
                NSString *head = [NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"saveFile\"; filename=\"%@\"\r\nContent-Type: application/octet-stream\r\n\r\n", boundary, filename];
                [body appendData:[head dataUsingEncoding:NSUTF8StringEncoding]]; [body appendData:data];
                [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
                NSString *slot = [@"recomptv-" stringByAppendingString:name.stringByDeletingPathExtension];
                NSData *response = Request(config, token, @"POST", @"api/saves",
                    @{@"rom_id":config[@"rom"], @"emulator":Emulator, @"slot":slot, @"overwrite":@"false", @"autocleanup":@"false"},
                    body, [@"multipart/form-data; boundary=" stringByAppendingString:boundary], &error);
                id value = response ? [NSJSONSerialization JSONObjectWithData:response options:0 error:nil] : nil;
                if (response && (![value isKindOfClass:NSDictionary.class] || ![value[@"rom_id"] isEqual:config[@"rom"]] ||
                    ![value[@"emulator"] isEqual:Emulator] || ![value[@"slot"] isEqual:slot] || !JSONInteger(value[@"id"]) || [value[@"id"] longLongValue] <= 0))
                    error = SaveError(@"RomM did not confirm a compatible backup. Local saves are retained.");
                if (!error) @synchronized(self) {
                    if ([self isCurrent:config]) { self.state[@"uploaded"][name] = hash; [self persist:&error]; }
                }
            }
            BOOL moreWork = NO;
            @synchronized(self) {
                self.backupQueued = NO;
                if ([self isCurrent:config]) {
                    for (NSString *name in RTVSaveNames()) {
                        NSData *latest = Unpack(self.state[@"current"][name]);
                        if (latest && RTVValidSave(name, latest) && ![self.state[@"deleted"][name] boolValue] &&
                            ![self.state[@"uploaded"][name] isEqual:Hash(latest)]) moreWork = YES;
                    }
                    self.message = error ? error.localizedDescription : moreWork ? @"New saves are waiting for backup." :
                        savedCount ? @"Saved locally and backed up to RomM." : @"Connected to RomM. Make a game save to start backups.";
                }
            }
            if (moreWork && !error) [self backupNow];
        }
    }];
}
- (void)listBackups:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    [self.queue addOperationWithBlock:^{
        @autoreleasepool {
            NSDictionary *config; NSString *token;
            @synchronized(self) { config = [self.state[@"config"] copy]; token = [self.credentials readToken]; }
            NSError *error = nil;
            NSMutableArray *backups = [NSMutableArray array];
            if (!config || !token.length) error = SaveError(@"Set up RomM backups first.");
            NSData *data = error ? nil : Request(config, token, @"GET", @"api/saves", @{@"rom_id":config[@"rom"]}, nil, nil, &error);
            id items = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (data && ![items isKindOfClass:NSArray.class]) error = SaveError(@"RomM returned an unreadable backup list.");
            if (!error) for (id item in items) {
                if (![item isKindOfClass:NSDictionary.class] || ![item[@"rom_id"] isEqual:config[@"rom"]] ||
                    ![item[@"emulator"] isEqual:Emulator] || !JSONInteger(item[@"id"]) || [item[@"id"] longLongValue] <= 0 ||
                    ![item[@"slot"] isKindOfClass:NSString.class] ||
                    (item[@"missing_from_fs"] && (![item[@"missing_from_fs"] isKindOfClass:NSNumber.class] || [item[@"missing_from_fs"] boolValue]))) continue;
                NSString *slot = item[@"slot"];
                if (![slot hasPrefix:@"recomptv-"]) continue;
                NSString *name = [[slot substringFromIndex:9] stringByAppendingString:@".sav"];
                if (![RTVSaveNames() containsObject:name]) continue;
                NSString *date = [item[@"created_at"] isKindOfClass:NSString.class] ? item[@"created_at"] : @"";
                [backups addObject:@{@"id":item[@"id"], @"name":name, @"date":date, @"configID":config[@"id"]}];
            }
            [backups sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"id"] compare:a[@"id"]]; }];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error ? nil : backups, error); });
        }
    }];
}
- (void)stageRestore:(NSDictionary *)backup completion:(void (^)(NSError *))completion {
    [self.queue addOperationWithBlock:^{
        @autoreleasepool {
            NSDictionary *config; NSString *token;
            @synchronized(self) { config = [self.state[@"config"] copy]; token = [self.credentials readToken]; }
            NSError *error = nil;
            NSString *name = backup[@"name"];
            if (!config || !token.length || ![backup[@"configID"] isEqual:config[@"id"]] ||
                ![RTVSaveNames() containsObject:name] || !JSONInteger(backup[@"id"]) || [backup[@"id"] longLongValue] <= 0)
                error = SaveError(@"The backup selection expired. Refresh the backup list.");
            NSString *path = [NSString stringWithFormat:@"api/saves/%lld/content", [backup[@"id"] longLongValue]];
            NSData *data = error ? nil : Request(config, token, @"GET", path, @{}, nil, nil, &error);
            if (data && !RTVValidSave(name, data)) error = SaveError(@"This is not a compatible Shipwright save. Local saves were kept.");
            if (!error) @synchronized(self) {
                if (![self isCurrent:config]) error = SaveError(@"RomM setup changed. Choose the backup again.");
                else {
                    self.state[@"pending"][name] = Pack(data);
                    if ([self persist:&error]) self.message = @"Backup downloaded. Restart the game to restore it; the current save will be preserved.";
                    else [self.state[@"pending"] removeObjectForKey:name];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }
    }];
}
- (BOOL)stageUndo:(NSString *)name error:(NSError **)error {
    @synchronized(self) {
        NSData *previous = Unpack(self.state[@"beforeRestore"][name]);
        if (!previous || !RTVValidSave(name, previous)) return Fail(error, @"There is no previous restored save for this slot.");
        self.state[@"pending"][name] = Pack(previous);
        if (![self persist:error]) { [self.state[@"pending"] removeObjectForKey:name]; return NO; }
        self.message = @"Previous save selected. Restart the game to restore it.";
        return YES;
    }
}
- (void)waitForBackups { [self.queue waitUntilAllOperationsAreFinished]; }
@end
