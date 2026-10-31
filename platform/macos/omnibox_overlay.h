#pragma once
#import <AppKit/AppKit.h>

@class SlateOmniboxCard, SlateOmniboxOverlay;
static const CGFloat kFieldWidth=560.0;
static const CGFloat kFieldHeight=50.0;
static const CGFloat kCornerRadius=14.0;

NSColor* _Nonnull SlateOmniboxGround(NSAppearance* _Nonnull appearance);
NSColor* _Nonnull SlateOmniboxInk(NSAppearance* _Nonnull appearance);
NSColor* _Nonnull SlateOmniboxHairline(NSAppearance* _Nonnull appearance);
BOOL SlateOmniboxReducedMotion(void);

@protocol SlateOmniboxDelegate <NSObject>
- (void)showSuggestionsForCard:(nonnull SlateOmniboxCard*)card query:(nonnull NSString*)query;
- (void)submitOmniboxCard:(nonnull SlateOmniboxCard*)card;
- (void)moveSuggestionDelta:(NSInteger)delta;
- (void)hideSuggestions;
@optional
- (nullable NSString*)completionForCard:(nullable SlateOmniboxCard*)card query:(nonnull NSString*)query;
- (void)showSuggestionsForOverlay:(nonnull NSString*)query;
- (void)submitOverlay:(nonnull SlateOmniboxOverlay*)overlay;
- (void)omniboxOverlayDidDismiss:(nonnull SlateOmniboxOverlay*)overlay;
@end

// AppKit counterparts of Omnibox.field, AddressField and SiteChip in the
// supplied reference. Suggestions are anchored separately below this view.
@interface SlateOmniboxCard : NSView <NSTextFieldDelegate>
@property(nonatomic,weak,nullable) id<SlateOmniboxDelegate> delegate;
@property(nonatomic,strong,nonnull) NSTextField* field;
@property(nonatomic,copy,nullable) NSDictionary<NSString*,NSString*>* searchSite;
@property(nonatomic,copy,nullable) NSDictionary<NSString*,NSString*>* suggestedSite;
@property(nonatomic,copy,nullable) NSString* placeholder;
@property(nonatomic,strong,nullable) NSColor* accentColor;
@property(nonatomic,strong,nullable) NSColor* inkColor;
@property(nonatomic) BOOL isDarkTheme;
@property(nonatomic) BOOL customDarkSet;
@property(nonatomic,readonly,nonnull) NSString* typedText;
@property(nonatomic,readonly) BOOL hasCompletion;
- (nonnull instancetype)initWithDelegate:(nullable id<SlateOmniboxDelegate>)delegate;
- (void)setText:(nonnull NSString*)text selectAll:(BOOL)all;
- (void)focusSelectingAll:(BOOL)all;
- (void)activateSite:(nonnull NSDictionary<NSString*,NSString*>*)site;
- (void)shake;
- (void)applyTheme;
@end

@interface SlateOmniboxStack : NSStackView
@end

// Hover never changes the keyboard's selection or the address field.
@interface SlateOmniboxRow : NSView
@property(nonatomic) BOOL highlighted;
@property(nonatomic,readonly) BOOL hovering;
- (nonnull instancetype)initWithTitle:(nonnull NSString*)title detail:(nullable NSString*)detail
 kind:(nonnull NSString*)kind image:(nullable NSImage*)image action:(nonnull dispatch_block_t)action;
@end

@interface SlateOmniboxOverlay : NSView
@property(nonatomic,weak,nullable) id<SlateOmniboxDelegate> delegate;
@property(nonatomic,strong,nonnull) NSView* backdrop;
@property(nonatomic,strong,nonnull) SlateOmniboxCard* card;
@property(nonatomic,readonly) BOOL isShowing;
@property(nonatomic,readonly,nonnull) NSTextField* field;
@property(nonatomic,readonly,nonnull) NSView* fieldCard;
- (nonnull instancetype)initWithDelegate:(nonnull id<SlateOmniboxDelegate>)delegate;
- (void)showOver:(nonnull NSView*)container initialText:(nullable NSString*)text;
- (void)dismiss;
- (void)shake;
- (void)applyTheme;
@end
