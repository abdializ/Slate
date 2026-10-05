#import "spaces_manager.h"

static NSString* const kFirstSpaceUUID = @"00000000-0000-0000-0000-000000000001";

@implementation SlateSpace

+ (NSString*)firstSpaceIdentifier {
    return kFirstSpaceUUID;
}

- (instancetype)init {
    if (self = [super init]) {
        _identifier = [[NSUUID UUID] UUIDString];
        _name = @"Space";
        _colour = 0;
        _icon = @"briefcase";
        _sharesSignIns = YES;
        _downloads = nil;
    }
    return self;
}

- (BOOL)isFirst {
    return [self.identifier isEqualToString:kFirstSpaceUUID];
}

- (NSString*)symbol {
    if (self.icon.length && [[SlateSpacesManager availableIcons] containsObject:self.icon]) {
        return self.icon;
    }
    return [self isFirst] ? @"house" : @"briefcase";
}

- (NSDictionary*)dictionaryRepresentation {
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    dict[@"id"] = self.identifier ?: kFirstSpaceUUID;
    dict[@"name"] = self.name ?: @"Personal";
    dict[@"colour"] = @(self.colour);
    if (self.icon) dict[@"icon"] = self.icon;
    dict[@"sharesSignIns"] = @(self.sharesSignIns);
    if (self.downloads.length) dict[@"downloads"] = self.downloads;
    return dict;
}

+ (instancetype)fromDictionary:(NSDictionary*)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    SlateSpace* space = [[SlateSpace alloc] init];
    if ([dict[@"id"] isKindOfClass:NSString.class]) {
        space.identifier = dict[@"id"];
    }
    if ([dict[@"name"] isKindOfClass:NSString.class]) {
        space.name = dict[@"name"];
    }
    if ([dict[@"colour"] isKindOfClass:NSNumber.class]) {
        space.colour = [dict[@"colour"] integerValue];
    }
    if ([dict[@"icon"] isKindOfClass:NSString.class]) {
        space.icon = dict[@"icon"];
    }
    if ([dict[@"sharesSignIns"] isKindOfClass:NSNumber.class]) {
        space.sharesSignIns = [dict[@"sharesSignIns"] boolValue];
    } else {
        space.sharesSignIns = space.isFirst;
    }
    if ([dict[@"downloads"] isKindOfClass:NSString.class] && [dict[@"downloads"] length]) {
        space.downloads = dict[@"downloads"];
    }
    return space;
}

@end

@interface SlateSpacesManager ()
@property (nonatomic, strong) NSMutableArray<SlateSpace*>* spaces;
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSMutableArray<NSDictionary*>*>* parkedTabs;
@property (nonatomic, strong) NSMutableDictionary<NSString*, WKWebsiteDataStore*>* stores;
@end

@implementation SlateSpacesManager

+ (instancetype)sharedManager {
    static SlateSpacesManager* instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SlateSpacesManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _spaces = [NSMutableArray array];
        _parkedTabs = [NSMutableDictionary dictionary];
        _stores = [NSMutableDictionary dictionary];
        _currentSpaceId = kFirstSpaceUUID;
        [self loadSpaces];
    }
    return self;
}

+ (NSArray<NSString*>*)availableIcons {
    return @[
        @"briefcase", @"building.2", @"desktopcomputer", @"laptopcomputer",
        @"chevron.left.forwardslash.chevron.right", @"terminal",
        @"sparkles", @"brain.head.profile", @"lightbulb", @"gamecontroller",
        @"beach.umbrella", @"cup.and.saucer", @"music.note", @"film",
        @"paintpalette", @"camera", @"house", @"book",
        @"graduationcap", @"cart", @"airplane", @"dumbbell", @"leaf", @"heart"
    ];
}

+ (NSArray<NSString*>*)availableIconNames {
    return @[
        @"Work", @"Office", @"Desktop", @"Laptop",
        @"Code", @"Terminal",
        @"AI", @"Thinking", @"Ideas", @"Games",
        @"Leisure", @"Café", @"Music", @"Film",
        @"Art", @"Photos", @"Home", @"Reading",
        @"Studies", @"Shopping", @"Travel", @"Sport", @"Nature", @"Personal"
    ];
}

