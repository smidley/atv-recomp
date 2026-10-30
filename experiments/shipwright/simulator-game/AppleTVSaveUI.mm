#import "AppleTVSaveStore.h"
#import <UIKit/UIKit.h>
#include "AppleTVGameplay.h"
#include <cstdio>

static RTVSaveStore *store;
static NSString *startupError;

void RecompTVInitializeSaveStorage(const char* root) {
    store = [[RTVSaveStore alloc] initWithRoot:@(root) defaults:NSUserDefaults.standardUserDefaults credentials:[RTVKeychainSaveCredentials new]];
    NSError *error = nil;
    if (![store prepareLocalFiles:&error]) {
        startupError = error.localizedDescription;
        fprintf(stderr, "[RecompTV Saves] Local recovery needs attention.\n");
    }
}
void RecompTVSaveWritten(const std::filesystem::path& path, const std::string& contents) {
    if (path.parent_path().filename() != "Save") return;
    @autoreleasepool {
        [store recordSave:@(path.filename().c_str()) data:[NSData dataWithBytes:contents.data() length:contents.size()] error:nil];
    }
}
bool RecompTVDeleteSave(const std::filesystem::path& path) {
    return path.parent_path().filename() == "Save" && [store deleteSave:@(path.filename().c_str()) error:nil];
}
void RecompTVBackupNow() { [store backupNow]; }

static UIViewController *Presenter() {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) {
            UIViewController *controller = window.rootViewController;
            while (controller.presentedViewController) controller = controller.presentedViewController;
            return controller;
        }
    }
    return nil;
}
static void Present(UIAlertController *alert) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = Presenter();
        if ([presenter isKindOfClass:UIAlertController.class]) {
            // A follow-up prompt must wait for the current alert to dismiss.
            [presenter dismissViewControllerAnimated:YES completion:^{
                [Presenter() presentViewController:alert animated:YES completion:nil];
            }];
        } else [presenter presentViewController:alert animated:YES completion:nil];
    });
}
static UIAlertController *Alert(NSString *title, NSString *message) {
    return [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
}
static void Message(NSString *title, NSString *message) {
    UIAlertController *alert = Alert(title, message);
    [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    Present(alert);
}
void RecompTVShowBackupStatus() { Message(@"Save backups", startupError ?: [store status]); }

static void AskToken(NSString *address, BOOL allowHTTP) {
    UIAlertController *alert = Alert(@"RomM client API token", @"Use a token with assets.read and assets.write permissions. It will be stored securely in this game's Keychain.");
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Client API token";
        field.secureTextEntry = YES;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak UIAlertController *weak = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Connect and back up" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSError *error = nil;
        NSString *token = weak.textFields.firstObject.text ?: @"";
        if (![store configureGameURL:address token:token allowHTTP:allowHTTP error:&error]) Message(@"Backup setup", error.localizedDescription);
        else Message(@"Backup setup", @"Local saves will be backed up in the background. Use Backup status to check the connection.");
        weak.textFields.firstObject.text = @"";
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    Present(alert);
}
void RecompTVShowBackupSetup() {
    UIAlertController *alert = Alert(@"RomM save backups", @"Paste this game's page address from RomM, ending in /rom/123. Use the same ROM edition as this game. These backups use Shipwright's save format.");
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"https://romm.example/rom/123";
        field.text = [store gameURL];
        field.keyboardType = UIKeyboardTypeURL;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak UIAlertController *weak = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *address = [weak.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if ([[NSURLComponents componentsWithString:address].scheme.lowercaseString isEqual:@"http"]) {
            UIAlertController *warning = Alert(@"Allow local HTTP?", @"This connection sends your token and saves without encryption. Allow it only for your trusted local RomM server.");
            [warning addAction:[UIAlertAction actionWithTitle:@"Allow local HTTP" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { AskToken(address, YES); }]];
            [warning addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            Present(warning);
        } else AskToken(address, NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    Present(alert);
}
static NSString *SlotLabel(NSString *name) {
    if ([name isEqual:@"global.sav"]) return @"Game preferences";
    return [NSString stringWithFormat:@"Save slot %@", [name substringWithRange:NSMakeRange(4, 1)]];
}
static void ShowVersions(NSArray<NSDictionary *> *backups, NSString *name, NSUInteger offset) {
    NSArray *matches = [backups filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) { return [item[@"name"] isEqual:name]; }]];
    UIAlertController *alert = Alert(SlotLabel(name), @"Select a backup. Restoration happens on the next launch, and keeps a copy of the current save.");
    for (NSUInteger i = offset; i < MIN(offset + 8, matches.count); ++i) {
        NSDictionary *backup = matches[i];
        NSISO8601DateFormatter *parser = [NSISO8601DateFormatter new];
        parser.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        NSDate *date = [parser dateFromString:backup[@"date"]];
        if (!date) {
            parser.formatOptions = NSISO8601DateFormatWithInternetDateTime;
            date = [parser dateFromString:backup[@"date"]];
        }
        NSString *label = date ? [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle] :
            [NSString stringWithFormat:@"Backup %@", backup[@"id"]];
        [alert addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            UIAlertController *confirm = Alert(@"Restore this backup?", @"After downloading, close and reopen the game to use this backup. The current save will be kept as a recovery copy. You can undo the restore in these settings.");
            [confirm addAction:[UIAlertAction actionWithTitle:@"Download for next launch" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [store stageRestore:backup completion:^(NSError *error) { Message(@"Restore backup", error ? error.localizedDescription : [store status]); }];
            }]];
            [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            Present(confirm);
        }]];
    }
    if (matches.count > offset + 8) [alert addAction:[UIAlertAction actionWithTitle:@"Older backups" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { ShowVersions(backups, name, offset + 8); }]];
    if (!matches.count) alert.message = @"No backups for this slot yet.";
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    Present(alert);
}
void RecompTVShowRestoreBackups() {
    [store listBackups:^(NSArray<NSDictionary *> *backups, NSError *error) {
        if (error) { Message(@"Restore backup", error.localizedDescription); return; }
        UIAlertController *alert = Alert(@"Restore from RomM", @"Choose a slot to see its saved versions.");
        for (NSString *name in RTVSaveNames()) [alert addAction:[UIAlertAction actionWithTitle:SlotLabel(name) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { ShowVersions(backups, name, 0); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        Present(alert);
    }];
}
void RecompTVShowUndoRestore() {
    UIAlertController *alert = Alert(@"Undo last restore", @"Select the slot to recover its save from before the last restore. The change takes effect next launch.");
    for (NSString *name in RTVSaveNames()) [alert addAction:[UIAlertAction actionWithTitle:SlotLabel(name) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSError *error = nil;
        BOOL ok = [store stageUndo:name error:&error];
        Message(@"Undo restore", ok ? [store status] : error.localizedDescription);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    Present(alert);
}
void RecompTVDisconnectBackups() {
    UIAlertController *alert = Alert(@"Disconnect RomM backups?", @"Local saves and existing backups on RomM will be kept.");
    [alert addAction:[UIAlertAction actionWithTitle:@"Disconnect" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [store disconnect]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    Present(alert);
}
void RecompTVInstallLifecycleObservers() {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationWillResignActiveNotification, UISceneWillDeactivateNotification,
                                      UIApplicationDidEnterBackgroundNotification, UISceneDidEnterBackgroundNotification,
                                      UIApplicationWillTerminateNotification])
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { RecompTVSetGameplayActive(false); }];
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UISceneDidActivateNotification])
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { RecompTVSetGameplayActive(true); }];
}
