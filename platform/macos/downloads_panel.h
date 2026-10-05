#pragma once
#import <Cocoa/Cocoa.h>
#import "platform/macos/download_manager.h"

@class SlateDelegate;

@interface SlateDownloadButton : NSView

@property (nonatomic, weak) SlateDelegate* owner;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL hovered;
@property (nonatomic, assign) CGFloat progress;
@property (nonatomic, assign) BOOL hasActiveDownloads;
@property (nonatomic, strong) NSColor* barInk;
@property (nonatomic, strong) NSColor* barMuted;
@property (nonatomic, strong) NSColor* accentInk;

- (void)updateStatus;

@end

@interface SlateDownloadsPanel : NSPanel <NSTableViewDataSource, NSTableViewDelegate>

+ (instancetype)sharedPanel;

@property (nonatomic, weak) SlateDelegate* owner;
@property (nonatomic, strong) NSColor* barColor;
@property (nonatomic, strong) NSColor* barInk;
@property (nonatomic, strong) NSColor* barMuted;
@property (nonatomic, strong) NSColor* accentInk;

- (void)toggleForButton:(NSView*)anchor inWindow:(NSWindow*)window;
- (void)showForButton:(NSView*)anchor inWindow:(NSWindow*)window;
- (void)hidePanel;
- (void)refreshList;

@end
