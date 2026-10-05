#pragma once
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

/// Manages form monitoring, sign-in detection, credential submission capture,
/// framework-safe autofill, passkey suppression, typing state, and fullscreen detection.
///
/// Direct translation of FormRelay into Objective-C++.
@interface SlateFormRelay : NSObject

/// Script message handler name: "officeForms"
@property (class, readonly, copy, nonnull) NSString* messageName;

/// Whether sites are offered passkeys (Settings › Passwords).
/// When false, PublicKeyCredential is hidden so sites smoothly fall back
/// to standard password authentication rather than getting stuck.
@property (class, nonatomic) BOOL passkeysOffered;

/// JavaScript to suppress broken passkey requests when the app lacks Apple's browser entitlement.
/// Injected at document start in pageWorld.
+ (nonnull NSString *)withoutPasskeysScript;

/// Main form relay JavaScript. Monitors sign-in inputs, submissions, in-place logins (settled),
/// caret position/typing state, and imminent fullscreen transitions.
/// Injected at document end in defaultClientWorld.
+ (nonnull NSString *)formScript;

/// Generates JavaScript to autofill the active sign-in form using the native
/// HTMLInputElement property descriptor setter, ensuring React, Vue, Angular,
/// and other frameworks recognize the value changes and enable submit buttons.
+ (nonnull NSString *)fillScriptWithUser:(nonnull NSString *)username password:(nonnull NSString *)password;

/// JavaScript to check if the current page still has a password box.
+ (nonnull NSString *)hasPasswordScript;

/// JavaScript to check if any form on the page contains user-typed unsaved content.
+ (nonnull NSString *)unsavedScript;

@end
