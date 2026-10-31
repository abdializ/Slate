#pragma once
#import <Cocoa/Cocoa.h>
#include "core/browser_engine.h"

// A presentation of existing tabs. Asking for a preview must never load a page.
@interface SlateTabPreview : NSObject
@property slate::TabId identifier;
@property slate::TabId partner;
@property(copy) NSString* title;
@property(copy) NSString* address;
@property(strong) NSImage* icon;
@property BOOL muted;
@property BOOL moon;
@property CGFloat screens;
@end

@protocol SlateTabSwitcherOwner <NSObject>
- (SlateTabPreview*)switcherTab:(slate::TabId)identifier;
- (void)switcherPreview:(slate::TabId)identifier completion:(void(^)(NSImage* image))completion;
- (void)switcherPick:(slate::TabId)identifier;
- (void)switcherAction:(unichar)action tab:(slate::TabId)identifier;
@end

@interface SlateTabSwitcher : NSObject
@property(weak) id<SlateTabSwitcherOwner> owner;
@property(readonly) BOOL active;
@property(readonly) BOOL visible;
@property(readonly) slate::TabId selected;
- (void)useSpace:(NSString*)space;
- (void)leftTab:(slate::TabId)identifier alive:(NSArray<NSNumber*>*)alive;
- (void)beginInWindow:(NSWindow*)window cards:(NSArray<NSNumber*>*)cards moons:(NSArray<NSNumber*>*)moons current:(slate::TabId)current fromMoon:(BOOL)fromMoon backwards:(BOOL)backwards;
- (BOOL)handleEvent:(NSEvent*)event;
- (void)removeTab:(slate::TabId)identifier;
- (void)cancel;
@end