- (NSString*)freeIcon {
    NSMutableSet<NSString*>* used = [NSMutableSet set];
    for (SlateSpace* s in self.spaces) {
        [used addObject:s.symbol];
    }
    for (NSString* icon in [SlateSpacesManager availableIcons]) {
        if (![used containsObject:icon]) return icon;
    }
    return @"briefcase";
}

- (SlateSpace*)currentSpace {
    for (SlateSpace* s in self.spaces) {
        if ([s.identifier isEqualToString:self.currentSpaceId]) return s;
    }
    return self.spaces.firstObject;
}

- (SlateSpace*)spaceForIdentifier:(NSString*)identifier {
    if (!identifier.length) return nil;
    for (SlateSpace* s in self.spaces) {
        if ([s.identifier isEqualToString:identifier]) return s;
    }
    return nil;
}

- (NSInteger)indexOfSpace:(NSString*)identifier {
    if (!identifier.length) return NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)self.spaces.count; ++i) {
        if ([self.spaces[i].identifier isEqualToString:identifier]) return i;
    }
    return NSNotFound;
}

- (SlateSpace*)addSpaceNamed:(NSString*)name icon:(NSString*)icon sharesSignIns:(BOOL)sharesSignIns {
    SlateSpace* space = [[SlateSpace alloc] init];
    space.identifier = [[NSUUID UUID] UUIDString];
    space.name = name.length ? name : @"New Space";
    space.icon = icon.length ? icon : [self freeIcon];
    space.sharesSignIns = sharesSignIns;
    space.colour = (NSInteger)(self.spaces.count % 6);
    [self.spaces addObject:space];
    [self saveSpaces];
    return space;
}

- (BOOL)deleteSpace:(NSString*)identifier {
    if (!identifier.length || [identifier isEqualToString:kFirstSpaceUUID]) return NO;
    NSInteger idx = [self indexOfSpace:identifier];
    if (idx == NSNotFound) return NO;
    
    SlateSpace* space = self.spaces[idx];
    BOOL hadSeparateStore = !space.sharesSignIns;
    [self.spaces removeObjectAtIndex:idx];
    [self.parkedTabs removeObjectForKey:identifier];
    [self saveSpaces];
    
    if (hadSeparateStore) {
        [self eraseStoreForSpaceId:identifier];
    }
    return YES;
}

- (void)renameSpace:(NSString*)identifier toName:(NSString*)name {
    SlateSpace* s = [self spaceForIdentifier:identifier];
    if (s && name.length) {
        s.name = name;
        [self saveSpaces];
    }
}

- (void)setSpaceIcon:(NSString*)identifier icon:(NSString*)icon {
    SlateSpace* s = [self spaceForIdentifier:identifier];
    if (s && icon.length) {
        s.icon = icon;
        [self saveSpaces];
    }
}

- (void)setSpaceDownloads:(NSString*)identifier folder:(NSString*)folder {
    SlateSpace* s = [self spaceForIdentifier:identifier];
    if (s) {
        s.downloads = folder.length ? folder : nil;
        [self saveSpaces];
    }
}

- (void)moveSpace:(NSString*)identifier toIndex:(NSInteger)toIndex {
    NSInteger fromIndex = [self indexOfSpace:identifier];
    if (fromIndex == NSNotFound || toIndex < 0 || toIndex >= (NSInteger)self.spaces.count || fromIndex == toIndex) return;
    
    SlateSpace* space = self.spaces[fromIndex];
    [self.spaces removeObjectAtIndex:fromIndex];
    [self.spaces insertObject:space atIndex:toIndex];
    [self saveSpaces];
}

- (WKWebsiteDataStore*)dataStoreForSpace:(SlateSpace*)space {
    if (!space || space.isFirst || space.sharesSignIns) {
        return [WKWebsiteDataStore defaultDataStore];
    }
    if (self.stores[space.identifier]) {
        return self.stores[space.identifier];
    }
    NSUUID* uuid = [[NSUUID alloc] initWithUUIDString:space.identifier];
    if (!uuid) return [WKWebsiteDataStore defaultDataStore];
    
    if (@available(macOS 10.15, *)) {
        WKWebsiteDataStore* store = [WKWebsiteDataStore dataStoreForIdentifier:uuid];
        if (store) {
            self.stores[space.identifier] = store;
            return store;
        }
    }
    return [WKWebsiteDataStore defaultDataStore];
}

