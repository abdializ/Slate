#import <Cocoa/Cocoa.h>

@interface SlateSpecsPanel : NSPanel

+ (instancetype)sharedPanel;
- (void)showForWindow:(NSWindow*)parentWindow;

@end
