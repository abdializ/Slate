#pragma once
#import <Cocoa/Cocoa.h>

/// The unified palette for Slate panels and cards, matching the reference design:
/// ground, hairline, ink, muted, faint, wash, accent.
@interface SlatePalette : NSObject
+ (NSColor*)ground;
+ (NSColor*)hairline;
+ (NSColor*)ink;
+ (NSColor*)muted;
+ (NSColor*)faint;
+ (NSColor*)wash;
+ (NSColor*)accent;
@end

/// The close button ("Door"): cross "xmark", help "Done   esc", smooth hover wash.
@interface SlatePlateDoorButton : NSButton
@property (nonatomic, copy) void (^actionBlock)(void);
+ (instancetype)doorWithAction:(void(^)(void))action;
@end

/// The hairline between two lines of a card, inset like the text.
@interface SlateRuleView : NSView
@property (nonatomic, assign) CGFloat inset;
+ (instancetype)ruleWithInset:(CGFloat)inset;
@end

/// A small heading over a card, for when a panel has more than one.
@interface SlateCaptionLabel : NSTextField
+ (instancetype)captionWithText:(NSString*)text;
@end

/// What a panel says when its list is empty.
@interface SlateNothingView : NSTextField
+ (instancetype)nothingWithText:(NSString*)text;
@end

/// A small text action inside a row — Show, Copy, Remove, Reset (Palette.wash in Capsule).
@interface SlateQuickButton : NSButton
@property (nonatomic, copy) void (^actionBlock)(void);
@property (nonatomic, strong) NSColor* tintColor;
+ (instancetype)quickWithTitle:(NSString*)title action:(void(^)(void))action;
+ (instancetype)quickWithTitle:(NSString*)title tint:(NSColor*)tint action:(void(^)(void))action;
@end

/// The field for narrowing a list. The wash, the glass, the caret (Hunt).
@interface SlateHuntField : NSView <NSTextFieldDelegate>
@property (nonatomic, strong) NSTextField* textField;
@property (nonatomic, copy) NSString* prompt;
@property (nonatomic, copy) void (^onTextChanged)(NSString* query);
@property (nonatomic, copy) NSString* text;
- (void)focus;
@end

/// One thing to set or do: what it is on the left, the control on the right.
@interface SlateLineView : NSView
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, strong) NSTextField* detailLabel;
@property (nonatomic, strong) NSView* controlView;
- (instancetype)initWithTitle:(NSString*)title detail:(NSString*)detail control:(NSView*)control;
- (instancetype)initWithTitle:(NSString*)title detail:(NSString*)detail control:(NSView*)control width:(CGFloat)width;
@end

/// A group of lines in one hairline box (Card).
@interface SlateCardView : NSView
- (void)setLines:(NSArray<SlateLineView*>*)lines;
- (void)addLine:(SlateLineView*)line;
@end

/// The plate: a rounded card with a title, a cross, whatever the panel is about,
/// and — when there is one — a foot below a hairline.
@interface SlatePlateView : NSView
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, strong) SlatePlateDoorButton* doorButton;
@property (nonatomic, strong) NSView* contentArea;
@property (nonatomic, strong) NSView* footArea;
@property (nonatomic, copy) void (^onClose)(void);

- (instancetype)initWithTitle:(NSString*)title width:(CGFloat)width close:(void(^)(void))close;
- (void)setContent:(NSView*)contentView;
- (void)setFoot:(NSView*)footView;
@end
