#pragma once
#import <Cocoa/Cocoa.h>
#import "platform/macos/bookmark_store.h"

@protocol SlateBookmarksOwner <NSObject>
- (void)openHomeAddress:(NSString*)address;
- (void)toggleBookmark:(id)sender;
@end

/// The interactive tree outline for bookmarks, supporting inline folder expansion,
/// drag-and-drop hierarchy reorganization, and rich context menus.
@interface SlateBookmarkOutlineView : NSView <NSDraggingSource, NSDraggingDestination>
@property (nonatomic, copy) void (^onOpenURL)(NSURL* url);
@property (nonatomic, copy) void (^onStructureChanged)(void);
- (void)reloadData;
@end

/// The button's dropdown: a compact 280pt floating menu panel showing the bookmarks tree
/// and foot actions ("Add This Page", "Manage Bookmarks…").
@interface SlateBookmarksDropdown : NSPanel
+ (instancetype)sharedDropdown;
+ (BOOL)isShown;
+ (void)hide;

@property (nonatomic, weak) id<SlateBookmarksOwner> owner;

- (void)showForAnchor:(NSView*)anchor inWindow:(NSWindow*)window;
- (void)toggleForAnchor:(NSView*)anchor inWindow:(NSWindow*)window;
- (void)hideDropdown;
- (void)refresh;
@end

/// The full Bookmarks manager modal/window plate (width 600pt) for viewing, reorganizing,
/// and importing bookmarks from installed browsers.
@interface SlateBookmarksPanel : NSPanel
+ (instancetype)sharedPanel;
+ (BOOL)isShown;

@property (nonatomic, weak) id<SlateBookmarksOwner> owner;

- (void)showBookmarksManager;
- (void)hidePanel;
- (void)refresh;
@end

/// Dynamic menu builder for Bookmarks bar folder popups and macOS menu bar items.
@interface SlateBookmarkMenu : NSObject <NSMenuDelegate>
+ (void)popUpFolder:(SlateBookmark*)folder forView:(NSView*)view owner:(id)owner;
+ (void)populateMenu:(NSMenu*)menu withBookmarks:(SlateBookmarks*)store owner:(id)owner;
@end
