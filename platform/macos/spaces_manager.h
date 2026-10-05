#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface SlateSpace : NSObject

@property (nonatomic, copy) NSString* identifier;
@property (nonatomic, copy) NSString* name;
@property (nonatomic, assign) NSInteger colour;
@property (nonatomic, copy) NSString* icon;
@property (nonatomic, assign) BOOL sharesSignIns;
@property (nonatomic, copy) NSString* downloads;

+ (NSString*)firstSpaceIdentifier;
- (BOOL)isFirst;
- (NSString*)symbol;

- (NSDictionary*)dictionaryRepresentation;
+ (instancetype)fromDictionary:(NSDictionary*)dict;

@end

@interface SlateSpacesManager : NSObject

@property (nonatomic, strong, readonly) NSMutableArray<SlateSpace*>* spaces;
@property (nonatomic, copy) NSString* currentSpaceId;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString*, NSMutableArray<NSDictionary*>*>* parkedTabs;

+ (instancetype)sharedManager;

- (SlateSpace*)currentSpace;
- (SlateSpace*)spaceForIdentifier:(NSString*)identifier;
- (NSInteger)indexOfSpace:(NSString*)identifier;

- (SlateSpace*)addSpaceNamed:(NSString*)name icon:(NSString*)icon sharesSignIns:(BOOL)sharesSignIns;
- (BOOL)deleteSpace:(NSString*)identifier;
- (void)renameSpace:(NSString*)identifier toName:(NSString*)name;
- (void)setSpaceIcon:(NSString*)identifier icon:(NSString*)icon;
- (void)setSpaceDownloads:(NSString*)identifier folder:(NSString*)folder;
- (void)moveSpace:(NSString*)identifier toIndex:(NSInteger)toIndex;

- (WKWebsiteDataStore*)dataStoreForSpace:(SlateSpace*)space;
- (void)eraseStoreForSpaceId:(NSString*)identifier;

- (NSString*)freeIcon;
+ (NSArray<NSString*>*)availableIcons;
+ (NSArray<NSString*>*)availableIconNames;

- (void)loadSpaces;
- (void)saveSpaces;

@end
