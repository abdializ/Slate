// File purpose: Declares a native panel presenting browser capability/resource comparison cards.

#import <Cocoa/Cocoa.h>

// Slate note: The singleton exposes a window presentation entry point to the browser.
@interface SlateSpecsPanel : NSPanel

+ (instancetype)sharedPanel;
- (void)showForWindow:(NSWindow*)parentWindow;

@end
