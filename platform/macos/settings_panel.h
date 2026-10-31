// File purpose: Declares the native settings pages and their connection to browser
// preferences/actions.

#import <Cocoa/Cocoa.h>

@class SlateDelegate;

// Slate note: The weak delegate reference avoids the settings window retaining the browser owner.
@interface SlateSettingsPanel : NSPanel

@property (nonatomic, weak) SlateDelegate* slateDelegate;

+ (instancetype)sharedPanel;
- (void)showForSlateDelegate:(SlateDelegate*)delegate;
- (void)showForSlateDelegate:(SlateDelegate*)delegate selectedPage:(NSString*)page;
- (void)updateFromDelegate;
#if defined(SLATE_ENABLE_VERIFY)
- (void)prepareUpdaterVerification:(SlateDelegate*)delegate;
#endif

@end
