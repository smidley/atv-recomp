#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The game adapter and the host tests use the same storage/network implementation.
// Credentials are deliberately kept out of preferences, save files, and diagnostics.
@protocol RTVSaveCredentials <NSObject>
- (nullable NSString *)readToken;
- (BOOL)writeToken:(NSString *)token;
@end

@interface RTVKeychainSaveCredentials : NSObject <RTVSaveCredentials>
- (instancetype)initWithAccount:(NSString *)account;
@end

@interface RTVSaveStore : NSObject
- (instancetype)initWithRoot:(NSString *)root defaults:(NSUserDefaults *)defaults
                 credentials:(id<RTVSaveCredentials>)credentials;
- (BOOL)prepareLocalFiles:(NSError **)error;
- (BOOL)recordSave:(NSString *)name data:(NSData *)data error:(NSError **)error;
- (BOOL)deleteSave:(NSString *)name error:(NSError **)error;
- (BOOL)configureGameURL:(NSString *)url token:(NSString *)token allowHTTP:(BOOL)allowHTTP error:(NSError **)error;
- (void)disconnect;
- (void)backupNow;
- (NSString *)status;
- (NSString *)gameURL;
- (void)listBackups:(void (^)(NSArray<NSDictionary *> * _Nullable, NSError * _Nullable))completion;
- (void)stageRestore:(NSDictionary *)backup completion:(void (^)(NSError * _Nullable))completion;
- (BOOL)stageUndo:(NSString *)name error:(NSError **)error;
// A bounded wait for tests/shutdown only; never used by a render callback.
- (void)waitForBackups;
@end

BOOL RTVValidSave(NSString *name, NSData *data);
NSArray<NSString *> *RTVSaveNames(void);
NS_ASSUME_NONNULL_END
