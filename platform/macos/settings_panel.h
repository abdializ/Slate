#import <Cocoa/Cocoa.h>

@class SlateDelegate;

@interface SlateSettingsPanel : NSPanel

@property (nonatomic, weak) SlateDelegate* slateDelegate;

+ (instancetype)sharedPanel;
- (void)showForSlateDelegate:(SlateDelegate*)delegate;
- (void)showForSlateDelegate:(SlateDelegate*)delegate selectedPage:(NSString*)page;
- (void)updateFromDelegate;

@end