- (void)eraseStoreForSpaceId:(NSString*)identifier {
    if (!identifier.length || [identifier isEqualToString:kFirstSpaceUUID]) return;
    
    NSUUID* uuid = [[NSUUID alloc] initWithUUIDString:identifier];
    WKWebsiteDataStore* store = self.stores[identifier];
    if (!store && uuid) {
        if (@available(macOS 10.15, *)) {
            store = [WKWebsiteDataStore dataStoreForIdentifier:uuid];
        }
    }
    if (store) {
        NSSet* everything = [WKWebsiteDataStore allWebsiteDataTypes];
        NSDate* epoch = [NSDate dateWithTimeIntervalSince1970:0];
        [store removeDataOfTypes:everything modifiedSince:epoch completionHandler:^{}];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [store removeDataOfTypes:everything modifiedSince:epoch completionHandler:^{}];
        });
        [self.stores removeObjectForKey:identifier];
    }
    if (uuid) {
        if (@available(macOS 14.0, *)) {
            [WKWebsiteDataStore removeDataStoreForIdentifier:uuid completionHandler:^(NSError* _Nullable error) {}];
        }
    }
}

#pragma mark - Persistence

static NSString* SpacesFilePath() {
    NSString* env = NSProcessInfo.processInfo.environment[@"SLATE_DATA_DIR"];
    NSString* dir = (env.length && env.isAbsolutePath) ? env : [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Slate"];
    return [dir stringByAppendingPathComponent:@"spaces.json"];
}

- (void)loadSpaces {
    [self.spaces removeAllObjects];
    [self.parkedTabs removeAllObjects];
    
    NSString* path = SpacesFilePath();
    NSData* data = [NSData dataWithContentsOfFile:path];
    if (data.length) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class]) {
            if ([json[@"currentSpaceId"] isKindOfClass:NSString.class]) {
                _currentSpaceId = json[@"currentSpaceId"];
            }
            if ([json[@"spaces"] isKindOfClass:NSArray.class]) {
                for (id item in json[@"spaces"]) {
                    SlateSpace* s = [SlateSpace fromDictionary:item];
                    if (s) [self.spaces addObject:s];
                }
            }
            if ([json[@"parkedTabs"] isKindOfClass:NSDictionary.class]) {
                for (NSString* key in json[@"parkedTabs"]) {
                    id list = json[@"parkedTabs"][key];
                    if ([list isKindOfClass:NSArray.class]) {
                        self.parkedTabs[key] = [NSMutableArray arrayWithArray:list];
                    }
                }
            }
        }
    }
    
    // Ensure the default / first space always exists at index 0
    BOOL hasFirst = NO;
    for (SlateSpace* s in self.spaces) {
        if (s.isFirst) { hasFirst = YES; break; }
    }
    if (!hasFirst) {
        SlateSpace* first = [[SlateSpace alloc] init];
        first.identifier = kFirstSpaceUUID;
        first.name = @"Personal";
        first.colour = 0;
        first.icon = @"house";
        first.sharesSignIns = YES;
        [self.spaces insertObject:first atIndex:0];
    }
    
    // Validate currentSpaceId
    if (![self spaceForIdentifier:self.currentSpaceId]) {
        self.currentSpaceId = self.spaces.firstObject.identifier;
    }
}

- (void)saveSpaces {
    NSMutableArray* spacesArray = [NSMutableArray array];
    for (SlateSpace* s in self.spaces) {
        [spacesArray addObject:[s dictionaryRepresentation]];
    }
    
    NSMutableDictionary* root = [NSMutableDictionary dictionary];
    root[@"version"] = @1;
    root[@"currentSpaceId"] = self.currentSpaceId ?: kFirstSpaceUUID;
    root[@"spaces"] = spacesArray;
    root[@"parkedTabs"] = self.parkedTabs ?: @{};
    
    NSData* data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    if (data) {
        NSString* path = SpacesFilePath();
        [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        [data writeToFile:path atomically:YES];
    }
}

@end
