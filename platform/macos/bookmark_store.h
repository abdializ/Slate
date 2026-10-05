#pragma once
#include "core/library.h"
#include <memory>
#include <string>

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>

/// A single bookmark node in the tree: either a site (with url) or a folder (with children).
@interface SlateBookmark : NSObject <NSCopying>
@property (nonatomic, copy) NSString* identifier;
@property (nonatomic, copy) NSString* title;
@property (nonatomic, copy) NSString* url; // nil or empty for a folder
@property (nonatomic, strong) NSMutableArray<SlateBookmark*>* children; // nil for a site

@property (nonatomic, readonly) BOOL isFolder;
@property (nonatomic, readonly) NSString* host;

+ (instancetype)siteWithTitle:(NSString*)title url:(NSString*)url;
+ (instancetype)folderWithTitle:(NSString*)title children:(NSArray<SlateBookmark*>*)children;

- (NSDictionary*)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary*)dict;
@end

/// Notification posted whenever bookmarks change (added, removed, moved, imported).
extern NSNotificationName const SlateBookmarksChangedNotification;

/// The central bookmarks store managing roots, persistence, and tree manipulations.
@interface SlateBookmarks : NSObject
@property (nonatomic, copy) NSArray<SlateBookmark*>* roots;
@property (nonatomic, readonly) BOOL isEmpty;
@property (nonatomic, readonly) NSUInteger count;

+ (instancetype)sharedStore;

+ (NSUInteger)countNodes:(NSArray<SlateBookmark*>*)nodes;
+ (NSArray<NSString*>*)urlsForNodes:(NSArray<SlateBookmark*>*)nodes;
+ (NSArray<NSDictionary*>*)foldersForNodes:(NSArray<SlateBookmark*>*)nodes depth:(NSInteger)depth;
+ (BOOL)node:(SlateBookmark*)node holdsIdentifier:(NSString*)identifier;

- (BOOL)containsURL:(NSString*)urlString;
- (SlateBookmark*)findURL:(NSString*)urlString;
- (SlateBookmark*)findNodeWithIdentifier:(NSString*)identifier;
- (void)addURL:(NSString*)urlString title:(NSString*)title;
- (void)removeWithIdentifier:(NSString*)identifier;
- (void)moveWithIdentifier:(NSString*)identifier intoFolderWithIdentifier:(NSString*)folderID;
- (void)takeNodes:(NSArray<SlateBookmark*>*)nodes fromBrowserNamed:(NSString*)name;
- (SlateBookmark*)insertNode:(SlateBookmark*)node intoParent:(NSString*)parentID;
- (void)updateWithIdentifier:(NSString*)identifier title:(NSString*)title url:(NSString*)url;

- (void)loadFromPath:(NSString*)path;
- (void)saveToPath:(NSString*)path;
- (void)load;
- (void)save;

// C++ bridge methods for backward compatibility
- (void)syncToBookmarkList:(slate::BookmarkList&)list;
- (void)syncFromBookmarkList:(const slate::BookmarkList&)list;
@end
#endif

namespace slate {
std::unique_ptr<BookmarkList> load_bookmarks(const std::string& path);
void save_bookmarks(const std::string& path, const BookmarkList& list);
}
