#pragma once
#include "core/browser_engine.h"
#include "core/protection.h"
#include "engine/engine_events.h"
#include <memory>

namespace slate {

// native_view is an NSView*. Construction and every call require the UI thread.
std::unique_ptr<BrowserEngine> make_webkit_engine(void* native_view, EngineEvents events,
                                                const std::string& url, ShieldController* shields=nullptr,
                                                bool incognito=false, void* website_data_store=nullptr,
                                                void* popup_configuration=nullptr);
void PurgeIncognitoStorage();

} // namespace slate

#ifdef __OBJC__
#import <WebKit/WebKit.h>
#import <Foundation/Foundation.h>

@interface SlateFrameRate : NSObject
+ (BOOL)is120HzAvailable;
+ (BOOL)isFast;
+ (void)setFast:(BOOL)fast;
+ (void)applyToPreferences:(WKPreferences*)prefs;
+ (BOOL)prefersNear60:(WKPreferences*)prefs;
+ (void)setFeatureValue:(BOOL)val inPreferences:(WKPreferences*)prefs;
@end
#endif

