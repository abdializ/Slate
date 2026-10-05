#pragma once
#import <AppKit/AppKit.h>

@class SlateOmniboxCard;
@class SlateOmniboxOverlay;

static const CGFloat kFieldWidth = 560.0;
static const CGFloat kFieldHeight = 52.0;
static const CGFloat kCornerRadius = 26.0;

@protocol SlateOmniboxDelegate <NSObject>
- (void)showSuggestionsForCard:(nonnull SlateOmniboxCard*)card query:(nonnull NSString*)query;
- (void)submitOmniboxCard:(nonnull SlateOmniboxCard*)card;
- (void)moveSuggestionDelta:(NSInteger)delta;
- (void)hideSuggestions;
@optional
- (void)showSuggestionsForOverlay:(nonnull NSString*)query;
- (void)submitOverlay:(nonnull SlateOmniboxOverlay*)overlay;
- (void)omniboxOverlayDidDismiss:(nonnull SlateOmniboxOverlay*)overlay;
@end

/// The unified Omnibox field card (Arc / Dia style).
/// Width: 540pt, Height: 50pt, Continuous corner radius 25pt.
@interface SlateOmniboxCard : NSView <NSTextFieldDelegate>

@property (nonatomic, weak, nullable) id<SlateOmniboxDelegate> delegate;
@property (nonatomic, strong, nonnull) NSTextField* field;
@property (nonatomic, copy, nullable) NSString* placeholder;
@property (nonatomic, strong, nullable) NSColor* accentColor;
@property (nonatomic, strong, nullable) NSColor* inkColor;
@property (nonatomic) BOOL isDarkTheme;
@property (nonatomic) BOOL customDarkSet;

- (nonnull instancetype)initWithDelegate:(nullable id<SlateOmniboxDelegate>)delegate;
- (void)shake;
- (void)applyTheme;

@end

/// Floating center Omnibox overlay raised over an active web page by ⌘L.
/// Encapsulates a SlateOmniboxCard inside a 0.74 opacity scrim backdrop.
@interface SlateOmniboxOverlay : NSView

@property (nonatomic, weak, nullable) id<SlateOmniboxDelegate> delegate;
@property (nonatomic, strong, nonnull) NSView* backdrop;
@property (nonatomic, strong, nonnull) SlateOmniboxCard* card;
@property (nonatomic, readonly) BOOL isShowing;
@property (nonatomic, readonly, nonnull) NSTextField* field;
@property (nonatomic, readonly, nonnull) NSView* fieldCard;

- (nonnull instancetype)initWithDelegate:(nonnull id<SlateOmniboxDelegate>)delegate;
- (void)showOver:(nonnull NSView*)container initialText:(nullable NSString*)text;
- (void)dismiss;
- (void)shake;
- (void)applyTheme;

@end
