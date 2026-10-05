#pragma once

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class SlateDelegate;

@interface SlateFindBar : NSVisualEffectView <NSTextFieldDelegate>

@property (nonatomic, weak) SlateDelegate* owner;
@property (nonatomic, weak) WKWebView* targetWebView;
@property (nonatomic, strong) NSTextField* searchField;
@property (nonatomic, strong) NSTextField* countLabel;
@property (nonatomic, strong) NSButton* prevButton;
@property (nonatomic, strong) NSButton* nextButton;
@property (nonatomic, strong) NSButton* closeButton;
@property (nonatomic, assign) NSInteger currentMatchIndex;
@property (nonatomic, assign) NSInteger totalMatches;
@property (nonatomic, copy) NSString* lastQuery;
@property (nonatomic, assign) BOOL isVisible;

- (instancetype)initWithOwner:(SlateDelegate*)owner;
- (void)showInView:(NSView*)containerView initialQuery:(NSString*)query;
- (void)hideAnimated;
- (void)findNext;
- (void)findPrevious;
- (void)performSearchWithQuery:(NSString*)query;
- (void)clearHighlights;
- (void)syncWithWebView:(WKWebView*)webView;

@end
