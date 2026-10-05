#pragma once
#import <AppKit/AppKit.h>

// ─── Known Players ──────────────────────────────────────────────────────────

/// Sites with a player worth following into the little window.
///
/// Anywhere else, a playing video is as likely to be a background as a film,
/// and the difference isn't something a script can tell from the outside.
@interface SlateKnownPlayers : NSObject
+ (BOOL)knowsURL:(NSURL * _Nullable)url;
@end

// ─── Isolate (JavaScript) ───────────────────────────────────────────────────

/// Everything but the video, out of the way. Visibility is inherited, so
/// hiding the body and turning it back on for the video alone leaves the
/// player's own machinery running untouched — which is what keeps the
/// stream alive where cutting the DOM about would kill it.
@interface SlateIsolate : NSObject
+ (NSString * _Nonnull)on;
+ (NSString * _Nonnull)off;
+ (NSString * _Nonnull)toggle;
+ (NSString * _Nonnull)where_;
+ (NSString * _Nonnull)skip:(double)seconds;
+ (NSString * _Nonnull)seek:(double)ratio;
@end

// ─── Float ──────────────────────────────────────────────────────────────────

/// A video that keeps playing after you have gone somewhere else, in a small
/// window that stays above everything — other tabs, and other apps.
///
/// The engine is not asked. The page itself is moved: everything but the
/// video is made invisible, the video is stretched to fill the viewport,
/// and the whole web view is lifted out of the window and into a small
/// floating one. The video never stops, because it is the same page it
/// always was — it has only changed windows.
@interface SlateFloat : NSObject

/// Asked to go away. The browser does the bookkeeping and calls back into
/// `drop`.
@property (nonatomic, copy, nullable) void (^onClose)(void);
/// Bring the window forward and go to the tab it came from.
@property (nonatomic, copy, nullable) void (^onReturn)(void);
/// Stop or start the video. Answers with whether it is playing now.
@property (nonatomic, copy, nullable) void (^onPlayPause)(void (^ _Nonnull)(BOOL playing));
/// Step over the bit you missed, or back to it.
@property (nonatomic, copy, nullable) void (^onSkip)(double seconds);
/// Seek to a fractional position (0.0 to 1.0) in the video.
@property (nonatomic, copy, nullable) void (^onSeek)(double ratio);
/// Asked every half second while the window is up, for the line along the
/// bottom edge.
@property (nonatomic, copy, nullable) void (^onProgress)(void (^ _Nonnull)(double through, BOOL playing));

@property (nonatomic, readonly) BOOL showing;

/// Two fingers flick the window to a corner instead of pushing it along.
/// Off unless asked for.
@property (class, nonatomic) BOOL flicks;

+ (NSPoint)cornerForFrame:(NSRect)frame
                    inArea:(NSRect)area
                    toward:(CGVector)way
                    margin:(CGFloat)margin;

+ (NSPoint)cornerForFrame:(NSRect)frame
                    inArea:(NSRect)area
                    toward:(CGVector)way;

- (void)lift:(NSView * _Nonnull)page;
- (void)drop;

@end
