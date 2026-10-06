#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "engine/webkit_engine.h"
#include "engine/webkit_shields.h"
#include "core/tab_model.h"
#include "core/navigation.h"
#include "core/shields.h"
#include "core/library.h"
#include "session_store.h"
#include "bookmark_store.h"
#import "platform/macos/bookmarks_panel.h"
#import "platform/macos/plate_components.h"
#include "platform/macos/active_browser_tab_shape.h"
#include "platform/macos/split_workspace.h"
#include "memory_monitor.h"
#include "core/credential_store.h"
#include "platform/macos/credential_persistence.h"
#include "platform/macos/browser_importer.h"
#import "platform/macos/passwords_panel.h"
#import "platform/macos/import_dialog.h"
#import "platform/macos/specs_panel.h"
#import "platform/macos/downloads_panel.h"
#import "platform/macos/download_manager.h"
#import "platform/macos/spaces_manager.h"
#import "platform/macos/settings_panel.h"
#import "platform/macos/site_card_panel.h"
#import "platform/macos/float_window.h"
#import "platform/macos/form_relay.h"
#import "platform/macos/omnibox_overlay.h"
#import "platform/macos/find_bar.h"
#include "engine/floating_video_js.h"
#import <SecurityInterface/SFCertificatePanel.h>
#include <map>
#include <memory>
#include <set>
#include <vector>
#include <cmath>

using slate::TabId;
namespace {
constexpr CGFloat kTitlebarHeight=42;
constexpr CGFloat kToolbarHeight=52;
constexpr CGFloat kSidebarOpenWidth=260;
constexpr CGFloat kRailBubble=32;
constexpr CGFloat kRailMark=20;
CGFloat RailMarkForWidth(CGFloat width) {
 return MIN(28.0, MAX(kRailMark, round(width * 0.32)));
}
constexpr CGFloat kRailRow=40;
constexpr CGFloat kSidebarBubbleWidth=48;
constexpr CGFloat kSidebarLabelWidth=148;
constexpr CGFloat kSidebarMinWidth=kSidebarBubbleWidth;
constexpr CGFloat kSidebarHeaderHeight=36;
constexpr CGFloat kCompactTabWidth=30;
constexpr CGFloat kTabHeight=38;
constexpr CGFloat kOmniboxWidth=860;
constexpr CGFloat kOmniboxHeight=38;
constexpr CGFloat kHomeSearchHeight=48;
constexpr CGFloat kPlateInset=6;
constexpr CGFloat kPlateGap=0;
constexpr CGFloat kPlateRadius=14;
constexpr CGFloat kBookmarksBarHeight=30;
const int kZoomStops[]={25,33,50,67,75,80,90,100,110,125,150,175,200,250,300,400,500};
int ClampZoomPercent(int percent) {
 const int last=kZoomStops[(int)(sizeof(kZoomStops)/sizeof(kZoomStops[0]))-1];
 if(percent<kZoomStops[0]) return kZoomStops[0];
 if(percent>last) return last;
 return percent;
}
int NextZoomPercent(int current, int delta) {
 const int count=(int)(sizeof(kZoomStops)/sizeof(kZoomStops[0]));
 if(delta>0) {
  for(int i=0;i<count;++i) if(kZoomStops[i]>current) return kZoomStops[i];
  return kZoomStops[count-1];
 }
 if(delta<0) {
  for(int i=count-1;i>=0;--i) if(kZoomStops[i]<current) return kZoomStops[i];
  return kZoomStops[0];
 }
 return 100;
}
double ZoomLevelForPercent(int percent) {
 return std::log(MAX(0.25, percent/100.0))/std::log(1.2);
}
CGFloat ClampSidebarWidth(CGFloat width, CGFloat windowWidth) {
 CGFloat maxW=MAX(kSidebarOpenWidth, windowWidth>1 ? windowWidth*0.72 : 560);
 return MAX(kSidebarBubbleWidth, MIN(maxW, width));
}
CGFloat SnapSidebarWidth(CGFloat width, CGFloat windowWidth) {
 width=ClampSidebarWidth(width, windowWidth);
 if(width<kSidebarLabelWidth) return kSidebarBubbleWidth;
 return width;
}
NSString* DataDirectory() {
 NSString* override=NSProcessInfo.processInfo.environment[@"SLATE_DATA_DIR"];
 if(override.length && override.isAbsolutePath) return override;
 NSString* support=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
 return [support stringByAppendingPathComponent:@"Slate"];
}
NSString* Text(const std::string& value) {
 return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}
NSString* PrefsPath() { return [DataDirectory() stringByAppendingPathComponent:@"ui.json"]; }
NSString* BookmarksPath() { return [DataDirectory() stringByAppendingPathComponent:@"bookmarks.json"]; }
NSString* PasswordsPath() { return [DataDirectory() stringByAppendingPathComponent:@"passwords.dat"]; }
static void InstallCrashHandler(void) {
 NSSetUncaughtExceptionHandler([](NSException* exception) {
  NSString* line = [NSString stringWithFormat:@"%@ — %@: %@\n%@\n\n",
   [NSDate date], exception.name, exception.reason ?: @"?",
   [exception.callStackSymbols componentsJoinedByString:@"\n"]];
  NSString* dataDir = DataDirectory();
  if (dataDir.length) {
   [NSFileManager.defaultManager createDirectoryAtPath:dataDir withIntermediateDirectories:YES attributes:nil error:nil];
   NSString* crashLog = [dataDir stringByAppendingPathComponent:@"crash.log"];
   NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:crashLog];
   if (handle) {
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
   } else {
    [line writeToFile:crashLog atomically:YES encoding:NSUTF8StringEncoding error:nil];
   }
  }
 });
}
struct SideRow {
 enum class Kind { Tab, Group, NewTab } kind=Kind::Tab;
 TabId tab=0;
 std::string group;
};
struct UiPrefs { BOOL vertical=NO; BOOL collapsed=NO; CGFloat sidebarWidth=kSidebarOpenWidth; NSString* accent=@"rose"; NSString* accentHex=@""; NSString* accentHex2=@""; int zoomPercent=100; BOOL showBookmarksBar=YES; CGFloat graniteIntensity=0.0; int themeMode=0; BOOL pages120Hz=NO; int tabStyle=1; TabId splitLeft=0; TabId splitRight=0; double splitRatio=0.5; BOOL splitRightActive=NO; std::vector<slate::SplitPair> splitGroups; };
NSColor* ColorSRGB(CGFloat r, CGFloat g, CGFloat b) {
 return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];
}
NSColor* ColorFromHex(NSString* hex) {
 if(hex.length<7 || ![hex hasPrefix:@"#"]) return nil;
 unsigned int value=0;
 NSScanner* scanner=[NSScanner scannerWithString:[hex substringFromIndex:1]];
 if(![scanner scanHexInt:&value]) return nil;
 return ColorSRGB(((value>>16)&0xff)/255.0, ((value>>8)&0xff)/255.0, (value&0xff)/255.0);
}
CGFloat ColorLuma(NSColor* color) {
 if(!color) return 1;
 NSColor* rgb=[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
 auto lin=[](CGFloat x){ return x<=0.04045 ? x/12.92 : std::pow((x+0.055)/1.055, 2.4); };
 return 0.2126*lin(rgb.redComponent)+0.7152*lin(rgb.greenComponent)+0.0722*lin(rgb.blueComponent);
}
BOOL ColorIsDark(NSColor* color) { return ColorLuma(color)<0.42; }
NSColor* ChromeTabStripColor(NSColor* toolbarColor) {
 if(!toolbarColor) return NSColor.windowBackgroundColor;
 const BOOL dark=ColorIsDark(toolbarColor);
 return [toolbarColor blendedColorWithFraction:dark ? 0.06 : 0.04
  ofColor:dark ? NSColor.whiteColor : NSColor.blackColor] ?: toolbarColor;
}
BOOL ColorsEqual(NSColor* a, NSColor* b) {
 if(a==b) return YES;
 if(!a || !b) return NO;
 NSColor* left=[a colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: a;
 NSColor* right=[b colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: b;
 return fabs(left.redComponent-right.redComponent)<0.012 &&
        fabs(left.greenComponent-right.greenComponent)<0.012 &&
        fabs(left.blueComponent-right.blueComponent)<0.012 &&
        fabs(left.alphaComponent-right.alphaComponent)<0.012;
}
NSColor* InkOn(NSColor* bg) {
 return ColorIsDark(bg) ? [NSColor colorWithCalibratedWhite:0.96 alpha:0.95] : [NSColor colorWithCalibratedWhite:0.11 alpha:0.92];
}
NSColor* MutedInkOn(NSColor* bg) {
 return ColorIsDark(bg) ? [NSColor colorWithCalibratedWhite:0.96 alpha:0.60] : [NSColor colorWithCalibratedWhite:0.11 alpha:0.58];
}
NSString* HexFromColor(NSColor* color) {
 NSColor* rgb=[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
 if(!rgb) return @"#E8E8EE";
 return [NSString stringWithFormat:@"#%02X%02X%02X",
  (int)llround(rgb.redComponent*255),(int)llround(rgb.greenComponent*255),(int)llround(rgb.blueComponent*255)];
}
NSColor* ChromeAccent(NSString* ident, NSString* hex, BOOL dark) {
 if([ident isEqualToString:@"custom"]) {
  NSColor* custom=ColorFromHex(hex);
  if(custom) return custom;
 }
 if([ident isEqualToString:@"slate"])
  return dark ? ColorSRGB(0.18,0.20,0.24) : ColorSRGB(0.35,0.40,0.46);
 if([ident isEqualToString:@"rose"])
  return dark ? ColorSRGB(0.34,0.22,0.24) : ColorSRGB(0.96,0.89,0.89);
 if([ident isEqualToString:@"mauve"])
  return dark ? ColorSRGB(0.28,0.20,0.32) : ColorSRGB(0.94,0.89,0.96);
 if([ident isEqualToString:@"coral"])
  return dark ? ColorSRGB(0.36,0.18,0.18) : ColorSRGB(0.96,0.89,0.87);
 if([ident isEqualToString:@"peach"])
  return dark ? ColorSRGB(0.36,0.24,0.18) : ColorSRGB(0.97,0.90,0.85);
 if([ident isEqualToString:@"marigold"])
  return dark ? ColorSRGB(0.36,0.30,0.18) : ColorSRGB(0.97,0.93,0.84);
 if([ident isEqualToString:@"sand"])
  return dark ? ColorSRGB(0.32,0.28,0.22) : ColorSRGB(0.96,0.93,0.87);
 if([ident isEqualToString:@"sage"])
  return dark ? ColorSRGB(0.22,0.30,0.26) : ColorSRGB(0.89,0.94,0.90);
 if([ident isEqualToString:@"sky"])
  return dark ? ColorSRGB(0.20,0.26,0.32) : ColorSRGB(0.89,0.93,0.97);
 if([ident isEqualToString:@"graphite"])
  return dark ? ColorSRGB(0.18,0.18,0.19) : ColorSRGB(0.30,0.30,0.33);
 return dark ? ColorSRGB(0.18,0.20,0.24) : ColorSRGB(0.91,0.93,0.95);
}
NSArray<NSDictionary*>* AccentCatalog() {
 return @[
  @{@"id":@"slate",@"title":@"Slate"},
  @{@"id":@"rose",@"title":@"Rose"},
  @{@"id":@"mauve",@"title":@"Mauve"},
  @{@"id":@"coral",@"title":@"Coral"},
  @{@"id":@"peach",@"title":@"Peach"},
  @{@"id":@"marigold",@"title":@"Marigold"},
  @{@"id":@"sand",@"title":@"Sand"},
  @{@"id":@"sage",@"title":@"Sage"},
  @{@"id":@"sky",@"title":@"Sky"},
  @{@"id":@"graphite",@"title":@"Graphite"}
 ];
}
NSColor* HostColor(NSString* host) {
 NSUInteger hash=host.hash;
 const CGFloat hue=((hash>>8)&0xff)/255.0;
 const CGFloat sat=0.42+((hash>>16)&0x3f)/255.0;
 const CGFloat brt=0.62+((hash>>24)&0x3f)/400.0;
 return [NSColor colorWithHue:hue saturation:sat brightness:brt alpha:1];
}
NSImage* LetterTile(NSString* letter, NSString* host, CGFloat size) {
 NSString* glyph=(letter.length ? [letter substringToIndex:1] : @"•").uppercaseString;
 NSColor* fill=HostColor(host.length ? host : glyph);
 NSImage* image=[NSImage imageWithSize:NSMakeSize(size,size) flipped:NO drawingHandler:^BOOL(NSRect rect) {
  NSBezierPath* path=[NSBezierPath bezierPathWithRoundedRect:rect xRadius:size/2.0 yRadius:size/2.0];
  [fill setFill];
  [path fill];
  NSMutableParagraphStyle* style=[NSMutableParagraphStyle new];
  style.alignment=NSTextAlignmentCenter;
  NSRect text=NSMakeRect(0, size*0.06, size, size*0.82);
  [glyph drawInRect:text withAttributes:@{
   NSFontAttributeName:[NSFont systemFontOfSize:size*0.56 weight:NSFontWeightSemibold],
   NSForegroundColorAttributeName:NSColor.whiteColor,
   NSParagraphStyleAttributeName:style
  }];
  return YES;
 }];
 [image setTemplate:NO];
 return image;
}
NSImage* ClipMark(NSImage* source, CGFloat size) {
 if(!source) return nil;
 NSImage* image=[NSImage imageWithSize:NSMakeSize(size,size) flipped:NO drawingHandler:^BOOL(NSRect rect) {
  NSBezierPath* path=[NSBezierPath bezierPathWithRoundedRect:rect xRadius:4 yRadius:4];
  [path addClip];
  [source drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1
   respectFlipped:YES hints:@{NSImageHintInterpolation:@(NSImageInterpolationHigh)}];
  return YES;
 }];
 [image setTemplate:NO];
 return image;
}
NSImage* AccentSwatch(NSColor* color) {
 NSImage* image=[[NSImage alloc] initWithSize:NSMakeSize(12,12)];
 [image lockFocus];
 [color setFill];
 [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.5,0.5,11,11) xRadius:3 yRadius:3] fill];
 [[color blendedColorWithFraction:0.25 ofColor:NSColor.blackColor] setStroke];
 NSBezierPath* stroke=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.5,0.5,11,11) xRadius:3 yRadius:3];
 stroke.lineWidth=1;
 [stroke stroke];
 [image unlockFocus];
 [image setTemplate:NO];
 return image;
}
UiPrefs LoadUiPrefs() {
 UiPrefs prefs;
 NSData* data=[NSData dataWithContentsOfFile:PrefsPath()];
 if(!data) return prefs;
 id root=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
 if(![root isKindOfClass:NSDictionary.class]) return prefs;
 NSDictionary* dict=root;
 if([dict[@"vertical_tabs"] isKindOfClass:NSNumber.class]) prefs.vertical=[dict[@"vertical_tabs"] boolValue];
 if([dict[@"sidebar_collapsed"] isKindOfClass:NSNumber.class]) prefs.collapsed=[dict[@"sidebar_collapsed"] boolValue];
 if([dict[@"tabs_collapsed"] isKindOfClass:NSNumber.class]) prefs.collapsed=[dict[@"tabs_collapsed"] boolValue];
 if([dict[@"sidebar_width"] isKindOfClass:NSNumber.class])
  prefs.sidebarWidth=ClampSidebarWidth([dict[@"sidebar_width"] doubleValue], 1200);
 if([dict[@"accent"] isKindOfClass:NSString.class] && [dict[@"accent"] length]) prefs.accent=dict[@"accent"];
 if([dict[@"accent_hex"] isKindOfClass:NSString.class]) prefs.accentHex=dict[@"accent_hex"];
 if([dict[@"accent_hex2"] isKindOfClass:NSString.class]) prefs.accentHex2=dict[@"accent_hex2"];
 if([dict[@"page_zoom"] isKindOfClass:NSNumber.class]) prefs.zoomPercent=ClampZoomPercent([dict[@"page_zoom"] intValue]);
 if([dict[@"show_bookmarks_bar"] isKindOfClass:NSNumber.class]) prefs.showBookmarksBar=[dict[@"show_bookmarks_bar"] boolValue];
 if([dict[@"granite_intensity"] isKindOfClass:NSNumber.class]) prefs.graniteIntensity=[dict[@"granite_intensity"] doubleValue];
 if([dict[@"theme_mode"] isKindOfClass:NSNumber.class]) prefs.themeMode=[dict[@"theme_mode"] intValue];
 if([dict[@"pages_120hz"] isKindOfClass:NSNumber.class]) prefs.pages120Hz=[dict[@"pages_120hz"] boolValue];
 if([dict[@"tab_style"] isKindOfClass:NSNumber.class]) prefs.tabStyle=[dict[@"tab_style"] intValue];
 else if([dict[@"tab_style"] isKindOfClass:NSString.class]) prefs.tabStyle=[dict[@"tab_style"] isEqualToString:@"regular"] ? 1 : 0;
 if([dict[@"split_left"] isKindOfClass:NSNumber.class]) prefs.splitLeft=[dict[@"split_left"] unsignedLongLongValue];
 if([dict[@"split_right"] isKindOfClass:NSNumber.class]) prefs.splitRight=[dict[@"split_right"] unsignedLongLongValue];
 if([dict[@"split_ratio"] isKindOfClass:NSNumber.class]) prefs.splitRatio=std::clamp([dict[@"split_ratio"] doubleValue],0.25,0.75);
 if([dict[@"split_active_right"] isKindOfClass:NSNumber.class]) prefs.splitRightActive=[dict[@"split_active_right"] boolValue];
 if([dict[@"split_groups"] isKindOfClass:NSArray.class]) for(id entry in dict[@"split_groups"]) {
  if(![entry isKindOfClass:NSDictionary.class]) continue;
  NSDictionary* group=entry;
  if(![group[@"left"] isKindOfClass:NSNumber.class] || ![group[@"right"] isKindOfClass:NSNumber.class]) continue;
  const TabId left=[group[@"left"] unsignedLongLongValue], right=[group[@"right"] unsignedLongLongValue];
  if(!left || !right || left==right) continue;
  double ratio=[group[@"ratio"] isKindOfClass:NSNumber.class] ? [group[@"ratio"] doubleValue] : 0.5;
  if(!std::isfinite(ratio)) ratio=0.5;
  prefs.splitGroups.push_back({left,right,std::clamp(ratio,0.25,0.75),
   [group[@"active_right"] boolValue] ? slate::SplitSide::Right : slate::SplitSide::Left});
 }
 return prefs;
}
NSString* TabHost(const slate::Tab& tab);
NSImage* BrowserGlyphImage() {
 static NSImage* glyph=nil;
 static dispatch_once_t onceToken;
 dispatch_once(&onceToken, ^{
  glyph=[NSImage imageNamed:@"BrowserGlyph"];
  if(!glyph) {
   NSString* path=[[NSBundle mainBundle] pathForResource:@"BrowserGlyph" ofType:@"png"];
   if(path) glyph=[[NSImage alloc] initWithContentsOfFile:path];
  }
  [glyph setTemplate:YES];
 });
 return glyph;
}
NSString* TabInitial(const slate::Tab& tab) {
 if(tab.incognito) return @"🕶";
 if(tab.url=="about:blank") return @"N";

 NSString* host=TabHost(tab);
 if([host hasPrefix:@"www."]) host=[host substringFromIndex:4];
 else if([host hasPrefix:@"m."]) host=[host substringFromIndex:2];
 else if([host hasPrefix:@"mobile."]) host=[host substringFromIndex:7];

 NSString* hostLower=host.lowercaseString;
 if([hostLower containsString:@"youtube"]) return @"Y";
 if([hostLower containsString:@"wisprflow"]) return @"W";
 if([hostLower containsString:@"ecourses"] || [hostLower containsString:@"canvas"]) return @"C";
 if([hostLower containsString:@"pvplace"] || [hostLower containsString:@"pvamu"]) return @"P";
 if([hostLower containsString:@"google"]) return @"G";
 if([hostLower containsString:@"github"]) return @"G";

 NSString* title=tab.title.empty() ? host : Text(tab.title);

 static NSRegularExpression* badgeRegex=nil;
 static dispatch_once_t onceToken;
 dispatch_once(&onceToken, ^{
  badgeRegex=[NSRegularExpression regularExpressionWithPattern:@"^\\s*[\\[\\(\\{]\\s*[0-9+]+\\s*[\\]\\)\\}]\\s*" options:0 error:nil];
 });
 if(badgeRegex && title.length) {
  title=[badgeRegex stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@""];
 }
 while(title.length > 0 && ([title hasPrefix:@"•"] || [title hasPrefix:@"*"] || [title hasPrefix:@"-"])) {
  title=[[title substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
 }

 for(NSUInteger i=0; i<title.length; ++i) {
  unichar c=[title characterAtIndex:i];
  if([[NSCharacterSet letterCharacterSet] characterIsMember:c]) {
   return [[title substringWithRange:NSMakeRange(i, 1)] uppercaseString];
  }
 }

 if(host.length > 0) {
  for(NSUInteger i=0; i<host.length; ++i) {
   unichar c=[host characterAtIndex:i];
   if([[NSCharacterSet letterCharacterSet] characterIsMember:c]) {
    return [[host substringWithRange:NSMakeRange(i, 1)] uppercaseString];
   }
  }
  for(NSUInteger i=0; i<host.length; ++i) {
   unichar c=[host characterAtIndex:i];
   if([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
    return [[host substringWithRange:NSMakeRange(i, 1)] uppercaseString];
   }
  }
 }
 return @"•";
}
NSString* TabLabel(const slate::Tab& tab) {
 if(tab.url=="about:blank") return tab.incognito ? @"Incognito" : @"New Tab";
 NSString* title=tab.title.empty() ? Text(tab.url) : Text(tab.title);
 if([title hasPrefix:@"http://"] || [title hasPrefix:@"https://"]) {
  NSURL* url=[NSURL URLWithString:title];
  if(url.host.length) title=url.host;
 }
 if(title.length>18) title=[[title substringToIndex:16] stringByAppendingString:@"…"];
 return title;
}
// Full-fidelity title for the vertical sidebar — real page title, NSTextField truncates naturally
NSString* TabSidebarTitle(const slate::Tab& tab) {
 NSString* raw=@"New Tab";
 if(tab.url=="about:blank") raw=tab.incognito ? @"Incognito Tab" : @"New Tab";
 else if(!tab.title.empty()) raw=Text(tab.title);
 else {
  NSURL* url=[NSURL URLWithString:Text(tab.url)];
  raw=url.host.length ? url.host : Text(tab.url);
 }
 return tab.incognito ? [@"🕶 " stringByAppendingString:raw] : raw;
}
CGFloat TabFillWidth(NSString* title) {
 return MAX(110, MIN(180, title.length*7.4+66));
}
NSString* TabHost(const slate::Tab& tab) {
 NSURL* url=[NSURL URLWithString:Text(tab.url)];
 return url.host.lowercaseString ?: @"";
}
BOOL TabHasMedia(const slate::Tab& tab) { return tab.protection.media_elements; }
NSString* TabPeekLabel(const slate::Tab& tab, BOOL showUrl) {
 if(showUrl) {
  NSString* host=TabHost(tab);
  if(host.length) return host;
  if(tab.url=="about:blank") return @"New Tab";
  return Text(tab.url);
 }
 return TabLabel(tab);
}
}

struct RuntimeTab {
 std::unique_ptr<slate::BrowserEngine> engine;
 NSView* __strong host=nil;
 bool back=false;
 bool forward=false;
 bool audible=false;
 bool video_playing=false;
 bool user_started_media=false;
 std::string primary_media_frame;
 bool has_video=false;
 bool pip_active=false;
 int auto_pip_origin=0; // 0 manual, 1 tab switch, 2 app deactivation
 bool suppress_auto_pip=false;
 bool pip_returning=false;
 bool loading=false;
 double progress=1;
 bool hide_scheduled=false;
 std::string theme_hex;
 bool has_sign_in=false;
 bool typing=false;
 bool immersed=false;
 CGRect focus_rect=CGRectNull;
 std::string pending_sign_in_origin;
 std::string pending_sign_in_user;
 std::string pending_sign_in_password;
 int video_width=0;
 int video_height=0;
 std::string video_quality;
 bool is_hdr=false;
};
static slate::TabModel model;
static std::map<TabId,RuntimeTab> runtimes;
static std::unique_ptr<slate::SessionStore> session;
static std::unique_ptr<slate::BookmarkList> bookmarks;
static std::unique_ptr<slate::CredentialStore> credentials;
static std::vector<slate::HistoryItem> importedHistory;
static std::unique_ptr<slate::MemoryMonitor> memoryMonitor;
static std::unique_ptr<slate::ShieldController> shields;
static slate::MemorySample memorySample{slate::Pressure::Normal,0,false};

@class SlateNavButton;
@class SlateHomeBoard;
@class SlatePinnedGrid;
@class SlateSidebarFoot;
@interface SlateGraniteView : NSView
@end

@class SlateThemePanel;
@class SlateDetachedTabWindow;
@interface SlateDelegate : NSObject <NSApplicationDelegate,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate,NSTextFieldDelegate,NSMenuDelegate,SlateBookmarksOwner,SlateOmniboxDelegate> {
 slate::WorkspaceLayout workspace;
}
@property(strong) NSMutableArray<NSURL*>* earlyURLs;
- (void)openExternalURL:(NSURL*)url;
+ (BOOL)isDefaultBrowser;
+ (void)becomeDefaultBrowser:(void(^)(BOOL success))completion;
@property(strong) SlatePinnedGrid* pinnedGrid;
@property(strong) SlateSidebarFoot* sidebarFoot;
@property(strong) SlateSpacesManager* spacesManager;
@property(strong) NSMenu* spacesMenu;
@property(strong) NSMenu* bookmarksMenu;
@property(strong) id spaceSwipeMonitor;
@property NSTimeInterval lastSpaceSwipeTime;
@property(strong) NSMutableSet<NSNumber*>* mutedTabIds;
@property(strong) NSView* savePasswordBanner;
@property(strong) NSString* pendingOrigin;
@property(strong) NSString* pendingUsername;
@property(strong) NSString* pendingPassword;
@property(strong) NSWindow* window;
@property(strong) NSMutableDictionary<NSNumber*,SlateDetachedTabWindow*>* detachedTabs;
@property(strong) NSView* titlebar;
@property(strong) NSView* toolbar;
@property(strong) NSView* chromePlate;
@property(strong) NSView* stage;
@property(strong) NSView* tabCluster;
@property(strong) NSView* tabStrip;
@property(strong) NSStackView* tabPills;
@property(strong) NSMutableArray<CAShapeLayer*>* splitTabShapeLayers;
@property(strong) NSMutableArray<CALayer*>* splitTabSeparatorLayers;
@property(strong) NSButton* addButton;
@property(strong) NSButton* sidebarAdd;
@property(strong) NSStackView* navCluster;
@property(strong) SlateNavButton* sidebarNavButton;
@property(strong) SlateNavButton* backButton;
@property(strong) SlateNavButton* forwardButton;
@property(strong) SlateNavButton* reloadButton;
@property(strong) NSLayoutConstraint* navLeadingTitle;
@property(strong) NSLayoutConstraint* navCenterTitle;
@property(strong) NSLayoutConstraint* tabLeadingTitle;
@property(strong) NSButton* extensionsButton;
@property(strong) NSButton* shieldsButton;
@property(strong) NSButton* bookmarkButton;
@property(strong) NSView* homeView;
@property(strong) SlateHomeBoard* homeBoard;
@property(copy) NSString* homeSignature;
@property(strong) SlateDownloadButton* downloadButton;
@property(strong) NSLayoutConstraint* downloadTrailingTitle;
@property(strong) NSLayoutConstraint* downloadCenterTitle;
@property(strong) NSLayoutConstraint* shieldsTrailingTitle;
@property(strong) NSLayoutConstraint* shieldsTrailingNoDownload;
@property(strong) NSLayoutConstraint* shieldsCenterTitle;
@property(strong) NSPopover* shieldsPopover;
@property(strong) NSTextField* shieldsStatus;
@property(strong) NSTextField* shieldsCount;
@property(strong) NSSwitch* shieldsToggle;
@property(strong) NSButton* shieldsPause;
@property(strong) NSPanel* suggestPanel;
@property(strong) NSStackView* suggestStack;
@property(strong) NSTextField* suggestQueryField;
@property(strong) NSView* suggestCard;
@property(strong) NSArray* suggestions;
@property(strong) NSURLSessionDataTask* suggestTask;
@property NSInteger suggestHighlight;
@property(strong) NSLayoutConstraint* titlebarFromRoot;
@property(strong) NSLayoutConstraint* titlebarFromSidebar;
@property(strong) NSLayoutConstraint* titlebarHeight;
@property(strong) NSLayoutConstraint* sidebarBelowChrome;
@property(strong) NSLayoutConstraint* sidebarFromTop;
@property(strong) NSLayoutConstraint* toolbarBelowTitlebar;
@property(strong) NSLayoutConstraint* toolbarFromTop;
@property(strong) NSLayoutConstraint* plateBelowTitlebar;
@property(strong) NSLayoutConstraint* plateFromTop;
@property(strong) NSLayoutConstraint* plateLeading;
@property(strong) NSLayoutConstraint* plateTrailing;
@property(strong) NSLayoutConstraint* plateBottom;
@property(strong) NSLayoutConstraint* plateFromTraffic;
@property(strong) NSLayoutConstraint* contentBelowToolbar;
@property(strong) NSLayoutConstraint* omniboxLeading;
@property(strong) NSLayoutConstraint* omniboxTrailing;
@property(strong) NSLayoutConstraint* omniboxPreferredWidth;
@property(strong) WKWebViewConfiguration* pendingPopupConfiguration;
@property(assign) TabId pendingPopupTab;
@property(strong) NSMutableDictionary<NSNumber*,NSImage*>* tabIcons;
@property(strong) NSView* omnibox;
@property(strong) NSLayoutConstraint* sidebarWidth;
@property(strong) NSLayoutConstraint* sidebarAddLeading;
@property(strong) NSLayoutConstraint* sidebarHeaderHeight;
@property(strong) NSLayoutConstraint* sidebarAddHeight;
@property(strong) NSLayoutConstraint* sidebarAddWidth;
@property(strong) NSLayoutConstraint* tabListLeading;
@property(strong) NSLayoutConstraint* tabListTrailing;
@property(strong) NSLayoutConstraint* tabStripWidth;
@property(strong) NSLayoutConstraint* addWidth;
@property(strong) NSView* sidebar;
@property(strong) NSView* sidebarDrag;
@property(strong) NSView* resizeHandle;
@property(strong) NSTextField* address;
@property(strong) NSTextField* status;
@property(strong) NSButton* protectButton;
@property(strong) NSButton* unloadButton;
@property(strong) NSView* content;
@property(strong) NSView* placeholder;
@property(strong) NSView* splitLeftPane;
@property(strong) NSView* splitRightPane;
@property(strong) NSView* splitFocusRing;
@property(strong) NSView* splitDivider;
@property(strong) NSView* splitOverlay;
@property(strong) NSView* splitLeftTarget;
@property(strong) NSView* splitRightTarget;
@property(strong) NSView* splitPreview;
@property(strong) NSImageView* splitPreviewIcon;
@property(strong) NSTextField* splitPreviewTitle;
@property TabId splitDraggedTab;
@property TabId splitSourceTab;
@property TabId splitDragBaseTab;
@property TabId splitDragCandidateTab;
@property(strong) NSTimer* splitDragTimer;
@property NSInteger splitDropSide;
@property TabId displayedSplitLeft;
@property TabId displayedSplitRight;
@property BOOL splitInstalling;
@property(strong) NSTableView* tabList;
@property(strong) NSMenuItem* verticalMenuItem;
@property(strong) NSMenuItem* hideTabsMenuItem;
@property(strong) NSMenuItem* zoomMenuItem;
@property(strong) NSMenu* accentMenu;
@property BOOL verticalTabs;
@property BOOL tabsCollapsed;
@property int zoomPercent;
@property BOOL quitting;
@property BOOL sessionWritable;
@property BOOL updatingList;
@property TabId displayedTab;
@property TabId hoveredTabId;
@property TabId bubbleTabId;
@property BOOL tabClusterHot;
@property BOOL addressDirty;
@property BOOL addressOpen;
@property CGFloat sidebarUserWidth;
// Hover-to-peek sidebar (Arc style): reveal while cursor is near left edge
@property BOOL sidebarPeeking;
@property(strong) NSTimer* peekDismissTimer;
@property(strong) id mouseMovedMonitor;
@property(strong) id localMouseMovedMonitor;
@property(copy) NSString* accentId;
@property(copy) NSString* accentHex;
@property(copy) NSString* accentHex2;
@property(strong) CAGradientLayer* chromeGradientLayer;
@property(strong) CAGradientLayer* homePlateGradientLayer;
@property(strong) NSButton* stealthBadge;
@property(strong) NSLayoutConstraint* stealthBadgeWidth;
@property(strong) NSLayoutConstraint* stealthBadgeLeading;
@property(strong) NSButton* securityButton;
@property(strong) NSLayoutConstraint* securityButtonWidth;
@property(strong) NSLayoutConstraint* securityButtonLeading;
@property(strong) NSLayoutConstraint* addressLeading;
@property(strong) NSLayoutConstraint* addressTrailing;
@property(strong) NSButton* autofillButton;
@property(strong) NSLayoutConstraint* autofillButtonWidth;
@property(strong) NSLayoutConstraint* autofillButtonTrailing;
@property(strong) NSButton* pipButton;
@property(strong) NSLayoutConstraint* pipButtonWidth;
@property(strong) NSLayoutConstraint* pipButtonTrailing;
@property(assign) TabId floatingTabId;
@property(strong) SlateFloat* floatWindow;
@property(weak) WKWebView* floatingWebView;
@property(strong) SlateOmniboxOverlay* omniboxOverlay;
@property(strong) SlateFindBar* findBar;
- (const slate::Tab*)selectedTab;
- (IBAction)toggleFloatingVideo:(id)sender;
- (void)liftTab:(TabId)identifier;
- (void)enterNativePiPForTab:(TabId)identifier manual:(BOOL)manual;
- (void)exitNativePiPForTab:(TabId)identifier;
- (void)dropFloat;
- (void)requestAutoPiPForTab:(TabId)identifier origin:(int)origin;
- (void)autoPiPForVisibleWorkspace;
- (void)returnAutoPiPForVisibleWorkspace;
- (void)appDidResignActive:(NSNotification*)notification;
- (void)appDidBecomeActive:(NSNotification*)notification;
- (void)showSuggestionsForCard:(SlateOmniboxCard*)card query:(NSString*)query;
- (void)submitOmniboxCard:(SlateOmniboxCard*)card;
- (void)showSuggestionsForOverlay:(NSString*)query;
- (void)submitOverlay:(SlateOmniboxOverlay*)overlay;
- (void)dismissOmniboxOverlay;
- (IBAction)findInPage:(id)sender;
- (IBAction)findNext:(id)sender;
- (IBAction)findPrevious:(id)sender;
- (IBAction)useSelectionForFind:(id)sender;
- (void)updatePipButtonState;
- (void)updateAutofillButtonState;
- (IBAction)triggerAutofillAction:(id)sender;
- (IBAction)showSiteCard:(id)sender;
- (void)updateSecurityChrome;
- (WKWebView*)currentWebView;
@property(strong) NSMutableArray<NSString*>* recentlyClosedUrls;
@property(strong) NSColor* barColor;
@property(strong) NSColor* barInk;
@property(strong) NSColor* barMuted;
@property(strong) NSColor* accentInk;
@property(strong) NSColor* accentMuted;
@property(copy) NSString* tabListSignature;
@property(copy) NSString* tabPaintSignature;
@property(copy) NSString* tabStripIdentity;
@property BOOL syncingGeometry;
@property BOOL chromeAnimating;
@property BOOL lastAddRail;
@property BOOL addChromeInited;
@property NSUInteger sideRowsGen;
@property NSUInteger chromeLayoutGen;
@property BOOL refreshQueued;
@property NSTimeInterval lastGeometryAt;
@property NSTimeInterval lastLoadBarAt;
@property(strong) NSView* loadBar;
@property(strong) NSLayoutConstraint* loadBarWidth;
@property(strong) NSView* bookmarksBar;
@property(strong) NSLayoutConstraint* bookmarksBarHeight;
@property(strong) NSScrollView* bookmarksScroll;
@property(strong) NSStackView* bookmarksStack;
@property BOOL showBookmarksBar;
@property CGFloat graniteIntensity;
@property int themeMode;
@property int tabStyle;
@property(strong) SlateGraniteView* graniteView;
@property(strong) SlateGraniteView* toolbarGraniteView;
@property(strong) NSView* trafficCluster;
@property(strong) NSArray<NSButton*>* fullScreenTrafficButtons;
@property(strong) NSButton* spaceBadgeButton;
@property(strong) NSLayoutConstraint* trafficLeading;
@property(strong) NSLayoutConstraint* trafficTop;
@property NSInteger trafficMode;
@property BOOL pinningTraffic;
@property BOOL pages120Hz;
@property(strong) NSMenuItem* pages120HzMenuItem;
#if defined(SLATE_ENABLE_VERIFY)
@property NSUInteger verifyLine;
@property NSTimeInterval verifyDelay;
#endif
- (BOOL)isDarkAppearance;
- (void)applyTabStyle;
- (void)selectPillTabStyle:(id)sender;
- (void)selectRegularTabStyle:(id)sender;
- (void)createWindow;
- (void)updateSpaceBadge;
- (void)spaceBadgeClicked:(id)sender;
- (void)togglePages120Hz:(id)sender;
- (void)requestClose;
- (void)refresh;
- (void)saveSession;
- (void)scheduleSave;
- (void)activateTab:(TabId)identifier;
- (BOOL)openSplitWithTab:(TabId)identifier side:(slate::SplitSide)side base:(TabId)base;
- (BOOL)replaceEmptySplitTab:(TabId)empty withTab:(TabId)identifier;
- (BOOL)isSplitPlaceholderTab:(TabId)identifier;
- (void)exitSplitView:(id)sender;
- (void)swapSplitSides:(id)sender;
- (void)splitTabFromMenu:(NSMenuItem*)sender;
- (void)updateSplitDragAtScreenPoint:(NSPoint)screenPoint tab:(TabId)identifier base:(TabId)base;
- (BOOL)finishSplitDragAtScreenPoint:(NSPoint)screenPoint tab:(TabId)identifier base:(TabId)base;
- (void)hideSplitDrag;
- (void)beginSidebarTabGesture:(TabId)identifier;
- (TabId)sidebarTabAtRow:(NSInteger)row;
- (TabId)sidebarDraggedTab:(id<NSDraggingInfo>)info;
- (NSDragOperation)updateSidebarPageDrop:(id<NSDraggingInfo>)info;
- (void)endSidebarTabGesture:(TabId)identifier;
- (void)setSplitRatioAtWindowPoint:(NSPoint)point;
- (void)finishSplitResize;
- (void)setupSplitViews;
- (NSInteger)splitSideForTab:(TabId)tab;
- (BOOL)tabInVisibleSplit:(TabId)tab;
- (void)layoutSplitOverlay;
- (void)finishClose:(TabId)identifier;
- (void)closeNextForQuit;
- (void)observePageEvent:(NSEvent*)event;
- (void)memoryChanged:(slate::MemorySample)sample;
#if defined(SLATE_ENABLE_VERIFY)
- (void)startVerifyCommands;
- (void)runVerifyLoopInBackground;
- (void)runVerifyCommand:(NSString*)line;
#endif
- (NSMenu*)tabMenu;
- (NSMenu*)tabStripMenu;
- (void)tabClusterHover:(BOOL)inside;
- (void)hoverTab:(TabId)identifier;
- (void)showExtensions:(id)sender;
- (void)showShields:(id)sender;
- (void)toggleBookmark:(id)sender;
- (void)toggleGroupCollapsed:(NSString*)groupId;
- (NSMenu*)groupMenu:(NSString*)groupId;
- (void)newTabGroup:(id)sender;
- (void)rebuildHome;
- (void)openHomeURL:(id)sender;
- (void)openHomeAddress:(NSString*)url;
- (void)openHomeGroupIdent:(NSString*)ident;
- (void)submitHomeSearch:(id)sender;
- (NSTextField*)homeSearchField;
- (IBAction)showPasswordsPanel:(id)sender;
- (IBAction)showImportBrowserData:(id)sender;
- (IBAction)showAboutSlate:(id)sender;
- (IBAction)showSettings:(id)sender;
- (void)systemAppearanceDidChange:(id)sender;
- (void)toggleShields:(id)sender;
- (void)pauseShieldsSite:(id)sender;
- (void)updateShieldsChrome;
- (void)toggleDownloads:(id)sender;
- (void)fetchSuggestions;
- (void)hideSuggestions;
- (void)pickSuggestion:(id)item;
- (void)applySuggestionHighlight;
- (void)goFromSuggestPanel:(id)sender;
- (void)moveSuggestion:(NSInteger)delta;
- (void)positionSuggestPanel;
- (void)positionSuggestPanelBelowHomeSearch;
- (void)showSuggestionList:(NSArray*)items;
- (void)showSuggestionList:(NSArray*)items fromHomeSearch:(BOOL)homeSearch;
- (void)fetchHomeSearchSuggestions;
- (void)selectTabAtIndex:(NSMenuItem*)sender;
- (void)newTab:(id)sender;
- (void)focusAddress:(id)sender;
- (void)handleTabClick:(TabId)identifier doubleClick:(BOOL)doubleClick;
- (void)setSidebarWidthLive:(CGFloat)width;
- (void)persistSidebarWidth;
- (void)syncTabListColumnWidth;
- (void)scheduleRefresh;
- (void)presentWorkspacePages;
- (BOOL)sidebarRevealed;
- (BOOL)sidebarIconRail;
- (BOOL)stripRevealed;
- (CGFloat)sidebarLayoutWidth;
- (void)toggleTabsReveal:(id)sender;
- (void)syncPageGeometry;
- (void)setTrafficLightsHidden:(BOOL)hidden;
- (void)layoutTrafficLights;
- (void)applyPageZoom;
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)resetZoom:(id)sender;
- (void)updateZoomMenu;
- (void)placeWindowChrome;
- (void)applyPlateChrome;
- (void)applyChromeInk;
- (void)persistUiPrefs;
- (void)setAccent:(id)sender;
- (void)chooseCustomAccent:(id)sender;
- (void)customAccentChanged:(NSColorPanel*)panel;
- (void)rebuildAccentMenu;
- (BOOL)tabIsAudible:(TabId)identifier;
- (void)updateNavChrome;
- (void)updateLoadChrome;
- (void)layoutOmnibox;
- (void)dismissOmnibox;
- (void)dismissOmniboxIfClickOutside:(NSEvent*)event;
- (BOOL)routeChromeClick:(NSEvent*)event;
- (void)syncBrowserOcclusion;
- (NSImage*)iconForTab:(const slate::Tab&)tab;
- (void)paintTabStripAnimated:(BOOL)animated;
- (void)rebuildTabStrip;
- (void)updateSplitTabShape;
- (void)rebuildBookmarksBar;
- (void)rebuildBookmarksMenu;
- (void)toggleBookmarksBar:(id)sender;
- (void)toggleBookmarksDropdown:(id)sender;
- (void)showBookmarksPanel:(id)sender;
- (void)removeBookmarkWithId:(NSString*)bId;
- (void)openUrl:(NSString*)url;
- (void)openUrl:(NSString*)url incognito:(BOOL)incognito;
- (void)beginClose:(TabId)identifier reason:(slate::CloseReason)reason;
- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
- (void)reload:(id)sender;
- (void)hardReload:(id)sender;
- (void)reopenClosedTab:(id)sender;
- (void)selectNextTab:(id)sender;
- (void)selectPreviousTab:(id)sender;
- (void)selectLastTab:(id)sender;
- (void)closeAllTabs:(id)sender;
- (void)closeTabWithId:(TabId)identifier;
- (void)unloadTabWithId:(TabId)identifier;
- (void)toggleTabMute:(TabId)identifier;
- (BOOL)tabIsMuted:(TabId)identifier;
- (BOOL)tabHasAudioState:(TabId)identifier;
- (NSMenu*)tabMenuForTab:(TabId)identifier;
- (void)togglePinTabItem:(id)sender;
- (void)toggleProtectionTabItem:(id)sender;
- (void)closeTabMenuItem:(id)sender;
- (void)toggleTabMuteItem:(id)sender;
- (void)switchSpaceToId:(NSString*)newSpaceId;
- (void)switchSpaceAtIndex:(NSInteger)index;
- (void)switchNextSpace;
- (void)switchPreviousSpace;
- (void)selectSpaceItem:(NSMenuItem*)sender;
- (void)rebuildSpacesMenu;
- (void)showSpaceMenuForButton:(NSView*)button;
- (void)askNewSpace:(id)sender;
- (void)renameCurrentSpace:(id)sender;
- (void)selectSpaceIconItem:(NSMenuItem*)sender;
- (void)moveCurrentSpaceLeft:(id)sender;
- (void)moveCurrentSpaceRight:(id)sender;
- (void)chooseSpaceDownloads:(id)sender;
- (void)resetSpaceDownloads:(id)sender;
- (void)deleteCurrentSpace:(id)sender;
- (void)cleanUpTabs:(id)sender;
- (void)copyCurrentUrl:(id)sender;
- (void)copyCurrentUrlAsMarkdown:(id)sender;
- (void)printPage:(id)sender;
- (void)sharePage:(id)sender;
- (void)findInPage:(id)sender;
- (void)findNext:(id)sender;
- (void)findPrevious:(id)sender;
- (void)viewSource:(id)sender;
- (void)inspectElement:(id)sender;
- (void)newWindow:(id)sender;
- (void)newIncognitoWindow:(id)sender;
- (void)newIncognitoTab:(id)sender;
- (void)showStealthInfo:(id)sender;
- (void)openNewWindowWithUrl:(NSString*)url;
- (WKWebView*)openPopupTabWithConfiguration:(WKWebViewConfiguration*)configuration url:(NSString*)url incognito:(BOOL)incognito;
- (void)tearOffTab:(TabId)tabId atScreenPoint:(NSPoint)screenPoint;
- (BOOL)reattachTab:(TabId)tabId atScreenPoint:(NSPoint)screenPoint;
- (void)reattachAllDetachedTabs;
- (SlateDetachedTabWindow*)detachedTabForWindow:(NSWindow*)window;
- (BOOL)handleDetachedKeyEvent:(NSEvent*)event;
- (void)navigateDetachedTab:(TabId)tabId toURL:(const std::string&)url;
- (void)dragMoveTab:(TabId)tabId toPoint:(NSPoint)localPoint;
- (TabId)splitTargetTabAtWindowPoint:(NSPoint)windowPoint excluding:(TabId)source side:(slate::SplitSide*)side;
- (CGFloat)availableTabStripWidth;
- (void)layoutTabPillsWithAvailableWidth:(CGFloat)availW;
@end
@interface SlateSidebarTable : NSTableView
@property(weak) SlateDelegate* owner;
@end
@implementation SlateSidebarTable
- (void)mouseDown:(NSEvent*)event {
 const NSInteger row=[self rowAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
 const TabId tab=[self.owner sidebarTabAtRow:row];
 if(tab) [self.owner beginSidebarTabGesture:tab];
 [super mouseDown:event];
 if(tab) {
  if(self.owner.splitDragCandidateTab==tab)
   [self.owner handleTabClick:tab doubleClick:event.clickCount>=2];
  [self.owner endSidebarTabGesture:tab];
 }
}
@end
#if defined(SLATE_ENABLE_VERIFY)
// Native drag payload and script-message fixtures exercise the same delegate
// methods AppKit/WebKit call, without touching the user's pasteboard or session.
@interface SlateVerifyDrag : NSObject
@property(strong) NSPasteboard* draggingPasteboard;
@property(strong) id draggingSource;
@property NSPoint draggingLocation;
@end
@implementation SlateVerifyDrag
@end
@interface SlateVerifyMessage : NSObject
@property(strong) NSString* name;
@property(strong) NSDictionary* body;
@end
@implementation SlateVerifyMessage
@end
#endif
@interface SlatePageSlot : NSView
@property(weak) SlateDelegate* owner;
@end
@class SlateTabPill;
@interface SlateAddTabButton : NSButton
@property(strong) NSColor* hoverInk;
@end
@interface SlateTabCloseButton : NSButton
@property(strong) NSColor* hoverInk;
@property(weak) SlateTabPill* pill;
@end
@interface SlateBookmarkButton : NSButton
@property(strong) NSString* bookmarkId;
@property(strong) NSString* urlString;
@property(strong) SlateBookmark* node;
@property(weak) SlateDelegate* owner;
@end
@interface SlateTabPill : NSButton
@property TabId tabId;
@property(strong) NSLayoutConstraint* widthConstraint;
@property BOOL expanded;
@property BOOL selectedTab;
@property BOOL incognitoTab;
@property BOOL hovered;
@property BOOL splitPartner;
@property BOOL splitConnected;
@property(copy) NSString* groupId;
@property(strong) NSColor* groupColor;
@property(strong) CAShapeLayer* tabShapeLayer;
@property(strong) SlateTabCloseButton* closeButton;
@property(strong) NSImageView* faviconView;
@property(strong) NSTextField* titleLabel;
- (void)ensureSubviews;
- (void)layoutTabSubviews;
- (void)applySelected:(BOOL)selected filled:(BOOL)filled hovered:(BOOL)hovered title:(NSString*)title incognito:(BOOL)incognito;
- (void)applySelected:(BOOL)selected filled:(BOOL)filled hovered:(BOOL)hovered title:(NSString*)title;
- (void)applySelected:(BOOL)selected filled:(BOOL)filled title:(NSString*)title;
- (void)applyFilled:(BOOL)filled title:(NSString*)title;
- (void)updateTabShape;
- (void)animateInactiveHover;
- (void)animateClose:(void(^)(void))completion;
@end
@interface SlateTabGroupPill : NSButton
@property(weak) SlateDelegate* owner;
@property(copy) NSString* groupId;
@property(copy) NSString* groupTitle;
@property(strong) NSColor* groupColor;
@property BOOL collapsed;
@property NSInteger tabCount;
@property BOOL hovered;
@property(strong) NSTrackingArea* trackingArea;
@property(strong) NSLayoutConstraint* widthConstraint;
- (void)updateStyle;
@end
typedef NS_ENUM(NSInteger, SlateNavMotion) { SlateNavMotionNone=0, SlateNavMotionBack=-1, SlateNavMotionForward=1, SlateNavMotionReload=2 };
@interface SlateNavButton : NSButton
@property SlateNavMotion navMotion;
@property(strong) NSImageView* glyph;
@property(strong) NSColor* hoverInk;
- (void)playMotion;
- (void)setBusy:(BOOL)busy;
@end
@implementation SlateNavButton
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 for(NSTrackingArea* area in [self.trackingAreas copy]) [self removeTrackingArea:area];
 [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect
  owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent*)event {
 if(!self.enabled) return;
 NSColor* ink=self.hoverInk ?: NSColor.labelColor;
 self.layer.backgroundColor=[ink colorWithAlphaComponent:0.12].CGColor;
}
- (void)mouseExited:(NSEvent*)event {
 self.layer.backgroundColor=NSColor.clearColor.CGColor;
}
- (void)mouseDown:(NSEvent*)event {
 if(!self.enabled) return;
 const CGFloat previous=self.alphaValue;
 self.alphaValue=MAX(0.45, previous*0.7);
 [super mouseDown:event];
 self.alphaValue=self.enabled ? 1 : 0.28;
}
- (void)layout {
 [super layout];
 if(self.glyph) {
  self.glyph.wantsLayer=YES;
  self.glyph.layer.anchorPoint=CGPointMake(0.5, 0.5);
  self.glyph.layer.position=CGPointMake(NSMidX(self.glyph.frame), NSMidY(self.glyph.frame));
 }
}
- (CALayer*)motionLayer {
 if(!self.glyph) return self.layer;
 self.glyph.wantsLayer=YES;
 self.glyph.layer.masksToBounds=NO;
 return self.glyph.layer;
}
- (void)playMotion {
 CALayer* layer=[self motionLayer];
 [layer removeAnimationForKey:@"nav"];
 if(self.navMotion==SlateNavMotionReload) {
  if(self.glyph) {
   self.glyph.wantsLayer=YES;
   self.glyph.layer.anchorPoint=CGPointMake(0.5, 0.5);
   self.glyph.layer.position=CGPointMake(NSMidX(self.glyph.frame), NSMidY(self.glyph.frame));
  }
  CABasicAnimation* spin=[CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
  spin.fromValue=@0; spin.toValue=@(M_PI*-2);
  spin.duration=0.48;
  spin.timingFunction=[CAMediaTimingFunction functionWithControlPoints:0.18 :0.8 :0.22 :1];
  [layer addAnimation:spin forKey:@"nav"];
  return;
 }
 if(self.navMotion==SlateNavMotionNone) return;
 const CGFloat delta=self.navMotion==SlateNavMotionForward ? 4 : -4;
 CAKeyframeAnimation* slide=[CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
 slide.values=@[@0, @(delta), @0];
 slide.keyTimes=@[@0, @0.4, @1];
 slide.duration=0.38;
 slide.timingFunctions=@[
  [CAMediaTimingFunction functionWithControlPoints:0.2 :0.95 :0.28 :1],
  [CAMediaTimingFunction functionWithControlPoints:0.16 :1.15 :0.3 :1]
 ];
 [layer addAnimation:slide forKey:@"nav"];
}
- (void)setBusy:(BOOL)busy {
 CALayer* layer=[self motionLayer];
 const BOOL spinning=[layer animationForKey:@"busy"]!=nil;
 if(busy==spinning) return;
 [layer removeAnimationForKey:@"busy"];
 if(!busy) {
  layer.transform=CATransform3DIdentity;
  return;
 }
 if(self.glyph) {
  self.glyph.wantsLayer=YES;
  self.glyph.layer.anchorPoint=CGPointMake(0.5, 0.5);
  self.glyph.layer.position=CGPointMake(NSMidX(self.glyph.frame), NSMidY(self.glyph.frame));
 }
 CABasicAnimation* spin=[CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
 spin.fromValue=@0; spin.toValue=@(M_PI*-2);
 spin.duration=0.72;
 spin.repeatCount=HUGE_VALF;
 [layer addAnimation:spin forKey:@"busy"];
}
@end
@implementation SlateAddTabButton
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 for(NSTrackingArea* a in [self.trackingAreas copy]) [self removeTrackingArea:a];
 [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent*)event {
 self.alphaValue=1.0;
 NSColor* ink=self.hoverInk ?: NSColor.labelColor;
 self.layer.backgroundColor=[ink colorWithAlphaComponent:0.09].CGColor;
}
- (void)mouseExited:(NSEvent*)event {
 self.alphaValue=0.72;
 self.layer.backgroundColor=NSColor.clearColor.CGColor;
}
@end
@implementation SlateTabCloseButton
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 for(NSTrackingArea* a in [self.trackingAreas copy]) [self removeTrackingArea:a];
 [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent*)event {
 NSColor* ink=self.hoverInk ?: NSColor.labelColor;
 self.layer.backgroundColor=[ink colorWithAlphaComponent:0.22].CGColor;
}
- (void)mouseExited:(NSEvent*)event {
 self.layer.backgroundColor=NSColor.clearColor.CGColor;
}
- (void)mouseDown:(NSEvent*)event {
 SlateDelegate* delegate=[self.pill.target isKindOfClass:SlateDelegate.class] ? (SlateDelegate*)self.pill.target : nil;
 if(delegate && self.pill.tabId) {
  if (([NSApp currentEvent].modifierFlags & NSEventModifierFlagOption) != 0) {
   [delegate unloadTabWithId:self.pill.tabId];
  } else {
   [delegate closeTabWithId:self.pill.tabId];
  }
 }
}
@end

@implementation SlateBookmarkButton
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 for(NSTrackingArea* a in [self.trackingAreas copy]) [self removeTrackingArea:a];
 [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent*)event {
 self.layer.backgroundColor = [SlatePalette wash].CGColor;
}
- (void)mouseExited:(NSEvent*)event {
 self.layer.backgroundColor = NSColor.clearColor.CGColor;
}
- (void)mouseDown:(NSEvent*)event {
 if(self.node && self.node.isFolder) {
  [SlateBookmarkMenu popUpFolder:self.node forView:self owner:self.owner];
  return;
 }
 if(event.modifierFlags & NSEventModifierFlagCommand) {
  if(self.urlString.length && self.owner) [self.owner openUrl:self.urlString];
  return;
 }
 [super mouseDown:event];
}
- (NSMenu*)menuForEvent:(NSEvent*)event {
 if(self.node && self.node.isFolder) {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:self.node.title ?: @"Folder"];
  NSMenuItem* openAll = [menu addItemWithTitle:@"Open All in Tabs" action:@selector(openAllInTabs:) keyEquivalent:@""];
  openAll.target = self;
  [menu addItem:[NSMenuItem separatorItem]];
  NSMenuItem* del = [menu addItemWithTitle:@"Delete Folder" action:@selector(deleteBookmark:) keyEquivalent:@""];
  del.target = self;
  return menu;
 }
 NSMenu* menu=[[NSMenu alloc] initWithTitle:@"Bookmark"];
 NSMenuItem* openNew=[menu addItemWithTitle:@"Open in New Tab" action:@selector(openInNewTab:) keyEquivalent:@""];
 openNew.target=self;
 NSMenuItem* openIncog=[menu addItemWithTitle:@"Open in New Incognito Tab" action:@selector(openInNewIncognitoTab:) keyEquivalent:@""];
 openIncog.target=self;
 NSMenuItem* copyLink=[menu addItemWithTitle:@"Copy Link Address" action:@selector(copyLink:) keyEquivalent:@""];
 copyLink.target=self;
 [menu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* del=[menu addItemWithTitle:@"Delete Bookmark" action:@selector(deleteBookmark:) keyEquivalent:@""];
 del.target=self;
 return menu;
}
- (void)openAllInTabs:(id)sender {
 if(self.node && self.node.isFolder && self.owner) {
  for(NSString* url in [SlateBookmarks urlsForNodes:self.node.children]) {
   [self.owner openUrl:url];
  }
 }
}
- (void)openInNewTab:(id)sender {
 if(self.urlString.length && self.owner) [self.owner openUrl:self.urlString];
}
- (void)openInNewIncognitoTab:(id)sender {
 if(self.urlString.length && self.owner) [self.owner openUrl:self.urlString incognito:YES];
}
- (void)copyLink:(id)sender {
 if(!self.urlString.length) return;
 NSPasteboard* pb=[NSPasteboard generalPasteboard];
 [pb clearContents];
 [pb setString:self.urlString forType:NSPasteboardTypeString];
}
- (void)deleteBookmark:(id)sender {
 if(self.bookmarkId.length && self.owner) [self.owner removeBookmarkWithId:self.bookmarkId];
}
@end

@implementation SlateTabPill
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 for(NSTrackingArea* area in [self.trackingAreas copy]) [self removeTrackingArea:area];
 [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect
  owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent*)event {
 self.hovered=YES;
 if(!self.selectedTab) [self animateInactiveHover];
 if(self.closeButton) {
  SlateDelegate* delegate=[self.target isKindOfClass:SlateDelegate.class] ? (SlateDelegate*)self.target : nil;
  const BOOL regularTabs = (delegate && delegate.tabStyle == 1);
  self.closeButton.hidden = regularTabs ? (!self.selectedTab && !self.hovered) : !(self.expanded && (self.hovered || self.selectedTab));
  [self layoutTabSubviews];
 }
}
- (void)mouseExited:(NSEvent*)event {
 self.hovered=NO;
 if(!self.selectedTab) [self animateInactiveHover];
 if(self.closeButton) {
  SlateDelegate* delegate=[self.target isKindOfClass:SlateDelegate.class] ? (SlateDelegate*)self.target : nil;
  const BOOL regularTabs = (delegate && delegate.tabStyle == 1);
  self.closeButton.hidden = regularTabs ? (!self.selectedTab && !self.hovered) : !(self.expanded && (self.hovered || self.selectedTab));
  [self layoutTabSubviews];
 }
}
- (NSView*)hitTest:(NSPoint)point {
 if(self.hidden || self.alphaValue<0.05) return nil;
 NSPoint local=[self convertPoint:point fromView:self.superview];
 if(!NSPointInRect(local, self.bounds)) return nil;
 if(self.closeButton && !self.closeButton.hidden) {
  NSPoint closeLocal=[self.closeButton convertPoint:point fromView:self.superview];
  if(NSPointInRect(closeLocal, self.closeButton.bounds)) return self.closeButton;
 }
 return self;
}
- (void)mouseDown:(NSEvent*)event {
 SlateDelegate* delegate=[self.target isKindOfClass:SlateDelegate.class] ? (SlateDelegate*)self.target : nil;
 if(self.closeButton && !self.closeButton.hidden) {
  NSPoint closePt=[self.closeButton convertPoint:event.locationInWindow fromView:nil];
  if(NSPointInRect(closePt, NSInsetRect(self.closeButton.bounds, -4, -4))) {
   if(delegate) [delegate beginClose:self.tabId reason:slate::CloseReason::Remove];
   return;
  }
 }
 if(event.clickCount > 1) {
  if(delegate) [delegate handleTabClick:self.tabId doubleClick:YES];
  return;
 }
 if(!delegate) return;

 NSWindow* dragWindow=self.window;
 const NSPoint startLocInWindow = event.locationInWindow;
 const NSPoint startLocInScreen = [dragWindow convertPointToScreen:startLocInWindow];
 const TabId baseTab=model.selected();
 BOOL isDragging = NO;
 BOOL isTearOffCandidate = NO;

 while (YES) {
  NSEvent* nextEvent = [dragWindow nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp
                                                untilDate:[NSDate distantFuture]
                                                   inMode:NSEventTrackingRunLoopMode
                                                  dequeue:YES];
  if (!nextEvent) break;

  if (nextEvent.type == NSEventTypeLeftMouseDragged) {
   NSPoint curLocInWindow = nextEvent.locationInWindow;
   NSPoint curLocInScreen = [dragWindow convertPointToScreen:curLocInWindow];
   CGFloat dx = curLocInScreen.x - startLocInScreen.x;
   CGFloat dy = curLocInScreen.y - startLocInScreen.y;
   CGFloat dist = hypot(dx, dy);

   if (!isDragging && dist > 6.0) {
    isDragging = YES;
   }

   if (isDragging) {
    NSRect winFrame = dragWindow.frame;
    NSRect tabClusterScreenRect = [dragWindow convertRectToScreen:[delegate.tabCluster convertRect:delegate.tabCluster.bounds toView:nil]];

    BOOL outsideTabBar = (fabs(dy) > 32.0) || !NSPointInRect(curLocInScreen, NSInsetRect(tabClusterScreenRect, -20, -12));
    BOOL outsideWindow = !NSPointInRect(curLocInScreen, winFrame);

    NSRect contentScreenRect=[dragWindow convertRectToScreen:[delegate.content convertRect:delegate.content.bounds toView:nil]];
    const BOOL overContent=NSPointInRect(curLocInScreen,contentScreenRect);
    isTearOffCandidate = (outsideTabBar || outsideWindow) && !overContent;
    if(overContent) {
     [NSCursor.arrowCursor set];
     self.alphaValue=0.75;
     [delegate updateSplitDragAtScreenPoint:curLocInScreen tab:self.tabId base:baseTab];
    } else if (isTearOffCandidate) {
     [delegate hideSplitDrag];
     [NSCursor.disappearingItemCursor set];
     self.alphaValue = 0.5;
    } else {
     [delegate hideSplitDrag];
     [NSCursor.arrowCursor set];
     self.alphaValue = 1.0;
     // The middle of another tab is a split drop zone. Its outer edges keep
     // the existing reorder gesture, so the two actions remain distinct.
     if(![delegate splitTargetTabAtWindowPoint:curLocInWindow excluding:self.tabId side:nullptr]) {
      NSPoint localInCluster = [delegate.tabCluster convertPoint:curLocInWindow fromView:nil];
      [delegate dragMoveTab:self.tabId toPoint:localInCluster];
     }
    }
   }
  } else if (nextEvent.type == NSEventTypeLeftMouseUp) {
   [NSCursor.arrowCursor set];
   self.alphaValue = 1.0;
   NSPoint endLocInScreen=[dragWindow convertPointToScreen:nextEvent.locationInWindow];
   BOOL didSplit=isDragging && [delegate finishSplitDragAtScreenPoint:endLocInScreen tab:self.tabId base:baseTab];
   if(isDragging && !didSplit) {
    slate::SplitSide side=slate::SplitSide::Right;
    const TabId target=[delegate splitTargetTabAtWindowPoint:nextEvent.locationInWindow excluding:self.tabId side:&side];
    if(target) didSplit=[delegate isSplitPlaceholderTab:target]
     ? [delegate replaceEmptySplitTab:target withTab:self.tabId]
     : [delegate openSplitWithTab:self.tabId side:side base:target];
   }
   NSRect contentScreenRect=[dragWindow convertRectToScreen:[delegate.content convertRect:delegate.content.bounds toView:nil]];
   if(isDragging && !didSplit && isTearOffCandidate && !NSPointInRect(endLocInScreen,contentScreenRect))
    [delegate tearOffTab:self.tabId atScreenPoint:endLocInScreen];
   else if(!isDragging) [delegate handleTabClick:self.tabId doubleClick:NO];
   break;
  }
 }
 [delegate hideSplitDrag];
}
- (NSMenu*)menuForEvent:(NSEvent*)event {
 SlateDelegate* delegate=(SlateDelegate*)self.target;
 return [delegate tabMenuForTab:self.tabId];
}
- (void)ensureSubviews {
 if(!self.faviconView) {
  self.faviconView=[[NSImageView alloc] initWithFrame:NSMakeRect(0,0,16,16)];
  self.faviconView.imageScaling=NSImageScaleProportionallyUpOrDown;
  self.faviconView.wantsLayer=YES;
  [self addSubview:self.faviconView];
 }
 if(!self.titleLabel) {
  self.titleLabel=[NSTextField labelWithString:@""];
  self.titleLabel.font=[NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
  self.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;
  self.titleLabel.maximumNumberOfLines=1;
  self.titleLabel.usesSingleLineMode=YES;
  self.titleLabel.cell.wraps=NO;
  self.titleLabel.cell.scrollable=NO;
  self.titleLabel.cell.truncatesLastVisibleLine=YES;
  self.titleLabel.wantsLayer=YES;
  self.titleLabel.bezeled=NO;
  self.titleLabel.drawsBackground=NO;
  self.titleLabel.editable=NO;
  self.titleLabel.selectable=NO;
  [self addSubview:self.titleLabel];
 }
 [self ensureCloseButton];
}
- (void)setImage:(NSImage*)image {
 [self ensureSubviews];
 self.faviconView.image=image;
 [super setImage:nil];
 [self setNeedsLayout:YES];
}
- (NSImage*)image {
 return self.faviconView.image;
}
- (void)setTitle:(NSString*)title {
 [self ensureSubviews];
 self.titleLabel.stringValue=title ?: @"";
 [super setTitle:@""];
}
- (NSString*)title {
 return self.titleLabel.stringValue ?: @"";
}
- (void)layout {
 [super layout];
 [self updateTabShape];
 [self layoutTabSubviews];
}
- (void)setFrame:(NSRect)frame {
 [super setFrame:frame];
 [self updateTabShape];
 [self layoutTabSubviews];
}
- (void)layoutTabSubviews {
 [self ensureSubviews];
 const NSRect b=self.bounds;
 const CGFloat w=b.size.width;
 const CGFloat h=b.size.height;
 if(w<=0 || h<=0) return;

 const CGFloat iconSize=16.0;
 const BOOL compact=(w<=36.0) || !self.expanded;

 if(compact) {
  const CGFloat iconX=round((w-iconSize)/2.0);
  const CGFloat iconY=round((h-iconSize)/2.0);
  self.faviconView.frame=NSMakeRect(iconX, iconY, iconSize, iconSize);
  self.faviconView.hidden=(self.faviconView.image==nil);
  self.titleLabel.hidden=YES;
  if(self.closeButton) self.closeButton.hidden=YES;
  return;
 }

 const CGFloat leftPadding=9.0;
 const CGFloat iconX=leftPadding;
 const CGFloat iconY=round((h-iconSize)/2.0);
 self.faviconView.frame=NSMakeRect(iconX, iconY, iconSize, iconSize);
 self.faviconView.hidden=(self.faviconView.image==nil);

 const CGFloat closeSize=16.0;
 const CGFloat rightMargin=6.0;
 const CGFloat closeX=w-rightMargin-closeSize;
 const CGFloat closeY=round((h-closeSize)/2.0);
 if(self.closeButton) {
  self.closeButton.frame=NSMakeRect(closeX, closeY, closeSize, closeSize);
 }

 const CGFloat iconSpacing=8.0;
 const CGFloat titleX=(self.faviconView.image!=nil) ? (iconX+iconSize+iconSpacing) : leftPadding;
 CGFloat maxTitleRight=w-rightMargin;
 if(self.closeButton && !self.closeButton.hidden) {
  maxTitleRight=closeX-4.0;
 }
 const CGFloat titleW=MAX(0.0, maxTitleRight-titleX);
 const CGFloat titleH=16.0;
 const CGFloat titleY=round((h-titleH)/2.0);
 self.titleLabel.frame=NSMakeRect(titleX, titleY, titleW, titleH);
 self.titleLabel.hidden=(titleW<10.0 || self.titleLabel.stringValue.length==0);
}
- (void)animateInactiveHover {
 CGColorRef previous=self.layer.backgroundColor ? CGColorRetain(self.layer.backgroundColor) : nullptr;
 [self updateTabShape];
 if(previous && self.layer.backgroundColor && !CGColorEqualToColor(previous, self.layer.backgroundColor)) {
  CABasicAnimation* fade=[CABasicAnimation animationWithKeyPath:@"backgroundColor"];
  fade.fromValue=(__bridge id)previous;
  fade.toValue=(__bridge id)self.layer.backgroundColor;
  fade.duration=0.15;
  fade.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
  [self.layer addAnimation:fade forKey:@"inactiveHover"];
 }
 if(previous) CGColorRelease(previous);
}
static NSColor* TabGroupColorForId(const std::string& groupId, const std::string& title) {
 static NSArray<NSColor*>* colors = nil;
 static dispatch_once_t once;
 dispatch_once(&once, ^{
  colors = @[
   [NSColor colorWithCalibratedRed:0.0 green:0.48 blue:1.0 alpha:1.0],   // Blue
   [NSColor colorWithCalibratedRed:0.69 green:0.32 blue:0.87 alpha:1.0], // Purple
   [NSColor colorWithCalibratedRed:1.0 green:0.58 blue:0.0 alpha:1.0],   // Orange
   [NSColor colorWithCalibratedRed:0.20 green:0.78 blue:0.35 alpha:1.0], // Green
   [NSColor colorWithCalibratedRed:1.0 green:0.18 blue:0.33 alpha:1.0],  // Pink / Rose
   [NSColor colorWithCalibratedRed:0.25 green:0.72 blue:0.85 alpha:1.0], // Teal / Cyan
   [NSColor colorWithCalibratedRed:0.95 green:0.70 blue:0.0 alpha:1.0],  // Gold / Yellow
   [NSColor colorWithCalibratedRed:0.55 green:0.55 blue:0.60 alpha:1.0]  // Slate
  ];
 });
 NSUInteger hash = 0;
 for (char c : groupId) hash = hash * 31 + (NSUInteger)(unsigned char)c;
 for (char c : title) hash = hash * 31 + (NSUInteger)(unsigned char)c;
 return colors[hash % colors.count];
}

- (void)updateTabShape {
 if(!self.layer) return;
 SlateDelegate* delegate=[self.target isKindOfClass:SlateDelegate.class] ? (SlateDelegate*)self.target : nil;
 BOOL isDark = delegate ? [delegate isDarkAppearance] : YES;
 if(!delegate && self.window) {
  NSAppearanceName appearanceName = [self.window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
  isDark = [appearanceName isEqualToString:NSAppearanceNameDarkAqua];
 }
 const BOOL regularTabs = (delegate && delegate.tabStyle == 1);
 const BOOL selected=self.selectedTab;
 self.layer.cornerCurve=kCACornerCurveContinuous;
 self.layer.zPosition=selected ? 10 : 0;
 self.layer.cornerRadius=selected ? 0 : (regularTabs ? 9.0 : 8.0);
 self.layer.masksToBounds=!selected;

 const BOOL hasGroup = (self.groupId.length > 0 && self.groupColor != nil);
 NSColor* chromeBg = delegate.window.backgroundColor
  ?: (isDark ? [NSColor colorWithCalibratedWhite:0.18 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.93 alpha:1.0]);
 const BOOL chromeIsDark = ColorIsDark(chromeBg);

 if(self.splitConnected) {
  if(self.tabShapeLayer) self.tabShapeLayer.hidden=YES;
  self.layer.backgroundColor=NSColor.clearColor.CGColor;
  self.layer.borderWidth=0;
  return;
 }
 if(selected) {
  NSColor* selectedColor=delegate.barColor
   ?: (isDark ? [NSColor colorWithCalibratedWhite:0.12 alpha:1.0] : NSColor.whiteColor);
  if(!self.tabShapeLayer) {
   self.tabShapeLayer=[CAShapeLayer layer];
   self.tabShapeLayer.masksToBounds=NO;
   [self.layer insertSublayer:self.tabShapeLayer atIndex:0];
  }
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.tabShapeLayer.hidden=NO;
  self.tabShapeLayer.frame=self.bounds;
  CGPathRef path=CreateActiveBrowserTabPath(self.bounds, self.isFlipped);
  self.tabShapeLayer.path=path;
  CGPathRelease(path);
  self.tabShapeLayer.fillColor=selectedColor.CGColor;
  self.layer.backgroundColor=NSColor.clearColor.CGColor;
  self.layer.borderWidth=0;
  [CATransaction commit];
  return;
 }
 if(self.tabShapeLayer) self.tabShapeLayer.hidden=YES;

 if(hasGroup) {
  self.layer.borderWidth = 1.0;
  self.layer.borderColor = [self.groupColor colorWithAlphaComponent:0.40].CGColor;
 } else {
  self.layer.borderWidth = self.splitPartner ? 1.0 : ((self.hovered && !regularTabs) ? 0.5 : 0.0);
  self.layer.borderColor = chromeIsDark ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.10].CGColor : [NSColor colorWithCalibratedWhite:0.0 alpha:0.06].CGColor;
  if(self.splitPartner && delegate) self.layer.borderColor=[ChromeAccent(delegate.accentId,delegate.accentHex,isDark) colorWithAlphaComponent:0.7].CGColor;
 }

 if(self.splitPartner && delegate) {
  self.layer.backgroundColor=[ChromeAccent(delegate.accentId,delegate.accentHex,isDark) colorWithAlphaComponent:0.16].CGColor;
 } else if(!self.hovered) {
  self.layer.backgroundColor=NSColor.clearColor.CGColor;
 } else if(hasGroup) {
  self.layer.backgroundColor=[self.groupColor colorWithAlphaComponent:0.12].CGColor;
 } else {
  NSColor* hoverInk=chromeIsDark ? NSColor.whiteColor : NSColor.blackColor;
  self.layer.backgroundColor=[hoverInk colorWithAlphaComponent:0.08].CGColor;
 }
}
- (void)ensureCloseButton {
 if(self.closeButton) return;
 self.closeButton=[[SlateTabCloseButton alloc] initWithFrame:NSMakeRect(0,0,16,16)];
 self.closeButton.pill=self;
 self.closeButton.bordered=NO;
 self.closeButton.bezelStyle=NSBezelStyleInline;
 self.closeButton.imagePosition=NSImageOnly;
 self.closeButton.wantsLayer=YES;
 self.closeButton.layer.cornerCurve=kCACornerCurveContinuous;
 self.closeButton.layer.cornerRadius=4.0;
 self.closeButton.layer.masksToBounds=YES;
 self.closeButton.toolTip=@"Close tab";
 NSImage* xImage=nil;
 if(@available(macOS 11.0, *)) {
  NSImageSymbolConfiguration* cfg=[NSImageSymbolConfiguration configurationWithPointSize:8.5 weight:NSFontWeightMedium];
  xImage=[[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close tab"] imageWithSymbolConfiguration:cfg];
 }
 if(!xImage) {
  xImage=[NSImage imageNamed:NSImageNameStopProgressTemplate];
 }
 self.closeButton.image=xImage;
 [self addSubview:self.closeButton];
}
- (void)applySelected:(BOOL)selected filled:(BOOL)filled hovered:(BOOL)hovered title:(NSString*)title incognito:(BOOL)incognito {
 SlateDelegate* delegate=[self.target isKindOfClass:SlateDelegate.class] ? (SlateDelegate*)self.target : nil;
 BOOL isDark = delegate ? [delegate isDarkAppearance] : YES;
 if(!delegate && self.window) {
  NSAppearanceName appearanceName = [self.window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
  isDark = [appearanceName isEqualToString:NSAppearanceNameDarkAqua];
 }
 const BOOL regularTabs = (delegate && delegate.tabStyle == 1);
 const BOOL isFilled = regularTabs || filled;
 const CGFloat width=isFilled ? TabFillWidth(title) : kCompactTabWidth;
 self.selectedTab=selected;
 self.expanded=isFilled;
 self.incognitoTab=incognito;
 self.hovered=hovered;

 NSColor* chromeBg = delegate.window.backgroundColor
  ?: (isDark ? [NSColor colorWithCalibratedWhite:0.18 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.93 alpha:1.0]);
 const BOOL chromeIsDark = ColorIsDark(chromeBg);

 NSColor* ink = nil;
 NSColor* textInk = nil;
 if(selected) {
  const BOOL activeDark = delegate.barColor ? ColorIsDark(delegate.barColor) : isDark;
  ink = activeDark ? [NSColor colorWithCalibratedWhite:0.96 alpha:0.95] : [NSColor colorWithCalibratedWhite:0.11 alpha:0.92];
  textInk = ink;
 } else {
  const BOOL inactiveDark = chromeIsDark;
  ink = inactiveDark ? [NSColor colorWithCalibratedWhite:0.96 alpha:0.95] : [NSColor colorWithCalibratedWhite:0.11 alpha:0.92];
  textInk = inactiveDark
   ? [NSColor colorWithCalibratedWhite:0.96 alpha:hovered ? 0.98 : 0.82]
   : [NSColor colorWithCalibratedWhite:0.11 alpha:hovered ? 0.95 : 0.78];
 }

 self.contentTintColor=ink;

 [self ensureSubviews];
 self.faviconView.contentTintColor=self.faviconView.image.isTemplate
  ? (selected ? (delegate.barInk ?: NSColor.labelColor) : ink)
  : nil;
 self.titleLabel.font=[NSFont systemFontOfSize:11.5 weight:selected ? NSFontWeightMedium : NSFontWeightRegular];
 self.titleLabel.textColor=textInk;
 self.titleLabel.stringValue=title ?: @"";

 [super setTitle:@""];
 [super setAttributedTitle:[[NSAttributedString alloc] initWithString:@""]];

 if(self.widthConstraint && !regularTabs) {
  self.widthConstraint.constant=width;
 }
 [self ensureCloseButton];
 self.closeButton.hoverInk=ink;
 self.closeButton.contentTintColor=ink;
 self.closeButton.hidden = regularTabs ? (!selected && !hovered) : !(isFilled && (hovered || selected));
 [self updateTabShape];
 [self layoutTabSubviews];
}
- (void)applySelected:(BOOL)selected filled:(BOOL)filled hovered:(BOOL)hovered title:(NSString*)title {
 [self applySelected:selected filled:filled hovered:hovered title:title incognito:self.incognitoTab];
}
- (void)applySelected:(BOOL)selected filled:(BOOL)filled title:(NSString*)title {
 [self applySelected:selected filled:filled hovered:NO title:title incognito:self.incognitoTab];
}
- (void)applyFilled:(BOOL)filled title:(NSString*)title {
 [self applySelected:self.selectedTab filled:filled hovered:NO title:title incognito:self.incognitoTab];
}
- (void)animateClose:(void(^)(void))completion {
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
  context.duration=0.2;
  context.timingFunction=[CAMediaTimingFunction functionWithControlPoints:0.3 :0 :1 :1];
  self.animator.alphaValue=0;
  self.widthConstraint.animator.constant=0;
 } completionHandler:completion];
}
@end

@implementation SlateTabGroupPill
- (instancetype)initWithFrame:(NSRect)frame {
 if(self = [super initWithFrame:frame]) {
  self.wantsLayer = YES;
  self.bordered = NO;
  self.bezelStyle = NSBezelStyleFlexiblePush;
  self.imagePosition = NSNoImage;
  self.alignment = NSTextAlignmentCenter;
  self.refusesFirstResponder = YES;
  self.target = self;
  self.action = @selector(groupClicked:);
  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.widthConstraint = [self.widthAnchor constraintEqualToConstant:70];
  self.widthConstraint.priority = NSLayoutPriorityDefaultLow;
  self.widthConstraint.active = YES;
  [self.heightAnchor constraintEqualToConstant:kTabHeight].active = YES;
  [self setContentHuggingPriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self setContentCompressionResistancePriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
 }
 return self;
}
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if(self.trackingArea) [self removeTrackingArea:self.trackingArea];
 self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
  owner:self userInfo:nil];
 [self addTrackingArea:self.trackingArea];
}
- (void)mouseEntered:(NSEvent*)event {
 (void)event;
 self.hovered = YES;
 [self updateStyle];
}
- (void)mouseExited:(NSEvent*)event {
 (void)event;
 self.hovered = NO;
 [self updateStyle];
}
- (void)groupClicked:(id)sender {
 (void)sender;
 if(self.owner && self.groupId.length) {
  [self.owner toggleGroupCollapsed:self.groupId];
 }
}
- (NSMenu*)menuForEvent:(NSEvent*)event {
 (void)event;
 if(self.owner && self.groupId.length) {
  return [self.owner groupMenu:self.groupId];
 }
 return nil;
}
- (void)updateStyle {
 if(!self.layer) return;
 const BOOL regularTabs = (self.owner && self.owner.tabStyle == 1);
 self.layer.cornerCurve = kCACornerCurveContinuous;
 if(regularTabs) {
  CACornerMask topCorners = self.isFlipped
   ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner)
   : (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
  self.layer.cornerRadius = 9.0;
  self.layer.maskedCorners = topCorners;
 } else {
  self.layer.cornerRadius = 8.0;
  self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
 }
 self.layer.masksToBounds = YES;

 NSColor* gColor = self.groupColor ?: [NSColor systemBlueColor];
 CGFloat bgAlpha = self.hovered ? 0.26 : (self.collapsed ? 0.22 : 0.14);
 self.layer.backgroundColor = [gColor colorWithAlphaComponent:bgAlpha].CGColor;
 self.layer.borderWidth = 1.0;
 self.layer.borderColor = [gColor colorWithAlphaComponent:self.hovered ? 0.70 : 0.45].CGColor;

 NSString* title = self.groupTitle.length ? self.groupTitle : @"Group";
 NSString* displayTitle = self.collapsed ? [NSString stringWithFormat:@"%@  %ld ›", title, (long)self.tabCount] : title;

 NSDictionary* attrs = @{
  NSFontAttributeName: [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold],
  NSForegroundColorAttributeName: gColor
 };
 self.attributedTitle = [[NSAttributedString alloc] initWithString:displayTitle attributes:attrs];
 self.toolTip = [NSString stringWithFormat:@"%@ (%ld tabs) — Click to %@", title, (long)self.tabCount, self.collapsed ? @"expand" : @"collapse"];

 NSSize textSize = [displayTitle sizeWithAttributes:attrs];
 CGFloat calculatedW = MAX(44.0, ceil(textSize.width + 16.0));
 self.widthConstraint.constant = calculatedW;
}
@end
namespace {
void FreezeWebLayer(NSView* view) {
 if(!view) return;
 view.clipsToBounds=YES;
 if(!view.layer) return;
 static NSDictionary* actions;
 static dispatch_once_t once;
 dispatch_once(&once, ^{
  NSNull* n=[NSNull null];
  actions=@{@"bounds":n,@"position":n,@"frame":n,@"contents":n,@"transform":n,
            @"sublayerTransform":n,@"contentsScale":n};
 });
 view.layer.actions=actions;
 view.layer.shouldRasterize=NO;
 view.layer.transform=CATransform3DIdentity;
 view.layer.sublayerTransform=CATransform3DIdentity;
}
NSRect WebFillRect(NSView* parent) {
 NSSize size=parent.bounds.size;
 if(parent.window) {
  NSSize backing=[parent convertSizeToBacking:size];
  backing.width=MAX(1, floor(backing.width));
  backing.height=MAX(1, floor(backing.height));
  size=[parent convertSizeFromBacking:backing];
 } else {
  size.width=MAX(1, floor(size.width));
  size.height=MAX(1, floor(size.height));
 }
 return NSMakeRect(0,0,size.width,size.height);
}
NSView* SplitChild(NSView* parent, NSString* identifier) {
 for(NSView* child in parent.subviews) if([child.identifier isEqualToString:identifier]) return child;
 return nil;
}
} // namespace
@implementation SlatePageSlot
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return [self.owner updateSidebarPageDrop:info]; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info { return [self.owner updateSidebarPageDrop:info]; }
- (void)draggingExited:(id<NSDraggingInfo>)info { [self.owner hideSplitDrag]; }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return [self.owner updateSidebarPageDrop:info]!=NSDragOperationNone; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
 const TabId tab=[self.owner sidebarDraggedTab:info];
 if(!tab) return NO;
 return [self.owner finishSplitDragAtScreenPoint:[self.window convertPointToScreen:info.draggingLocation]
  tab:tab base:self.owner.splitDragBaseTab ?: model.selected()];
}
- (void)layout {
 [super layout];
 [self pinPageHosts];
}
- (void)setFrameSize:(NSSize)size {
 [super setFrameSize:size];
 [self pinPageHosts];
}
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
 [super resizeSubviewsWithOldSize:oldSize];
 [self pinPageHosts];
}
- (void)pinPageHosts {
 if(!self.owner || self.owner.syncingGeometry || self.owner.chromeAnimating) return;
 [self.owner syncPageGeometry];
}
@end
@interface SlateSplitDivider : NSView
@property(weak) SlateDelegate* owner;
@property BOOL hovered;
@end
@implementation SlateSplitDivider
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)resetCursorRects {
 [super resetCursorRects];
 [self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor];
}
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 for(NSTrackingArea* area in [self.trackingAreas copy]) [self removeTrackingArea:area];
 [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect
  owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent*)event { self.hovered=YES; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent*)event { self.hovered=NO; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)dirtyRect {
 [super drawRect:dirtyRect];
 if(!self.hovered) return;
 NSColor* color=[ChromeAccent(self.owner.accentId,self.owner.accentHex,[self.owner isDarkAppearance]) colorWithAlphaComponent:0.55];
 [color setFill];
 NSRectFill(NSMakeRect(floor(NSMidX(self.bounds)),0,1,NSHeight(self.bounds)));
}
- (void)mouseDown:(NSEvent*)event { [self.window makeFirstResponder:self]; }
- (void)mouseDragged:(NSEvent*)event { [self.owner setSplitRatioAtWindowPoint:event.locationInWindow]; }
- (void)mouseUp:(NSEvent*)event { [self.owner finishSplitResize]; }
- (void)keyDown:(NSEvent*)event {
 if(event.keyCode!=123 && event.keyCode!=124) { [super keyDown:event]; return; }
 NSPoint point=[self.owner.content convertPoint:NSMakePoint(NSMidX(self.frame)+(event.keyCode==123?-12:12),0) toView:nil];
 [self.owner setSplitRatioAtWindowPoint:point];
 [self.owner finishSplitResize];
}
- (NSMenu*)menuForEvent:(NSEvent*)event {
 NSMenu* menu=[[NSMenu alloc] init];
 NSMenuItem* swap=[menu addItemWithTitle:@"Swap Split Sides" action:@selector(swapSplitSides:) keyEquivalent:@""];
 swap.target=self.owner;
 NSMenuItem* close=[menu addItemWithTitle:@"Exit Split View" action:@selector(exitSplitView:) keyEquivalent:@""];
 close.target=self.owner;
 return menu;
}
@end
@interface SlateSplitOverlay : NSView
@end
@implementation SlateSplitOverlay
- (NSView*)hitTest:(NSPoint)point { return nil; }
@end
@interface SlateTabPills : NSStackView
@property(weak) SlateDelegate* owner;
@end
@implementation SlateTabPills
- (void)layout {
 [super layout];
 [self.owner updateSplitTabShape];
}
@end
@interface SlateTabCluster : NSView
@property(weak) SlateDelegate* owner;
@end
@implementation SlateTabCluster
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (NSView*)hitTest:(NSPoint)point {
 if(self.hidden || self.alphaValue<0.05) return nil;
 NSPoint local=[self convertPoint:point fromView:self.superview];
 if(!NSPointInRect(local, NSInsetRect(self.bounds,0,-6))) return nil;
 NSView* hit=[super hitTest:point];
 return hit ?: self;
}
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 for(NSTrackingArea* area in [self.trackingAreas copy]) [self removeTrackingArea:area];
 [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited|NSTrackingMouseMoved|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect
  owner:self userInfo:nil]];
}
- (TabId)tabIdAtPoint:(NSPoint)point {
 for(NSView* view in self.owner.tabPills.arrangedSubviews) {
  SlateTabPill* pill=(SlateTabPill*)view;
  NSRect frame=[self convertRect:pill.frame fromView:pill.superview];
  if(NSPointInRect(point,NSInsetRect(frame,-4,-8))) return pill.tabId;
 }
 return 0;
}
- (void)mouseDown:(NSEvent*)event {
 NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
 for(NSView* view in self.owner.tabPills.arrangedSubviews) {
  if(![view isKindOfClass:SlateTabPill.class]) continue;
  SlateTabPill* pill=(SlateTabPill*)view;
  NSRect frame=[self convertRect:pill.frame fromView:pill.superview];
  if(NSPointInRect(point, NSInsetRect(frame,-4,-8))) {
   [pill mouseDown:event];
   return;
  }
 }
 if(self.owner.addButton.alphaValue>0.4 && NSPointInRect(point,self.owner.addButton.frame))
  [self.owner newTab:self.owner.addButton];
}
- (void)rightMouseDown:(NSEvent*)event {
 NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
 TabId hit=[self tabIdAtPoint:point];
 if(!hit) {
  NSMenu* menu=[self.owner tabStripMenu];
  if(menu) [NSMenu popUpContextMenu:menu withEvent:event forView:self];
  return;
 }
 [NSMenu popUpContextMenu:[self.owner tabMenuForTab:hit] withEvent:event forView:self];
}
- (NSMenu*)menuForEvent:(NSEvent*)event {
 NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
 TabId hit=[self tabIdAtPoint:point];
 if(!hit) return [self.owner tabStripMenu];
 return [self.owner tabMenuForTab:hit];
}
- (void)mouseEntered:(NSEvent*)event { [self.owner tabClusterHover:YES]; [self mouseMoved:event]; }
- (void)mouseExited:(NSEvent*)event { [self.owner tabClusterHover:NO]; }
- (void)mouseMoved:(NSEvent*)event {
 [self.owner hoverTab:[self tabIdAtPoint:[self convertPoint:event.locationInWindow fromView:nil]]];
}
- (void)otherMouseDown:(NSEvent*)event {
 if(event.buttonNumber==2) {
  NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
  TabId hit=[self tabIdAtPoint:point];
  if(hit) [self.owner beginClose:hit reason:slate::CloseReason::Remove];
 }
}
@end
typedef NS_ENUM(NSInteger, SlateRowPillStyle) {
 SlateRowPillNone,
 SlateRowPillSingleTab, // Selected tab outside group
 SlateRowPillGroupCollapsed,
 SlateRowPillGroupTop,
 SlateRowPillGroupMiddle,
 SlateRowPillGroupBottom
};

@interface SlateTabBubble : NSView
@property(weak) SlateDelegate* owner;
@property TabId tabId;
@property BOOL selectedTab;
@property BOOL loading;
@property(strong) NSImage* mark;
@property(strong) CALayer* bgLayer;
@property(strong) CALayer* iconLayer;
@end
@implementation SlateTabBubble
- (instancetype)initWithFrame:(NSRect)frame {
 if(self=[super initWithFrame:frame]) {
  self.wantsLayer = YES;
  self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
  self.bgLayer = [CALayer layer];
  self.iconLayer = [CALayer layer];
  self.iconLayer.contentsGravity = kCAGravityResizeAspect;
  [self.layer addSublayer:self.bgLayer];
  [self.layer addSublayer:self.iconLayer];
 }
 return self;
}
- (BOOL)isFlipped { return NO; }
- (BOOL)wantsUpdateLayer { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)mouseDown:(NSEvent*)event {
 [self.superview mouseDown:event];
}
- (void)updateLayer {
 const BOOL rail=self.owner && [self.owner sidebarIconRail];

 [CATransaction begin];
 [CATransaction setDisableActions:YES];

 self.bgLayer.hidden = YES;
 // The row cell owns the visible mark size and centers this view in the rail.
 self.iconLayer.frame = self.bounds;

 if(self.mark) {
  id contents = [self.mark layerContentsForContentsScale:self.window.backingScaleFactor ?: 2.0];
  if(self.mark.isTemplate) {
   CALayer* mask=self.iconLayer.mask ?: [CALayer layer];
   mask.frame=self.iconLayer.bounds;
   mask.contentsGravity=kCAGravityResizeAspect;
   mask.contents=contents;
   self.iconLayer.mask=mask;
   self.iconLayer.contents=nil;
   self.iconLayer.backgroundColor=(self.selectedTab ? NSColor.labelColor : NSColor.secondaryLabelColor).CGColor;
  } else {
   self.iconLayer.mask=nil;
   self.iconLayer.backgroundColor=nil;
   self.iconLayer.contents=contents;
  }
  self.iconLayer.opacity = self.loading ? 0.55 : 1.0;
 } else {
  self.iconLayer.mask=nil;
  self.iconLayer.backgroundColor=nil;
  self.iconLayer.contents = nil;
 }

 [CATransaction commit];
}
@end

@interface SlateTabActionButton : NSButton
@property BOOL circularBg;
@property BOOL hovered;
@property(strong) NSTrackingArea* trackingArea;
@end

@implementation SlateTabActionButton
- (instancetype)initWithFrame:(NSRect)frame {
 if(self = [super initWithFrame:frame]) {
  self.bordered = NO;
  self.bezelStyle = NSBezelStyleRegularSquare;
  self.title = @"";
  self.imagePosition = NSImageOnly;
  self.imageScaling = NSImageScaleProportionallyDown;
  self.refusesFirstResponder = YES;
  self.wantsLayer = YES;
  self.layer.cornerRadius = round(frame.size.width / 2.0);
  if(@available(macOS 11.0, *)) self.layer.cornerCurve = kCACornerCurveCircular;
 }
 return self;
}
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if(self.trackingArea) [self removeTrackingArea:self.trackingArea];
 self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
  owner:self userInfo:nil];
 [self addTrackingArea:self.trackingArea];
}
- (void)mouseEntered:(NSEvent*)event {
 self.hovered = YES;
 [self updateLayer];
}
- (void)mouseExited:(NSEvent*)event {
 self.hovered = NO;
 [self updateLayer];
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 if(self.hovered || self.circularBg) {
  self.layer.backgroundColor = [[NSColor.labelColor colorWithAlphaComponent:0.07] CGColor];
 } else {
  self.layer.backgroundColor = NSColor.clearColor.CGColor;
 }
 [CATransaction commit];
}
@end

@interface SlateSideRowCell : NSView
@property(weak) SlateDelegate* owner;
@property TabId tabId;
@property(strong) SlateTabBubble* bubble;
@property(strong) NSTextField* label;
@property(strong) SlateTabActionButton* closeButton;
@property(strong) SlateTabActionButton* speakerButton;
@property(strong) NSImageView* pipBadge;
@property(strong) NSImageView* splitBadge;
@property(strong) NSProgressIndicator* spinner;
@property BOOL hovering;
@property BOOL isLoading;
@property BOOL inGroup;
@property(strong) NSTrackingArea* trackingArea;
- (void)configureWithTab:(const slate::Tab&)tab isRail:(BOOL)rail;
- (void)updateLayoutForHover;
@end

@implementation SlateSideRowCell
- (instancetype)initWithFrame:(NSRect)frame {
 if(self = [super initWithFrame:frame]) {
  self.wantsLayer = YES;

  self.bubble = [[SlateTabBubble alloc] initWithFrame:NSZeroRect];
  [self addSubview:self.bubble];

  self.label = [NSTextField labelWithString:@""];
  self.label.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
  self.label.lineBreakMode = NSLineBreakByTruncatingTail;
  [self addSubview:self.label];

  self.speakerButton = [[SlateTabActionButton alloc] initWithFrame:NSMakeRect(0, 0, 15, 15)];
  self.speakerButton.target = self;
  self.speakerButton.action = @selector(speakerClicked:);
  self.speakerButton.hidden = YES;
  [self addSubview:self.speakerButton];

  self.closeButton = [[SlateTabActionButton alloc] initWithFrame:NSMakeRect(0, 0, 15, 15)];
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:8 weight:NSFontWeightSemibold];
   self.closeButton.image = [[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close Tab"] imageWithSymbolConfiguration:cfg];
  }
  self.closeButton.target = self;
  self.closeButton.action = @selector(closeClicked:);
  self.closeButton.toolTip = @"Close Tab (⌘W)";
  self.closeButton.hidden = YES;
  [self addSubview:self.closeButton];

  self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 15, 15)];
  self.spinner.style = NSProgressIndicatorStyleSpinning;
  self.spinner.controlSize = NSControlSizeSmall;
  self.spinner.hidden = YES;
  [self addSubview:self.spinner];

  self.pipBadge = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 15, 15)];
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:9 weight:NSFontWeightSemibold];
   self.pipBadge.image = [[NSImage imageWithSystemSymbolName:@"pip.fill" accessibilityDescription:@"Picture in Picture"] imageWithSymbolConfiguration:cfg];
  }
  self.pipBadge.contentTintColor = [NSColor systemBlueColor];
  self.pipBadge.toolTip = @"Picture in Picture active";
  self.pipBadge.hidden = YES;
  [self addSubview:self.pipBadge];
  self.splitBadge=[[NSImageView alloc] initWithFrame:NSMakeRect(0,0,15,15)];
  self.splitBadge.image=[NSImage imageWithSystemSymbolName:@"rectangle.split.2x1" accessibilityDescription:@"Split view"];
  self.splitBadge.hidden=YES;
  [self addSubview:self.splitBadge];
 }
 return self;
}
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (NSView*)hitTest:(NSPoint)point {
 if(self.hidden) return nil;
 NSPoint local=[self convertPoint:point fromView:self.superview];
 if(!NSPointInRect(local,self.bounds)) return nil;
 for(NSButton* button in @[self.closeButton,self.speakerButton]) {
  if(button.hidden) continue;
  NSPoint buttonPoint=[button convertPoint:point fromView:self.superview];
  if(NSPointInRect(buttonPoint,button.bounds)) return button;
 }
 // Route favicon and title drags through the row's drag-aware mouse handler.
 return self;
}
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if(self.trackingArea) [self removeTrackingArea:self.trackingArea];
 self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
  owner:self userInfo:nil];
 [self addTrackingArea:self.trackingArea];
}
- (void)mouseEntered:(NSEvent*)event {
 self.hovering = YES;
 [self updateLayoutForHover];
}
- (void)mouseExited:(NSEvent*)event {
 self.hovering = NO;
 [self updateLayoutForHover];
}
- (void)mouseDown:(NSEvent*)event {
 if(self.owner && self.tabId && self.superview)
  [self.superview mouseDown:event];
}
- (void)otherMouseDown:(NSEvent*)event {
 if(event.buttonNumber == 2 && self.owner && self.tabId) {
  [self.owner closeTabWithId:self.tabId];
 } else {
  [super otherMouseDown:event];
 }
}
- (NSMenu*)menuForEvent:(NSEvent*)event {
 if(self.owner && self.tabId) {
  return [self.owner tabMenuForTab:self.tabId];
 }
 return [super menuForEvent:event];
}
- (void)closeClicked:(id)sender {
 if(self.owner && self.tabId) {
  if (([NSApp currentEvent].modifierFlags & NSEventModifierFlagOption) != 0) {
   [self.owner unloadTabWithId:self.tabId];
  } else {
   [self.owner closeTabWithId:self.tabId];
  }
 }
}
- (void)speakerClicked:(id)sender {
 if(self.owner && self.tabId) {
  [self.owner toggleTabMute:self.tabId];
 }
}
- (void)configureWithTab:(const slate::Tab&)tab isRail:(BOOL)rail {
 self.tabId = tab.id;
 self.inGroup = !tab.group_id.empty() && !tab.pinned;
 self.bubble.owner = self.owner;
 self.bubble.tabId = tab.id;
 self.bubble.selectedTab = tab.selected;
 auto loadIt = runtimes.find(tab.id);
 self.isLoading = (loadIt != runtimes.end() && loadIt->second.loading);
 self.bubble.loading = self.isLoading;
 self.bubble.mark = [self.owner iconForTab:tab];

 NSString* title = TabSidebarTitle(tab);
 self.label.stringValue = title;
 self.toolTip = title;

 const BOOL isMuted = [self.owner tabIsMuted:tab.id];
 const BOOL isAudible = [self.owner tabIsAudible:tab.id];
 if(isMuted) {
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:8 weight:NSFontWeightRegular];
   self.speakerButton.image = [[NSImage imageWithSystemSymbolName:@"speaker.slash.fill" accessibilityDescription:@"Unmute Tab"] imageWithSymbolConfiguration:cfg];
  }
  self.speakerButton.toolTip = @"Unmute Tab";
 } else if(isAudible) {
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:8 weight:NSFontWeightRegular];
   self.speakerButton.image = [[NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill" accessibilityDescription:@"Mute Tab"] imageWithSymbolConfiguration:cfg];
  }
  self.speakerButton.toolTip = @"Mute Tab";
 }
 self.speakerButton.contentTintColor = self.owner.accentMuted ?: NSColor.secondaryLabelColor;
 self.pipBadge.hidden = !tab.pip_active;
 const NSInteger splitSide=[self.owner splitSideForTab:tab.id];
 self.splitBadge.hidden=!splitSide;
 self.splitBadge.toolTip=splitSide ? (splitSide==1 ? @"Left pane in split view" : @"Right pane in split view") : nil;
 self.splitBadge.contentTintColor=self.owner.accentMuted ?: NSColor.secondaryLabelColor;


 if(self.isLoading) {
  if(!self.spinner.isDisplayedWhenStopped) {
   self.spinner.displayedWhenStopped = YES;
   [self.spinner startAnimation:nil];
  }
 } else {
  [self.spinner stopAnimation:nil];
 }

 [self updateLayoutForHover];
}
- (void)layout {
 [super layout];
 [self updateLayoutForHover];
}
- (void)updateLayoutForHover {
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 const BOOL rail = (self.owner && [self.owner sidebarIconRail]) || NSWidth(self.bounds) <= 100;
 if(rail) {
  const CGFloat markSize=RailMarkForWidth(NSWidth(self.bounds));
  self.bubble.frame = NSMakeRect(round((NSWidth(self.bounds)-markSize)/2.0),
    round((NSHeight(self.bounds)-markSize)/2.0), markSize, markSize);
  self.label.hidden = YES;
  self.closeButton.hidden = YES;
  self.speakerButton.hidden = YES;
  self.pipBadge.hidden = YES;
  self.spinner.hidden = YES;
  self.splitBadge.hidden=![self.owner splitSideForTab:self.tabId];
  self.splitBadge.frame=NSMakeRect(NSMaxX(self.bubble.frame)-4,NSMinY(self.bubble.frame)-3,12,12);
  [CATransaction commit];
  return;
 }

 const CGFloat width = NSWidth(self.bounds);
 const CGFloat rowH = 28.0;
 const CGFloat indent = self.inGroup ? 24.0 : 10.0;

 self.label.hidden = NO;
 self.bubble.frame = NSMakeRect(indent, round((rowH - 15) / 2.0), 15, 15);

 const BOOL isAudible = [self.owner tabIsAudible:self.tabId];
 const BOOL isMuted = [self.owner tabIsMuted:self.tabId];
 const BOOL hasAudio = isAudible || isMuted;
 const auto* tab = model.find(self.tabId);
 const BOOL live = tab && tab->selected;
 const BOOL isPip = tab && tab->pip_active;

 CGFloat rightOffset = width - 22;
 if(self.hovering) {
  self.closeButton.hidden = NO;
  self.closeButton.frame = NSMakeRect(rightOffset, round((rowH - 15) / 2.0), 15, 15);
  rightOffset -= 20;
 } else {
  self.closeButton.hidden = YES;
 }

 if(hasAudio) {
  self.speakerButton.hidden = NO;
  self.speakerButton.frame = NSMakeRect(rightOffset, round((rowH - 15) / 2.0), 15, 15);
  rightOffset -= 20;
 } else {
  self.speakerButton.hidden = YES;
 }

 if(isPip) {
  self.pipBadge.hidden = NO;
  self.pipBadge.frame = NSMakeRect(rightOffset, round((rowH - 15) / 2.0), 15, 15);
  rightOffset -= 18;
 } else {
  self.pipBadge.hidden = YES;
 }

 self.splitBadge.hidden=![self.owner splitSideForTab:self.tabId];
 if(!self.splitBadge.hidden) {
  self.splitBadge.frame=NSMakeRect(rightOffset,round((rowH-15)/2.0),15,15);
  rightOffset-=18;
 }
 if(self.isLoading) {
  if(self.hovering) {
   self.spinner.hidden = YES;
  } else {
   self.spinner.hidden = NO;
   self.spinner.frame = NSMakeRect(rightOffset, round((rowH - 15) / 2.0), 15, 15);
   rightOffset -= 20;
  }
 } else {
  self.spinner.hidden = YES;
 }

 CGFloat trailingLimit = rightOffset - 4;
 const CGFloat labelX = indent + 15 + 8;
 self.label.frame = NSMakeRect(labelX, round((rowH - 16) / 2.0), MAX(0, trailingLimit - labelX), 16);

 NSColor* ink = self.owner.accentInk ?: NSColor.labelColor;
 if(live) {
  self.label.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
  self.label.textColor = ink;
 } else if(self.hovering) {
  self.label.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
  self.label.textColor = [ink colorWithAlphaComponent:0.85];
 } else {
  self.label.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
  self.label.textColor = [ink colorWithAlphaComponent:0.75];
 }
 [CATransaction commit];
}
@end

@interface SlateCapsuleRow : NSTableRowView
@property(weak) SlateDelegate* owner;
@property TabId tabId;
@property(strong) NSString* groupId;
@property BOOL isNewTabRow;
@property BOOL hovered;
@property(strong) NSTrackingArea* trackingArea;
@property(strong) CALayer* pillLayer;
@end

@implementation SlateCapsuleRow
- (instancetype)initWithFrame:(NSRect)frame {
 if(self=[super initWithFrame:frame]) {
  self.wantsLayer = YES;
  self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
  self.pillLayer = [CALayer layer];
  [self.layer addSublayer:self.pillLayer];
 }
 return self;
}
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if(self.trackingArea) [self removeTrackingArea:self.trackingArea];
 self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
  owner:self userInfo:nil];
 [self addTrackingArea:self.trackingArea];
}
- (void)mouseEntered:(NSEvent*)event {
 self.hovered = YES;
 [self updateLayer];
 for(NSView* sub in self.subviews) {
  if([sub isKindOfClass:SlateSideRowCell.class]) {
   [(SlateSideRowCell*)sub setHovering:YES];
   [(SlateSideRowCell*)sub updateLayoutForHover];
  }
 }
}
- (void)mouseExited:(NSEvent*)event {
 self.hovered = NO;
 [self updateLayer];
 for(NSView* sub in self.subviews) {
  if([sub isKindOfClass:SlateSideRowCell.class]) {
   [(SlateSideRowCell*)sub setHovering:NO];
   [(SlateSideRowCell*)sub updateLayoutForHover];
  }
 }
}
- (void)updatePillGeometry {
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 if(self.isNewTabRow) {
  self.pillLayer.frame = NSZeroRect;
 } else if(self.groupId) {
  self.pillLayer.frame = self.bounds;
 } else {
  self.pillLayer.frame = self.bounds;
 }
 [CATransaction commit];
}
- (void)drawSelectionInRect:(NSRect)dirtyRect {}
- (void)drawBackgroundInRect:(NSRect)dirtyRect {}
- (void)layout {
 [super layout];
 [self updatePillGeometry];
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 [self updatePillGeometry];

 NSColor* ink = self.owner.accentInk ?: NSColor.labelColor;

 if(self.isNewTabRow) {
  self.pillLayer.backgroundColor = NSColor.clearColor.CGColor;
  self.pillLayer.cornerRadius = 0;
  [CATransaction commit];
  return;
 }

 if(self.groupId) {
  if(self.hovered) {
   self.pillLayer.backgroundColor = [[ink colorWithAlphaComponent:0.05] CGColor];
   self.pillLayer.cornerRadius = 6;
   if(@available(macOS 11.0, *)) self.pillLayer.cornerCurve = kCACornerCurveContinuous;
  } else {
   self.pillLayer.backgroundColor = NSColor.clearColor.CGColor;
   self.pillLayer.cornerRadius = 0;
  }
  [CATransaction commit];
  return;
 }

 self.pillLayer.cornerRadius = 9;
 if(@available(macOS 11.0, *)) self.pillLayer.cornerCurve = kCACornerCurveContinuous;
 self.pillLayer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
 if(self.selected || [self.owner tabInVisibleSplit:self.tabId]) {
  self.pillLayer.backgroundColor = [[ink colorWithAlphaComponent:0.14] CGColor];
 } else if(self.hovered) {
  self.pillLayer.backgroundColor = [[ink colorWithAlphaComponent:0.07] CGColor];
 } else {
  self.pillLayer.backgroundColor = NSColor.clearColor.CGColor;
 }

 [CATransaction commit];
}
- (void)mouseDown:(NSEvent*)event {
 if(self.owner && self.tabId) [self.owner beginSidebarTabGesture:self.tabId];
 else if(self.owner && self.groupId) [self.owner toggleGroupCollapsed:self.groupId];
 [super mouseDown:event];
 if(self.owner && self.tabId) {
  if(self.owner.splitDragCandidateTab==self.tabId)
   [self.owner handleTabClick:self.tabId doubleClick:event.clickCount>=2];
  [self.owner endSidebarTabGesture:self.tabId];
 }
}
@end

@interface SlatePinSquare : NSView
@property(weak) SlateDelegate* owner;
@property TabId tabId;
@property BOOL live;
@property BOOL hovered;
@property BOOL asleep;
@property(strong) NSImage* mark;
@property(strong) NSTrackingArea* trackingArea;
@property(strong) CALayer* bgLayer;
@property(strong) CALayer* iconLayer;
@property NSPoint startLocation;
@property BOOL dragStarted;
- (void)updateStyle;
@end

@interface SlatePinnedGrid : NSView
@property(weak) SlateDelegate* owner;
@property(strong) NSMutableArray<SlatePinSquare*>* squares;
@property(strong) NSLayoutConstraint* heightConstraint;
@property std::vector<TabId> pinnedIds;
- (void)rebuildWithTabs:(const std::vector<slate::Tab>&)tabs selectedId:(TabId)selectedId;
- (void)updateLayoutForWidth:(CGFloat)width;
- (void)handleDragFromSquare:(SlatePinSquare*)square atPoint:(NSPoint)pt;
- (void)finishDrag;
@end

@implementation SlatePinSquare
- (instancetype)initWithFrame:(NSRect)frame {
 if(self = [super initWithFrame:frame]) {
  self.wantsLayer = YES;
  self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
  self.bgLayer = [CALayer layer];
  self.iconLayer = [CALayer layer];
  self.iconLayer.contentsGravity = kCAGravityResizeAspect;
  [self.layer addSublayer:self.bgLayer];
  [self.layer addSublayer:self.iconLayer];
 }
 return self;
}
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if(self.trackingArea) [self removeTrackingArea:self.trackingArea];
 self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
  owner:self userInfo:nil];
 [self addTrackingArea:self.trackingArea];
}
- (void)mouseEntered:(NSEvent*)event {
 self.hovered = YES;
 [self updateStyle];
}
- (void)mouseExited:(NSEvent*)event {
 self.hovered = NO;
 [self updateStyle];
}
- (void)mouseDown:(NSEvent*)event {
 self.dragStarted = NO;
 self.startLocation = [self.superview convertPoint:event.locationInWindow fromView:nil];
 if(event.clickCount >= 2) {
  if(self.owner) {
   [self.owner.address selectText:nil];
   [self.owner.window makeFirstResponder:self.owner.address];
  }
  return;
 }
 if(self.owner) [self.owner activateTab:self.tabId];
}
- (void)mouseDragged:(NSEvent*)event {
 NSPoint pt = [self.superview convertPoint:event.locationInWindow fromView:nil];
 CGFloat dx = pt.x - self.startLocation.x;
 CGFloat dy = pt.y - self.startLocation.y;
 if(hypot(dx, dy) > 6.0) {
  self.dragStarted = YES;
  if([self.superview isKindOfClass:SlatePinnedGrid.class]) {
   [(SlatePinnedGrid*)self.superview handleDragFromSquare:self atPoint:pt];
  }
 }
}
- (void)mouseUp:(NSEvent*)event {
 if(self.dragStarted) {
  self.dragStarted = NO;
  if([self.superview isKindOfClass:SlatePinnedGrid.class]) {
   [(SlatePinnedGrid*)self.superview finishDrag];
  }
 }
}
- (void)otherMouseDown:(NSEvent*)event {
 if(event.buttonNumber == 2 && self.owner && self.tabId) {
  [self.owner closeTabWithId:self.tabId];
 } else {
  [super otherMouseDown:event];
 }
}
- (NSMenu*)menuForEvent:(NSEvent*)event {
 if(self.owner && self.tabId) {
  return [self.owner tabMenuForTab:self.tabId];
 }
 return [super menuForEvent:event];
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
 [self updateStyle];
}
- (void)layout {
 [super layout];
 [self updateStyle];
}
- (void)updateStyle {
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 const CGFloat width = NSWidth(self.bounds);
 const CGFloat height = NSHeight(self.bounds);
 const CGFloat scale = MIN(width, height);
 self.bgLayer.frame = self.bounds;
 self.bgLayer.cornerRadius = round(scale * 9.0 / 34.0);
 if(@available(macOS 11.0, *)) self.bgLayer.cornerCurve = kCACornerCurveContinuous;

 NSColor* ink = self.owner.accentInk ?: NSColor.labelColor;
 if(self.live) {
  self.bgLayer.backgroundColor = [[ink colorWithAlphaComponent:0.14] CGColor];
 } else if(self.hovered) {
  self.bgLayer.backgroundColor = [[ink colorWithAlphaComponent:0.07] CGColor];
 } else {
  self.bgLayer.backgroundColor = [[ink colorWithAlphaComponent:0.035] CGColor];
 }

 const CGFloat iconSize = (self.owner && [self.owner sidebarIconRail])
  ? RailMarkForWidth([self.owner sidebarLayoutWidth]) : round(scale * 16.0 / 34.0);
 self.iconLayer.frame = NSMakeRect(round((width - iconSize) / 2.0), round((height - iconSize) / 2.0), iconSize, iconSize);
 if(self.mark) {
  id contents=[self.mark layerContentsForContentsScale:self.window.backingScaleFactor ?: 2.0];
  if(self.mark.isTemplate) {
   CALayer* mask=self.iconLayer.mask ?: [CALayer layer];
   mask.frame=self.iconLayer.bounds;
   mask.contentsGravity=kCAGravityResizeAspect;
   mask.contents=contents;
   self.iconLayer.mask=mask;
   self.iconLayer.contents=nil;
   self.iconLayer.backgroundColor=(self.live ? NSColor.labelColor : NSColor.secondaryLabelColor).CGColor;
  } else {
   self.iconLayer.mask=nil;
   self.iconLayer.backgroundColor=nil;
   self.iconLayer.contents=contents;
  }
  self.iconLayer.opacity = self.asleep ? 0.45 : 1.0;
 } else {
  self.iconLayer.mask=nil;
  self.iconLayer.backgroundColor=nil;
  self.iconLayer.contents = nil;
 }
 [CATransaction commit];
}
@end

@implementation SlatePinnedGrid
- (instancetype)initWithFrame:(NSRect)frame {
 if(self = [super initWithFrame:frame]) {
  self.wantsLayer = YES;
  self.squares = [NSMutableArray array];
 }
 return self;
}
- (BOOL)isFlipped { return YES; }
- (void)rebuildWithTabs:(const std::vector<slate::Tab>&)tabs selectedId:(TabId)selectedId {
 self.pinnedIds.clear();
 std::vector<slate::Tab> pinned;
 for(const auto& t : tabs) {
  if(t.pinned) {
   pinned.push_back(t);
   self.pinnedIds.push_back(t.id);
  }
 }

 if(pinned.empty()) {
  self.hidden = YES;
  self.heightConstraint.constant = 0;
  for(SlatePinSquare* sq in self.squares) [sq removeFromSuperview];
  [self.squares removeAllObjects];
  return;
 }

 self.hidden = NO;
 CGFloat sidebarW = NSWidth(self.bounds);
 if(sidebarW <= 0 && self.owner) sidebarW = [self.owner sidebarLayoutWidth];
 if(sidebarW <= 0) sidebarW = kSidebarOpenWidth;

 const BOOL rail = (self.owner && [self.owner sidebarIconRail]) || sidebarW < 100;
 const int count = (int)pinned.size();
 const int cols = rail ? 1 : std::max(3, (count + 1) / 2);
 const CGFloat pinGap = 4.0;
 const CGFloat available = sidebarW - 20.0 - (cols - 1) * pinGap;
 const CGFloat pinWidth = rail ? 34.0 : std::max(20.0, available / (CGFloat)cols);
 const CGFloat pinHeight = std::min(34.0, pinWidth);
 const int numRows = (count + cols - 1) / cols;
 const CGFloat totalH = numRows * pinHeight + std::max(0, numRows - 1) * pinGap + 10.0;
 self.heightConstraint.constant = totalH;

 while(self.squares.count > pinned.size()) {
  [self.squares.lastObject removeFromSuperview];
  [self.squares removeLastObject];
 }
 while(self.squares.count < pinned.size()) {
  SlatePinSquare* sq = [[SlatePinSquare alloc] initWithFrame:NSZeroRect];
  sq.owner = self.owner;
  [self addSubview:sq];
  [self.squares addObject:sq];
 }

 for(size_t i = 0; i < pinned.size(); ++i) {
  const auto& tab = pinned[i];
  SlatePinSquare* sq = self.squares[i];
  sq.owner = self.owner;
  sq.tabId = tab.id;
  sq.live = (tab.id == selectedId);
  sq.asleep = !model.live(tab.id);
  sq.mark = [self.owner iconForTab:tab];
  sq.toolTip = TabSidebarTitle(tab);

  const int row = (int)i / cols;
  const int col = (int)i % cols;
  const CGFloat x = rail ? round((sidebarW - pinWidth) / 2.0) : (10.0 + col * (pinWidth + pinGap));
  const CGFloat y = row * (pinHeight + pinGap);
  sq.frame = NSMakeRect(x, y, pinWidth, pinHeight);
  [sq updateStyle];
 }
}
- (void)updateLayoutForWidth:(CGFloat)width {
 if(self.squares.count == 0) return;
 const BOOL rail = (self.owner && [self.owner sidebarIconRail]) || width < 100;
 const int count = (int)self.squares.count;
 const int cols = rail ? 1 : std::max(3, (count + 1) / 2);
 const CGFloat pinGap = 4.0;
 const CGFloat available = width - 20.0 - (cols - 1) * pinGap;
 const CGFloat pinWidth = rail ? 34.0 : std::max(20.0, available / (CGFloat)cols);
 const CGFloat pinHeight = std::min(34.0, pinWidth);
 const int numRows = (count + cols - 1) / cols;
 const CGFloat totalH = numRows * pinHeight + std::max(0, numRows - 1) * pinGap + 10.0;
 self.heightConstraint.constant = totalH;

 for(size_t i = 0; i < self.squares.count; ++i) {
  SlatePinSquare* sq = self.squares[i];
  const int row = (int)i / cols;
  const int col = (int)i % cols;
  const CGFloat x = rail ? round((width - pinWidth) / 2.0) : (10.0 + col * (pinWidth + pinGap));
  const CGFloat y = row * (pinHeight + pinGap);
  sq.frame = NSMakeRect(x, y, pinWidth, pinHeight);
  [sq updateStyle];
 }
}
- (void)handleDragFromSquare:(SlatePinSquare*)square atPoint:(NSPoint)pt {
 NSInteger fromIdx = [self.squares indexOfObject:square];
 if(fromIdx == NSNotFound) return;
 CGFloat sidebarW = NSWidth(self.bounds);
 const BOOL rail = (self.owner && [self.owner sidebarIconRail]) || sidebarW < 100;
 const int count = (int)self.squares.count;
 const int cols = rail ? 1 : std::max(3, (count + 1) / 2);
 const CGFloat pinGap = 4.0;
 const CGFloat available = sidebarW - 20.0 - (cols - 1) * pinGap;
 const CGFloat pinWidth = rail ? 34.0 : std::max(20.0, available / (CGFloat)cols);
 const CGFloat pinHeight = std::min(34.0, pinWidth);

 int col = rail ? 0 : (int)floor((pt.x - 10.0) / (pinWidth + pinGap));
 int row = (int)floor(pt.y / (pinHeight + pinGap));
 if(col < 0) col = 0; if(col >= cols) col = cols - 1;
 if(row < 0) row = 0;
 int toIdx = row * cols + col;
 if(toIdx >= count) toIdx = count - 1;
 if(toIdx >= 0 && toIdx < count && toIdx != fromIdx) {
  std::vector<TabId> order;
  for(const auto& t : model.tabs()) order.push_back(t.id);
  TabId moveId = square.tabId;
  auto it = std::find(order.begin(), order.end(), moveId);
  if(it != order.end()) {
   order.erase(it);
   size_t pinnedSeen = 0;
   size_t insertAt = 0;
   for(size_t i = 0; i < order.size(); ++i) {
    const auto* t = model.find(order[i]);
    if(t && t->pinned) {
     if(pinnedSeen == (size_t)toIdx) { insertAt = i; break; }
     pinnedSeen++;
     insertAt = i + 1;
    }
   }
   order.insert(order.begin() + insertAt, moveId);
   model.reorder_tabs(order);
   [self.owner refresh];
   [self.owner scheduleSave];
  }
 }
}
- (void)finishDrag {
 [self.owner scheduleSave];
}
@end

@interface SlateDoorButton : NSButton
@property(weak) SlateDelegate* owner;
@property BOOL on;
@property BOOL hovered;
@property(strong) NSTrackingArea* trackingArea;
@property(copy, nonatomic) NSString* symbolName;
- (void)updateStyle;
@end

@implementation SlateDoorButton
- (instancetype)initWithSymbol:(NSString*)symbol help:(NSString*)help target:(id)target action:(SEL)action {
 if(self = [super initWithFrame:NSMakeRect(0, 0, 26, 26)]) {
  self.symbolName = symbol;
  self.target = target;
  self.action = action;
  self.toolTip = help;
  self.bordered = NO;
  self.bezelStyle = NSBezelStyleRegularSquare;
  self.refusesFirstResponder = YES;
  self.wantsLayer = YES;
  self.layer.cornerRadius = 8.0;
  if(@available(macOS 11.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightMedium];
   self.image = [[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:help] imageWithSymbolConfiguration:cfg];
  }
  self.imagePosition = NSImageOnly;
  self.imageScaling = NSImageScaleProportionallyDown;
 }
 return self;
}
- (void)setSymbolName:(NSString*)symbolName {
 _symbolName = [symbolName copy];
 if(@available(macOS 11.0, *)) {
  NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightMedium];
  self.image = [[NSImage imageWithSystemSymbolName:_symbolName accessibilityDescription:self.toolTip] imageWithSymbolConfiguration:cfg];
 }
}
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if(self.trackingArea) [self removeTrackingArea:self.trackingArea];
 self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
  owner:self userInfo:nil];
 [self addTrackingArea:self.trackingArea];
}
- (void)mouseEntered:(NSEvent*)event {
 self.hovered = YES;
 [self updateStyle];
}
- (void)mouseExited:(NSEvent*)event {
 self.hovered = NO;
 [self updateStyle];
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
 [self updateStyle];
}
- (void)updateStyle {
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 NSColor* ink = self.owner.accentInk ?: NSColor.labelColor;
 if(self.on) {
  self.contentTintColor = ink;
  self.layer.backgroundColor = [[ink colorWithAlphaComponent:0.14] CGColor];
 } else if(self.hovered) {
  self.contentTintColor = [ink colorWithAlphaComponent:0.70];
  self.layer.backgroundColor = [[ink colorWithAlphaComponent:0.07] CGColor];
 } else {
  self.contentTintColor = [ink colorWithAlphaComponent:0.55];
  self.layer.backgroundColor = NSColor.clearColor.CGColor;
 }
 [CATransaction commit];
}
@end

@interface SlateSidebarFoot : NSView
@property(weak, nonatomic) SlateDelegate* owner;
@property(strong) SlateDoorButton* spaceDoor;
@property(strong) SlateDoorButton* bookmarksDoor;
@property(strong) SlateDoorButton* downloadsDoor;
@property(strong) SlateDoorButton* passwordsDoor;
@property(strong) SlateDoorButton* settingsDoor;
- (void)updateDoors;
@end

@implementation SlateSidebarFoot
- (instancetype)initWithFrame:(NSRect)frame {
 if(self = [super initWithFrame:frame]) {
  self.wantsLayer = YES;
  self.spaceDoor = [[SlateDoorButton alloc] initWithSymbol:@"house" help:@"Spaces (⌃1–⌃9)" target:self action:@selector(spaceClicked:)];
  self.bookmarksDoor = [[SlateDoorButton alloc] initWithSymbol:@"bookmark" help:@"Bookmarks" target:self action:@selector(bookmarksClicked:)];
  self.downloadsDoor = [[SlateDoorButton alloc] initWithSymbol:@"arrow.down.circle" help:@"Downloads" target:self action:@selector(downloadsClicked:)];
  self.passwordsDoor = [[SlateDoorButton alloc] initWithSymbol:@"key" help:@"Passwords" target:self action:@selector(passwordsClicked:)];
  self.settingsDoor = [[SlateDoorButton alloc] initWithSymbol:@"gearshape" help:@"Settings" target:self action:@selector(settingsClicked:)];

  [self addSubview:self.spaceDoor];
  [self addSubview:self.bookmarksDoor];
  [self addSubview:self.downloadsDoor];
  [self addSubview:self.passwordsDoor];
  [self addSubview:self.settingsDoor];
 }
 return self;
}
- (BOOL)isFlipped { return YES; }
- (void)setOwner:(SlateDelegate*)owner {
 _owner = owner;
 self.spaceDoor.owner = owner;
 self.bookmarksDoor.owner = owner;
 self.downloadsDoor.owner = owner;
 self.passwordsDoor.owner = owner;
 self.settingsDoor.owner = owner;
}
- (void)layout {
 [super layout];
 const CGFloat doorSize = 26.0;
 const CGFloat spacing = 2.0;
 const BOOL rail = (self.owner && [self.owner sidebarIconRail]) || NSWidth(self.bounds) < 100;

 if(rail) {
  self.spaceDoor.hidden = NO;
  self.spaceDoor.frame = NSMakeRect(round((NSWidth(self.bounds) - doorSize) / 2.0), 0, doorSize, doorSize);
  self.bookmarksDoor.hidden = YES;
  self.downloadsDoor.hidden = YES;
  self.passwordsDoor.hidden = YES;
  self.settingsDoor.hidden = YES;
  return;
 }

 self.bookmarksDoor.hidden = NO;
 self.downloadsDoor.hidden = NO;
 self.passwordsDoor.hidden = NO;
 self.settingsDoor.hidden = NO;

 CGFloat x = 10.0;
 CGFloat y = 0.0;

 self.spaceDoor.frame = NSMakeRect(x, y, doorSize, doorSize);
 x += doorSize + 6.0;

 self.bookmarksDoor.frame = NSMakeRect(x, y, doorSize, doorSize);
 x += doorSize + spacing;
 self.downloadsDoor.frame = NSMakeRect(x, y, doorSize, doorSize);
 x += doorSize + spacing;
 self.passwordsDoor.frame = NSMakeRect(x, y, doorSize, doorSize);
 x += doorSize + spacing;
 self.settingsDoor.frame = NSMakeRect(x, y, doorSize, doorSize);
}
- (void)spaceClicked:(id)sender {
 if(self.owner) [self.owner showSpaceMenuForButton:self.spaceDoor];
}
- (void)bookmarksClicked:(id)sender {
 if(self.owner) [self.owner toggleBookmarksBar:sender];
 [self updateDoors];
}
- (void)downloadsClicked:(id)sender {
 if(self.owner) [[SlateDownloadsPanel sharedPanel] toggleForButton:self.downloadsDoor inWindow:self.owner.window];
 [self updateDoors];
}
- (void)passwordsClicked:(id)sender {
 if(self.owner) [self.owner showPasswordsPanel:sender];
}
- (void)settingsClicked:(id)sender {
 if(self.owner) [self.owner showSettings:sender];
}
- (void)updateDoors {
 SlateSpace* curSpace = [self.owner.spacesManager currentSpace];
 if(curSpace) {
  self.spaceDoor.symbolName = curSpace.symbol;
  self.spaceDoor.toolTip = [NSString stringWithFormat:@"%@ — ⌃1–⌃9 to switch", curSpace.name];
 }
 [self.spaceDoor updateStyle];
 self.bookmarksDoor.on = self.owner.showBookmarksBar;
 self.downloadsDoor.on = [SlateDownloadsPanel sharedPanel].isVisible;
 [self.bookmarksDoor updateStyle];
 [self.downloadsDoor updateStyle];
 [self.passwordsDoor updateStyle];
 [self.settingsDoor updateStyle];
}
@end

@interface SlateGroupHeader : NSView
@end
@implementation SlateGroupHeader
- (instancetype)initWithFrame:(NSRect)frame {
 if(self=[super initWithFrame:frame]) {
  self.wantsLayer = YES;
 }
 return self;
}
- (BOOL)isFlipped { return YES; }
@end

@interface SlateInlineAddRow : NSView
@property(weak) SlateDelegate* owner;
@property BOOL isRail;
@property BOOL hovered;
@property(strong) NSTrackingArea* trackingArea;
@property(strong) CALayer* pillLayer;
@property(strong) NSImageView* plusIcon;
@property(strong) NSTextField* label;
@end

@implementation SlateInlineAddRow
- (instancetype)initWithFrame:(NSRect)frame {
 if(self=[super initWithFrame:frame]) {
  self.wantsLayer=YES;
  self.pillLayer=[CALayer layer];
  [self.layer addSublayer:self.pillLayer];

  self.plusIcon=[[NSImageView alloc] initWithFrame:NSZeroRect];
  self.plusIcon.imageScaling=NSImageScaleProportionallyDown;
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg=[NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightMedium];
   self.plusIcon.image=[[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"New tab"] imageWithSymbolConfiguration:cfg];
  } else {
   self.plusIcon.image=[NSImage imageNamed:@"TabIconTemplate"];
  }
  [self addSubview:self.plusIcon];

  self.label=[NSTextField labelWithString:@"New tab"];
  self.label.font=[NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
  [self addSubview:self.label];
 }
 return self;
}
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if(self.trackingArea) [self removeTrackingArea:self.trackingArea];
 self.trackingArea=[[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
  owner:self userInfo:nil];
 [self addTrackingArea:self.trackingArea];
}
- (void)mouseEntered:(NSEvent*)event {
 self.hovered=YES;
 [self updateLayer];
}
- (void)mouseExited:(NSEvent*)event {
 self.hovered=NO;
 [self updateLayer];
}
- (void)mouseDown:(NSEvent*)event {
 if(self.owner) [self.owner newTab:self];
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 NSColor* ink=self.owner.accentInk ?: NSColor.labelColor;
 if(self.hovered) {
  self.plusIcon.contentTintColor=[ink colorWithAlphaComponent:0.70];
  self.label.textColor=[ink colorWithAlphaComponent:0.70];
  self.pillLayer.backgroundColor=[[ink colorWithAlphaComponent:0.07] CGColor];
 } else {
  self.plusIcon.contentTintColor=[ink colorWithAlphaComponent:0.40];
  self.label.textColor=[ink colorWithAlphaComponent:0.40];
  self.pillLayer.backgroundColor=NSColor.clearColor.CGColor;
 }
 self.pillLayer.frame=self.bounds;
 self.pillLayer.cornerRadius=9;
 if(@available(macOS 11.0, *)) self.pillLayer.cornerCurve=kCACornerCurveContinuous;
 [CATransaction commit];
}
- (void)layout {
 [super layout];
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 const BOOL isRail = self.isRail || NSWidth(self.bounds) <= 100;
 self.label.hidden=isRail;
 self.pillLayer.frame=self.bounds;
 if(isRail) {
  self.plusIcon.frame=NSMakeRect(round((NSWidth(self.bounds)-15)/2.0), round((NSHeight(self.bounds)-15)/2.0), 15, 15);
 } else {
  self.plusIcon.frame=NSMakeRect(10, round((NSHeight(self.bounds)-15)/2.0), 15, 15);
  self.label.frame=NSMakeRect(33, round((NSHeight(self.bounds)-16)/2.0), MAX(0, NSWidth(self.bounds)-43), 16);
 }
 [self updateLayer];
 [CATransaction commit];
}
@end

@interface SlateDragRegion : NSView
@property(strong) NSEvent* pressedEvent;
@property BOOL hasDragged;
@end

@implementation SlateDragRegion
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }

- (NSView*)hitTest:(NSPoint)point {
 if(self.window) {
  NSPoint winPt = [self convertPoint:point toView:nil];
  for(NSWindowButton kind : {NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton}) {
   NSButton* button=[self.window standardWindowButton:kind];
   if(button && button.superview && !button.hidden && button.alphaValue>0) {
    NSRect buttonInWin=[button.superview convertRect:button.frame toView:nil];
    if(NSPointInRect(winPt, NSInsetRect(buttonInWin,-4,-4))) return nil;
   }
  }
 }
 NSView* hit=[super hitTest:point];
 if(hit && hit!=self) return hit;
 NSPoint local=[self convertPoint:point fromView:self.superview];
 for(NSView* sub in self.subviews.reverseObjectEnumerator) {
  if(sub.hidden || sub.alphaValue<0.05) continue;
  NSPoint inSub=[sub convertPoint:local fromView:self];
  if(NSPointInRect(inSub, NSInsetRect(sub.bounds,-2,-6))) {
   NSView* inner=[sub hitTest:local];
   return inner ?: sub;
  }
 }
 return hit;
}

- (void)mouseDown:(NSEvent*)event {
 if(event.clickCount >= 2) {
  NSString* action = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleActionOnDoubleClick"];
  if([@"Minimize" isEqualToString:action]) {
   [self.window performMiniaturize:nil];
  } else {
   [self.window zoom:nil];
  }
  return;
 }
 self.pressedEvent = event;
 self.hasDragged = NO;
}

- (void)mouseDragged:(NSEvent*)event {
 if(!self.window || !self.pressedEvent || self.hasDragged) return;
 const CGFloat dx = event.locationInWindow.x - self.pressedEvent.locationInWindow.x;
 const CGFloat dy = event.locationInWindow.y - self.pressedEvent.locationInWindow.y;
 if(fabs(dx) < 3.0 && fabs(dy) < 3.0) return;
 self.hasDragged = YES;
 [self.window performWindowDragWithEvent:self.pressedEvent];
}

- (void)mouseUp:(NSEvent*)event {
 self.pressedEvent = nil;
 self.hasDragged = NO;
}
- (NSMenu*)menuForEvent:(NSEvent*)event {
 if([self.window.delegate isKindOfClass:NSClassFromString(@"SlateDelegate")]) {
  return [(SlateDelegate*)self.window.delegate tabStripMenu];
 }
 return [super menuForEvent:event];
}
- (void)rightMouseDown:(NSEvent*)event {
 if([self.window.delegate isKindOfClass:NSClassFromString(@"SlateDelegate")]) {
  NSMenu* menu = [(SlateDelegate*)self.window.delegate tabStripMenu];
  if(menu) {
   [NSMenu popUpContextMenu:menu withEvent:event forView:self];
   return;
  }
 }
 [super rightMouseDown:event];
}
@end
static void (*orig_addTitlebarSubview)(id, SEL, NSView*) = NULL;
static void swizzle_addTitlebarSubview(id self, SEL _cmd, NSView* subview) {
 if(subview && [subview isKindOfClass:NSButton.class]) {
  if([subview.superview isKindOfClass:NSClassFromString(@"SlateTrafficCluster")]) {
   return;
  }
  NSWindow* win = [self respondsToSelector:@selector(window)] ? [self window] : nil;
  if(win && [win.delegate isKindOfClass:NSClassFromString(@"SlateDelegate")]) {
   SlateDelegate* del = (SlateDelegate*)win.delegate;
   if(del.trafficCluster && (subview == [win standardWindowButton:NSWindowCloseButton] ||
                             subview == [win standardWindowButton:NSWindowMiniaturizeButton] ||
                             subview == [win standardWindowButton:NSWindowZoomButton])) {
    return;
   }
  }
 }
 if(orig_addTitlebarSubview) {
  orig_addTitlebarSubview(self, _cmd, subview);
 }
}

static void (*orig_titlebar_addSubview)(id, SEL, NSView*) = NULL;
static void swizzle_titlebar_addSubview(id self, SEL _cmd, NSView* subview) {
 if(subview && [subview isKindOfClass:NSButton.class]) {
  if([subview.superview isKindOfClass:NSClassFromString(@"SlateTrafficCluster")]) {
   return;
  }
  NSWindow* win = [self respondsToSelector:@selector(window)] ? [self window] : nil;
  if(win && [win.delegate isKindOfClass:NSClassFromString(@"SlateDelegate")]) {
   SlateDelegate* del = (SlateDelegate*)win.delegate;
   if(del.trafficCluster && (subview == [win standardWindowButton:NSWindowCloseButton] ||
                             subview == [win standardWindowButton:NSWindowMiniaturizeButton] ||
                             subview == [win standardWindowButton:NSWindowZoomButton])) {
    return;
   }
  }
 }
 if(orig_titlebar_addSubview) {
  orig_titlebar_addSubview(self, _cmd, subview);
 }
}

static void InstallThemeFrameSwizzle(void) {
 // Keep AppKit titlebar hierarchy intact to avoid layout thrashing
}

@interface SlateTrafficCluster : NSView
@property(weak) SlateDelegate* owner;
@end
@implementation SlateTrafficCluster
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (NSView*)hitTest:(NSPoint)point {
 NSView* hit=[super hitTest:point];
 return hit==self ? nil : hit;
}
- (void)layout {
 [super layout];
}
@end
@interface SlateResizeHandle : NSView
@property(weak) SlateDelegate* owner;
@property CGFloat startWidth;
@property CGFloat startX;
@property BOOL onEdge;
@property(strong) NSTrackingArea* trackingArea;
@property(strong) CALayer* hairlineLayer;
- (void)updateHairline;
@end

@implementation SlateResizeHandle
- (instancetype)initWithFrame:(NSRect)frame {
 if(self = [super initWithFrame:frame]) {
  self.wantsLayer = YES;
  self.hairlineLayer = [CALayer layer];
  [self.layer addSublayer:self.hairlineLayer];
 }
 return self;
}
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)resetCursorRects {
 [self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor];
}
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if(self.trackingArea) [self removeTrackingArea:self.trackingArea];
 self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
  owner:self userInfo:nil];
 [self addTrackingArea:self.trackingArea];
}
- (void)mouseEntered:(NSEvent*)event {
 self.onEdge = YES;
 [self updateHairline];
}
- (void)mouseExited:(NSEvent*)event {
 self.onEdge = NO;
 [self updateHairline];
}
- (void)mouseDown:(NSEvent*)event {
 if(event.clickCount >= 2) {
  [self.owner setSidebarWidthLive:kSidebarOpenWidth];
  [self.owner persistSidebarWidth];
  return;
 }
 self.startX=event.locationInWindow.x;
 self.startWidth=self.owner.sidebarWidth.constant;
 [self updateHairline];
}
- (void)mouseDragged:(NSEvent*)event {
 [self.owner setSidebarWidthLive:self.startWidth+(event.locationInWindow.x-self.startX)];
 [self updateHairline];
}
- (void)mouseUp:(NSEvent*)event {
 [self.owner persistSidebarWidth];
 [self updateHairline];
}
- (void)layout {
 [super layout];
 [self updateHairline];
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
 [self updateHairline];
}
- (void)updateHairline {
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 const BOOL active = self.onEdge || (NSEvent.pressedMouseButtons & 1);
 const CGFloat hlWidth = active ? 2.0 : 0.0;
 const CGFloat x = round(NSMidX(self.bounds) - hlWidth / 2.0);
 self.hairlineLayer.frame = NSMakeRect(x, 0, hlWidth, NSHeight(self.bounds));
 NSColor* ink = self.owner.accentInk ?: NSColor.labelColor;
 if(active) {
  self.hairlineLayer.backgroundColor = [[ink colorWithAlphaComponent:0.18] CGColor];
 } else {
  self.hairlineLayer.backgroundColor = NSColor.clearColor.CGColor;
 }
 [CATransaction commit];
}
@end
@interface SlateChromeView : NSView
@end
@implementation SlateChromeView
- (BOOL)mouseDownCanMoveWindow { return NO; }
@end
typedef NS_ENUM(NSInteger, SlateSuggestionKind) {
 SlateSuggestionKindSearch=0,   // magnifying glass icon
 SlateSuggestionKindURL=1,      // globe icon
 SlateSuggestionKindHistory=2,  // clock / globe icon
 SlateSuggestionKindOpen=3,     // open tab dot icon (5px circle)
};
@interface SlateSuggestion : NSObject
@property(copy) NSString* title;
@property(copy) NSString* subtitle;  // domain or URL shown muted after "—"
@property(copy) NSString* query;
@property SlateSuggestionKind kind;
@property TabId tabId;
+ (instancetype)search:(NSString*)title query:(NSString*)query;
+ (instancetype)url:(NSString*)title subtitle:(NSString*)subtitle query:(NSString*)query;
+ (instancetype)history:(NSString*)title subtitle:(NSString*)subtitle query:(NSString*)query;
+ (instancetype)open:(NSString*)title subtitle:(NSString*)subtitle query:(NSString*)query tabId:(TabId)tabId;
@end
@implementation SlateSuggestion
+ (instancetype)search:(NSString*)title query:(NSString*)query {
 SlateSuggestion* item=[self new];
 item.title=title; item.subtitle=@""; item.query=query; item.kind=SlateSuggestionKindSearch;
 return item;
}
+ (instancetype)url:(NSString*)title subtitle:(NSString*)subtitle query:(NSString*)query {
 SlateSuggestion* item=[self new];
 item.title=title; item.subtitle=subtitle ?: @""; item.query=query; item.kind=SlateSuggestionKindURL;
 return item;
}
+ (instancetype)history:(NSString*)title subtitle:(NSString*)subtitle query:(NSString*)query {
 SlateSuggestion* item=[self new];
 item.title=title; item.subtitle=subtitle ?: @""; item.query=query; item.kind=SlateSuggestionKindHistory;
 return item;
}
+ (instancetype)open:(NSString*)title subtitle:(NSString*)subtitle query:(NSString*)query tabId:(TabId)tabId {
 SlateSuggestion* item=[self new];
 item.title=title; item.subtitle=subtitle ?: @""; item.query=query; item.kind=SlateSuggestionKindOpen; item.tabId=tabId;
 return item;
}
// Legacy factory kept for binary compat
+ (instancetype)title:(NSString*)title query:(NSString*)query {
 return [self search:title query:query];
}
@end
@interface SlateSuggestPanel : NSPanel
@end
@implementation SlateSuggestPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end
@interface SlateSuggestRow : NSView
@property(weak) SlateDelegate* owner;
@property(strong) SlateSuggestion* item;
@property(strong) NSView* fill;
@property(strong) NSTextField* label;
@property(nonatomic) BOOL highlighted;
@end
@implementation SlateSuggestRow
- (instancetype)initWithItem:(SlateSuggestion*)item owner:(SlateDelegate*)owner {
 self=[super initWithFrame:NSZeroRect];
 if(self) {
  _item=item; _owner=owner;
  self.translatesAutoresizingMaskIntoConstraints=NO;
  self.wantsLayer=YES;
  // Highlight fill pill — inset from edges, rounded
  _fill=[[NSView alloc] initWithFrame:NSZeroRect];
  _fill.translatesAutoresizingMaskIntoConstraints=NO;
  _fill.wantsLayer=YES;
  _fill.layer.cornerRadius=8;
  if(@available(macOS 11.0,*)) _fill.layer.cornerCurve=kCACornerCurveContinuous;
  NSColor* ink = owner.barInk ?: NSColor.labelColor;
  NSColor* muted = owner.barMuted ?: [ink colorWithAlphaComponent:0.55];

  NSView* leadingIndicator = nil;
  if(item.kind == SlateSuggestionKindOpen) {
   NSView* dot = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 6, 6)];
   dot.wantsLayer = YES;
   dot.layer.cornerRadius = 3;
   dot.layer.backgroundColor = [ink colorWithAlphaComponent:0.55].CGColor;
   dot.translatesAutoresizingMaskIntoConstraints = NO;
   leadingIndicator = dot;
  } else {
   NSString* iconName=(item.kind==SlateSuggestionKindSearch) ? @"magnifyingglass" : ((item.kind==SlateSuggestionKindHistory) ? @"clock" : @"globe");
   NSImageSymbolConfiguration* iconConf=[NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightLight];
   NSImageView* icon=[[NSImageView alloc] initWithFrame:NSZeroRect];
   icon.image=[[NSImage imageWithSystemSymbolName:iconName accessibilityDescription:nil] imageWithSymbolConfiguration:iconConf];
   icon.contentTintColor=muted;
   icon.translatesAutoresizingMaskIntoConstraints=NO;
   leadingIndicator = icon;
  }
  // Label: title (medium) + optional " — domain" (muted)
  NSMutableAttributedString* astr=[[NSMutableAttributedString alloc] init];
  NSString* mainTitle=item.title ?: @"";
  NSDictionary* titleAttr=@{
   NSFontAttributeName:[NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
   NSForegroundColorAttributeName:ink
  };
  [astr appendAttributedString:[[NSAttributedString alloc] initWithString:mainTitle attributes:titleAttr]];
  if(item.subtitle.length) {
   NSDictionary* mutedAttr=@{
    NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
    NSForegroundColorAttributeName:muted
   };
   NSString* suffix=[NSString stringWithFormat:@"  —  %@", item.subtitle];
   [astr appendAttributedString:[[NSAttributedString alloc] initWithString:suffix attributes:mutedAttr]];
  }
  _label=[NSTextField labelWithString:@""];
  _label.attributedStringValue=astr;
  _label.lineBreakMode=NSLineBreakByTruncatingTail;
  _label.translatesAutoresizingMaskIntoConstraints=NO;
  _label.refusesFirstResponder=YES;
  [_label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [_label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self addSubview:_fill];
  [self addSubview:leadingIndicator];
  [self addSubview:_label];

  const CGFloat indicatorSize = (item.kind == SlateSuggestionKindOpen) ? 6 : 18;
  const CGFloat indicatorLead = (item.kind == SlateSuggestionKindOpen) ? 22 : 18;
  const CGFloat labelGap = (item.kind == SlateSuggestionKindOpen) ? 16 : 12;

  [NSLayoutConstraint activateConstraints:@[
   [self.heightAnchor constraintEqualToConstant:44],
   // Fill spans full row with 4pt horizontal and 2pt vertical inset
   [_fill.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
   [_fill.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
   [_fill.topAnchor constraintEqualToAnchor:self.topAnchor constant:2],
   [_fill.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2],
   // Indicator: centered vertically
   [leadingIndicator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:indicatorLead],
   [leadingIndicator.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
   [leadingIndicator.widthAnchor constraintEqualToConstant:indicatorSize],
   [leadingIndicator.heightAnchor constraintEqualToConstant:indicatorSize],
   // Label right of indicator
   [_label.leadingAnchor constraintEqualToAnchor:leadingIndicator.trailingAnchor constant:labelGap],
   [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
   [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
  ]];
 }
 return self;
}
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)acceptsFirstResponder { return NO; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 for(NSTrackingArea* area in self.trackingAreas) [self removeTrackingArea:area];
 NSTrackingArea* area=[[NSTrackingArea alloc] initWithRect:self.bounds
  options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect
  owner:self userInfo:nil];
 [self addTrackingArea:area];
}
- (void)setHighlighted:(BOOL)highlighted {
 _highlighted=highlighted;
 NSColor* ink = self.owner.barInk ?: NSColor.labelColor;
 self.fill.layer.backgroundColor=highlighted
  ? [ink colorWithAlphaComponent:0.12].CGColor
  : NSColor.clearColor.CGColor;
}
- (void)mouseEntered:(NSEvent*)event {
 self.owner.suggestHighlight=[self.owner.suggestStack.arrangedSubviews indexOfObject:self];
 [self.owner applySuggestionHighlight];
}
- (void)mouseExited:(NSEvent*)event {}
- (void)mouseDown:(NSEvent*)event { [self.owner pickSuggestion:self.item]; }
@end

static NSImage* g_graniteTile = nil;
static NSImage* GranitePatternImage() {
 if(g_graniteTile) return g_graniteTile;
 const int size = 128;
 NSBitmapImageRep* rep = [[NSBitmapImageRep alloc]
     initWithBitmapDataPlanes:NULL
     pixelsWide:size
     pixelsHigh:size
     bitsPerSample:8
     samplesPerPixel:4
     hasAlpha:YES
     isPlanar:NO
     colorSpaceName:NSDeviceRGBColorSpace
     bytesPerRow:size * 4
     bitsPerPixel:32];
 unsigned char* p = [rep bitmapData];
 uint32_t s = 0x85ebca6b;
 auto rnd = [&s]() -> uint32_t {
  s ^= s << 13; s ^= s >> 17; s ^= s << 5;
  return s;
 };
 for(int y = 0; y < size; ++y) {
  for(int x = 0; x < size; ++x) {
   int idx = (y * size + x) * 4;
   uint32_t val = rnd();
   int prob = (val & 0xFF);
   if(prob < 38) {
    int darkAlpha = 35 + ((val >> 8) & 0x3F);
    p[idx + 0] = 18; p[idx + 1] = 18; p[idx + 2] = 22; p[idx + 3] = (unsigned char)darkAlpha;
   } else if(prob > 218) {
    int lightAlpha = 40 + ((val >> 8) & 0x4F);
    p[idx + 0] = 250; p[idx + 1] = 252; p[idx + 2] = 255; p[idx + 3] = (unsigned char)lightAlpha;
   } else if(prob >= 100 && prob < 125) {
    int midAlpha = 15 + ((val >> 8) & 0x1F);
    p[idx + 0] = 70; p[idx + 1] = 72; p[idx + 2] = 80; p[idx + 3] = (unsigned char)midAlpha;
   } else {
    p[idx + 0] = 0; p[idx + 1] = 0; p[idx + 2] = 0; p[idx + 3] = 0;
   }
  }
 }
 [rep setSize:NSMakeSize(64, 64)];
 g_graniteTile = [[NSImage alloc] initWithSize:NSMakeSize(64, 64)];
 [g_graniteTile addRepresentation:rep];
 return g_graniteTile;
}

@implementation SlateGraniteView
- (BOOL)isOpaque { return NO; }
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)drawRect:(NSRect)dirtyRect {
 NSImage* tile = GranitePatternImage();
 if(!tile) return;
 [NSGraphicsContext saveGraphicsState];
 [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationNone;
 CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
 CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
 [[NSColor colorWithPatternImage:tile] setFill];
 NSRectFillUsingOperation(dirtyRect, NSCompositingOperationSourceOver);
 [NSGraphicsContext restoreGraphicsState];
}
@end

@interface SlateWavySlider : NSControl
@property(nonatomic) CGFloat value;
@property(nonatomic, copy) void (^onValueChanged)(CGFloat val);
@end
@implementation SlateWavySlider
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)setValue:(CGFloat)value {
 _value = std::max(0.0, std::min(1.0, (double)value));
 [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
 const NSRect bounds = self.bounds;
 const CGFloat pad = 12.0;
 const CGFloat trackW = bounds.size.width - pad * 2.0;
 if(trackW <= 0) return;
 const CGFloat midY = bounds.size.height / 2.0;

 NSRect barRect = NSMakeRect(pad, midY - 1.5, trackW, 3.0);
 NSBezierPath* bar = [NSBezierPath bezierPathWithRoundedRect:barRect xRadius:1.5 yRadius:1.5];
 [[NSColor.quaternaryLabelColor colorWithAlphaComponent:0.25] setFill];
 [bar fill];

 const CGFloat thumbX = pad + _value * trackW;
 const CGFloat cycles = 6.0;
 const CGFloat amp = 5.5;
 const int steps = (int)trackW;

 NSBezierPath* fullWave = [NSBezierPath bezierPath];
 for(int i = 0; i <= steps; ++i) {
  CGFloat x = pad + i;
  CGFloat t = (CGFloat)i / trackW;
  CGFloat y = midY + amp * std::sin(t * cycles * 2.0 * M_PI);
  if(i == 0) [fullWave moveToPoint:NSMakePoint(x, y)];
  else [fullWave lineToPoint:NSMakePoint(x, y)];
 }
 fullWave.lineWidth = 2.4;
 fullWave.lineCapStyle = NSLineCapStyleRound;
 fullWave.lineJoinStyle = NSLineJoinStyleRound;

 [NSGraphicsContext saveGraphicsState];
 [NSBezierPath clipRect:NSMakeRect(0, 0, thumbX, bounds.size.height)];
 [[NSColor.labelColor colorWithAlphaComponent:0.65] setStroke];
 [fullWave stroke];
 [NSGraphicsContext restoreGraphicsState];

 [NSGraphicsContext saveGraphicsState];
 [NSBezierPath clipRect:NSMakeRect(thumbX, 0, bounds.size.width - thumbX, bounds.size.height)];
 [[NSColor.tertiaryLabelColor colorWithAlphaComponent:0.35] setStroke];
 [fullWave stroke];
 [NSGraphicsContext restoreGraphicsState];

 const CGFloat thumbW = 15.0;
 const CGFloat thumbH = 30.0;
 const NSRect thumbRect = NSMakeRect(thumbX - thumbW / 2.0, midY - thumbH / 2.0, thumbW, thumbH);

 [NSGraphicsContext saveGraphicsState];
 NSShadow* shadow = [NSShadow new];
 shadow.shadowBlurRadius = 3.5;
 shadow.shadowOffset = NSMakeSize(0, -1);
 shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.22];
 [shadow set];

 NSBezierPath* pill = [NSBezierPath bezierPathWithRoundedRect:thumbRect xRadius:thumbW/2.0 yRadius:thumbW/2.0];
 [NSColor.whiteColor setFill];
 [pill fill];
 [NSGraphicsContext restoreGraphicsState];

 [[NSColor.blackColor colorWithAlphaComponent:0.08] setStroke];
 pill.lineWidth = 0.5;
 [pill stroke];
}
- (void)updateValueWithEvent:(NSEvent *)event {
 NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
 const CGFloat pad = 12.0;
 const CGFloat trackW = self.bounds.size.width - pad * 2.0;
 if(trackW <= 0) return;
 CGFloat val = (p.x - pad) / trackW;
 self.value = std::max(0.0, std::min(1.0, (double)val));
 if(self.onValueChanged) self.onValueChanged(self.value);
}
- (void)mouseDown:(NSEvent *)event {
 [self updateValueWithEvent:event];
}
- (void)mouseDragged:(NSEvent *)event {
 [self updateValueWithEvent:event];
}
@end

@interface SlateGranitePreviewView : NSView
@property(nonatomic) CGFloat intensity;
@property(nonatomic, copy) void (^onToggle)(void);
@end
@implementation SlateGranitePreviewView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)setIntensity:(CGFloat)intensity {
 _intensity = intensity;
 [self setNeedsDisplay:YES];
}
- (void)mouseDown:(NSEvent *)event {
 if(self.onToggle) self.onToggle();
}
- (void)drawRect:(NSRect)dirtyRect {
 const NSRect bounds = self.bounds;
 const NSPoint center = NSMakePoint(NSMidX(bounds), NSMidY(bounds));
 const CGFloat diskR = 19.0;
 const CGFloat haloR = 25.5;
 const int dotCount = 18;

 const CGFloat dotAlpha = 0.20 + 0.55 * _intensity;
 NSColor* dotColor = [NSColor.labelColor colorWithAlphaComponent:dotAlpha];
 [dotColor setFill];
 for(int i = 0; i < dotCount; ++i) {
  CGFloat angle = i * (2.0 * M_PI / dotCount);
  CGFloat dx = center.x + haloR * std::cos(angle);
  CGFloat dy = center.y + haloR * std::sin(angle);
  NSRect dotRect = NSMakeRect(dx - 1.25, dy - 1.25, 2.5, 2.5);
  NSBezierPath* dot = [NSBezierPath bezierPathWithOvalInRect:dotRect];
  [dot fill];
 }

 NSRect diskRect = NSMakeRect(center.x - diskR, center.y - diskR, diskR * 2.0, diskR * 2.0);
 NSBezierPath* diskPath = [NSBezierPath bezierPathWithOvalInRect:diskRect];

 [NSGraphicsContext saveGraphicsState];
 NSShadow* shadow = [NSShadow new];
 shadow.shadowBlurRadius = 3.0;
 shadow.shadowOffset = NSMakeSize(0, -1);
 shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.18];
 [shadow set];
 [NSColor.whiteColor setFill];
 [diskPath fill];
 [NSGraphicsContext restoreGraphicsState];

 [NSGraphicsContext saveGraphicsState];
 [diskPath addClip];

 NSGradient* grad = [[NSGradient alloc] initWithStartingColor:ColorSRGB(0.92, 0.92, 0.94)
                                                  endingColor:ColorSRGB(0.68, 0.69, 0.72)];
 [grad drawInBezierPath:diskPath angle:-45.0];

 NSImage* tile = GranitePatternImage();
 if(tile) {
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationNone;
  CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
  CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
  [[NSColor colorWithPatternImage:tile] setFill];
  CGContextSetAlpha(ctx, MIN(1.0, 0.15 + _intensity * 0.85));
  NSRectFillUsingOperation(diskRect, NSCompositingOperationSourceOver);
  [NSGraphicsContext restoreGraphicsState];
 }
 [NSGraphicsContext restoreGraphicsState];

 [[NSColor.whiteColor colorWithAlphaComponent:0.40] setStroke];
 diskPath.lineWidth = 1.0;
 [diskPath stroke];
}
@end

@interface SlateSwatchRowView : NSView
@property(nonatomic, copy) NSString* selectedHex;
@property(nonatomic, copy) void (^onSelectHex)(NSString* hex);
@end
@implementation SlateSwatchRowView {
 NSArray<NSString*>* _palette;
}
- (instancetype)initWithFrame:(NSRect)frame {
 self = [super initWithFrame:frame];
 if(self) {
  _palette = @[
   @"#EBE8E1", @"#F2A2B0", @"#A37FB7", @"#E26D6D", @"#EE9E70",
   @"#ECC86E", @"#8ED8B0", @"#7BB8DC", @"#586B8A", @"#4A4B52"
  ];
 }
 return self;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)setSelectedHex:(NSString *)selectedHex {
 _selectedHex = [selectedHex copy];
 [self setNeedsDisplay:YES];
}
- (NSRect)chevronLeftRect {
 return NSMakeRect(2, (self.bounds.size.height - 20) / 2.0, 16, 20);
}
- (NSRect)chevronRightRect {
 return NSMakeRect(self.bounds.size.width - 18, (self.bounds.size.height - 20) / 2.0, 16, 20);
}
- (NSRect)swatchRectAtIndex:(NSUInteger)idx {
 const CGFloat padL = 20.0;
 const CGFloat padR = 20.0;
 const CGFloat availW = self.bounds.size.width - padL - padR;
 const NSUInteger count = _palette.count;
 const CGFloat swatchD = 16.0;
 const CGFloat gap = (count > 1) ? (availW - count * swatchD) / (count - 1) : 0;
 const CGFloat x = padL + idx * (swatchD + gap);
 const CGFloat y = (self.bounds.size.height - swatchD) / 2.0;
 return NSMakeRect(x, y, swatchD, swatchD);
}
- (void)stepSelection:(NSInteger)delta {
 NSUInteger currentIdx = 0;
 BOOL found = NO;
 for(NSUInteger i = 0; i < _palette.count; ++i) {
  if([_palette[i] caseInsensitiveCompare:self.selectedHex ?: @""] == NSOrderedSame) {
   currentIdx = i;
   found = YES;
   break;
  }
 }
 NSInteger nextIdx = found ? ((NSInteger)currentIdx + delta) : 0;
 if(nextIdx < 0) nextIdx = _palette.count - 1;
 else if(nextIdx >= (NSInteger)_palette.count) nextIdx = 0;
 NSString* hex = _palette[nextIdx];
 self.selectedHex = hex;
 if(self.onSelectHex) self.onSelectHex(hex);
}
- (void)mouseDown:(NSEvent *)event {
 NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
 if(NSPointInRect(p, [self chevronLeftRect])) {
  [self stepSelection:-1];
  return;
 }
 if(NSPointInRect(p, [self chevronRightRect])) {
  [self stepSelection:1];
  return;
 }
 for(NSUInteger i = 0; i < _palette.count; ++i) {
  NSRect r = [self swatchRectAtIndex:i];
  if(NSPointInRect(p, NSInsetRect(r, -2, -4))) {
   NSString* hex = _palette[i];
   self.selectedHex = hex;
   if(self.onSelectHex) self.onSelectHex(hex);
   return;
  }
 }
}
- (void)drawRect:(NSRect)dirtyRect {
 NSDictionary* arrowAttr = @{
  NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
  NSForegroundColorAttributeName: [NSColor.labelColor colorWithAlphaComponent:0.40]
 };
 [@"‹" drawInRect:NSOffsetRect([self chevronLeftRect], 3, -1) withAttributes:arrowAttr];
 [@"›" drawInRect:NSOffsetRect([self chevronRightRect], 4, -1) withAttributes:arrowAttr];

 for(NSUInteger i = 0; i < _palette.count; ++i) {
  NSString* hex = _palette[i];
  NSRect r = [self swatchRectAtIndex:i];
  NSColor* col = ColorFromHex(hex) ?: NSColor.grayColor;
  BOOL isSel = [hex caseInsensitiveCompare:self.selectedHex ?: @""] == NSOrderedSame;

  if(isSel) {
   NSRect ringRect = NSInsetRect(r, -2.5, -2.5);
   NSBezierPath* ring = [NSBezierPath bezierPathWithOvalInRect:ringRect];
   [[NSColor.labelColor colorWithAlphaComponent:0.55] setStroke];
   ring.lineWidth = 1.5;
   [ring stroke];
  }

  NSBezierPath* circle = [NSBezierPath bezierPathWithOvalInRect:r];
  [col setFill];
  [circle fill];

  [[NSColor.blackColor colorWithAlphaComponent:0.10] setStroke];
  circle.lineWidth = 0.5;
  [circle stroke];
 }
}
@end

struct SlateThemeBubblePoint {
 NSPoint normCenter;
 CGFloat radius;
 NSString* __strong hex;
};

@interface SlateThemePreviewCanvas : NSView
@property(strong) NSColor* accentColor;
@property(nonatomic) CGFloat graniteIntensity;
@property(nonatomic) int themeMode;
@property(nonatomic) int selectedBubbleIndex;
@property(nonatomic, copy) void (^onModeChanged)(int newMode);
@property(nonatomic, copy) void (^onColorAdjusted)(NSString* hex);
@property(nonatomic, copy) void (^onBubbleSelected)(int index, NSString* hex);
- (void)setSelectedBubbleHex:(NSString*)hex;
- (NSString*)selectedBubbleHex;
- (NSString*)primaryHex;
- (NSString*)secondaryHex;
- (void)setPrimaryHex:(NSString*)h1 secondaryHex:(NSString*)h2;
@end

@implementation SlateThemePreviewCanvas {
 std::vector<SlateThemeBubblePoint> _bubbles;
 int _dragIndex;
}
- (instancetype)initWithFrame:(NSRect)frame {
 self = [super initWithFrame:frame];
 if(self) {
  _dragIndex = -1;
  _selectedBubbleIndex = 1;
  _themeMode = 0;
  _graniteIntensity = 0.0;
  _accentColor = ColorSRGB(0.925, 0.845, 0.835);
  _bubbles.push_back({NSMakePoint(0.70, 0.72), 9.0, @"#F2A2B0"});
  _bubbles.push_back({NSMakePoint(0.74, 0.44), 21.0, @"#EE9E70"});
  _bubbles.push_back({NSMakePoint(0.55, 0.28), 12.0, @"#ECC86E"});
 }
 return self;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (NSRect)modeClusterRect {
 const CGFloat w = 84.0;
 const CGFloat h = 24.0;
 return NSMakeRect((self.bounds.size.width - w) / 2.0, self.bounds.size.height - h - 10.0, w, h);
}
- (NSRect)modeItemRectAtIndex:(int)idx {
 NSRect cluster = [self modeClusterRect];
 CGFloat itemW = cluster.size.width / 3.0;
 return NSMakeRect(cluster.origin.x + idx * itemW, cluster.origin.y, itemW, cluster.size.height);
}
- (NSRect)stepperRect {
 const CGFloat w = 48.0;
 const CGFloat h = 20.0;
 return NSMakeRect((self.bounds.size.width - w) / 2.0, 10.0, w, h);
}
- (NSRect)minusRect {
 NSRect st = [self stepperRect];
 return NSMakeRect(st.origin.x, st.origin.y, st.size.width / 2.0, st.size.height);
}
- (NSRect)plusRect {
 NSRect st = [self stepperRect];
 return NSMakeRect(st.origin.x + st.size.width / 2.0, st.origin.y, st.size.width / 2.0, st.size.height);
}
- (NSPoint)pointForBubble:(const SlateThemeBubblePoint&)b {
 return NSMakePoint(b.normCenter.x * self.bounds.size.width, b.normCenter.y * self.bounds.size.height);
}
- (NSString*)selectedBubbleHex {
 if(_selectedBubbleIndex >= 0 && _selectedBubbleIndex < (int)_bubbles.size()) {
  return _bubbles[_selectedBubbleIndex].hex ?: @"";
 }
 return @"";
}
- (void)setSelectedBubbleHex:(NSString*)hex {
 if(!hex.length) return;
 if(_selectedBubbleIndex >= 0 && _selectedBubbleIndex < (int)_bubbles.size()) {
  _bubbles[_selectedBubbleIndex].hex = [hex copy];
  [self setNeedsDisplay:YES];
 }
}
- (NSString*)primaryHex {
 if(_bubbles.size() > 1) return _bubbles[1].hex ?: @"";
 if(_bubbles.size() > 0) return _bubbles[0].hex ?: @"";
 return @"";
}
- (NSString*)secondaryHex {
 if(_bubbles.size() > 1 && ![_bubbles[0].hex isEqualToString:_bubbles[1].hex]) return _bubbles[0].hex ?: @"";
 if(_bubbles.size() > 2 && ![_bubbles[2].hex isEqualToString:_bubbles[1].hex]) return _bubbles[2].hex ?: @"";
 return @"";
}
- (void)setPrimaryHex:(NSString*)h1 secondaryHex:(NSString*)h2 {
 if(_bubbles.size() > 1) {
  if(h1.length) _bubbles[1].hex = [h1 copy];
  if(h2.length) _bubbles[0].hex = [h2 copy];
 } else if(_bubbles.size() > 0 && h1.length) {
  _bubbles[0].hex = [h1 copy];
 }
 [self setNeedsDisplay:YES];
}
- (void)mouseDown:(NSEvent *)event {
 NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
 for(int i = 0; i < 3; ++i) {
  if(NSPointInRect(p, [self modeItemRectAtIndex:i])) {
   self.themeMode = i;
   [self setNeedsDisplay:YES];
   if(self.onModeChanged) self.onModeChanged(i);
   return;
  }
 }
 if(NSPointInRect(p, [self minusRect])) {
  if(_bubbles.size() > 1) {
   _bubbles.pop_back();
   if(_selectedBubbleIndex >= (int)_bubbles.size()) {
    _selectedBubbleIndex = (int)_bubbles.size() - 1;
   }
   [self setNeedsDisplay:YES];
   if(self.onBubbleSelected) self.onBubbleSelected(_selectedBubbleIndex, [self selectedBubbleHex]);
   if(self.onColorAdjusted) self.onColorAdjusted([self selectedBubbleHex]);
  }
  return;
 }
 if(NSPointInRect(p, [self plusRect])) {
  if(_bubbles.size() < 5) {
   CGFloat r = 14.0;
   CGFloat x = 0.35 + (_bubbles.size() % 2) * 0.25;
   CGFloat y = 0.45 + (_bubbles.size() % 3) * 0.15;
   NSArray<NSString*>* fallbackColors = @[@"#8ED8B0", @"#7BB8DC", @"#A37FB7"];
   NSString* addHex = fallbackColors[(_bubbles.size() - 3) % fallbackColors.count];
   _bubbles.push_back({NSMakePoint(x, y), r, addHex});
   _selectedBubbleIndex = (int)_bubbles.size() - 1;
   [self setNeedsDisplay:YES];
   if(self.onBubbleSelected) self.onBubbleSelected(_selectedBubbleIndex, addHex);
   if(self.onColorAdjusted) self.onColorAdjusted(addHex);
  }
  return;
 }
 _dragIndex = -1;
 for(int i = (int)_bubbles.size() - 1; i >= 0; --i) {
  NSPoint bp = [self pointForBubble:_bubbles[i]];
  CGFloat dist = std::hypot(p.x - bp.x, p.y - bp.y);
  if(dist <= _bubbles[i].radius + 8.0) {
   _dragIndex = i;
   _selectedBubbleIndex = i;
   [self setNeedsDisplay:YES];
   if(self.onBubbleSelected) self.onBubbleSelected(i, _bubbles[i].hex);
   break;
  }
 }
}
- (void)mouseDragged:(NSEvent *)event {
 if(_dragIndex >= 0 && _dragIndex < (int)_bubbles.size()) {
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  CGFloat nx = std::max(0.12, std::min(0.88, p.x / self.bounds.size.width));
  CGFloat ny = std::max(0.12, std::min(0.88, p.y / self.bounds.size.height));
  _bubbles[_dragIndex].normCenter = NSMakePoint(nx, ny);

  NSString* currentHex = _bubbles[_dragIndex].hex;
  NSColor* base = (currentHex.length ? ColorFromHex(currentHex) : nil) ?: self.accentColor ?: ColorSRGB(0.925, 0.845, 0.835);
  NSColor* rgb = [base colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: base;
  CGFloat h = 0, s = 0, b = 0, a = 0;
  [rgb getHue:&h saturation:&s brightness:&b alpha:&a];
  CGFloat newSat = std::max(0.15, std::min(0.85, (double)nx));
  CGFloat newBrt = std::max(0.35, std::min(0.98, (double)ny));
  NSColor* adjusted = [NSColor colorWithHue:h saturation:newSat brightness:newBrt alpha:1.0];
  _bubbles[_dragIndex].hex = HexFromColor(adjusted);

  [self setNeedsDisplay:YES];
  if(self.onColorAdjusted) self.onColorAdjusted(_bubbles[_dragIndex].hex);
 }
}
- (void)mouseUp:(NSEvent *)event {
 _dragIndex = -1;
}
- (void)drawRect:(NSRect)dirtyRect {
 const NSRect bounds = self.bounds;
 NSBezierPath* clip = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:14.0 yRadius:14.0];

 [NSGraphicsContext saveGraphicsState];
 [clip addClip];

 NSColor* c1 = (_bubbles.size() > 1 && _bubbles[1].hex.length) ? ColorFromHex(_bubbles[1].hex) : (self.accentColor ?: ColorSRGB(0.92, 0.92, 0.94));
 NSColor* c0 = (_bubbles.size() > 0 && _bubbles[0].hex.length) ? ColorFromHex(_bubbles[0].hex) : c1;
 if(!c1) c1 = ColorSRGB(0.92, 0.92, 0.94);
 if(!c0) c0 = c1;

 NSColor* fill1 = [c1 blendedColorWithFraction:0.55 ofColor:ColorSRGB(0.94, 0.94, 0.95)];
 NSColor* fill0 = [c0 blendedColorWithFraction:0.55 ofColor:ColorSRGB(0.94, 0.94, 0.95)];

 if([_bubbles[0].hex isEqualToString:_bubbles[1].hex] || _bubbles.size() <= 1) {
  [fill1 setFill];
  [clip fill];
 } else {
  NSGradient* bgGrad = [[NSGradient alloc] initWithStartingColor:fill0 endingColor:fill1];
  [bgGrad drawInBezierPath:clip angle:-45.0];
 }

 if(_bubbles.size() > 1) {
  NSPoint mainPt = [self pointForBubble:_bubbles[1]];
  NSGradient* radial = [[NSGradient alloc] initWithStartingColor:[c1 colorWithAlphaComponent:0.35]
                                                     endingColor:[c1 colorWithAlphaComponent:0.0]];
  [radial drawFromCenter:mainPt radius:10.0 toCenter:mainPt radius:120.0 options:0];
 }

 if(_graniteIntensity > 0.005) {
  NSImage* tile = GranitePatternImage();
  if(tile) {
   [NSGraphicsContext saveGraphicsState];
   [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationNone;
   CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
   CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
   [[NSColor colorWithPatternImage:tile] setFill];
   CGContextSetAlpha(ctx, MIN(1.0, _graniteIntensity * 0.40));
   NSRectFillUsingOperation(bounds, NSCompositingOperationSourceOver);
   [NSGraphicsContext restoreGraphicsState];
  }
 }

 for(int i = 0; i < 3; ++i) {
  NSRect ir = [self modeItemRectAtIndex:i];
  BOOL isActive = (self.themeMode == i);
  if(isActive) {
   NSRect pillRect = NSInsetRect(ir, 3, 2);
   NSBezierPath* pill = [NSBezierPath bezierPathWithRoundedRect:pillRect xRadius:6 yRadius:6];
   [[NSColor.whiteColor colorWithAlphaComponent:0.55] setFill];
   [pill fill];
  }
  NSString* sym = (i == 0) ? @"✦" : ((i == 1) ? @"☼" : @"☾");
  CGFloat fontSize = (i == 0) ? 12.0 : ((i == 1) ? 14.0 : 13.0);
  NSColor* symColor = isActive ? NSColor.labelColor : [NSColor.labelColor colorWithAlphaComponent:0.45];
  NSMutableParagraphStyle* ps = [NSMutableParagraphStyle new];
  ps.alignment = NSTextAlignmentCenter;
  NSRect textRect = NSOffsetRect(ir, 0, (i == 1 ? -1 : 0));
  [sym drawInRect:textRect withAttributes:@{
   NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightMedium],
   NSForegroundColorAttributeName: symColor,
   NSParagraphStyleAttributeName: ps
  }];
 }

 for(size_t i = 0; i < _bubbles.size(); ++i) {
  NSPoint bp = [self pointForBubble:_bubbles[i]];
  CGFloat r = _bubbles[i].radius;
  NSRect bRect = NSMakeRect(bp.x - r, bp.y - r, r * 2.0, r * 2.0);
  NSBezierPath* bPath = [NSBezierPath bezierPathWithOvalInRect:bRect];

  [NSGraphicsContext saveGraphicsState];
  NSShadow* sh = [NSShadow new];
  sh.shadowBlurRadius = 4.0;
  sh.shadowOffset = NSMakeSize(0, -2);
  sh.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.16];
  [sh set];
  [NSColor.whiteColor setFill];
  [bPath fill];
  [NSGraphicsContext restoreGraphicsState];

  NSColor* bubbleCol = ColorFromHex(_bubbles[i].hex) ?: (self.accentColor ?: ColorSRGB(0.95, 0.65, 0.72));
  [bubbleCol setFill];
  [bPath fill];

  [NSColor.whiteColor setStroke];
  bPath.lineWidth = 2.4;
  [bPath stroke];

  // Active selection ring around selected bubble
  if((int)i == _selectedBubbleIndex) {
   NSRect selRect = NSInsetRect(bRect, -3.5, -3.5);
   NSBezierPath* selRing = [NSBezierPath bezierPathWithOvalInRect:selRect];
   [[NSColor.whiteColor colorWithAlphaComponent:0.95] setStroke];
   selRing.lineWidth = 2.0;
   [selRing stroke];
  }
 }

 NSMutableParagraphStyle* stPs = [NSMutableParagraphStyle new];
 stPs.alignment = NSTextAlignmentCenter;
 NSDictionary* stAttr = @{
  NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
  NSForegroundColorAttributeName: [NSColor.labelColor colorWithAlphaComponent:0.40],
  NSParagraphStyleAttributeName: stPs
 };
 [@"–" drawInRect:[self minusRect] withAttributes:stAttr];
 [@"+" drawInRect:[self plusRect] withAttributes:stAttr];

 [NSGraphicsContext restoreGraphicsState];

 [[NSColor.blackColor colorWithAlphaComponent:0.06] setStroke];
 clip.lineWidth = 1.0;
 [clip stroke];
}
@end

@interface SlateThemeCardView : NSVisualEffectView
@property(strong) SlateThemePreviewCanvas* canvas;
@property(strong) SlateSwatchRowView* swatchRow;
@property(strong) SlateWavySlider* wavySlider;
@property(strong) SlateGranitePreviewView* granitePreview;
@end
@implementation SlateThemeCardView
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return YES; }
- (instancetype)initWithFrame:(NSRect)frame {
 self = [super initWithFrame:frame];
 if(self) {
  self.material = NSVisualEffectMaterialPopover;
  self.blendingMode = NSVisualEffectBlendingModeBehindWindow;
  self.state = NSVisualEffectStateActive;
  self.wantsLayer = YES;
  self.layer.cornerRadius = 18.0;
  self.layer.masksToBounds = YES;
  self.layer.borderWidth = 1.0;
  self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.25].CGColor;

  _canvas = [[SlateThemePreviewCanvas alloc] initWithFrame:NSMakeRect(10, 10, 236, 194)];
  [self addSubview:_canvas];

  _swatchRow = [[SlateSwatchRowView alloc] initWithFrame:NSMakeRect(10, 212, 236, 32)];
  [self addSubview:_swatchRow];

  _wavySlider = [[SlateWavySlider alloc] initWithFrame:NSMakeRect(10, 252, 172, 60)];
  [self addSubview:_wavySlider];

  _granitePreview = [[SlateGranitePreviewView alloc] initWithFrame:NSMakeRect(190, 255, 54, 54)];
  [self addSubview:_granitePreview];
 }
 return self;
}
@end

@interface SlateThemePanel : NSPanel
@property(weak) SlateDelegate* slateDelegate;
@property(readonly) SlateThemeCardView* card;
+ (instancetype)sharedPanel;
- (void)showForSlateDelegate:(SlateDelegate*)delegate;
- (void)updateFromDelegate;
@end
@implementation SlateThemePanel {
 SlateThemeCardView* _card;
}
- (SlateThemeCardView*)card { return _card; }
static SlateThemePanel* s_sharedThemePanel = nil;
+ (instancetype)sharedPanel {
 if(!s_sharedThemePanel) {
  s_sharedThemePanel = [[SlateThemePanel alloc] initWithContentRect:NSMakeRect(0, 0, 256, 324)
      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
      backing:NSBackingStoreBuffered defer:NO];
  s_sharedThemePanel.opaque = NO;
  s_sharedThemePanel.backgroundColor = NSColor.clearColor;
  s_sharedThemePanel.hasShadow = YES;
  s_sharedThemePanel.hidesOnDeactivate = YES;
  s_sharedThemePanel.floatingPanel = YES;
  s_sharedThemePanel.becomesKeyOnlyIfNeeded = YES;
  s_sharedThemePanel.releasedWhenClosed = NO;
  s_sharedThemePanel.level = NSPopUpMenuWindowLevel;

  SlateThemeCardView* card = [[SlateThemeCardView alloc] initWithFrame:NSMakeRect(0, 0, 256, 324)];
  s_sharedThemePanel.contentView = card;
  s_sharedThemePanel->_card = card;

  __weak SlateThemePanel* weakPanel = s_sharedThemePanel;

  card.canvas.onModeChanged = ^(int newMode) {
   SlateThemePanel* strongPanel = weakPanel;
   if(!strongPanel || !strongPanel.slateDelegate) return;
   strongPanel.slateDelegate.themeMode = newMode;
   [strongPanel.slateDelegate applyPlateChrome];
   [strongPanel.slateDelegate persistUiPrefs];
   [strongPanel updateFromDelegate];
  };

  card.canvas.onBubbleSelected = ^(int idx, NSString* hex) {
   SlateThemePanel* strongPanel = weakPanel;
   if(!strongPanel) return;
   strongPanel->_card.swatchRow.selectedHex = hex;
  };

  card.canvas.onColorAdjusted = ^(NSString* hex) {
   SlateThemePanel* strongPanel = weakPanel;
   if(!strongPanel || !strongPanel.slateDelegate) return;
   strongPanel.slateDelegate.accentId = @"custom";
   strongPanel.slateDelegate.accentHex = [strongPanel->_card.canvas primaryHex];
   strongPanel.slateDelegate.accentHex2 = [strongPanel->_card.canvas secondaryHex];
   [strongPanel.slateDelegate applyPlateChrome];
   [strongPanel.slateDelegate persistUiPrefs];
   [strongPanel.slateDelegate rebuildAccentMenu];
   strongPanel->_card.swatchRow.selectedHex = hex;
  };

  card.swatchRow.onSelectHex = ^(NSString* hex) {
   SlateThemePanel* strongPanel = weakPanel;
   if(!strongPanel || !strongPanel.slateDelegate) return;
   [strongPanel->_card.canvas setSelectedBubbleHex:hex];
   strongPanel.slateDelegate.accentId = @"custom";
   strongPanel.slateDelegate.accentHex = [strongPanel->_card.canvas primaryHex];
   strongPanel.slateDelegate.accentHex2 = [strongPanel->_card.canvas secondaryHex];
   [strongPanel.slateDelegate applyPlateChrome];
   [strongPanel.slateDelegate persistUiPrefs];
   [strongPanel.slateDelegate rebuildAccentMenu];
  };

  card.wavySlider.onValueChanged = ^(CGFloat val) {
   SlateThemePanel* strongPanel = weakPanel;
   if(!strongPanel || !strongPanel.slateDelegate) return;
   strongPanel.slateDelegate.graniteIntensity = val;
   strongPanel->_card.granitePreview.intensity = val;
   strongPanel->_card.canvas.graniteIntensity = val;
   [strongPanel->_card.canvas setNeedsDisplay:YES];
   [strongPanel.slateDelegate applyPlateChrome];
   [strongPanel.slateDelegate persistUiPrefs];
  };

  card.granitePreview.onToggle = ^{
   SlateThemePanel* strongPanel = weakPanel;
   if(!strongPanel || !strongPanel.slateDelegate) return;
   CGFloat nextVal = (strongPanel.slateDelegate.graniteIntensity > 0.05) ? 0.0 : 0.45;
   strongPanel.slateDelegate.graniteIntensity = nextVal;
   strongPanel->_card.wavySlider.value = nextVal;
   strongPanel->_card.granitePreview.intensity = nextVal;
   strongPanel->_card.canvas.graniteIntensity = nextVal;
   [strongPanel->_card.canvas setNeedsDisplay:YES];
   [strongPanel.slateDelegate applyPlateChrome];
   [strongPanel.slateDelegate persistUiPrefs];
  };
 }
 return s_sharedThemePanel;
}
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)cancelOperation:(id)sender {
 [self orderOut:nil];
}
- (void)updateFromDelegate {
 if(!self.slateDelegate) return;
 const BOOL systemDark = [[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
 const BOOL isDark = (self.slateDelegate.themeMode == 1) ? NO : ((self.slateDelegate.themeMode == 2) ? YES : systemDark);

 NSColor* col = ChromeAccent(self.slateDelegate.accentId, self.slateDelegate.accentHex, isDark);
 _card.canvas.accentColor = col;
 _card.canvas.graniteIntensity = self.slateDelegate.graniteIntensity;
 _card.canvas.themeMode = self.slateDelegate.themeMode;
 if(self.slateDelegate.accentHex.length) {
  [_card.canvas setPrimaryHex:self.slateDelegate.accentHex secondaryHex:self.slateDelegate.accentHex2 ?: @""];
 }
 [_card.canvas setNeedsDisplay:YES];

 NSString* currentSelHex = [_card.canvas selectedBubbleHex];
 _card.swatchRow.selectedHex = currentSelHex.length ? currentSelHex : (self.slateDelegate.accentHex.length ? self.slateDelegate.accentHex : HexFromColor(col));

 _card.wavySlider.value = self.slateDelegate.graniteIntensity;
 _card.granitePreview.intensity = self.slateDelegate.graniteIntensity;
}
- (void)showForSlateDelegate:(SlateDelegate*)delegate {
 if(self.isVisible && self.slateDelegate == delegate) {
  [self orderOut:nil];
  return;
 }
 self.slateDelegate = delegate;
 [self updateFromDelegate];

 NSRect winFrame = delegate.window.frame;
 const CGFloat w = 256.0;
 const CGFloat h = 324.0;
 CGFloat x = NSMaxX(winFrame) - w - 24.0;
 CGFloat y = NSMaxY(winFrame) - h - 54.0;
 [self setFrame:NSMakeRect(x, y, w, h) display:YES];

 [delegate.window addChildWindow:self ordered:NSWindowAbove];
 [self makeKeyAndOrderFront:nil];
}
@end

@interface SlateOmnibox : NSView
@property(strong) NSView* surface;
@property(strong) NSTrackingArea* hoverTrackingArea;
@property(strong) NSColor* barColor;
@property(nonatomic, assign) BOOL hovered;
@property(nonatomic, assign) BOOL focused;
- (void)applyContrast;
- (void)shake;
@end
@interface SlateAddressField : NSTextField
- (void)shake;
@end
@implementation SlateAddressField
- (void)shake {
 CAKeyframeAnimation* anim=[CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
 anim.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
 anim.duration=0.45;
 anim.values=@[ @(0), @(-9), @(9), @(-7), @(7), @(-4), @(4), @(-1), @(1), @(0) ];
 [self.layer addAnimation:anim forKey:@"shake"];
 if(self.superview && [self.superview respondsToSelector:@selector(shake)]) {
  [(id)self.superview shake];
 }
}
- (BOOL)becomeFirstResponder {
 BOOL ok = [super becomeFirstResponder];
 if (ok) {
  if ([self.superview isKindOfClass:SlateOmnibox.class]) ((SlateOmnibox*)self.superview).focused=YES;
  dispatch_async(dispatch_get_main_queue(), ^{
   NSTextView* editor = (NSTextView*)[self.window fieldEditor:YES forObject:self];
   if (editor && [editor isKindOfClass:NSTextView.class]) {
    NSColor* ink = NSColor.labelColor;
    if([self.delegate respondsToSelector:@selector(barInk)]) {
     NSColor* bi = [(id)self.delegate barInk];
     if(bi) ink = bi;
    }
    editor.selectedTextAttributes = @{
     NSBackgroundColorAttributeName: [ink colorWithAlphaComponent:0.12],
     NSForegroundColorAttributeName: ink
    };
    [editor selectAll:nil];
   }
  });
 }
 return ok;
}
- (BOOL)resignFirstResponder {
 BOOL ok=[super resignFirstResponder];
 if(ok && [self.superview isKindOfClass:SlateOmnibox.class]) ((SlateOmnibox*)self.superview).focused=NO;
 return ok;
}
@end
@implementation SlateOmnibox
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (instancetype)initWithFrame:(NSRect)frame {
 self=[super initWithFrame:frame];
 if(self) {
  self.wantsLayer=YES;
  self.layer.cornerRadius=kOmniboxHeight/2.0;
  if(@available(macOS 11.0, *)) {
   self.layer.cornerCurve=kCACornerCurveContinuous;
  }
  self.layer.masksToBounds=NO;
  self.layer.borderWidth=1.0;
  self.layer.shadowColor=NSColor.blackColor.CGColor;
  self.layer.shadowRadius=6.0;
  self.layer.shadowOffset=CGSizeMake(0,-2);
  _surface=[[NSView alloc] initWithFrame:self.bounds];
  _surface.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
  _surface.wantsLayer=YES;
  _surface.layer.cornerRadius=kOmniboxHeight/2.0;
  _surface.layer.masksToBounds=YES;
  [self addSubview:_surface positioned:NSWindowBelow relativeTo:nil];
  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(accessibilityDisplayChanged:) name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
  [self applyContrast];
 }
 return self;
}
- (void)dealloc {
 [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}
- (void)accessibilityDisplayChanged:(NSNotification*)notification { [self applyContrast]; }
- (void)setHovered:(BOOL)hovered { if(_hovered!=hovered) { _hovered=hovered; [self applyContrast]; } }
- (void)setFocused:(BOOL)focused { if(_focused!=focused) { _focused=focused; [self applyContrast]; } }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if(_hoverTrackingArea) [self removeTrackingArea:_hoverTrackingArea];
 _hoverTrackingArea=[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingInVisibleRect|NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow owner:self userInfo:nil];
 [self addTrackingArea:_hoverTrackingArea];
}
- (void)mouseEntered:(NSEvent*)event { self.hovered=YES; }
- (void)mouseExited:(NSEvent*)event { self.hovered=NO; }
- (void)layout {
 [super layout];
 const CGFloat h=NSHeight(self.bounds);
 const CGFloat r=round(h/2.0);
 self.layer.cornerRadius=r;
 _surface.layer.cornerRadius=r;
 if(@available(macOS 11.0, *)) {
  self.layer.cornerCurve=kCACornerCurveContinuous;
  _surface.layer.cornerCurve=kCACornerCurveContinuous;
 }
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 CGPathRef path=CGPathCreateWithRoundedRect(self.bounds, r, r, NULL);
 self.layer.shadowPath=path;
 CGPathRelease(path);
 [CATransaction commit];
}
- (void)viewDidChangeEffectiveAppearance { [self applyContrast]; }
- (void)applyContrast {
 NSWorkspace* workspace=[NSWorkspace sharedWorkspace];
 const BOOL opaque=workspace.accessibilityDisplayShouldReduceTransparency;
 const BOOL contrast=workspace.accessibilityDisplayShouldIncreaseContrast;
 const BOOL dark=self.barColor ? ColorIsDark(self.barColor)
  : [[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
 NSColor* tint=dark ? NSColor.whiteColor : NSColor.blackColor;
 CGFloat fillAlpha=self.focused ? 0.19 : (self.hovered ? 0.16 : 0.13);
 _surface.layer.backgroundColor=(opaque ? NSColor.controlBackgroundColor : [tint colorWithAlphaComponent:fillAlpha]).CGColor;
 CGFloat edgeAlpha=contrast ? 0.28 : (self.focused ? 0.14 : (self.hovered ? 0.11 : 0.08));
 self.layer.borderWidth=contrast ? 1.0 : 0.75;
 self.layer.borderColor=[[NSColor labelColor] colorWithAlphaComponent:edgeAlpha].CGColor;
 self.layer.shadowOpacity=opaque ? 0.0 : 0.04;
}
- (void)shake {
 CAKeyframeAnimation* anim=[CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
 anim.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
 anim.duration=0.45;
 anim.values=@[ @(0), @(-9), @(9), @(-7), @(7), @(-4), @(4), @(-1), @(1), @(0) ];
 [self.layer addAnimation:anim forKey:@"shake"];

 CGColorRef origBorder=self.layer.borderColor;
 if(origBorder) CGColorRetain(origBorder);
 NSColor* alertRed=[NSColor colorWithCalibratedRed:0.92 green:0.26 blue:0.26 alpha:0.45];
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
  ctx.duration=0.15;
  self.layer.borderColor=alertRed.CGColor;
 } completionHandler:^{
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
   [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx2) {
    ctx2.duration=0.25;
    self.layer.borderColor=origBorder;
   } completionHandler:^{
    if(origBorder) CGColorRelease(origBorder);
   }];
  });
 }];
}
@end
@interface SlateHomeOrb : NSView
@property(weak) SlateDelegate* owner;
@property(copy) NSString* ident;
@property(copy) NSString* caption;
@property(copy) NSString* detail;
@property(strong) NSImage* glyph;
@property BOOL folder;
@property BOOL pressed;
@end
@implementation SlateHomeOrb
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)drawRect:(NSRect)dirty {
 NSColor* ink=self.owner.barInk ?: NSColor.labelColor;
 NSColor* muted=self.owner.barMuted ?: NSColor.secondaryLabelColor;
 const CGFloat side=48;
 NSRect bubble=NSMakeRect(NSMidX(self.bounds)-side/2.0, 6, side, side);
 NSBezierPath* path=[NSBezierPath bezierPathWithRoundedRect:bubble xRadius:side/2.0 yRadius:side/2.0];
 [[ink colorWithAlphaComponent:self.pressed?0.20:0.10] setFill];
 [path fill];
 if(self.glyph) {
  NSRect icon=NSInsetRect(bubble, 12, 12);
  [self.glyph drawInRect:icon fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
 }
 NSMutableParagraphStyle* style=[NSMutableParagraphStyle new];
 style.alignment=NSTextAlignmentCenter;
 style.lineBreakMode=NSLineBreakByTruncatingTail;
 NSRect title=NSMakeRect(2, 58, NSWidth(self.bounds)-4, 16);
 [(self.caption ?: @"") drawInRect:title withAttributes:@{
  NSFontAttributeName:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
  NSForegroundColorAttributeName:ink,
  NSParagraphStyleAttributeName:style
 }];
 NSRect host=NSMakeRect(2, 74, NSWidth(self.bounds)-4, 14);
 [(self.detail ?: @"") drawInRect:host withAttributes:@{
  NSFontAttributeName:[NSFont systemFontOfSize:10 weight:NSFontWeightRegular],
  NSForegroundColorAttributeName:muted,
  NSParagraphStyleAttributeName:style
 }];
}
- (void)mouseDown:(NSEvent*)event { self.pressed=YES; self.needsDisplay=YES; }
- (void)mouseUp:(NSEvent*)event {
 self.pressed=NO; self.needsDisplay=YES;
 NSPoint local=[self convertPoint:event.locationInWindow fromView:nil];
 if(!NSPointInRect(local, self.bounds)) return;
 if(self.folder) [self.owner openHomeGroupIdent:self.ident];
 else [self.owner openHomeAddress:self.ident];
}
@end
@interface SlateHomeBoard : NSView
@property(weak) SlateDelegate* owner;
@property(nonatomic, strong) NSColor* wash;
@property(strong) NSTextField* greeting;
@property(strong) NSView* brandGroup;
@property(strong) NSImageView* brandGlyph;
@property(strong) SlateOmniboxCard* omniboxCard;
@property(strong) NSMutableArray<SlateHomeOrb*>* orbs;
@property(strong) NSTimer* greetingTimer;
- (void)startGreetingTimer;
- (void)stopGreetingTimer;
- (void)updateGreetingMessage;
@end
@implementation SlateHomeBoard
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (instancetype)initWithFrame:(NSRect)frame {
 self=[super initWithFrame:frame];
 if(self) {
  self.wantsLayer=YES;
  self.layerContentsRedrawPolicy=NSViewLayerContentsRedrawOnSetNeedsDisplay;
  _orbs=[NSMutableArray array];
  _greeting=[NSTextField labelWithString:@""];
  _greeting.drawsBackground=NO;
  _greeting.selectable=NO;
  NSFontDescriptor* serif=[[NSFont systemFontOfSize:40 weight:NSFontWeightLight].fontDescriptor
   fontDescriptorWithDesign:NSFontDescriptorSystemDesignSerif];
  _greeting.font=[NSFont fontWithDescriptor:serif size:40] ?: [NSFont systemFontOfSize:40 weight:NSFontWeightLight];
  _greeting.translatesAutoresizingMaskIntoConstraints=YES;
  [self addSubview:_greeting];
  _brandGroup=[[NSView alloc] initWithFrame:NSZeroRect];
  [self addSubview:_brandGroup];
  _brandGlyph=[[NSImageView alloc] initWithFrame:NSZeroRect];
  _brandGlyph.image=BrowserGlyphImage();
  _brandGlyph.imageScaling=NSImageScaleProportionallyUpOrDown;
  _brandGlyph.translatesAutoresizingMaskIntoConstraints=NO;
  _brandGlyph.accessibilityLabel=@"Slate";
  [_brandGroup addSubview:_brandGlyph];
  _omniboxCard=[[SlateOmniboxCard alloc] initWithDelegate:nil];
  _omniboxCard.translatesAutoresizingMaskIntoConstraints=NO;
  [_brandGroup addSubview:_omniboxCard];
  const CGFloat glyphWidth=52.0;
  NSSize glyphSize=_brandGlyph.image.size;
  const CGFloat glyphHeight=glyphSize.width>0 ? glyphWidth*glyphSize.height/glyphSize.width : 71.0;
  [NSLayoutConstraint activateConstraints:@[
   [_brandGlyph.centerXAnchor constraintEqualToAnchor:_brandGroup.centerXAnchor],
   [_brandGlyph.topAnchor constraintEqualToAnchor:_brandGroup.topAnchor],
   [_brandGlyph.widthAnchor constraintEqualToConstant:glyphWidth],
   [_brandGlyph.heightAnchor constraintEqualToConstant:glyphHeight],
   [_omniboxCard.centerXAnchor constraintEqualToAnchor:_brandGroup.centerXAnchor],
   [_omniboxCard.topAnchor constraintEqualToAnchor:_brandGlyph.bottomAnchor constant:26.0],
   [_omniboxCard.widthAnchor constraintEqualToAnchor:_brandGroup.widthAnchor],
   [_omniboxCard.heightAnchor constraintEqualToConstant:52.0],
   [_omniboxCard.bottomAnchor constraintEqualToAnchor:_brandGroup.bottomAnchor]
  ]];
  [self startGreetingTimer];
 }
 return self;
}
- (void)setWash:(NSColor*)wash {
 _wash=wash;
 self.brandGlyph.contentTintColor=wash;
}
- (void)dealloc {
 [self stopGreetingTimer];
}
- (void)startGreetingTimer {
 [self stopGreetingTimer];
 [self updateGreetingMessage];
 __weak typeof(self) weakSelf=self;
 _greetingTimer=[NSTimer scheduledTimerWithTimeInterval:30.0 repeats:YES block:^(NSTimer* timer) {
  [weakSelf updateGreetingMessage];
 }];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onClockChanged:) name:NSSystemClockDidChangeNotification object:nil];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onClockChanged:) name:NSCalendarDayChangedNotification object:nil];
}
- (void)stopGreetingTimer {
 if(_greetingTimer) { [_greetingTimer invalidate]; _greetingTimer=nil; }
 [[NSNotificationCenter defaultCenter] removeObserver:self name:NSSystemClockDidChangeNotification object:nil];
 [[NSNotificationCenter defaultCenter] removeObserver:self name:NSCalendarDayChangedNotification object:nil];
}
- (void)onClockChanged:(NSNotification*)note {
 [self updateGreetingMessage];
}
- (void)viewWillMoveToWindow:(NSWindow*)newWindow {
 [super viewWillMoveToWindow:newWindow];
 if(newWindow) [self startGreetingTimer];
 else [self stopGreetingTimer];
}
- (void)updateGreetingMessage {
  const auto* curTab=self.owner ? [self.owner selectedTab] : nullptr;
  const BOOL isIncog=curTab && curTab->incognito;
  if(isIncog) {
   self.greeting.stringValue=@"🕶 Untrackable Mode";
   self.greeting.hidden=NO;
   self.omniboxCard.placeholder=@"Search untrackably or enter address";
  } else {
   self.greeting.stringValue=@"";
   self.greeting.hidden=YES;
   self.omniboxCard.placeholder=@"Search or enter address";
  }
  self.greeting.textColor=self.owner.barInk ?: NSColor.labelColor;
  [self setNeedsLayout:YES];
  [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirty {
  CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] CGContext];
  if (!ctx) return;

  const CGFloat w = NSWidth(self.bounds);
  const CGFloat h = NSHeight(self.bounds);
  if (w <= 0 || h <= 0) return;

  // Accurately determine Light vs Dark mode based on explicit themeMode and appearance
  const BOOL isDark = (self.owner && self.owner.themeMode == 1) ? NO
    : ((self.owner && self.owner.themeMode == 2) ? YES
    : [[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua]);

  NSColor* accent = ChromeAccent(self.owner.accentId, self.owner.accentHex, isDark);
  NSColor* srgb = [accent colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: accent;
  CGFloat r = 0, g = 0, b = 0, a = 1;
  [srgb getRed:&r green:&g blue:&b alpha:&a];
  CGFloat hue = 0, sat = 0, bri = 0;
  [srgb getHue:&hue saturation:&sat brightness:&bri alpha:&a];

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

  // Base Canvas Vertical Background Gradient is provided seamlessly by root chromeGradientLayer across the entire window.

  // 2. Progressive Blurred Thermal Heat Map in bottom-right corner (Adaptive to Accent, Dimmed & Ultra-Blurred)
  const int bw = (int)ceil(w * 0.5);
  const int bh = (int)ceil(h * 0.5);
  if (bw > 10 && bh > 10) {
    CGContextRef bctx = CGBitmapContextCreate(NULL, bw, bh, 8, bw * 4, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (bctx) {
      const CGPoint hc = CGPointMake(bw * 0.90, bh * 0.82);
      const CGFloat sc = 0.5;

      auto WrapHue = [](CGFloat h_val) -> CGFloat {
        while (h_val < 0.0) h_val += 1.0;
        while (h_val >= 1.0) h_val -= 1.0;
        return h_val;
      };

      auto SetZoneColor = [&](CGFloat h_offset, CGFloat s_mult, CGFloat s_add, CGFloat b_val, CGFloat a_val) {
        CGFloat zh = WrapHue(hue + h_offset);
        CGFloat zs = MAX(0.12, MIN(1.0, sat * s_mult + s_add));
        NSColor* c = [NSColor colorWithHue:zh saturation:zs brightness:b_val alpha:a_val];
        NSColor* rgb = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: c;
        CGFloat zr = 0, zg = 0, zb = 0, za = 1;
        [rgb getRed:&zr green:&zg blue:&zb alpha:&za];
        CGContextSetRGBFillColor(bctx, zr, zg, zb, za);
      };

      if (!isDark) {
        // Light mode adaptive thermal heat zones (Dimmed, Muffled & Soft)
        // Zone 1: Broad atmospheric aura (flaring up-left)
        SetZoneColor(-0.070, 1.10, 0.15, 0.85, 0.48);
        CGContextFillEllipseInRect(bctx, CGRectMake(hc.x - 240 * sc, hc.y - 280 * sc, 460 * sc, 480 * sc));

        // Zone 2: Outer thermal plume (flaring up-left)
        SetZoneColor(-0.035, 1.15, 0.20, 0.94, 0.60);
        CGContextFillEllipseInRect(bctx, CGRectMake(hc.x - 200 * sc, hc.y - 210 * sc, 380 * sc, 390 * sc));

        // Zone 3: Solar body
        SetZoneColor(0.030, 1.05, 0.15, 0.98, 0.70);
        CGContextFillEllipseInRect(bctx, CGRectMake(hc.x - 150 * sc, hc.y - 150 * sc, 290 * sc, 290 * sc));

        // Zone 4: Vibrant warm transition
        SetZoneColor(0.075, 0.80, 0.22, 1.00, 0.78);
        CGContextFillEllipseInRect(bctx, CGRectMake(hc.x - 95 * sc, hc.y - 95 * sc, 180 * sc, 180 * sc));

        // Zone 5: Incandescent core nucleus
        SetZoneColor(0.110, 0.40, 0.15, 1.00, 0.82);
        CGContextFillEllipseInRect(bctx, CGRectMake(hc.x - 50 * sc, hc.y - 50 * sc, 95 * sc, 95 * sc));
      } else {
        // Dark mode adaptive thermal cosmic zones (Dimmed, Muffled & Soft)
        // Zone 1: Broad cosmic aura
        SetZoneColor(-0.070, 1.00, 0.10, 0.60, 0.40);
        CGContextFillEllipseInRect(bctx, CGRectMake(hc.x - 280 * sc, hc.y - 300 * sc, 520 * sc, 540 * sc));

        // Zone 2: Thermal plume
        SetZoneColor(-0.035, 1.10, 0.15, 0.80, 0.55);
        CGContextFillEllipseInRect(bctx, CGRectMake(hc.x - 210 * sc, hc.y - 220 * sc, 390 * sc, 410 * sc));

        // Zone 3: Solar body
        SetZoneColor(0.030, 1.05, 0.12, 0.90, 0.65);
        CGContextFillEllipseInRect(bctx, CGRectMake(hc.x - 150 * sc, hc.y - 150 * sc, 290 * sc, 290 * sc));

        // Zone 4: Warm transition
        SetZoneColor(0.075, 0.75, 0.18, 1.00, 0.72);
        CGContextFillEllipseInRect(bctx, CGRectMake(hc.x - 95 * sc, hc.y - 95 * sc, 180 * sc, 180 * sc));

        // Zone 5: Incandescent core
        SetZoneColor(0.110, 0.35, 0.12, 1.00, 0.80);
        CGContextFillEllipseInRect(bctx, CGRectMake(hc.x - 50 * sc, hc.y - 50 * sc, 95 * sc, 95 * sc));
      }

      CGImageRef rawImg = CGBitmapContextCreateImage(bctx);
      CGContextRelease(bctx);

      if (rawImg) {
        CIImage* ciInput = [CIImage imageWithCGImage:rawImg];
        CIFilter* filter = [CIFilter filterWithName:@"CIGaussianBlur"];
        [filter setValue:ciInput forKey:kCIInputImageKey];
        [filter setValue:@(55.0) forKey:kCIInputRadiusKey]; // 55.0 in 0.5x context = 110px blur radius
        CIImage* ciOutput = [filter valueForKey:kCIOutputImageKey];
        static CIContext* s_ciContext = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          s_ciContext = [CIContext contextWithOptions:nil];
        });
        CGRect cropRect = CGRectMake(0, 0, bw, bh);
        CGImageRef blurredImg = [s_ciContext createCGImage:ciOutput fromRect:cropRect];
        if (blurredImg) {
          NSImage* img = [[NSImage alloc] initWithCGImage:blurredImg size:self.bounds.size];
          [img drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.92];
          CGImageRelease(blurredImg);
        }
        CGImageRelease(rawImg);
      }
    }
  }

  CGColorSpaceRelease(colorSpace);
}
- (void)layout {
  [super layout];
  const CGFloat w=NSWidth(self.bounds);
  const CGFloat visibleHeight=(self.enclosingScrollView && self.enclosingScrollView.contentView.bounds.size.height > 10)
   ? self.enclosingScrollView.contentView.bounds.size.height
   : NSHeight(self.bounds);

  const CGFloat cardW=MIN(680.0, MAX(280.0, w-32.0));
  const NSSize glyphSize=self.brandGlyph.image.size;
  const CGFloat glyphHeight=glyphSize.width>0 ? 52.0*glyphSize.height/glyphSize.width : 64.0;
  const CGFloat groupH=glyphHeight+26.0+52.0;
  const CGFloat maxY=MAX(48.0, visibleHeight-groupH-32.0);
  const CGFloat groupY=MIN(maxY, MAX(48.0, round(visibleHeight*0.35-groupH/2.0)));
  self.brandGroup.frame=NSMakeRect((w-cardW)/2.0,groupY,cardW,groupH);
  [self.brandGroup layoutSubtreeIfNeeded];
  [self.omniboxCard layoutSubtreeIfNeeded];
  if(self.greeting && !self.greeting.hidden && self.greeting.stringValue.length>0) {
   [self.greeting sizeToFit];
   NSRect greet=self.greeting.frame;
   greet.origin.x=round((w-NSWidth(greet))/2.0);
   greet.origin.y=MAX(8.0, groupY-NSHeight(greet)-16.0);
   self.greeting.frame=greet;
  }
}
@end
@interface SlateStageView : NSView
@property(weak) SlateDelegate* owner;
@end
@implementation SlateStageView
- (void)layout {
 [super layout];
 if(self.owner && self.owner.homePlateGradientLayer && !self.owner.homePlateGradientLayer.hidden) {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.owner.homePlateGradientLayer.frame = self.bounds;
  [CATransaction commit];
 }
}
@end
// A tab-layout switch resizes the clip view without resizing the window.
// Keep the start page centered in the available page area in both orientations.
@interface SlateHomeScroll : NSScrollView
@end
@implementation SlateHomeScroll
- (void)layout {
 [super layout];
 SlateHomeBoard* board=(SlateHomeBoard*)self.documentView;
 if(![board isKindOfClass:SlateHomeBoard.class]) return;
 const NSSize available=self.contentView.bounds.size;
 const NSRect frame=NSMakeRect(0,0,MAX(1,available.width),MAX(available.height, 400));
 if(!NSEqualRects(board.frame,frame)) {
  board.frame=frame;
 }
 [board setNeedsLayout:YES];
 [board layoutSubtreeIfNeeded];
 [board setNeedsDisplay:YES];
}
@end
@interface SlateApplication : NSApplication
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation SlateApplication
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent*)event {
 SlateDelegate* delegate=(SlateDelegate*)self.delegate;
 if([delegate detachedTabForWindow:event.window]) {
  if(event.type==NSEventTypeKeyDown && [delegate handleDetachedKeyEvent:event]) return;
  [super sendEvent:event];
  return;
 }
 if(event.type==NSEventTypeKeyDown) {
  NSEventModifierFlags flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
  id responder = [event.window firstResponder];
  BOOL isEditingText = [responder isKindOfClass:[NSTextView class]] || [responder isKindOfClass:[NSTextField class]];

  // Back & Forward keyboard shortcuts: Command + Left/Right Arrow
  if(!isEditingText && (flags & NSEventModifierFlagCommand) && !(flags & (NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift))) {
   if(event.keyCode == 123) { // Left arrow
    [delegate goBack:nil];
    return;
   }
   if(event.keyCode == 124) { // Right arrow
    [delegate goForward:nil];
    return;
   }
  }

  // Next & Previous Tab: Control + Tab and Control + Shift + Tab
  if((flags & NSEventModifierFlagControl) && event.keyCode == 48) { // 48 = Tab
   if(flags & NSEventModifierFlagShift) {
    [delegate selectPreviousTab:nil];
   } else {
    [delegate selectNextTab:nil];
   }
   return;
  }

  // Escape to dismiss find bar
  if(event.keyCode == 53 && delegate.findBar && delegate.findBar.isVisible) {
   [delegate.findBar hideAnimated];
   return;
  }

  // Control + 1..9 for Spaces switching
  if((flags & NSEventModifierFlagControl) && !(flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift))) {
   NSString* chars = event.charactersIgnoringModifiers;
   if(chars.length == 1) {
    unichar ch = [chars characterAtIndex:0];
    if(ch >= '1' && ch <= '9') {
     [delegate switchSpaceAtIndex:(ch - '1')];
     return;
    }
   }
  }

  // Intercept key equivalents before CEF absorbs them:
  if(flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) {
   BOOL isBasicEdit = (event.keyCode == 0 || event.keyCode == 6 || event.keyCode == 7 || event.keyCode == 8 || event.keyCode == 9); // a, z, x, c, v
   if(!isEditingText || !isBasicEdit) {
    if([NSApp.mainMenu performKeyEquivalent:event]) {
     return;
    }
   }
  }
 }
 if(event.type==NSEventTypeLeftMouseDown || event.type==NSEventTypeRightMouseDown)
  [delegate dismissOmniboxIfClickOutside:event];
 if((event.type==NSEventTypeLeftMouseDown || event.type==NSEventTypeRightMouseDown) &&
    [delegate routeChromeClick:event]) {
  [delegate observePageEvent:event];
  return;
 }
 [delegate observePageEvent:event];
 [super sendEvent:event];
}
- (void)terminate:(id)sender { [(SlateDelegate*)self.delegate requestClose]; }
@end

@class SlateDetachedTabWindow;
@interface SlateDetachedTabPill : SlateTabPill
@property(weak) SlateDetachedTabWindow* controller;
@end
@interface SlateDetachedTabWindow : NSObject <NSWindowDelegate, SlateOmniboxDelegate>
@property(weak) SlateDelegate* owner;
@property TabId tabId;
@property(strong) NSWindow* window;
@property(strong) NSView* titlebar;
@property(strong) NSView* toolbar;
@property(strong) NSView* bookmarksBar;
@property(strong) NSView* pageContainer;
@property(strong) SlateHomeScroll* homeView;
@property(strong) SlateHomeBoard* homeBoard;
@property(strong) SlateDetachedTabPill* tabPill;
@property(strong) SlateOmnibox* omnibox;
@property(strong) SlateAddressField* address;
@property(strong) SlateNavButton* backButton;
@property(strong) SlateNavButton* forwardButton;
@property(strong) SlateNavButton* reloadButton;
@property(strong) NSButton* securityButton;
@property(strong) NSButton* bookmarkButton;
@property(strong) NSButton* shieldsButton;
@property(strong) NSButton* downloadButton;
- (instancetype)initWithOwner:(SlateDelegate*)owner tab:(TabId)tabId atScreenPoint:(NSPoint)point;
- (void)refresh;
- (void)showNewTabPage;
- (void)dismissWithoutClosingTab;
@end
@implementation SlateDetachedTabPill
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)mouseDown:(NSEvent*)event {
 SlateDetachedTabWindow* controller=self.controller;
 if(!controller) return;
 const NSPoint start=[controller.window convertPointToScreen:event.locationInWindow];
 [controller.window performWindowDragWithEvent:event];
 const NSPoint end=NSEvent.mouseLocation;
 if(hypot(end.x-start.x,end.y-start.y)>6)
  [controller.owner reattachTab:controller.tabId atScreenPoint:end];
}
@end
@implementation SlateDetachedTabWindow
- (SlateNavButton*)navigationButton:(NSString*)symbol description:(NSString*)description
                                  frame:(NSRect)frame action:(SEL)action {
 SlateNavButton* button=[[SlateNavButton alloc] initWithFrame:frame];
 button.image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:description];
 button.bordered=NO;
 button.imagePosition=NSImageOnly;
 button.target=self;
 button.action=action;
 button.wantsLayer=YES;
 button.layer.cornerRadius=8;
 [self.toolbar addSubview:button];
 return button;
}
- (NSButton*)toolbarButton:(NSString*)symbol description:(NSString*)description
                          frame:(NSRect)frame action:(SEL)action {
 NSButton* button=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:description]
                                     target:self action:action];
 button.frame=frame;
 button.bordered=NO;
 button.imagePosition=NSImageOnly;
 button.toolTip=description;
 [self.toolbar addSubview:button];
 return button;
}
- (void)layoutChrome {
 const CGFloat width=NSWidth(self.toolbar.bounds);
 const CGFloat omniboxWidth=MIN(1100,MAX(180,MIN(width*0.64,width-330)));
 self.omnibox.frame=NSMakeRect((width-omniboxWidth)/2,7,omniboxWidth,kOmniboxHeight);
 self.securityButton.frame=NSMakeRect(13,9,16,18);
 self.address.frame=NSMakeRect(38,4,omniboxWidth-50,30);
 self.bookmarkButton.frame=NSMakeRect(width-112,14,22,22);
 self.shieldsButton.frame=NSMakeRect(width-80,14,22,22);
 self.downloadButton.frame=NSMakeRect(width-48,14,22,22);
 self.bookmarksBar.hidden=!self.owner.showBookmarksBar;
 const CGFloat bookmarksHeight=self.owner.showBookmarksBar ? kBookmarksBarHeight : 0;
 self.bookmarksBar.frame=NSMakeRect(0,NSMinY(self.toolbar.frame)-bookmarksHeight,width,bookmarksHeight);
 self.pageContainer.frame=NSMakeRect(0,0,width,NSMinY(self.bookmarksBar.frame));
}
- (instancetype)initWithOwner:(SlateDelegate*)owner tab:(TabId)tabId atScreenPoint:(NSPoint)point {
 if(!(self=[super init])) return nil;
 self.owner=owner;
 self.tabId=tabId;
 const NSSize size=NSMakeSize(1000,700);
 NSScreen* screen=owner.window.screen ?: NSScreen.mainScreen;
 const NSRect visible=screen.visibleFrame;
 const CGFloat x=MIN(MAX(NSMinX(visible),point.x-220),MAX(NSMinX(visible),NSMaxX(visible)-size.width));
 const CGFloat y=MIN(MAX(NSMinY(visible),point.y-size.height+48),MAX(NSMinY(visible),NSMaxY(visible)-size.height));
 self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(x,y,size.width,size.height)
  styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|
            NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView
  backing:NSBackingStoreBuffered defer:NO];
 self.window.title=@"Slate";
 self.window.titleVisibility=NSWindowTitleHidden;
 self.window.titlebarAppearsTransparent=YES;
 self.window.titlebarSeparatorStyle=NSTitlebarSeparatorStyleNone;
 self.window.tabbingMode=NSWindowTabbingModeDisallowed;
 self.window.releasedWhenClosed=NO;
 self.window.minSize=NSMakeSize(600,400);
 self.window.delegate=self;
 NSView* root=self.window.contentView;
 root.wantsLayer=YES;
 self.titlebar=[[SlateDragRegion alloc] initWithFrame:NSMakeRect(0,size.height-kTitlebarHeight,size.width,kTitlebarHeight)];
 self.titlebar.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;
 self.titlebar.wantsLayer=YES;
 [root addSubview:self.titlebar];
 self.toolbar=[[SlateDragRegion alloc] initWithFrame:NSMakeRect(0,size.height-kTitlebarHeight-kToolbarHeight,size.width,kToolbarHeight)];
 self.toolbar.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;
 self.toolbar.wantsLayer=YES;
 [root addSubview:self.toolbar];
 const CGFloat bookmarksHeight=owner.showBookmarksBar ? kBookmarksBarHeight : 0;
 self.bookmarksBar=[[NSView alloc] initWithFrame:NSMakeRect(0,size.height-kTitlebarHeight-kToolbarHeight-bookmarksHeight,size.width,bookmarksHeight)];
 self.bookmarksBar.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;
 self.bookmarksBar.wantsLayer=YES;
 self.bookmarksBar.hidden=!owner.showBookmarksBar;
 [root addSubview:self.bookmarksBar];
 self.pageContainer=[[NSView alloc] initWithFrame:NSMakeRect(0,0,size.width,size.height-kTitlebarHeight-kToolbarHeight-bookmarksHeight)];
 self.pageContainer.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
 self.pageContainer.wantsLayer=YES;
 [root addSubview:self.pageContainer];
 self.tabPill=[[SlateDetachedTabPill alloc] initWithFrame:NSMakeRect(100,0,180,kTabHeight)];
 self.tabPill.controller=self;
 self.tabPill.tabId=tabId;
 self.tabPill.target=owner;
 self.tabPill.bordered=NO;
 self.tabPill.wantsLayer=YES;
 self.tabPill.toolTip=@"Drag this tab into another Slate tab bar";
 self.tabPill.accessibilityLabel=@"Detached browser tab";
 [self.titlebar addSubview:self.tabPill];
 self.backButton=[self navigationButton:@"chevron.left" description:@"Back"
                                     frame:NSMakeRect(46,10,30,30) action:@selector(goBack:)];
 self.forwardButton=[self navigationButton:@"chevron.right" description:@"Forward"
                                        frame:NSMakeRect(80,10,30,30) action:@selector(goForward:)];
 self.reloadButton=[self navigationButton:@"arrow.clockwise" description:@"Reload"
                                       frame:NSMakeRect(114,10,30,30) action:@selector(reload:)];
 [self navigationButton:@"sidebar.left" description:@"Show tabs"
                  frame:NSMakeRect(12,10,30,30) action:@selector(showMainTabs:)];
 self.omnibox=[[SlateOmnibox alloc] initWithFrame:NSZeroRect];
 [self.toolbar addSubview:self.omnibox];
 self.securityButton=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"lock.fill" accessibilityDescription:@"Secure Connection"]
                                             target:self action:@selector(showSiteInformation:)];
 self.securityButton.bordered=NO;
 [self.omnibox addSubview:self.securityButton];
 self.address=[[SlateAddressField alloc] initWithFrame:NSZeroRect];
 self.address.font=[NSFont systemFontOfSize:14];
 self.address.bezeled=NO;
 self.address.bordered=NO;
 self.address.drawsBackground=NO;
 self.address.focusRingType=NSFocusRingTypeNone;
 self.address.placeholderString=@"Search Google or enter address";
 self.address.accessibilityLabel=@"Website address";
 self.address.target=self;
 self.address.action=@selector(navigate:);
 [self.omnibox addSubview:self.address];
 self.bookmarkButton=[self toolbarButton:@"star" description:@"Bookmark"
                                  frame:NSZeroRect action:@selector(toggleBookmark:)];
 self.shieldsButton=[self toolbarButton:@"checkmark.shield" description:@"Slate Shields"
                                 frame:NSZeroRect action:@selector(showShields:)];
 self.downloadButton=[self toolbarButton:@"arrow.down" description:@"Downloads"
                                  frame:NSZeroRect action:@selector(showDownloads:)];
 [self rebuildBookmarksBar];
 [self layoutChrome];
 [self refresh];
 [self.window makeKeyAndOrderFront:nil];
 return self;
}
- (void)refresh {
 const auto* tab=model.find(self.tabId);
 if(!tab) return;
 [self layoutChrome];
 self.tabPill.image=[self.owner iconForTab:*tab];
 [self.tabPill applySelected:YES filled:YES hovered:NO title:TabLabel(*tab) incognito:tab->incognito];
 self.tabPill.frame=NSMakeRect(100,0,TabFillWidth(TabLabel(*tab)),kTabHeight);
 if(self.address.currentEditor==nil) self.address.stringValue=tab->url=="about:blank" ? @"" : Text(tab->url);
 self.backButton.enabled=runtimes.contains(self.tabId) && runtimes.at(self.tabId).back;
 self.forwardButton.enabled=runtimes.contains(self.tabId) && runtimes.at(self.tabId).forward;
 NSColor* chrome=self.owner.barColor ?: NSColor.windowBackgroundColor;
 self.toolbar.layer.backgroundColor=chrome.CGColor;
 self.bookmarksBar.layer.backgroundColor=chrome.CGColor;
 self.titlebar.layer.backgroundColor=(self.owner.window.backgroundColor ?: chrome).CGColor;
 self.window.backgroundColor=self.owner.window.backgroundColor ?: chrome;
 self.omnibox.barColor=chrome;
 [self.omnibox applyContrast];
 if(self.homeBoard) {
  self.homeBoard.wash=chrome;
  self.homeBoard.omniboxCard.accentColor=chrome;
  self.homeBoard.omniboxCard.inkColor=self.owner.barInk;
  [self.homeBoard.omniboxCard applyTheme];
  [self.homeBoard setNeedsDisplay:YES];
 }
 NSColor* ink=self.owner.barInk ?: NSColor.labelColor;
 self.address.textColor=ink;
 self.securityButton.contentTintColor=ink;
 self.bookmarkButton.contentTintColor=ink;
 self.shieldsButton.contentTintColor=ink;
 self.downloadButton.contentTintColor=ink;
 self.backButton.hoverInk=ink;
 self.forwardButton.hoverInk=ink;
 self.reloadButton.hoverInk=ink;
 self.backButton.contentTintColor=ink;
 self.forwardButton.contentTintColor=ink;
 self.reloadButton.contentTintColor=ink;
 self.securityButton.hidden=tab->url.rfind("https:",0)!=0;
 const BOOL saved=[[SlateBookmarks sharedStore] containsURL:Text(tab->url)];
 self.bookmarkButton.image=[NSImage imageWithSystemSymbolName:saved ? @"star.fill" : @"star" accessibilityDescription:@"Bookmark"];
 self.bookmarkButton.enabled=tab->url.rfind("http",0)==0;
 const auto host=slate::host_from_url(tab->url);
 const BOOL blocking=slate::WebKitShields::Shared().IsEnabled() &&
  (host.empty() || slate::WebKitShields::Shared().IsSiteEnabled(host));
 self.shieldsButton.image=[NSImage imageWithSystemSymbolName:blocking ? @"checkmark.shield" : @"shield.slash"
                                    accessibilityDescription:@"Slate Shields"];
 for(NSView* view in self.bookmarksBar.subviews)
  if([view isKindOfClass:NSButton.class]) ((NSButton*)view).contentTintColor=ink;
}
- (void)goBack:(id)sender { auto it=runtimes.find(self.tabId); if(it!=runtimes.end() && it->second.engine) it->second.engine->back(); }
- (void)goForward:(id)sender { auto it=runtimes.find(self.tabId); if(it!=runtimes.end() && it->second.engine) it->second.engine->forward(); }
- (void)reload:(id)sender { auto it=runtimes.find(self.tabId); if(it!=runtimes.end() && it->second.engine) it->second.engine->reload(); }
- (void)navigate:(id)sender {
 NSString* text=[self.address.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(!text.length) return;
 const auto target=slate::resolve_address_bar(text.UTF8String ?: "");
 [self.owner navigateDetachedTab:self.tabId toURL:target.url];
 [self.window makeFirstResponder:self.pageContainer];
}
- (void)showMainTabs:(id)sender { [self.owner.window makeKeyAndOrderFront:nil]; }
- (void)rebuildBookmarksBar {
 for(NSView* view in [self.bookmarksBar.subviews copy]) [view removeFromSuperview];
 CGFloat x=16;
 const CGFloat maxWidth=NSWidth(self.bookmarksBar.bounds)-16;
 for(SlateBookmark* node in [SlateBookmarks sharedStore].roots) {
  if(x>=maxWidth) break;
  NSString* title=node.title.length ? node.title : (node.url ?: @"Untitled");
  if(title.length>24) title=[[title substringToIndex:22] stringByAppendingString:@"…"];
  SlateBookmarkButton* button=[SlateBookmarkButton buttonWithTitle:title target:self action:@selector(openBookmark:)];
  button.node=node;
  button.bookmarkId=node.identifier;
  button.urlString=node.url ?: @"";
  button.owner=self.owner;
  button.bordered=NO;
  button.bezelStyle=NSBezelStyleInline;
  button.imagePosition=NSImageLeading;
  button.image=[NSImage imageWithSystemSymbolName:node.isFolder ? @"folder" : @"globe"
                             accessibilityDescription:node.isFolder ? @"Folder" : @"Bookmark"];
  button.font=[NSFont systemFontOfSize:12];
  button.contentTintColor=self.owner.barInk ?: NSColor.labelColor;
  [button sizeToFit];
  const CGFloat width=MIN(NSWidth(button.frame)+18,maxWidth-x);
  button.frame=NSMakeRect(x,3,width,24);
  [self.bookmarksBar addSubview:button];
  x+=width+10;
 }
}
- (void)openBookmark:(SlateBookmarkButton*)button {
 if(button.node.isFolder) { [SlateBookmarkMenu popUpFolder:button.node forView:button owner:self.owner]; return; }
 NSString* url=button.urlString;
 if(url.length) [self.owner navigateDetachedTab:self.tabId toURL:slate::resolve_address_bar(url.UTF8String).url];
}
- (void)showNewTabPage {
 if(self.homeView) return;
 self.homeView=[[SlateHomeScroll alloc] initWithFrame:self.pageContainer.bounds];
 self.homeView.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
 self.homeView.drawsBackground=NO;
 self.homeView.hasVerticalScroller=YES;
 self.homeBoard=[[SlateHomeBoard alloc] initWithFrame:self.homeView.bounds];
 self.homeBoard.owner=self.owner;
 self.homeBoard.wash=self.owner.barColor;
 self.homeBoard.omniboxCard.accentColor=self.owner.barColor;
 self.homeBoard.omniboxCard.inkColor=self.owner.barInk;
 self.homeBoard.omniboxCard.delegate=self;
 [self.homeBoard.omniboxCard applyTheme];
 self.homeView.documentView=self.homeBoard;
 [self.pageContainer addSubview:self.homeView];
}
- (void)showSuggestionsForCard:(SlateOmniboxCard*)card query:(NSString*)query { (void)card; (void)query; }
- (void)moveSuggestionDelta:(NSInteger)delta { (void)delta; }
- (void)hideSuggestions {}
- (void)submitOmniboxCard:(SlateOmniboxCard*)card {
 NSString* value=[card.field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(!value.length) { [card shake]; return; }
 const auto target=slate::resolve_address_bar(value.UTF8String ?: "");
 [self.owner navigateDetachedTab:self.tabId toURL:target.url];
}
- (void)showSiteInformation:(id)sender {
 (void)sender;
 const auto* tab=model.find(self.tabId);
 if(!tab || tab->url.empty() || tab->url=="about:blank") return;
 WKWebView* webView=nil;
 auto runtime=runtimes.find(self.tabId);
 if(runtime!=runtimes.end()) for(NSView* view in runtime->second.host.subviews)
  if([view isKindOfClass:WKWebView.class]) { webView=(WKWebView*)view; break; }
 [[SlateSiteCardPanel sharedPanel] updateWithURL:[NSURL URLWithString:Text(tab->url)]
                                          trust:webView ? webView.serverTrust : NULL
                                  secureContent:webView ? webView.hasOnlySecureContent : YES
                                           zoom:self.owner.zoomPercent];
 [SlateSiteCardPanel sharedPanel].owner=self.owner;
 [[SlateSiteCardPanel sharedPanel] toggleForAnchor:self.securityButton inWindow:self.window];
}
- (void)toggleBookmark:(id)sender {
 (void)sender;
 const auto* tab=model.find(self.tabId);
 if(!tab || tab->url.rfind("http",0)!=0) return;
 SlateBookmarks* store=[SlateBookmarks sharedStore];
 NSString* url=Text(tab->url);
 SlateBookmark* existing=[store findURL:url];
 if(existing) [store removeWithIdentifier:existing.identifier];
 else [store addURL:url title:TabLabel(*tab)];
 [self refresh];
 [self.owner rebuildBookmarksBar];
 [self.owner rebuildBookmarksMenu];
 [self.owner scheduleSave];
}
- (void)showShields:(id)sender { (void)sender; [self.owner showShields:self.shieldsButton]; }
- (void)showDownloads:(id)sender {
 (void)sender;
 [[SlateDownloadsPanel sharedPanel] toggleForButton:self.downloadButton inWindow:self.window];
}
- (BOOL)windowShouldClose:(NSWindow*)sender { [self.owner closeTabWithId:self.tabId]; return NO; }
- (void)windowDidResize:(NSNotification*)notification {
 [self layoutChrome];
 auto it=runtimes.find(self.tabId);
 if(it!=runtimes.end() && it->second.engine) it->second.engine->host_geometry_changed();
}
- (void)windowDidBecomeKey:(NSNotification*)notification {
 auto it=runtimes.find(self.tabId);
 if(it!=runtimes.end() && it->second.engine) { it->second.engine->set_occluded(NO); it->second.engine->focus(); }
}
- (void)windowDidChangeOcclusionState:(NSNotification*)notification { [self.owner syncBrowserOcclusion]; }
- (void)windowDidMiniaturize:(NSNotification*)notification { [self.owner syncBrowserOcclusion]; }
- (void)windowDidDeminiaturize:(NSNotification*)notification { [self.owner syncBrowserOcclusion]; }
- (void)dismissWithoutClosingTab {
 self.window.delegate=nil;
 [self.window close];
 self.window=nil;
}
@end

@implementation SlateDelegate
- (instancetype)init {
 if(self = [super init]) {
  self.spacesManager = [SlateSpacesManager sharedManager];
  self.tabIcons = [NSMutableDictionary dictionary];
  self.detachedTabs=[NSMutableDictionary dictionary];
 }
 return self;
}
- (NSButton*)button:(NSString*)title action:(SEL)action {
 NSButton* button=[NSButton buttonWithTitle:title target:self action:action];
 button.bezelStyle=NSBezelStyleRounded; button.font=[NSFont systemFontOfSize:11];
 return button;
}
- (NSImage*)navSymbol:(NSString*)name fallback:(NSString*)fallback label:(NSString*)label {
 NSImage* image=[NSImage imageWithSystemSymbolName:name accessibilityDescription:label]
  ?: [NSImage imageWithSystemSymbolName:fallback accessibilityDescription:label];
 NSImageSymbolConfiguration* config=[NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium];
 return [image imageWithSymbolConfiguration:config] ?: image;
}
- (SlateNavButton*)navButton:(NSString*)symbol fallback:(NSString*)fallback label:(NSString*)label
                     action:(SEL)action motion:(SlateNavMotion)motion {
 SlateNavButton* button=[[SlateNavButton alloc] initWithFrame:NSZeroRect];
 button.target=self; button.action=action; button.navMotion=motion;
 button.bezelStyle=NSBezelStyleInline; button.bordered=NO; button.imagePosition=NSImageOnly;
 button.translatesAutoresizingMaskIntoConstraints=NO; button.toolTip=label;
 button.refusesFirstResponder=YES; button.keyEquivalent=@"";
 button.wantsLayer=YES; button.layer.cornerRadius=7; button.layer.masksToBounds=YES;
 button.glyph=[[NSImageView alloc] initWithFrame:NSZeroRect];
 button.glyph.image=[self navSymbol:symbol fallback:fallback label:label];
 button.glyph.imageScaling=NSImageScaleProportionallyDown;
 button.glyph.contentTintColor=NSColor.labelColor;
 button.glyph.wantsLayer=YES;
 button.glyph.translatesAutoresizingMaskIntoConstraints=NO;
 [button addSubview:button.glyph];
 [NSLayoutConstraint activateConstraints:@[
  [button.widthAnchor constraintEqualToConstant:28],
  [button.heightAnchor constraintEqualToConstant:28],
  [button.glyph.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
  [button.glyph.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
  [button.glyph.widthAnchor constraintEqualToConstant:14],
  [button.glyph.heightAnchor constraintEqualToConstant:14]
 ]];
 return button;
}
- (NSTextField*)label:(NSString*)value size:(CGFloat)size color:(NSColor*)color {
 NSTextField* field=[NSTextField labelWithString:value];
 field.font=[NSFont systemFontOfSize:size]; field.textColor=color;
 field.drawsBackground=NO; return field;
}
- (std::vector<TabId>)orderedIds {
 std::vector<TabId> pinned, grouped, rest;
 std::set<TabId> seen;
 for(const auto& tab:model.tabs()) if(tab.pinned && !self.detachedTabs[@(tab.id)]) { pinned.push_back(tab.id); seen.insert(tab.id); }
 for(const auto& group:model.groups())
  for(const auto& tab:model.tabs()) if(!self.detachedTabs[@(tab.id)] && !seen.contains(tab.id) && tab.group_id==group.id) {
   grouped.push_back(tab.id); seen.insert(tab.id);
  }
 for(const auto& tab:model.tabs()) if(!self.detachedTabs[@(tab.id)] && !seen.contains(tab.id)) rest.push_back(tab.id);
 pinned.insert(pinned.end(),grouped.begin(),grouped.end());
 pinned.insert(pinned.end(),rest.begin(),rest.end());
 return pinned;
}
- (std::vector<SideRow>)buildSidebarRows {
 std::vector<SideRow> rows;
 const BOOL rail=[self sidebarIconRail];
 std::set<TabId> placed;
 for(TabId id:[self orderedIds]) {
  const auto* tab=model.find(id);
  if(tab && tab->pinned) { placed.insert(id); }
 }
 for(const auto& group:model.groups()) {
  if(!rail) rows.push_back({SideRow::Kind::Group,0,group.id});
  if(group.collapsed && !rail) {
   for(const auto& tab:model.tabs()) if(tab.group_id==group.id) placed.insert(tab.id);
   continue;
  }
  for(const auto& tab:model.tabs()) if(!self.detachedTabs[@(tab.id)] && !placed.contains(tab.id) && tab.group_id==group.id) {
   rows.push_back({SideRow::Kind::Tab,tab.id,{}});
   placed.insert(tab.id);
  }
 }
 for(TabId id:[self orderedIds]) if(!placed.contains(id)) rows.push_back({SideRow::Kind::Tab,id,{}});
 rows.push_back({SideRow::Kind::NewTab,0,{}});
 return rows;
}
- (const std::vector<SideRow>&)sidebarRows {
 static std::vector<SideRow> cache;
 static NSUInteger built=~0u;
 if(built!=self.sideRowsGen) {
  built=self.sideRowsGen;
  cache=[self buildSidebarRows];
 }
 return cache;
}
- (void)pinEdges:(NSView*)view to:(NSView*)parent top:(CGFloat)top {
 view.translatesAutoresizingMaskIntoConstraints=NO;
 [NSLayoutConstraint activateConstraints:@[
  [view.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
  [view.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor],
  [view.topAnchor constraintEqualToAnchor:parent.topAnchor constant:top],
  [view.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor]
 ]];
}
- (BOOL)sidebarRevealed {
 return self.verticalTabs && (!self.tabsCollapsed || self.sidebarPeeking);
}
- (BOOL)sidebarIconRail {
 return [self sidebarRevealed] && [self sidebarLayoutWidth] < kSidebarLabelWidth;
}
- (BOOL)stripRevealed {
 return !self.verticalTabs && !self.tabsCollapsed;
}
- (CGFloat)sidebarLayoutWidth {
 if(![self sidebarRevealed]) return 0;
 CGFloat width=ClampSidebarWidth(self.sidebarUserWidth, self.window.frame.size.width);
 // The native traffic lights can require more room than the minimum icon rail.
 // Give that protected titlebar space to the rail instead of leaving a dead gap.
 if(width<kSidebarLabelWidth && self.plateFromTraffic.constant>0)
  width=MAX(width,self.plateFromTraffic.constant-kPlateInset);
 return width;
}
- (BOOL)isDarkAppearance {
 const BOOL systemDark=[[self.window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
 return (self.themeMode==1) ? NO : ((self.themeMode==2) ? YES : systemDark);
}
- (void)createWindow {
 InstallThemeFrameSwizzle();
 self.sessionWritable=YES;
 session=slate::make_session_store([DataDirectory() stringByAppendingPathComponent:@"session.json"].UTF8String);
 NSString* loadError=nil;
 try { model=slate::TabModel(session->load(), session->last_groups()); }
 catch(const std::exception&) { self.sessionWritable=NO; loadError=@"The saved session could not be read. The original file is preserved; this window will not overwrite it."; }
 if(model.tabs().empty()) model.add("about:blank");
 try { bookmarks=slate::load_bookmarks(BookmarksPath().UTF8String); }
 catch(const std::exception&) { bookmarks=std::make_unique<slate::BookmarkList>(); }
 UiPrefs prefs=LoadUiPrefs();
 self.verticalTabs=prefs.vertical;
 self.tabsCollapsed=prefs.collapsed;
 self.zoomPercent=prefs.zoomPercent;
 self.sidebarUserWidth=ClampSidebarWidth(prefs.sidebarWidth, 1200);
 self.accentId=prefs.accent.length ? prefs.accent : @"rose";
 self.accentHex=prefs.accentHex ?: @"";
 self.accentHex2=prefs.accentHex2 ?: @"";
 self.recentlyClosedUrls=[NSMutableArray array];
 self.graniteIntensity=prefs.graniteIntensity;
 self.themeMode=prefs.themeMode;
 self.pages120Hz=prefs.pages120Hz;
 self.tabStyle=prefs.tabStyle;
 auto savedPairs=prefs.splitGroups;
 if(savedPairs.empty() && prefs.splitLeft && prefs.splitRight && prefs.splitLeft!=prefs.splitRight)
  savedPairs.push_back({prefs.splitLeft,prefs.splitRight,prefs.splitRatio,
   prefs.splitRightActive ? slate::SplitSide::Right : slate::SplitSide::Left});
 for(const auto& pair:savedPairs) if(model.find(pair.left) && model.find(pair.right)) {
  workspace.open(pair.left,pair.right,slate::SplitSide::Right);
  workspace.ratio=pair.ratio;
  workspace.active=pair.active;
 }
 workspace.select(model.selected());
 [SlateFrameRate setFast:self.pages120Hz];
 self.floatingTabId=0;
 self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1200,800)
  styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|
            NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView
  backing:NSBackingStoreBuffered defer:NO];
 self.window.title=@"Slate"; self.window.delegate=self; self.window.releasedWhenClosed=NO;
 self.window.minSize=NSMakeSize(480,360); self.window.titlebarAppearsTransparent=YES;
 self.window.titleVisibility=NSWindowTitleHidden; self.window.tabbingMode=NSWindowTabbingModeDisallowed;
 self.window.titlebarSeparatorStyle=NSTitlebarSeparatorStyleNone;
 self.window.backgroundColor=NSColor.windowBackgroundColor;
 [self.window setFrameAutosaveName:@"SlateMainWindow"];
 [self.window center];
 self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorFullScreenAllowsTiling;
 self.window.defaultButtonCell=nil;
 NSView* root=self.window.contentView;
 root.wantsLayer=YES;
 // Keep AppKit in charge of the content view's window-sized frame.
 root.translatesAutoresizingMaskIntoConstraints=YES;
 root.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
 [NSDistributedNotificationCenter.defaultCenter addObserver:self
  selector:@selector(systemAppearanceDidChange:)
  name:@"AppleInterfaceThemeChangedNotification"
  object:nil];
 [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:NSKeyValueObservingOptionNew context:nil];
 [NSNotificationCenter.defaultCenter addObserver:self
  selector:@selector(onBookmarksChangedNotification:)
  name:SlateBookmarksChangedNotification
  object:nil];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appDidResignActive:)
  name:NSApplicationDidResignActiveNotification object:NSApp];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appDidBecomeActive:)
  name:NSApplicationDidBecomeActiveNotification object:NSApp];
 self.tabIcons=[NSMutableDictionary dictionary];
 self.titlebar=[[SlateDragRegion alloc] initWithFrame:NSZeroRect];
 self.titlebar.translatesAutoresizingMaskIntoConstraints=NO;
 self.titlebar.wantsLayer=YES;
 self.titlebar.clipsToBounds=NO;
 self.titlebarHeight=[self.titlebar.heightAnchor constraintEqualToConstant:self.verticalTabs || prefs.collapsed ? 0 : kTitlebarHeight];
 self.tabCluster=[[SlateTabCluster alloc] initWithFrame:NSZeroRect];
 ((SlateTabCluster*)self.tabCluster).owner=self;
 self.tabCluster.translatesAutoresizingMaskIntoConstraints=NO;
 self.tabCluster.clipsToBounds=NO;
 [self.tabCluster setContentHuggingPriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
 [self.tabCluster setContentCompressionResistancePriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
 [self.titlebar addSubview:self.tabCluster];
 self.sidebarNavButton=[self navButton:@"sidebar.left" fallback:@"rectangle.split.1x2" label:@"Sidebar"
  action:@selector(toggleTabsReveal:) motion:SlateNavMotionNone];
 self.backButton=[self navButton:@"chevron.left" fallback:@"chevron.left" label:@"Back"
  action:@selector(goBack:) motion:SlateNavMotionBack];
 self.forwardButton=[self navButton:@"chevron.right" fallback:@"chevron.right" label:@"Forward"
  action:@selector(goForward:) motion:SlateNavMotionForward];
 self.reloadButton=[self navButton:@"arrow.clockwise" fallback:@"arrow.clockwise" label:@"Reload"
  action:@selector(reload:) motion:SlateNavMotionReload];
 self.navCluster=[NSStackView stackViewWithViews:@[self.sidebarNavButton,self.backButton,self.forwardButton,self.reloadButton]];
 self.navCluster.orientation=NSUserInterfaceLayoutOrientationHorizontal;
 self.navCluster.spacing=4; self.navCluster.alignment=NSLayoutAttributeCenterY;
 self.navCluster.translatesAutoresizingMaskIntoConstraints=NO;
 SlateTabPills* tabPills=[[SlateTabPills alloc] initWithFrame:NSZeroRect];
 tabPills.owner=self;
 self.tabPills=tabPills;
 self.tabPills.orientation=NSUserInterfaceLayoutOrientationHorizontal;
 self.tabPills.spacing=(prefs.tabStyle == 1) ? 3.0 : 8.0;
 self.tabPills.alignment=NSLayoutAttributeBottom;
 self.tabPills.edgeInsets=NSEdgeInsetsMake(0,0,0,2);
 self.tabPills.translatesAutoresizingMaskIntoConstraints=NO;
 self.tabPills.wantsLayer=YES;
 self.tabPills.clipsToBounds=NO;
 self.tabPills.layer.masksToBounds=NO;
 self.splitTabShapeLayers=[NSMutableArray array];
 self.splitTabSeparatorLayers=[NSMutableArray array];
 [self.tabPills setContentHuggingPriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
 [self.tabPills setContentCompressionResistancePriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
 [self.tabCluster addSubview:self.tabPills];
 NSImage* newTabIcon=nil;
 if(@available(macOS 11.0, *)) {
  NSImageSymbolConfiguration* cfg=[NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium];
  newTabIcon=[[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"New tab"] imageWithSymbolConfiguration:cfg];
 }
 if(!newTabIcon) {
  newTabIcon=[NSImage imageNamed:@"TabIconTemplate"];
  newTabIcon.size=NSMakeSize(14, 14);
 }
 self.addButton=[[SlateAddTabButton alloc] initWithFrame:NSMakeRect(0,0,26,26)];
 self.addButton.image=newTabIcon;
 self.addButton.target=self; self.addButton.action=@selector(newTab:);
 self.addButton.bezelStyle=NSBezelStyleInline; self.addButton.bordered=NO; self.addButton.imagePosition=NSImageOnly;
 self.addButton.translatesAutoresizingMaskIntoConstraints=NO; self.addButton.toolTip=@"New tab (⌘T)";
 self.addButton.refusesFirstResponder=YES; self.addButton.keyEquivalent=@"";
 self.addButton.wantsLayer=YES; self.addButton.alphaValue=0.72;
 self.addButton.layer.cornerCurve=kCACornerCurveContinuous;
 self.addButton.layer.cornerRadius=7.0;
 [self.tabCluster addSubview:self.addButton];
 self.tabStripWidth=[self.tabPills.widthAnchor constraintEqualToConstant:96];
 self.tabStripWidth.priority=NSLayoutPriorityDefaultLow;
 self.addWidth=[self.addButton.widthAnchor constraintEqualToConstant:26];
 self.spaceBadgeButton=[[NSButton alloc] initWithFrame:NSMakeRect(0,0,20,20)];
 self.spaceBadgeButton.translatesAutoresizingMaskIntoConstraints=NO;
 self.spaceBadgeButton.bordered=NO;
 self.spaceBadgeButton.bezelStyle=NSBezelStyleInline;
 self.spaceBadgeButton.wantsLayer=YES;
 self.spaceBadgeButton.layer.cornerRadius=10.0;
 self.spaceBadgeButton.layer.masksToBounds=YES;
 if(@available(macOS 11.0, *)) self.spaceBadgeButton.layer.cornerCurve=kCACornerCurveContinuous;
 self.spaceBadgeButton.target=self;
 self.spaceBadgeButton.action=@selector(spaceBadgeClicked:);
 self.spaceBadgeButton.refusesFirstResponder=YES;
 [self.titlebar addSubview:self.spaceBadgeButton];
 self.tabLeadingTitle=[self.tabCluster.leadingAnchor constraintEqualToAnchor:self.titlebar.leadingAnchor constant:112];
 [NSLayoutConstraint activateConstraints:@[
  [self.spaceBadgeButton.trailingAnchor constraintEqualToAnchor:self.titlebar.trailingAnchor constant:-14],
  [self.spaceBadgeButton.centerYAnchor constraintEqualToAnchor:self.titlebar.centerYAnchor],
  [self.spaceBadgeButton.widthAnchor constraintEqualToConstant:20],
  [self.spaceBadgeButton.heightAnchor constraintEqualToConstant:20],
  self.tabLeadingTitle,
  [self.tabCluster.bottomAnchor constraintEqualToAnchor:self.titlebar.bottomAnchor],
  [self.tabCluster.topAnchor constraintEqualToAnchor:self.titlebar.topAnchor constant:4],
  [self.tabCluster.trailingAnchor constraintLessThanOrEqualToAnchor:self.spaceBadgeButton.leadingAnchor constant:-8],
  [self.tabPills.leadingAnchor constraintEqualToAnchor:self.tabCluster.leadingAnchor],
  [self.tabPills.bottomAnchor constraintEqualToAnchor:self.tabCluster.bottomAnchor],
  [self.tabPills.topAnchor constraintEqualToAnchor:self.tabCluster.topAnchor],
  self.tabStripWidth,
  [self.addButton.leadingAnchor constraintEqualToAnchor:self.tabPills.trailingAnchor constant:4],
  [self.addButton.centerYAnchor constraintEqualToAnchor:self.tabCluster.centerYAnchor],
  [self.addButton.heightAnchor constraintEqualToConstant:26],
  [self.addButton.trailingAnchor constraintEqualToAnchor:self.tabCluster.trailingAnchor],
  self.addWidth
 ]];
 NSImage* shieldsIcon=[NSImage imageWithSystemSymbolName:@"checkmark.shield" accessibilityDescription:@"Slate Shields"]
  ?: [NSImage imageWithSystemSymbolName:@"shield" accessibilityDescription:@"Slate Shields"];
 self.shieldsButton=[NSButton buttonWithImage:shieldsIcon target:self action:@selector(showShields:)];
 self.shieldsButton.bezelStyle=NSBezelStyleInline; self.shieldsButton.bordered=NO;
 self.shieldsButton.imagePosition=NSImageOnly;
 self.shieldsButton.translatesAutoresizingMaskIntoConstraints=NO;
 self.shieldsButton.toolTip=@"Slate Shields";
 self.shieldsButton.refusesFirstResponder=YES;
 NSImage* bookmarkIcon=[NSImage imageWithSystemSymbolName:@"star" accessibilityDescription:@"Bookmark"]
  ?: [NSImage imageWithSystemSymbolName:@"bookmark" accessibilityDescription:@"Bookmark"];
 self.bookmarkButton=[NSButton buttonWithImage:bookmarkIcon target:self action:@selector(toggleBookmarksDropdown:)];
 self.bookmarkButton.bezelStyle=NSBezelStyleInline; self.bookmarkButton.bordered=NO;
 self.bookmarkButton.imagePosition=NSImageOnly;
 self.bookmarkButton.translatesAutoresizingMaskIntoConstraints=NO;
 self.bookmarkButton.toolTip=@"Bookmarks (⌘D to toggle, click for dropdown)";
 self.bookmarkButton.refusesFirstResponder=YES;
 self.downloadButton=[[SlateDownloadButton alloc] initWithFrame:NSMakeRect(0,0,22,22)];
 self.downloadButton.translatesAutoresizingMaskIntoConstraints=NO;
 self.downloadButton.owner=self;
 [NSLayoutConstraint activateConstraints:@[
  [self.downloadButton.widthAnchor constraintEqualToConstant:22],
  [self.downloadButton.heightAnchor constraintEqualToConstant:22],
  [self.shieldsButton.widthAnchor constraintEqualToConstant:22],
  [self.shieldsButton.heightAnchor constraintEqualToConstant:22],
  [self.bookmarkButton.widthAnchor constraintEqualToConstant:22],
  [self.bookmarkButton.heightAnchor constraintEqualToConstant:22],
  [self.navCluster.heightAnchor constraintEqualToConstant:kTabHeight]
 ]];
 self.omnibox=[[SlateOmnibox alloc] initWithFrame:NSZeroRect];
 self.omnibox.translatesAutoresizingMaskIntoConstraints=NO;
 self.omnibox.wantsLayer=YES; self.omnibox.layerContentsRedrawPolicy=NSViewLayerContentsRedrawOnSetNeedsDisplay;
 self.securityButton=[[NSButton alloc] initWithFrame:NSZeroRect];
 self.securityButton.translatesAutoresizingMaskIntoConstraints=NO;
 self.securityButton.bordered=NO;
 self.securityButton.imagePosition=NSImageOnly;
 self.securityButton.image=[NSImage imageWithSystemSymbolName:@"lock.fill" accessibilityDescription:@"Site Information"] ?: [NSImage imageWithSystemSymbolName:@"lock" accessibilityDescription:@"Site Information"];
 self.securityButton.target=self;
 self.securityButton.action=@selector(showSiteCard:);
 self.securityButton.toolTip=@"Site Information";
 self.securityButton.refusesFirstResponder=YES;
 self.securityButton.hidden=YES;
 [self.omnibox addSubview:self.securityButton];
  self.stealthBadge=[[NSButton alloc] initWithFrame:NSZeroRect];
  self.stealthBadge.translatesAutoresizingMaskIntoConstraints=NO;
  self.stealthBadge.bordered=NO;
  self.stealthBadge.bezelStyle=NSBezelStyleInline;
  self.stealthBadge.wantsLayer=YES;
  self.stealthBadge.layer.cornerRadius=10.0;
  self.stealthBadge.layer.masksToBounds=YES;
  self.stealthBadge.layer.backgroundColor=[NSColor colorWithCalibratedWhite:0.12 alpha:0.95].CGColor;
  self.stealthBadge.layer.borderWidth=0.5;
  self.stealthBadge.layer.borderColor=[NSColor colorWithCalibratedWhite:0.35 alpha:0.75].CGColor;
  NSMutableAttributedString* badgeTitle=[[NSMutableAttributedString alloc] initWithString:@"🕶 Untrackable" attributes:@{
   NSFontAttributeName:[NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
   NSForegroundColorAttributeName:[NSColor colorWithCalibratedWhite:0.92 alpha:1.0]
  }];
  self.stealthBadge.attributedTitle=badgeTitle;
  self.stealthBadge.target=self;
  self.stealthBadge.action=@selector(showStealthInfo:);
  self.stealthBadge.toolTip=@"Untrackable Session Active\n• In-memory only (zero disk traces)\n• Anti-fingerprinting defenses active\n• WebRTC UDP leaks prevented\n• Trackers and pings blocked\n(Click for details)";
  self.stealthBadge.hidden=YES;
  [self.omnibox addSubview:self.stealthBadge];
 self.address=[[SlateAddressField alloc] initWithFrame:NSZeroRect];
 self.address.placeholderString=@"Search Google or enter address";
 self.address.font=[NSFont systemFontOfSize:14]; self.address.alignment=NSTextAlignmentLeft;
 self.address.textColor=NSColor.labelColor;
 self.address.bezeled=NO; self.address.bordered=NO; self.address.drawsBackground=NO;
 self.address.focusRingType=NSFocusRingTypeNone;
 self.address.target=self; self.address.action=@selector(navigate:); self.address.delegate=self;
 self.address.translatesAutoresizingMaskIntoConstraints=NO;
 self.address.accessibilityLabel=@"Website address";
 [self.address setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
 [self.address setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
 [self.omnibox addSubview:self.address];
 self.autofillButton=[[NSButton alloc] initWithFrame:NSZeroRect];
 self.autofillButton.translatesAutoresizingMaskIntoConstraints=NO;
 self.autofillButton.bordered=NO;
 self.autofillButton.bezelStyle=NSBezelStyleInline;
 self.autofillButton.buttonType=NSButtonTypeMomentaryChange;
 if (@available(macOS 11.0, *)) {
  self.autofillButton.image=[NSImage imageWithSystemSymbolName:@"key.fill" accessibilityDescription:@"Autofill Password"];
 }
 self.autofillButton.contentTintColor=NSColor.secondaryLabelColor;
 self.autofillButton.toolTip=@"Autofill saved password for this site";
 self.autofillButton.target=self;
 self.autofillButton.action=@selector(triggerAutofillAction:);
 self.autofillButton.hidden=YES;
 [self.omnibox addSubview:self.autofillButton];
 self.pipButton=[[NSButton alloc] initWithFrame:NSZeroRect];
 self.pipButton.translatesAutoresizingMaskIntoConstraints=NO;
 self.pipButton.bordered=NO;
 self.pipButton.buttonType=NSButtonTypeMomentaryChange;
 self.pipButton.imagePosition=NSImageOnly;
 self.pipButton.imageScaling=NSImageScaleProportionallyDown;
 self.pipButton.refusesFirstResponder=YES;
 if (@available(macOS 11.0, *)) {
  self.pipButton.image=[NSImage imageWithSystemSymbolName:@"pip.enter" accessibilityDescription:@"Picture in Picture"];
 }
 self.pipButton.contentTintColor=NSColor.secondaryLabelColor;
 self.pipButton.toolTip=@"Picture in Picture (⌥⌘P)";
 self.pipButton.target=self;
 self.pipButton.action=@selector(toggleFloatingVideo:);
 self.pipButton.hidden=YES;
 [self.omnibox addSubview:self.pipButton];

 self.sidebar=[[NSView alloc] initWithFrame:NSZeroRect];
 self.sidebar.translatesAutoresizingMaskIntoConstraints=NO; self.sidebar.wantsLayer=YES;
 self.sidebar.clipsToBounds=YES;
 self.sidebar.layer.masksToBounds=YES;
 [root addSubview:self.sidebar];
 self.sidebarWidth=[self.sidebar.widthAnchor constraintEqualToConstant:[self sidebarLayoutWidth]];
 self.sidebarBelowChrome=[self.sidebar.topAnchor constraintEqualToAnchor:root.topAnchor];
 self.sidebarFromTop=[self.sidebar.topAnchor constraintEqualToAnchor:root.topAnchor];
 self.sidebarBelowChrome.active=NO;
 self.sidebarFromTop.active=YES;
 [NSLayoutConstraint activateConstraints:@[
  [self.sidebar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
  [self.sidebar.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
  self.sidebarWidth
 ]];
 NSScrollView* scroll=[[NSScrollView alloc] initWithFrame:NSZeroRect];
 scroll.drawsBackground=NO; scroll.hasVerticalScroller=YES; scroll.borderType=NSNoBorder;
 scroll.translatesAutoresizingMaskIntoConstraints=NO;
 self.tabList=[[SlateSidebarTable alloc] initWithFrame:NSZeroRect];
 ((SlateSidebarTable*)self.tabList).owner=self;
 self.tabList.autoresizingMask=NSViewWidthSizable;
 NSTableColumn* column=[[NSTableColumn alloc] initWithIdentifier:@"tab"];
 column.minWidth=24; column.maxWidth=4000; column.width=[self sidebarLayoutWidth] > 0 ? [self sidebarLayoutWidth] : (kSidebarOpenWidth-12);
 column.resizingMask=NSTableColumnAutoresizingMask;
 [self.tabList addTableColumn:column]; self.tabList.headerView=nil;
 if(@available(macOS 11.0, *)) self.tabList.style=NSTableViewStylePlain;
 self.tabList.columnAutoresizingStyle=NSTableViewUniformColumnAutoresizingStyle;
 self.tabList.backgroundColor=NSColor.clearColor; self.tabList.rowHeight=28;
 self.tabList.selectionHighlightStyle=NSTableViewSelectionHighlightStyleNone;
 self.tabList.intercellSpacing=NSMakeSize(0,2);
 self.tabList.delegate=self; self.tabList.dataSource=self;
 self.tabList.allowsEmptySelection=YES; self.tabList.accessibilityLabel=@"Tabs";
 scroll.hasHorizontalScroller=NO;
 scroll.horizontalScrollElasticity=NSScrollElasticityNone;
 [self.tabList registerForDraggedTypes:@[@"slate.tab.drag"]];
 [self.tabList setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
 self.tabList.menu=[[NSMenu alloc] init]; self.tabList.menu.delegate=self;
 scroll.documentView=self.tabList; [self.sidebar addSubview:scroll];
 self.sidebarAdd=[NSButton buttonWithTitle:@"New Tab" target:self action:@selector(newTab:)];
 NSImage* sidebarNewTabIcon = nil;
 if (@available(macOS 11.0, *)) {
  NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightMedium];
  sidebarNewTabIcon = [[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"New tab"] imageWithSymbolConfiguration:cfg];
 }
 if (!sidebarNewTabIcon) {
  sidebarNewTabIcon = [NSImage imageNamed:@"TabIconTemplate"];
  sidebarNewTabIcon.size = NSMakeSize(12, 12);
 }
 self.sidebarAdd.image=sidebarNewTabIcon;
 self.sidebarAdd.imagePosition=NSImageLeading;
 self.sidebarAdd.bezelStyle=NSBezelStyleRegularSquare; self.sidebarAdd.bordered=NO;
 self.sidebarAdd.font=[NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
 self.sidebarAdd.contentTintColor=NSColor.secondaryLabelColor;
 self.sidebarAdd.alignment=NSTextAlignmentLeft;
 self.sidebarAdd.translatesAutoresizingMaskIntoConstraints=NO;
 self.sidebarAdd.refusesFirstResponder=YES;
 [self.sidebar addSubview:self.sidebarAdd];
 self.sidebarDrag=[[SlateDragRegion alloc] initWithFrame:NSZeroRect];
 self.sidebarDrag.translatesAutoresizingMaskIntoConstraints=NO;
 self.sidebarDrag.clipsToBounds=YES;
 [self.sidebar addSubview:self.sidebarDrag];
 self.pinnedGrid=[[SlatePinnedGrid alloc] initWithFrame:NSZeroRect];
 self.pinnedGrid.translatesAutoresizingMaskIntoConstraints=NO;
 self.pinnedGrid.owner=self;
 [self.sidebar addSubview:self.pinnedGrid];
 NSLayoutConstraint* pinnedH=[self.pinnedGrid.heightAnchor constraintEqualToConstant:0];
 self.pinnedGrid.heightConstraint=pinnedH;
 self.sidebarFoot=[[SlateSidebarFoot alloc] initWithFrame:NSZeroRect];
 self.sidebarFoot.translatesAutoresizingMaskIntoConstraints=NO;
 self.sidebarFoot.owner=self;
 [self.sidebar addSubview:self.sidebarFoot];
 self.protectButton=[NSButton checkboxWithTitle:@"Keep loaded" target:self action:@selector(toggleProtection:)];
 self.protectButton.font=[NSFont systemFontOfSize:11];
 self.unloadButton=[self button:@"Unload" action:@selector(unloadTab:)];
 self.sidebarAddLeading=[self.sidebarAdd.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor constant:18];
 NSLayoutConstraint* addCenter=[self.sidebarAdd.centerXAnchor constraintEqualToAnchor:self.sidebar.centerXAnchor];
 addCenter.priority=NSLayoutPriorityDefaultHigh;
 self.sidebarHeaderHeight=[self.sidebarDrag.heightAnchor constraintEqualToConstant:kSidebarHeaderHeight];
 self.tabListLeading=[scroll.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor constant:10];
 self.tabListTrailing=[scroll.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:-10];
 self.tabListTrailing.priority=NSLayoutPriorityDefaultHigh;
 self.sidebarAddHeight=[self.sidebarAdd.heightAnchor constraintEqualToConstant:kRailBubble];
 self.sidebarAddWidth=[self.sidebarAdd.widthAnchor constraintEqualToConstant:kRailBubble];
 self.sidebarAddWidth.active=NO;
 self.sidebarAdd.hidden=YES;
 [NSLayoutConstraint activateConstraints:@[
  [self.sidebarDrag.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor],
  [self.sidebarDrag.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor],
  [self.sidebarDrag.topAnchor constraintEqualToAnchor:self.sidebar.topAnchor],
  self.sidebarHeaderHeight,
  [self.pinnedGrid.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor],
  [self.pinnedGrid.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor],
  [self.pinnedGrid.topAnchor constraintEqualToAnchor:self.sidebarDrag.bottomAnchor],
  pinnedH,
  self.tabListLeading,
  self.tabListTrailing,
  [scroll.topAnchor constraintEqualToAnchor:self.pinnedGrid.bottomAnchor constant:2],
  [scroll.bottomAnchor constraintEqualToAnchor:self.sidebarFoot.topAnchor constant:-4],
  [self.sidebarFoot.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor],
  [self.sidebarFoot.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor],
  [self.sidebarFoot.bottomAnchor constraintEqualToAnchor:self.sidebar.bottomAnchor],
  [self.sidebarFoot.heightAnchor constraintEqualToConstant:36]
 ]];
 self.toolbar=[[SlateDragRegion alloc] initWithFrame:NSZeroRect];
 self.toolbar.translatesAutoresizingMaskIntoConstraints=NO;
 self.chromePlate=[[NSView alloc] initWithFrame:NSZeroRect];
 self.chromePlate.translatesAutoresizingMaskIntoConstraints=NO;
 self.chromePlate.wantsLayer=YES;
 self.graniteView=[[SlateGraniteView alloc] initWithFrame:NSZeroRect];
 self.graniteView.translatesAutoresizingMaskIntoConstraints=NO;
 self.graniteView.wantsLayer=YES;
 [root addSubview:self.graniteView positioned:NSWindowBelow relativeTo:nil];
 [NSLayoutConstraint activateConstraints:@[
  [self.graniteView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
  [self.graniteView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
  [self.graniteView.topAnchor constraintEqualToAnchor:root.topAnchor],
  [self.graniteView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
 ]];
 [root addSubview:self.chromePlate];
 self.stage=[[SlateStageView alloc] initWithFrame:NSZeroRect];
 ((SlateStageView*)self.stage).owner=self;
 self.stage.translatesAutoresizingMaskIntoConstraints=NO;
 self.stage.wantsLayer=YES;
 [root addSubview:self.titlebar];
 [self.chromePlate addSubview:self.stage];
 [self.stage addSubview:self.toolbar];
 self.plateFromTop=[self.chromePlate.topAnchor constraintEqualToAnchor:self.titlebar.bottomAnchor constant:kPlateInset];
 self.plateFromTop.active=YES;
 self.plateLeading=[self.chromePlate.leadingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:kPlateInset];
 self.plateTrailing=[self.chromePlate.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kPlateInset];
 self.plateBottom=[self.chromePlate.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kPlateInset];
 self.plateFromTraffic=[self.chromePlate.leadingAnchor constraintGreaterThanOrEqualToAnchor:root.leadingAnchor constant:0];
 self.plateLeading.priority=NSLayoutPriorityDefaultHigh;
 self.plateFromTraffic.active=self.verticalTabs;
 [NSLayoutConstraint activateConstraints:@[
  self.plateFromTop,
  self.plateLeading,
  self.plateTrailing,
  self.plateBottom,
  [self.stage.leadingAnchor constraintEqualToAnchor:self.chromePlate.leadingAnchor],
  [self.stage.trailingAnchor constraintEqualToAnchor:self.chromePlate.trailingAnchor],
  [self.stage.topAnchor constraintEqualToAnchor:self.chromePlate.topAnchor],
  [self.stage.bottomAnchor constraintEqualToAnchor:self.chromePlate.bottomAnchor],
  [self.titlebar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
  [self.titlebar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
  [self.titlebar.topAnchor constraintEqualToAnchor:root.topAnchor],
  self.titlebarHeight,
  [self.toolbar.leadingAnchor constraintEqualToAnchor:self.stage.leadingAnchor],
  [self.toolbar.trailingAnchor constraintEqualToAnchor:self.stage.trailingAnchor],
  [self.toolbar.topAnchor constraintEqualToAnchor:self.stage.topAnchor],
  [self.toolbar.heightAnchor constraintEqualToConstant:kToolbarHeight]
 ]];
 self.toolbarGraniteView=[[SlateGraniteView alloc] initWithFrame:NSZeroRect];
 self.toolbarGraniteView.translatesAutoresizingMaskIntoConstraints=NO;
 self.toolbarGraniteView.wantsLayer=YES;
 [self.toolbar addSubview:self.toolbarGraniteView positioned:NSWindowBelow relativeTo:nil];
 [NSLayoutConstraint activateConstraints:@[
  [self.toolbarGraniteView.leadingAnchor constraintEqualToAnchor:self.toolbar.leadingAnchor],
  [self.toolbarGraniteView.trailingAnchor constraintEqualToAnchor:self.toolbar.trailingAnchor],
  [self.toolbarGraniteView.topAnchor constraintEqualToAnchor:self.toolbar.topAnchor],
  [self.toolbarGraniteView.bottomAnchor constraintEqualToAnchor:self.toolbar.bottomAnchor]
 ]];
 [self.toolbar addSubview:self.navCluster];
 [self.toolbar addSubview:self.downloadButton];
 [self.toolbar addSubview:self.shieldsButton];
 [self.toolbar addSubview:self.bookmarkButton];
 self.loadBar=[[NSView alloc] initWithFrame:NSZeroRect];
 self.loadBar.translatesAutoresizingMaskIntoConstraints=NO;
 self.loadBar.wantsLayer=YES;
 self.loadBar.hidden=YES;
 [self.toolbar addSubview:self.loadBar];
 self.loadBarWidth=[self.loadBar.widthAnchor constraintEqualToConstant:0];
 self.navLeadingTitle=[self.navCluster.leadingAnchor constraintEqualToAnchor:self.toolbar.leadingAnchor constant:16];
 self.navCenterTitle=[self.navCluster.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor constant:1];
 self.downloadTrailingTitle=[self.downloadButton.trailingAnchor constraintEqualToAnchor:self.toolbar.trailingAnchor constant:-14];
 self.downloadCenterTitle=[self.downloadButton.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor constant:1];
 self.shieldsTrailingTitle=[self.shieldsButton.trailingAnchor constraintEqualToAnchor:self.downloadButton.leadingAnchor constant:-8];
 self.shieldsTrailingNoDownload=[self.shieldsButton.trailingAnchor constraintEqualToAnchor:self.toolbar.trailingAnchor constant:-14];
 self.shieldsCenterTitle=[self.shieldsButton.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor constant:1];
 [NSLayoutConstraint activateConstraints:@[
  self.navLeadingTitle, self.navCenterTitle,
  self.downloadTrailingTitle, self.downloadCenterTitle,
  self.shieldsTrailingTitle, self.shieldsCenterTitle,
  [self.bookmarkButton.trailingAnchor constraintEqualToAnchor:self.shieldsButton.leadingAnchor constant:-8],
  [self.bookmarkButton.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor constant:1],
  [self.loadBar.leadingAnchor constraintEqualToAnchor:self.toolbar.leadingAnchor],
  [self.loadBar.bottomAnchor constraintEqualToAnchor:self.toolbar.bottomAnchor],
  [self.loadBar.heightAnchor constraintEqualToConstant:2],
  self.loadBarWidth
 ]];
  self.showBookmarksBar=prefs.showBookmarksBar;
  self.bookmarksBar=[[NSView alloc] initWithFrame:NSZeroRect];
  self.bookmarksBar.translatesAutoresizingMaskIntoConstraints=NO;
  self.bookmarksBar.wantsLayer=YES;
  [self.stage addSubview:self.bookmarksBar];

  self.bookmarksScroll=[[NSScrollView alloc] initWithFrame:NSZeroRect];
  self.bookmarksScroll.translatesAutoresizingMaskIntoConstraints=NO;
  self.bookmarksScroll.drawsBackground=NO;
  self.bookmarksScroll.hasHorizontalScroller=NO;
  self.bookmarksScroll.hasVerticalScroller=NO;
  self.bookmarksScroll.horizontalScrollElasticity=NSScrollElasticityAutomatic;
  [self.bookmarksBar addSubview:self.bookmarksScroll];

  self.bookmarksStack=[NSStackView stackViewWithViews:@[]];
  self.bookmarksStack.orientation=NSUserInterfaceLayoutOrientationHorizontal;
  self.bookmarksStack.spacing=4;
  self.bookmarksStack.alignment=NSLayoutAttributeCenterY;
  self.bookmarksStack.edgeInsets=NSEdgeInsetsMake(0, 10, 0, 10);
  self.bookmarksStack.translatesAutoresizingMaskIntoConstraints=NO;
  self.bookmarksScroll.documentView=self.bookmarksStack;

  self.bookmarksBarHeight=[self.bookmarksBar.heightAnchor constraintEqualToConstant:self.showBookmarksBar ? kBookmarksBarHeight : 0];
  self.bookmarksBar.hidden=!self.showBookmarksBar;

  [NSLayoutConstraint activateConstraints:@[
   [self.bookmarksBar.leadingAnchor constraintEqualToAnchor:self.stage.leadingAnchor],
   [self.bookmarksBar.trailingAnchor constraintEqualToAnchor:self.stage.trailingAnchor],
   [self.bookmarksBar.topAnchor constraintEqualToAnchor:self.toolbar.bottomAnchor],
   self.bookmarksBarHeight,
   [self.bookmarksScroll.leadingAnchor constraintEqualToAnchor:self.bookmarksBar.leadingAnchor],
   [self.bookmarksScroll.trailingAnchor constraintEqualToAnchor:self.bookmarksBar.trailingAnchor],
   [self.bookmarksScroll.topAnchor constraintEqualToAnchor:self.bookmarksBar.topAnchor],
   [self.bookmarksScroll.bottomAnchor constraintEqualToAnchor:self.bookmarksBar.bottomAnchor],
   [self.bookmarksStack.centerYAnchor constraintEqualToAnchor:self.bookmarksScroll.centerYAnchor],
   [self.bookmarksStack.leadingAnchor constraintEqualToAnchor:self.bookmarksScroll.leadingAnchor],
   [self.bookmarksStack.heightAnchor constraintEqualToAnchor:self.bookmarksBar.heightAnchor]
  ]];

 self.content=[[SlatePageSlot alloc] initWithFrame:NSZeroRect];
 ((SlatePageSlot*)self.content).owner=self;
 [self.content registerForDraggedTypes:@[@"slate.tab.drag"]];
 self.content.translatesAutoresizingMaskIntoConstraints=NO; self.content.wantsLayer=YES;
 self.content.clipsToBounds=YES;
 self.content.layer.masksToBounds=YES;
 [self.stage addSubview:self.content];
 [NSLayoutConstraint activateConstraints:@[
  [self.content.topAnchor constraintEqualToAnchor:self.bookmarksBar.bottomAnchor],
  [self.content.leadingAnchor constraintEqualToAnchor:self.stage.leadingAnchor],
  [self.content.trailingAnchor constraintEqualToAnchor:self.stage.trailingAnchor],
  [self.content.bottomAnchor constraintEqualToAnchor:self.stage.bottomAnchor]
 ]];
 self.resizeHandle=[[SlateResizeHandle alloc] initWithFrame:NSZeroRect];
 ((SlateResizeHandle*)self.resizeHandle).owner=self;
 self.resizeHandle.translatesAutoresizingMaskIntoConstraints=NO;
 [root addSubview:self.resizeHandle];
 [NSLayoutConstraint activateConstraints:@[
  [self.resizeHandle.leadingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:-4],
  [self.resizeHandle.widthAnchor constraintEqualToConstant:9],
  [self.resizeHandle.topAnchor constraintEqualToAnchor:self.sidebar.topAnchor],
  [self.resizeHandle.bottomAnchor constraintEqualToAnchor:self.sidebar.bottomAnchor]
 ]];
 self.placeholder=[[NSView alloc] initWithFrame:NSZeroRect];
 [self.content addSubview:self.placeholder];
 self.placeholder.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
 NSTextField* empty=[self label:@"This tab is unloaded. Restore reloads its address." size:13 color:NSColor.secondaryLabelColor];
 empty.translatesAutoresizingMaskIntoConstraints=NO; [self.placeholder addSubview:empty];
 NSButton* restore=[self button:@"Restore tab" action:@selector(restoreTab:)];
 restore.translatesAutoresizingMaskIntoConstraints=NO; [self.placeholder addSubview:restore];
 NSScrollView* homeScroll=[[SlateHomeScroll alloc] initWithFrame:NSZeroRect];
 homeScroll.drawsBackground=NO; homeScroll.borderType=NSNoBorder;
 homeScroll.hasVerticalScroller=YES; homeScroll.hasHorizontalScroller=NO;
 homeScroll.translatesAutoresizingMaskIntoConstraints=NO;
 self.homeView=homeScroll;
 self.homeBoard=[[SlateHomeBoard alloc] initWithFrame:NSZeroRect];
 self.homeBoard.owner=self;
 self.homeBoard.omniboxCard.delegate=self;
 homeScroll.documentView=self.homeBoard;
 [self.content addSubview:self.homeView];
 self.homeView.translatesAutoresizingMaskIntoConstraints=YES;
 self.homeView.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
 [self setupSplitViews];
 [self.toolbar addSubview:self.omnibox];
 [self.omnibox setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
 [self.omnibox setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
 self.omniboxLeading=[self.omnibox.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.navCluster.trailingAnchor constant:12];
 self.omniboxTrailing=[self.omnibox.trailingAnchor constraintLessThanOrEqualToAnchor:self.bookmarkButton.leadingAnchor constant:-12];
 NSLayoutConstraint* omniboxCenter=[self.omnibox.centerXAnchor constraintEqualToAnchor:self.toolbar.centerXAnchor];
 omniboxCenter.priority=900;
 NSLayoutConstraint* omniboxMaxW=[self.omnibox.widthAnchor constraintLessThanOrEqualToConstant:1100];
 NSLayoutConstraint* omniboxMinW=[self.omnibox.widthAnchor constraintGreaterThanOrEqualToConstant:620];
 omniboxMinW.priority=760;
 // Compute the capped preferred width without tying window width to the cap.
 self.omniboxPreferredWidth=[self.omnibox.widthAnchor constraintEqualToConstant:MIN(1100,NSWidth(root.bounds)*0.64)];
 self.omniboxPreferredWidth.priority=NSLayoutPriorityDefaultHigh;
 [NSLayoutConstraint activateConstraints:@[
  [empty.centerXAnchor constraintEqualToAnchor:self.placeholder.centerXAnchor],
  [empty.centerYAnchor constraintEqualToAnchor:self.placeholder.centerYAnchor constant:-18],
  [restore.centerXAnchor constraintEqualToAnchor:self.placeholder.centerXAnchor],
  [restore.topAnchor constraintEqualToAnchor:empty.bottomAnchor constant:12],
  self.omniboxLeading, self.omniboxTrailing,
  omniboxCenter, omniboxMaxW, omniboxMinW, self.omniboxPreferredWidth,
  [self.omnibox.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor constant:1],
  [self.omnibox.heightAnchor constraintEqualToConstant:kOmniboxHeight],
  [self.omnibox.widthAnchor constraintGreaterThanOrEqualToConstant:180],
  self.securityButtonLeading=[self.securityButton.leadingAnchor constraintEqualToAnchor:self.omnibox.leadingAnchor constant:0],
  self.securityButtonWidth=[self.securityButton.widthAnchor constraintEqualToConstant:0],
  [self.securityButton.centerYAnchor constraintEqualToAnchor:self.omnibox.centerYAnchor],
  [self.securityButton.heightAnchor constraintEqualToConstant:18],
  self.stealthBadgeLeading=[self.stealthBadge.leadingAnchor constraintEqualToAnchor:self.securityButton.trailingAnchor constant:2],
  self.stealthBadgeWidth=[self.stealthBadge.widthAnchor constraintEqualToConstant:0],
  [self.stealthBadge.centerYAnchor constraintEqualToAnchor:self.omnibox.centerYAnchor],
  [self.stealthBadge.heightAnchor constraintEqualToConstant:20],
  self.addressLeading=[self.address.leadingAnchor constraintEqualToAnchor:self.stealthBadge.trailingAnchor constant:6],
  self.pipButtonTrailing=[self.pipButton.trailingAnchor constraintEqualToAnchor:self.omnibox.trailingAnchor constant:-6],
  self.pipButtonWidth=[self.pipButton.widthAnchor constraintEqualToConstant:0],
  [self.pipButton.centerYAnchor constraintEqualToAnchor:self.omnibox.centerYAnchor],
  [self.pipButton.heightAnchor constraintEqualToConstant:22],
  self.autofillButtonTrailing=[self.autofillButton.trailingAnchor constraintEqualToAnchor:self.pipButton.leadingAnchor constant:-2],
  self.autofillButtonWidth=[self.autofillButton.widthAnchor constraintEqualToConstant:0],
  [self.autofillButton.centerYAnchor constraintEqualToAnchor:self.omnibox.centerYAnchor],
  [self.autofillButton.heightAnchor constraintEqualToConstant:18],
  self.addressTrailing=[self.address.trailingAnchor constraintEqualToAnchor:self.autofillButton.leadingAnchor constant:-4],
  [self.address.centerYAnchor constraintEqualToAnchor:self.omnibox.centerYAnchor]
 ]];
 // ── Suggestion dropdown ──────────────────────────────────────────────────
 // White/accent rounded card with drop shadow (square top corners applied during positioning)
 NSView* paletteRoot = [[NSView alloc] initWithFrame:NSZeroRect];
 paletteRoot.translatesAutoresizingMaskIntoConstraints = NO;
 paletteRoot.wantsLayer = YES;
 paletteRoot.layer.masksToBounds = NO;
 paletteRoot.layer.shadowColor = [NSColor.blackColor CGColor];
 paletteRoot.layer.shadowOpacity = 0.18;
 paletteRoot.layer.shadowRadius = 16;
 paletteRoot.layer.shadowOffset = CGSizeMake(0, -2);

 NSView* card = [[NSView alloc] initWithFrame:NSZeroRect];
 card.translatesAutoresizingMaskIntoConstraints = NO;
 card.wantsLayer = YES;
 card.layer.cornerRadius = 14;
 if(@available(macOS 11.0,*)) card.layer.cornerCurve = kCACornerCurveContinuous;
 card.layer.masksToBounds = YES;
 card.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
 self.suggestCard = card;
 [paletteRoot addSubview:card];
 [NSLayoutConstraint activateConstraints:@[
  [card.leadingAnchor constraintEqualToAnchor:paletteRoot.leadingAnchor],
  [card.trailingAnchor constraintEqualToAnchor:paletteRoot.trailingAnchor],
  [card.topAnchor constraintEqualToAnchor:paletteRoot.topAnchor],
  [card.bottomAnchor constraintEqualToAnchor:paletteRoot.bottomAnchor],
 ]];

 // ── Suggestion stack ────────────────────────────────────────────────────
 self.suggestStack = [NSStackView stackViewWithViews:@[]];
 self.suggestStack.orientation = NSUserInterfaceLayoutOrientationVertical;
 self.suggestStack.spacing = 0;
 self.suggestStack.alignment = NSLayoutAttributeLeading;
 self.suggestStack.distribution = NSStackViewDistributionFill;
 self.suggestStack.edgeInsets = NSEdgeInsetsMake(4, 0, 4, 0);
 self.suggestStack.translatesAutoresizingMaskIntoConstraints = NO;

 [card addSubview:self.suggestStack];
 [NSLayoutConstraint activateConstraints:@[
  [self.suggestStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
  [self.suggestStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
  [self.suggestStack.topAnchor constraintEqualToAnchor:card.topAnchor],
  [self.suggestStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
 ]];

 // ── NSPanel ──────────────────────────────────────────────────────────────
 self.suggestPanel=[[SlateSuggestPanel alloc] initWithContentRect:NSMakeRect(0,0,520,40)
  styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel
  backing:NSBackingStoreBuffered defer:NO];
 self.suggestPanel.opaque=NO;
 self.suggestPanel.backgroundColor=NSColor.clearColor;
 self.suggestPanel.hasShadow=NO; // shadow is on paletteRoot.layer
 self.suggestPanel.hidesOnDeactivate=YES;
 self.suggestPanel.floatingPanel=YES;
 self.suggestPanel.becomesKeyOnlyIfNeeded=YES;
 self.suggestPanel.releasedWhenClosed=NO;
 self.suggestPanel.level=NSPopUpMenuWindowLevel;
 self.suggestPanel.contentView=paletteRoot;
 self.status=[self label:@"" size:11 color:NSColor.tertiaryLabelColor];
 self.status.translatesAutoresizingMaskIntoConstraints=NO; self.status.hidden=YES;
 [root addSubview:self.status];
 self.trafficCluster=[[SlateTrafficCluster alloc] initWithFrame:NSZeroRect];
 ((SlateTrafficCluster*)self.trafficCluster).owner=self;
 self.trafficCluster.translatesAutoresizingMaskIntoConstraints=NO;
 self.trafficCluster.wantsLayer=YES;
 [root addSubview:self.trafficCluster];
 self.trafficCluster.hidden=YES;
 // Separate AppKit-created controls stay in our full-screen chrome. Leave
 // the window's titlebar-owned buttons in AppKit's hierarchy for transitions.
 NSMutableArray<NSButton*>* fullScreenButtons=[NSMutableArray array];
 NSUInteger trafficIndex=0;
 for(NSWindowButton kind : {NSWindowCloseButton,NSWindowMiniaturizeButton,NSWindowZoomButton}) {
  NSButton* button=[NSWindow standardWindowButton:kind forStyleMask:self.window.styleMask];
  if(!button) continue;
  button.frame=NSMakeRect(trafficIndex*20,2,14,14);
  button.target=self.window;
  button.action=kind==NSWindowCloseButton ? @selector(performClose:) :
   kind==NSWindowMiniaturizeButton ? @selector(performMiniaturize:) : @selector(toggleFullScreen:);
  button.refusesFirstResponder=YES;
  button.accessibilityLabel=kind==NSWindowCloseButton ? @"Close window" :
   kind==NSWindowMiniaturizeButton ? @"Minimize window" : @"Exit full screen";
  button.identifier=kind==NSWindowCloseButton ? @"SlateFullscreenClose" :
   kind==NSWindowMiniaturizeButton ? @"SlateFullscreenMinimize" : @"SlateFullscreenExit";
  button.toolTip=button.accessibilityLabel;
  [self.trafficCluster addSubview:button];
  [fullScreenButtons addObject:button];
  ++trafficIndex;
 }
 self.fullScreenTrafficButtons=fullScreenButtons;
 self.trafficMode=-1;
 [NSLayoutConstraint activateConstraints:@[
  self.trafficLeading=[self.trafficCluster.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],
  self.trafficTop=[self.trafficCluster.topAnchor constraintEqualToAnchor:root.topAnchor constant:12],
  [self.trafficCluster.widthAnchor constraintEqualToConstant:68],
  [self.trafficCluster.heightAnchor constraintEqualToConstant:18]
 ]];
 [self applyTabLayout:NO];
 [self updateSpaceBadge];
 [self updateZoomMenu];
 [self applyPlateChrome];
 [self updateNavChrome];
 [self rebuildBookmarksBar];
 [self.window.contentView layoutSubtreeIfNeeded];
 if(self.window.isMiniaturized) [self.window deminiaturize:nil];
 if(self.window.frame.size.width < 600 || self.window.frame.size.height < 400) {
  [self.window setFrame:NSMakeRect(100, 100, 1200, 800) display:YES];
  [self.window center];
 }
 [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
 [self syncTabListColumnWidth];
 if([self sidebarLayoutWidth]>0 && self.tabList) [self.tabList reloadData];
 {
  // Native WebKit owns the compiled lists; this object stores only UI policy.
  shields=std::make_unique<slate::ShieldController>();
  if(!slate::WebKitShields::Shared().IsEnabled()) shields->set_mode(slate::ShieldMode::Off);
  for(const auto& site:slate::WebKitShields::Shared().DisabledSites()) shields->pause_site(site);
  fprintf(stderr,"SLATE_SHIELDS native_rules=%zu\n",slate::WebKitShields::Shared().CompiledRuleCount());
 }
 if(workspace.visible_for(model.selected())) {
  const TabId focused=model.selected();
  const TabId other=workspace.left==focused ? workspace.right : workspace.left;
  workspace.select(focused);
  self.splitInstalling=YES;
  [self activateTab:other];
  [self activateTab:focused];
  self.splitInstalling=NO;
 } else [self activateTab:model.selected()];
 __weak SlateDelegate* weakSelf=self;
 if(self.earlyURLs.count) {
  NSArray<NSURL*>* early=[self.earlyURLs copy];
  [self.earlyURLs removeAllObjects];
  for(NSUInteger idx=0; idx<early.count; ++idx) {
   NSURL* u=early[idx];
   if(idx==0) {
    [self openExternalURL:u];
   } else {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((idx*0.15)*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
     [weakSelf openExternalURL:u];
    });
   }
  }
 }
 memoryMonitor=slate::monitor_memory([weakSelf](slate::MemorySample sample) { [weakSelf memoryChanged:sample]; });
 fprintf(stderr,"SLATE_SESSION_RESTORED tabs=%zu loaded=%zu selected=%llu\n",
  model.tabs().size(),runtimes.size(),static_cast<unsigned long long>(model.selected()));
 if(loadError) {
  NSAlert* alert=[[NSAlert alloc] init]; alert.messageText=@"Session recovery"; alert.informativeText=loadError;
  [alert beginSheetModalForWindow:self.window completionHandler:nil];
 }
 // Setup mouse monitor for hover-to-peek sidebar
 self.mouseMovedMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskMouseMoved handler:^(NSEvent *event) {
  [weakSelf checkSidebarPeek];
 }];
 // Local monitor catches moves when the app is active and over its own windows
 self.localMouseMovedMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved handler:^NSEvent*(NSEvent *event) {
  [weakSelf checkSidebarPeek];
  return event;
 }];
 // Initialize custom downloads directory if configured on active space
 SlateSpace* initialSpace = [self.spacesManager currentSpace];
 if(initialSpace.downloads.length) {
  [SlateDownloadManager sharedManager].downloadsDirectory = initialSpace.downloads;
 }
 [self.sidebarFoot updateDoors];

 // Two-finger horizontal swipe across sidebar switches spaces
 self.spaceSwipeMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel handler:^NSEvent*(NSEvent *event) {
  if(!weakSelf.verticalTabs || weakSelf.tabsCollapsed || weakSelf.quitting) return event;
  if(event.window != weakSelf.window) return event;
  NSPoint pt = [weakSelf.sidebar convertPoint:event.locationInWindow fromView:nil];
  if(!NSPointInRect(pt, weakSelf.sidebar.bounds)) return event;

  const CGFloat dx = event.scrollingDeltaX;
  const CGFloat dy = event.scrollingDeltaY;
  if(fabs(dx) > fabs(dy) * 1.4 && fabs(dx) > 18.0) {
   NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
   if(now - weakSelf.lastSpaceSwipeTime > 0.35) {
    weakSelf.lastSpaceSwipeTime = now;
    if(dx < -18.0) {
     [weakSelf switchNextSpace];
    } else if(dx > 18.0) {
     [weakSelf switchPreviousSpace];
    }
   }
  }
  return event;
 }];
}
- (void)updateOmniboxPreferredWidth {
 const BOOL fullScreen=(self.window.styleMask & NSWindowStyleMaskFullScreen)!=0;
 const CGFloat inset=fullScreen ? 5.0 : kPlateInset;
 const CGFloat available=MAX(0,NSWidth(self.window.frame)-[self sidebarLayoutWidth]-2*inset);
 self.omniboxPreferredWidth.constant=MIN(1100,MAX(180,available*0.64));
}
- (void)applyTabLayout:(BOOL)animate {
 [self updateOmniboxPreferredWidth];
 [self placeWindowChrome];
 const BOOL showStrip=[self stripRevealed];
 const CGFloat width=[self sidebarLayoutWidth];
 ++self.chromeLayoutGen;
 self.chromeAnimating=animate;
 [CATransaction begin];
 [CATransaction setDisableActions:!animate];
 if(animate) {
  [CATransaction setAnimationDuration:0.2];
  [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
 }
 self.sidebar.hidden=width==0;
 self.sidebar.alphaValue=1;
 self.sidebarWidth.constant=width;
 self.titlebar.alphaValue=showStrip ? 1 : 0;
 self.titlebarHeight.constant=showStrip ? kTitlebarHeight : 0;
 self.tabCluster.hidden=!showStrip;
 self.tabCluster.alphaValue=showStrip ? 1 : 0;
 self.tabLeadingTitle.constant=showStrip ? 112 : 12;
 self.resizeHandle.hidden=width==0;
 self.plateFromTraffic.active=NO;
 self.navLeadingTitle.constant=([self trafficLayoutMode]==3 ? 88 : 16);
 // The horizontal plate meets the tab strip without an exposed gap.
 // Its remaining edges keep the same inset as the vertical plate.
 const BOOL isFs = (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
 const CGFloat fullscreenWebInset = 5.0;
 CGFloat inset = isFs ? fullscreenWebInset : kPlateInset;
 self.plateFromTop.constant = showStrip ? 0 : inset;
 self.plateLeading.constant = inset;
 self.plateTrailing.constant = -inset;
 self.plateBottom.constant = -inset;
 if(showStrip) {
  self.addWidth.constant=26;
  self.addButton.alphaValue=0.72;
  [self rebuildTabStrip];
 } else {
  self.tabStripWidth.constant=0;
  self.addWidth.constant=0;
  self.addButton.alphaValue=0;
 }
 [self applyPlateChrome];
 const BOOL hideToolbarDownload = (self.verticalTabs && width > 0);
 self.downloadButton.hidden = hideToolbarDownload;
 if(hideToolbarDownload) {
  self.downloadTrailingTitle.active = NO;
  self.downloadCenterTitle.active = NO;
  self.shieldsTrailingTitle.active = NO;
  self.shieldsTrailingNoDownload.active = YES;
 } else {
  self.shieldsTrailingNoDownload.active = NO;
  self.downloadTrailingTitle.active = YES;
  self.downloadCenterTitle.active = YES;
  self.shieldsTrailingTitle.active = YES;
 }
 self.spaceBadgeButton.hidden=!showStrip;
 if(showStrip) [self updateSpaceBadge];
 [self layoutTrafficLights];
 [self.window.contentView layoutSubtreeIfNeeded];
 [self.content layoutSubtreeIfNeeded];
 if(self.homePlateGradientLayer && !self.homePlateGradientLayer.hidden) {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.homePlateGradientLayer.frame = self.stage.bounds;
  [CATransaction commit];
 }
 if(self.chromeGradientLayer && !self.chromeGradientLayer.hidden) {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.chromeGradientLayer.frame = self.window.contentView.bounds;
  [CATransaction commit];
 }
 if(self.homeView && !self.homeView.hidden && self.homeBoard) {
  NSSize clip = self.homeView.bounds.size;
  if(clip.width > 8) {
   NSRect frame = self.homeBoard.frame;
   frame.origin = NSZeroPoint;
   frame.size.width = clip.width;
   frame.size.height = MAX(clip.height, NSHeight(frame));
   self.homeBoard.frame = frame;
   [self.homeBoard setNeedsLayout:YES];
   [self.homeBoard layoutSubtreeIfNeeded];
   [self.homeBoard setNeedsDisplay:YES];
  }
 }
 [self syncTabListColumnWidth];
 if(width>0 && self.tabList) [self.tabList reloadData];
 if(animate) {
  [CATransaction setCompletionBlock:^{
   self.chromeAnimating = NO;
   [self.window.contentView layoutSubtreeIfNeeded];
   [self.content layoutSubtreeIfNeeded];
   if(self.homePlateGradientLayer && !self.homePlateGradientLayer.hidden) {
    self.homePlateGradientLayer.frame = self.stage.bounds;
   }
   if(self.homeView && !self.homeView.hidden && self.homeBoard) {
    NSSize clip = self.homeView.bounds.size;
    if(clip.width > 8) {
     NSRect frame = self.homeBoard.frame;
     frame.origin = NSZeroPoint;
     frame.size.width = clip.width;
     frame.size.height = MAX(clip.height, NSHeight(frame));
     self.homeBoard.frame = frame;
     [self.homeBoard setNeedsLayout:YES];
     [self.homeBoard layoutSubtreeIfNeeded];
     [self.homeBoard setNeedsDisplay:YES];
    }
   }
   [self syncPageGeometry];
  }];
 } else {
  self.chromeAnimating = NO;
 }
 [self notifyBrowserGeometry];
 [CATransaction commit];
}
- (void)toggleVerticalTabs:(id)sender {
 if(self.quitting) return;
 self.verticalTabs=!self.verticalTabs;
 self.tabsCollapsed=NO;
 [self persistUiPrefs];
 self.verticalMenuItem.state=self.verticalTabs ? NSControlStateValueOn : NSControlStateValueOff;
 fprintf(stderr,"SLATE_TAB_LAYOUT vertical=%d collapsed=%d\n",self.verticalTabs?1:0,self.tabsCollapsed?1:0);
 [self applyTabLayout:NO];
}
- (void)toggleTabsReveal:(id)sender {
 if(self.quitting) return;
 self.tabsCollapsed=!self.tabsCollapsed;
 [self persistUiPrefs];
 fprintf(stderr,"SLATE_TAB_LAYOUT vertical=%d collapsed=%d\n",self.verticalTabs?1:0,self.tabsCollapsed?1:0);
 [self applyTabLayout:NO];
}
- (void)togglePages120Hz:(id)sender {
 if(self.quitting) return;
 self.pages120Hz=!self.pages120Hz;
 [SlateFrameRate setFast:self.pages120Hz];
 for(auto& [identifier, item] : runtimes) {
  if(item.engine) item.engine->set_high_refresh_rate(self.pages120Hz);
 }
 self.pages120HzMenuItem.state=self.pages120Hz ? NSControlStateValueOn : NSControlStateValueOff;
 [self persistUiPrefs];
 fprintf(stderr,"SLATE_FRAMERATE fast=%d\n", self.pages120Hz ? 1 : 0);
}
- (void)checkSidebarPeek {
 if(!self.verticalTabs || !self.tabsCollapsed || self.quitting) return;
 NSPoint loc = [NSEvent mouseLocation];
 NSRect windowRect = self.window.frame;
 CGFloat relX = loc.x - NSMinX(windowRect);
 CGFloat relY = loc.y - NSMinY(windowRect);
 const CGFloat topBarSafetyZone = 52.0;
 const BOOL inTopBar = (relY >= NSHeight(windowRect) - topBarSafetyZone);
 BOOL nearLeftEdge = !inTopBar && (relX >= -20 && relX <= 8) && (relY >= 0 && relY < NSHeight(windowRect) - topBarSafetyZone);
 if(self.sidebarPeeking) {
  CGFloat peekWidth = ClampSidebarWidth(self.sidebarUserWidth, NSWidth(windowRect));
  BOOL insideSidebar = (relX >= -30 && relX <= peekWidth + 20) && (relY >= -20 && relY <= NSHeight(windowRect) + 20);
  if(insideSidebar) {
   [self.peekDismissTimer invalidate];
   self.peekDismissTimer = nil;
  } else {
   if(!self.peekDismissTimer) {
    self.peekDismissTimer = [NSTimer scheduledTimerWithTimeInterval:0.4
     target:self selector:@selector(hideSidebarPeek) userInfo:nil repeats:NO];
   }
  }
 } else {
  if(nearLeftEdge && NSApp.isActive) {
   [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(revealSidebarPeek) object:nil];
   [self performSelector:@selector(revealSidebarPeek) withObject:nil afterDelay:0.15];
  } else {
   [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(revealSidebarPeek) object:nil];
  }
 }
}
- (void)revealSidebarPeek {
 self.sidebarPeeking = YES;
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
  context.duration = 0.2;
  context.allowsImplicitAnimation = YES;
  [self applyTabLayout:YES];
 } completionHandler:nil];
}
- (void)hideSidebarPeek {
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(revealSidebarPeek) object:nil];
 [self.peekDismissTimer invalidate];
 self.peekDismissTimer = nil;
 self.sidebarPeeking = NO;
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
  context.duration = 0.25;
  context.allowsImplicitAnimation = YES;
  [self applyTabLayout:YES];
 } completionHandler:nil];
}
- (void)placeWindowChrome {
 const BOOL revealed=![self tabsCollapsed];
 self.sidebarNavButton.toolTip=revealed ? @"Hide tabs" : @"Show tabs";
 NSColor* ink=self.barInk ?: NSColor.labelColor;
 self.sidebarNavButton.layer.backgroundColor=revealed ? [ink colorWithAlphaComponent:0.12].CGColor : NSColor.clearColor.CGColor;
 if(self.hideTabsMenuItem)
  self.hideTabsMenuItem.title=revealed ? @"Hide Tabs" : @"Show Tabs";
}
- (void)applyPlateChrome {
 const BOOL systemDark=[[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]]
  isEqualToString:NSAppearanceNameDarkAqua];
 const BOOL isDark=(self.themeMode==1) ? NO : ((self.themeMode==2) ? YES : systemDark);
 NSAppearance* targetAppearance=nil;
 if(self.themeMode==1) {
  targetAppearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
 } else if(self.themeMode==2) {
  targetAppearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
 }
 if(self.window.appearance!=targetAppearance) {
  self.window.appearance=targetAppearance;
 }
 NSColor* fill=ChromeAccent(self.accentId, self.accentHex, isDark);
 NSColor* plate=isDark ? ColorSRGB(0.11,0.11,0.12) : ColorSRGB(0.97,0.96,0.95);
 NSColor* bar=plate;
 const auto* tab=model.find(model.selected());
 const BOOL home=tab && tab->url=="about:blank";
 auto it=runtimes.find(model.selected());
 if(!home && it!=runtimes.end() && !it->second.theme_hex.empty()) {
  NSColor* site=ColorFromHex(Text(it->second.theme_hex));
  if(site) bar=site;
  self.barInk=InkOn(bar);
  self.barMuted=MutedInkOn(bar);
 } else {
  bar=[fill blendedColorWithFraction:isDark?0.35:0.20 ofColor:plate] ?: fill;
  self.barInk=isDark ? [NSColor colorWithCalibratedWhite:0.96 alpha:0.95] : [NSColor colorWithCalibratedWhite:0.11 alpha:0.92];
  self.barMuted=isDark ? [NSColor colorWithCalibratedWhite:0.96 alpha:0.60] : [NSColor colorWithCalibratedWhite:0.11 alpha:0.58];
 }
 if(home) {
  NSColor* srgb=[fill colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: fill;
  CGFloat hue=0, saturation=0, brightness=0, alpha=0;
  [srgb getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
  bar=isDark ? [NSColor colorWithHue:hue saturation:MIN(saturation*0.35,0.25) brightness:0.09 alpha:1.0] : fill;
  self.barInk=InkOn(bar);
  self.barMuted=MutedInkOn(bar);
 }
 const BOOL showStrip=[self stripRevealed];
 self.accentInk = ColorIsDark(fill) ? [NSColor colorWithCalibratedWhite:0.96 alpha:0.95] : [NSColor colorWithCalibratedWhite:0.11 alpha:0.92];
 self.accentMuted = ColorIsDark(fill) ? [NSColor colorWithCalibratedWhite:0.96 alpha:0.60] : [NSColor colorWithCalibratedWhite:0.11 alpha:0.58];
 const BOOL barChanged=!ColorsEqual(self.barColor, bar);
 static NSString* lastHex2 = @"";
 const BOOL hex2Changed = ![self.accentHex2 isEqualToString:lastHex2];
 lastHex2 = [self.accentHex2 copy];
 static BOOL lastHome = NO;
 const BOOL homeChanged = (home != lastHome);
 lastHome = home;
 static BOOL lastStrip = NO;
 const BOOL stripChanged = (showStrip != lastStrip);
 lastStrip = showStrip;
 const BOOL isFs = (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
 static BOOL lastFs = NO;
 const BOOL fsChanged = (isFs != lastFs);
 lastFs = isFs;
 const BOOL fillChanged=!self.window.backgroundColor || !ColorsEqual(self.window.backgroundColor, fill) || hex2Changed || homeChanged || stripChanged || fsChanged;
 self.barColor=bar;
 if(self.graniteIntensity<=0.005 || home) {
  self.graniteView.hidden=YES;
  self.toolbarGraniteView.hidden=YES;
 } else {
  self.graniteView.hidden=NO;
  self.graniteView.alphaValue=MIN(1.0, self.graniteIntensity*0.45);
  self.toolbarGraniteView.hidden=NO;
  self.toolbarGraniteView.alphaValue=MIN(1.0, self.graniteIntensity*0.35);
 }
 if(barChanged || fillChanged) {
  NSView* root=self.window.contentView;
  root.wantsLayer=YES;
  if(home) {
   // Keep the accent on the outer shell and the New Tab canvas inside the plate.
   NSColor* srgb = [fill colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: fill;
   CGFloat r = 0, g = 0, b = 0, a = 1;
   [srgb getRed:&r green:&g blue:&b alpha:&a];
   CGFloat hue = 0, sat = 0, bri = 0;
   [srgb getHue:&hue saturation:&sat brightness:&bri alpha:&a];

   if(!self.homePlateGradientLayer) {
    self.homePlateGradientLayer = [CAGradientLayer layer];
    self.homePlateGradientLayer.startPoint = CGPointMake(0.5, 0.0);
    self.homePlateGradientLayer.endPoint = CGPointMake(0.5, 1.0);
    [self.stage.layer insertSublayer:self.homePlateGradientLayer atIndex:0];
   }
   [CATransaction begin];
   [CATransaction setDisableActions:YES];
   self.chromeGradientLayer.hidden = YES;
   self.homePlateGradientLayer.hidden = NO;
   self.homePlateGradientLayer.frame = self.stage.bounds;
   if(isDark) {
    NSColor* cTop = bar;
    NSColor* cBottom = [NSColor colorWithHue:hue saturation:MIN(sat * 0.45, 0.30) brightness:0.04 alpha:1.0];
    self.homePlateGradientLayer.colors = @[ (id)cTop.CGColor, (id)cBottom.CGColor ];
    self.homePlateGradientLayer.locations = @[ @0.0, @1.0 ];
   } else {
    NSColor* cTop = bar;
    NSColor* cMid = [NSColor colorWithHue:hue saturation:MIN(sat * 0.40, 0.15) brightness:0.99 alpha:1.0];
    NSColor* cBottom = [NSColor colorWithHue:hue saturation:MIN(sat * 0.30, 0.12) brightness:0.97 alpha:1.0];
    self.homePlateGradientLayer.colors = @[ (id)cTop.CGColor, (id)cMid.CGColor, (id)cBottom.CGColor ];
    self.homePlateGradientLayer.locations = @[ @0.0, @0.38, @1.0 ];
   }
   [CATransaction commit];
   root.layer.backgroundColor = fill.CGColor;
   self.window.backgroundColor = fill;

   // The titlebar remains part of the colored shell; the toolbar is inside the plate.
   self.sidebar.layer.backgroundColor = NSColor.clearColor.CGColor;
   self.titlebar.wantsLayer = YES;
   self.titlebar.layer.backgroundColor = fill.CGColor;
   self.toolbar.wantsLayer = YES;
   self.toolbar.layer.backgroundColor = NSColor.clearColor.CGColor;
   if(!self.chromePlate.layer) self.chromePlate.wantsLayer = YES;
   self.chromePlate.layer.masksToBounds = NO;
   self.chromePlate.layer.shadowOpacity = 0;
   const BOOL isFs = (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
   const CGFloat fsRadius = 8.0;
   if(!self.stage.layer) self.stage.wantsLayer = YES;
   if(@available(macOS 11.0, *)) {
    self.stage.layer.cornerCurve = kCACornerCurveContinuous;
    self.content.layer.cornerCurve = kCACornerCurveContinuous;
   }
   self.stage.layer.cornerRadius = isFs ? fsRadius : kPlateRadius;
   self.stage.layer.masksToBounds = YES;
   self.stage.layer.backgroundColor = NSColor.clearColor.CGColor;
   self.stage.layer.borderWidth = 0;
   self.content.layer.backgroundColor = NSColor.clearColor.CGColor;
   self.content.layer.cornerRadius = isFs ? fsRadius : 0;
   self.content.layer.masksToBounds = YES;
   self.content.clipsToBounds = YES;
   for(auto& [identifier, item] : runtimes) {
    if(item.host) {
     if(@available(macOS 11.0, *)) item.host.layer.cornerCurve = kCACornerCurveContinuous;
     item.host.layer.cornerRadius = isFs ? fsRadius : 0;
     item.host.layer.masksToBounds = YES;
     item.host.clipsToBounds = YES;
    }
   }
   if(!self.bookmarksBar.layer) self.bookmarksBar.wantsLayer = YES;
   self.bookmarksBar.layer.backgroundColor = NSColor.clearColor.CGColor;
  } else {
   if(self.homePlateGradientLayer) self.homePlateGradientLayer.hidden = YES;
   // Both tab layouts use the same inset browser plate and page-colored chrome.
   NSColor* fill2 = (self.accentHex2.length > 0) ? (ColorFromHex(self.accentHex2) ?: fill) : fill;
   if(self.accentHex2.length > 0 && ![self.accentHex2 isEqualToString:self.accentHex]) {
    if(!self.chromeGradientLayer) {
     self.chromeGradientLayer = [CAGradientLayer layer];
     self.chromeGradientLayer.startPoint = CGPointMake(0.0, 0.0);
     self.chromeGradientLayer.endPoint = CGPointMake(1.0, 1.0);
     [root.layer insertSublayer:self.chromeGradientLayer atIndex:0];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.chromeGradientLayer.hidden = NO;
    self.chromeGradientLayer.frame = root.bounds;
    self.chromeGradientLayer.colors = @[ (id)fill2.CGColor, (id)fill.CGColor ];
    self.chromeGradientLayer.locations = nil;
    [CATransaction commit];
    root.layer.backgroundColor = NSColor.clearColor.CGColor;
   } else {
    if(self.chromeGradientLayer) {
     self.chromeGradientLayer.hidden = YES;
    }
    root.layer.backgroundColor = fill.CGColor;
   }
   self.window.backgroundColor = fill;

   self.sidebar.layer.backgroundColor = NSColor.clearColor.CGColor;
   self.titlebar.wantsLayer = YES;
   self.titlebar.layer.backgroundColor = showStrip ? fill.CGColor : bar.CGColor;
   self.toolbar.wantsLayer = YES;
   self.toolbar.layer.backgroundColor = bar.CGColor;
   if(!self.chromePlate.layer) self.chromePlate.wantsLayer = YES;
   self.chromePlate.layer.masksToBounds = NO;
   const BOOL isFs = (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
   const CGFloat fsRadius = 8.0;
   self.chromePlate.layer.shadowColor = NSColor.blackColor.CGColor;
   self.chromePlate.layer.shadowOpacity = (showStrip || isFs) ? 0 : (isDark ? 0.18 : 0.08);
   self.chromePlate.layer.shadowRadius = 8;
   self.chromePlate.layer.shadowOffset = NSMakeSize(0,-1);
   if(!self.stage.layer) self.stage.wantsLayer = YES;
   if(@available(macOS 11.0, *)) {
    self.stage.layer.cornerCurve = kCACornerCurveContinuous;
    self.content.layer.cornerCurve = kCACornerCurveContinuous;
   }
   self.stage.layer.cornerRadius = isFs ? fsRadius : kPlateRadius;
   self.stage.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
   self.stage.layer.masksToBounds = YES;
   self.stage.layer.backgroundColor = bar.CGColor;
   self.stage.layer.borderWidth = (showStrip || isFs) ? 0 : 1;
   self.stage.layer.borderColor = [InkOn(bar) colorWithAlphaComponent:ColorIsDark(bar)?0.10:0.06].CGColor;
   self.content.layer.backgroundColor = bar.CGColor;
   self.content.layer.cornerRadius = isFs ? fsRadius : 0;
   self.content.layer.masksToBounds = YES;
   self.content.clipsToBounds = YES;
   for(auto& [identifier, item] : runtimes) {
    if(item.host) {
     if(@available(macOS 11.0, *)) item.host.layer.cornerCurve = kCACornerCurveContinuous;
     item.host.layer.cornerRadius = isFs ? fsRadius : 0;
     item.host.layer.masksToBounds = YES;
     item.host.clipsToBounds = YES;
    }
   }
   if(!self.bookmarksBar.layer) self.bookmarksBar.wantsLayer = YES;
   self.bookmarksBar.layer.backgroundColor = bar.CGColor;
  }
  for(NSView* b in self.bookmarksStack.arrangedSubviews) {
   if([b isKindOfClass:NSButton.class]) {
    NSButton* btn=(NSButton*)b;
    btn.contentTintColor=self.barInk ?: NSColor.labelColor;
    if(btn.attributedTitle.length>0) {
     NSMutableAttributedString* mas=[btn.attributedTitle mutableCopy];
     [mas addAttribute:NSForegroundColorAttributeName value:(self.barInk ?: NSColor.labelColor) range:NSMakeRange(0, mas.length)];
     btn.attributedTitle=mas;
    }
   }
  }
 }
 if([self stripRevealed]) [self paintTabStripAnimated:NO];
 [self applyChromeInk];
 if(self.homeBoard) {
  self.homeBoard.wash=fill;
  self.homeBoard.appearance=isDark
   ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]
   : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
  self.homeBoard.omniboxCard.accentColor=fill;
  self.homeBoard.omniboxCard.inkColor=isDark ? [NSColor colorWithCalibratedWhite:0.96 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
  self.homeBoard.omniboxCard.isDarkTheme=isDark;
  [self.homeBoard.omniboxCard applyTheme];
  [self.homeBoard setNeedsDisplay:YES];
 }
 NSColor* webBg = isDark ? ColorSRGB(0.11,0.11,0.12) : ColorSRGB(0.97,0.96,0.95);
 for(auto& [identifier, item] : runtimes) {
  if(item.host) {
   item.host.wantsLayer = YES;
   item.host.layer.backgroundColor = webBg.CGColor;
   for(NSView* sub in item.host.subviews) {
    if([sub isKindOfClass:WKWebView.class]) {
     WKWebView* wv = (WKWebView*)sub;
     if(@available(macOS 12.0, *)) {
      wv.underPageBackgroundColor = webBg;
     }
     wv.wantsLayer = YES;
     wv.layer.backgroundColor = webBg.CGColor;
    }
   }
  }
 }
 if(home && !self.homeView.hidden) {
  if(barChanged || fillChanged) self.homeSignature=nil;
  [self rebuildHome];
 }
}
- (void)applyChromeInk {
 NSColor* ink=self.barInk ?: NSColor.labelColor;
 NSColor* muted=self.barMuted ?: NSColor.secondaryLabelColor;
 NSColor* sideInk=self.accentInk ?: ink;
 NSColor* sideMuted=self.accentMuted ?: muted;
 self.address.textColor=ink;
 self.address.placeholderAttributedString=[[NSAttributedString alloc] initWithString:@"Search Google or enter address"
  attributes:@{NSForegroundColorAttributeName:muted, NSFontAttributeName:[NSFont systemFontOfSize:13]}];
 if([self.omnibox isKindOfClass:SlateOmnibox.class]) {
  ((SlateOmnibox*)self.omnibox).barColor=self.barColor;
  [(SlateOmnibox*)self.omnibox applyContrast];
 }
 SlateNavButton* navButtons[] = {self.sidebarNavButton, self.backButton, self.forwardButton, self.reloadButton};
 for(SlateNavButton* button : navButtons) {
  if(!button) continue;
  button.hoverInk=ink;
  button.glyph.contentTintColor=button.enabled ? ink : muted;
 }
 self.extensionsButton.contentTintColor=ink;
 self.shieldsButton.contentTintColor=ink;
 self.bookmarkButton.contentTintColor=ink;
 self.downloadButton.barInk=ink;
 self.downloadButton.barMuted=muted;
 self.downloadButton.accentInk=self.accentInk;
 [self.downloadButton setNeedsDisplay:YES];
 [SlateDownloadsPanel sharedPanel].barColor=self.barColor;
 [SlateDownloadsPanel sharedPanel].barInk=ink;
 [SlateDownloadsPanel sharedPanel].barMuted=muted;
 [SlateDownloadsPanel sharedPanel].accentInk=self.accentInk;
 NSColor* tabInk=sideInk;
 self.addButton.contentTintColor=tabInk;
 if([self.addButton isKindOfClass:SlateAddTabButton.class]) ((SlateAddTabButton*)self.addButton).hoverInk=tabInk;
 self.sidebarAdd.contentTintColor=sideInk;
 const BOOL rail=[self sidebarIconRail];
 const BOOL railChanged=!self.addChromeInited || self.lastAddRail!=rail;
 self.addChromeInited=YES;
 self.lastAddRail=rail;
 self.sidebarAdd.imagePosition=rail ? NSImageOnly : NSImageLeading;
 self.sidebarAdd.toolTip=@"New tab (⌘T)";
 if(railChanged) {
  self.sidebarAddLeading.constant=rail ? 0 : 18;
  self.sidebarAddLeading.priority=rail ? NSLayoutPriorityDefaultLow : NSLayoutPriorityRequired;
  if(self.tabListLeading) self.tabListLeading.constant=rail ? 0 : 6;
  if(self.tabListTrailing) self.tabListTrailing.constant=rail ? 0 : -6;
  if(self.sidebarHeaderHeight) [self layoutTrafficLights];
  if(self.sidebarAddHeight) self.sidebarAddHeight.constant=rail ? kRailBubble : 28;
  if(self.sidebarAddWidth) self.sidebarAddWidth.active=rail;
  if(self.navLeadingTitle) self.navLeadingTitle.constant=16;
  self.sidebarAdd.wantsLayer=YES;
  self.sidebarAdd.layer.cornerRadius=rail ? 10 : 8;
  self.sidebarAdd.layer.masksToBounds=YES;
  self.sidebarAdd.imageScaling=NSImageScaleProportionallyDown;
  NSImage* plus=nil;
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg=[NSImageSymbolConfiguration configurationWithPointSize:rail ? 13 : 11 weight:NSFontWeightMedium];
   plus=[[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"New tab"] imageWithSymbolConfiguration:cfg];
  }
  if(!plus) {
   plus=[NSImage imageNamed:@"TabIconTemplate"];
   plus.size=NSMakeSize(rail?14:12, rail?14:12);
  }
  self.sidebarAdd.image=plus;
  self.tabList.rowHeight=rail ? kRailRow : 28;
  self.tabList.intercellSpacing=NSMakeSize(0,2);
  self.sideRowsGen++;
 }
 self.sidebarAdd.layer.backgroundColor=rail ? [sideInk colorWithAlphaComponent:0.10].CGColor : nil;
 if(rail) {
  if(self.sidebarAdd.title.length) self.sidebarAdd.title=@"";
 } else if(railChanged) {
  self.sidebarAdd.attributedTitle=[[NSAttributedString alloc] initWithString:@"New Tab"
   attributes:@{NSForegroundColorAttributeName:sideMuted,
                NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightRegular]}];
 }
 [self updateNavChrome];
 [self updateShieldsChrome];
 if(self.sidebarFoot) [self.sidebarFoot updateDoors];
 if(self.pinnedGrid) [self.pinnedGrid updateLayoutForWidth:self.sidebarUserWidth];
 if([self.resizeHandle isKindOfClass:SlateResizeHandle.class]) {
  [(SlateResizeHandle*)self.resizeHandle updateHairline];
 }
 static NSColor* lastBarInk;
 static NSColor* lastAccentInk;
 const BOOL stripInkChanged=!ColorsEqual(lastBarInk,self.barInk);
 const BOOL sideInkChanged=!ColorsEqual(lastAccentInk,self.accentInk);
 lastBarInk=self.barInk;
 lastAccentInk=self.accentInk;
 if(stripInkChanged && [self stripRevealed]) [self paintTabStripAnimated:NO];
 if(sideInkChanged && [self sidebarRevealed] && self.tabList) [self.tabList reloadData];
}
- (void)persistUiPrefs {
 NSMutableArray* splitGroups=[NSMutableArray array];
 for(const auto& pair:workspace.pairs()) [splitGroups addObject:@{
  @"left":@(pair.left), @"right":@(pair.right), @"ratio":@(pair.ratio),
  @"active_right":@(pair.active==slate::SplitSide::Right)
 }];
 NSMutableDictionary* root=[NSMutableDictionary dictionaryWithDictionary:@{
  @"version":@1,
  @"vertical_tabs":@(self.verticalTabs),
  @"tabs_collapsed":@(self.tabsCollapsed),
  @"sidebar_width":@(ClampSidebarWidth(self.sidebarUserWidth, 1200)),
  @"accent":self.accentId ?: @"rose",
  @"page_zoom":@(self.zoomPercent),
  @"show_bookmarks_bar":@(self.showBookmarksBar),
  @"granite_intensity":@(self.graniteIntensity),
  @"theme_mode":@(self.themeMode),
  @"pages_120hz":@(self.pages120Hz),
  @"tab_style":@(self.tabStyle),
  @"split_left":@(workspace.split() ? workspace.left : 0),
  @"split_right":@(workspace.split() ? workspace.right : 0),
  @"split_ratio":@(workspace.ratio),
  @"split_active_right":@(workspace.active==slate::SplitSide::Right),
  @"split_groups":splitGroups
 }];
 if(self.accentHex.length) root[@"accent_hex"]=self.accentHex;
 if(self.accentHex2.length) root[@"accent_hex2"]=self.accentHex2;
 NSData* data=[NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
 [[NSFileManager defaultManager] createDirectoryAtPath:DataDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
 [data writeToFile:PrefsPath() options:NSDataWritingAtomic error:nil];
}
- (void)setTrafficLightsHidden:(BOOL)hidden {
 self.trafficCluster.hidden=hidden;
 for(NSWindowButton kind : {NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton}) {
  NSButton* button=[self.window standardWindowButton:kind];
  button.hidden=hidden;
  button.alphaValue=hidden ? 0 : 1;
 }
}
- (NSInteger)trafficLayoutMode {
 if([self stripRevealed]) return 1;
 if(self.verticalTabs && [self sidebarLayoutWidth] > 0) return 2;
 return 3;
}
- (void)layoutTrafficLights {
 if(!self.window || self.quitting || !self.window.contentView) return;
 NSView* root=self.window.contentView;
 const BOOL fullScreen=(self.window.styleMask & NSWindowStyleMaskFullScreen)!=0;
 self.trafficCluster.hidden=!fullScreen;
 if(fullScreen) {
  const CGFloat top=[self stripRevealed] ? (kTitlebarHeight-18)/2 :
   [self sidebarRevealed] ? 14 : 5+(kToolbarHeight-18)/2;
  if(fabs(self.trafficTop.constant-top)>0.5) self.trafficTop.constant=top;
  for(NSButton* button in self.fullScreenTrafficButtons)
   button.enabled=button.action!=@selector(performMiniaturize:) && !self.window.attachedSheet;
 }
 CGFloat rightEdge=0;
 CGFloat bottomFromTop=0;
 if(fullScreen) {
  [root layoutSubtreeIfNeeded];
  NSRect controls=[self.trafficCluster convertRect:self.trafficCluster.bounds toView:root];
  rightEdge=NSMaxX(controls);
  bottomFromTop=NSMaxY(root.bounds)-NSMinY(controls);
 } else {
  for(NSWindowButton kind : {NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton}) {
   NSButton* button=[self.window standardWindowButton:kind];
   if(!button || !button.superview || button.hidden || button.hiddenOrHasHiddenAncestor || button.alphaValue<=0) continue;
   NSRect buttonInRoot=[button.superview convertRect:button.frame toView:root];
   rightEdge=MAX(rightEdge, NSMaxX(buttonInRoot));
   bottomFromTop=MAX(bottomFromTop, NSMaxY(root.bounds)-NSMinY(buttonInRoot));
  }
 }
 // Only the browser plate and sidebar items avoid the native controls. The
 // sidebar background remains continuous behind the titlebar.
 if(self.plateFromTraffic) {
  CGFloat safeLeading=rightEdge>0 ? ceil(rightEdge+16) : 0;
  if(fabs(self.plateFromTraffic.constant-safeLeading)>0.5) self.plateFromTraffic.constant=safeLeading;
  self.plateFromTraffic.active=(![self stripRevealed] && ![self sidebarRevealed] && rightEdge>0);
  if(self.verticalTabs && [self sidebarRevealed] && self.sidebarWidth) {
   CGFloat railWidth=[self sidebarLayoutWidth];
   if(fabs(self.sidebarWidth.constant-railWidth)>0.5) {
   self.sidebarWidth.constant=railWidth;
   [self.pinnedGrid updateLayoutForWidth:railWidth];
    [root layoutSubtreeIfNeeded];
    [self syncTabListColumnWidth];
    [self.tabList reloadData];
   }
  }
 }
 if(self.sidebarHeaderHeight) {
  CGFloat safeHeight=(self.verticalTabs && [self sidebarLayoutWidth]>0 && bottomFromTop>0)
    ? ceil(bottomFromTop+22) : kSidebarHeaderHeight;
  safeHeight=MAX(kSidebarHeaderHeight,safeHeight);
  if(fabs(self.sidebarHeaderHeight.constant-safeHeight)>0.5) self.sidebarHeaderHeight.constant=safeHeight;
 }
 if(self.navLeadingTitle)
  self.navLeadingTitle.constant=(!fullScreen && [self trafficLayoutMode]==3 ? 88 : 16);
}
- (void)windowDidUpdate:(NSNotification*)notification {
 if(notification.object!=self.window || self.quitting) return;
 [self layoutTrafficLights];
}
- (void)applyPageZoom {
 const double level=ZoomLevelForPercent(self.zoomPercent);
 for(auto& [identifier,item]:runtimes) if(item.engine) item.engine->set_zoom(level);
 [self updateZoomMenu];
 [[SlateSiteCardPanel sharedPanel] updateZoomPercent:self.zoomPercent];
}
- (void)zoomIn:(id)sender {
 self.zoomPercent=NextZoomPercent(self.zoomPercent, 1);
 [self persistUiPrefs];
 [self applyPageZoom];
}
- (void)zoomOut:(id)sender {
 self.zoomPercent=NextZoomPercent(self.zoomPercent, -1);
 [self persistUiPrefs];
 [self applyPageZoom];
}
- (void)resetZoom:(id)sender {
 self.zoomPercent=100;
 [self persistUiPrefs];
 [self applyPageZoom];
}
- (void)updateZoomMenu {
 if(!self.zoomMenuItem) return;
 self.zoomMenuItem.title=[NSString stringWithFormat:@"Page Zoom (%d%%)", self.zoomPercent];
}
- (void)applyTabStyle {
 self.tabPills.spacing = (self.tabStyle == 1) ? 3.0 : 8.0;
 [self rebuildTabStrip];
 [self paintTabStripAnimated:NO];
}
- (void)selectPillTabStyle:(id)sender {
 (void)sender;
 self.tabStyle = 0;
 [self applyTabStyle];
 [self persistUiPrefs];
}
- (void)selectRegularTabStyle:(id)sender {
 (void)sender;
 self.tabStyle = 1;
 [self applyTabStyle];
 [self persistUiPrefs];
}
- (void)setAccent:(id)sender {
 NSString* ident=[sender isKindOfClass:NSMenuItem.class] ? ((NSMenuItem*)sender).representedObject : nil;
 if(![ident isKindOfClass:NSString.class] || !ident.length) return;
 self.accentId=ident;
 if(![ident isEqualToString:@"custom"]) self.accentHex=@"";
 [self persistUiPrefs];
 [self applyPlateChrome];
 [self rebuildAccentMenu];
}
- (void)chooseCustomAccent:(id)sender {
 [[SlateSettingsPanel sharedPanel] showForSlateDelegate:self selectedPage:@"appearance"];
}
- (void)customAccentChanged:(NSColorPanel*)panel {
 self.accentId=@"custom";
 self.accentHex=HexFromColor(panel.color);
 [self persistUiPrefs];
 [self applyPlateChrome];
 [self rebuildAccentMenu];
 [[SlateThemePanel sharedPanel] updateFromDelegate];
}
- (void)rebuildAccentMenu {
 if(!self.accentMenu) return;
 const BOOL dark=[[self.window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]]
  isEqualToString:NSAppearanceNameDarkAqua];
 for(NSMenuItem* item in self.accentMenu.itemArray) {
  NSString* ident=item.representedObject;
  if(![ident isKindOfClass:NSString.class]) continue;
  item.state=[ident isEqualToString:self.accentId] ? NSControlStateValueOn : NSControlStateValueOff;
  NSString* hex=[ident isEqualToString:@"custom"] ? self.accentHex : @"";
  item.image=AccentSwatch(ChromeAccent(ident, hex, dark));
 }
}
- (BOOL)tabIsAudible:(TabId)identifier {
 auto it=runtimes.find(identifier);
 return it!=runtimes.end() && it->second.audible;
}
- (BOOL)tabIsMuted:(TabId)identifier {
 return [self.mutedTabIds containsObject:@(identifier)];
}
- (BOOL)tabHasAudioState:(TabId)identifier {
 return [self tabIsAudible:identifier] || [self tabIsMuted:identifier];
}
- (void)toggleTabMute:(TabId)identifier {
 if(!identifier) return;
 if(!self.mutedTabIds) self.mutedTabIds = [NSMutableSet set];
 const BOOL isMuted = [self.mutedTabIds containsObject:@(identifier)];
 if(isMuted) {
  [self.mutedTabIds removeObject:@(identifier)];
 } else {
  [self.mutedTabIds addObject:@(identifier)];
 }
 auto it = runtimes.find(identifier);
 if(it != runtimes.end() && it->second.engine) {
  const std::string js = isMuted
   ? "document.querySelectorAll('video, audio').forEach(function(el){ el.muted = false; });"
   : "document.querySelectorAll('video, audio').forEach(function(el){ el.muted = true; });";
  it->second.engine->execute_script(js);
 }
 [self refresh];
}
- (void)closeTabWithId:(TabId)identifier {
 if(!self.quitting && identifier) [self beginClose:identifier reason:slate::CloseReason::Remove];
}

- (void)unloadTabWithId:(TabId)identifier {
 if(self.quitting || !identifier || !model.live(identifier) || model.closing(identifier) || model.find(identifier)->protected_content) return;
 NSAlert* alert=[[NSAlert alloc] init]; alert.messageText=@"Unload this tab?";
 alert.informativeText=@"The address and title stay in your tab list. Form entries, scrolling, playback and page history may be lost. Restoring reloads the page.";
 [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Unload"];
 [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
  if(response==NSAlertSecondButtonReturn && !self.quitting) [self beginClose:identifier reason:slate::CloseReason::Discard];
 }];
}

- (void)unloadTabMenuItem:(id)sender {
 if([sender isKindOfClass:NSMenuItem.class]) {
  TabId tid = (TabId)[((NSMenuItem*)sender).representedObject unsignedLongLongValue];
  if(tid) [self unloadTabWithId:tid];
 }
}
- (void)togglePinTabItem:(id)sender {
 if([sender isKindOfClass:NSMenuItem.class]) {
  TabId tid = (TabId)[((NSMenuItem*)sender).representedObject unsignedLongLongValue];
  const auto* tab = model.find(tid);
  if(tab) {
   model.pin(tid, !tab->pinned);
   [self refresh];
   [self scheduleSave];
  }
 }
}
- (void)toggleProtectionTabItem:(id)sender {
 if([sender isKindOfClass:NSMenuItem.class]) {
  TabId tid = (TabId)[((NSMenuItem*)sender).representedObject unsignedLongLongValue];
  const auto* tab = model.find(tid);
  if(tab) {
   model.protect(tid, !tab->protected_content);
   [self refresh];
   [self scheduleSave];
  }
 }
}
- (void)toggleTabMuteItem:(id)sender {
 if([sender isKindOfClass:NSMenuItem.class]) {
  TabId tid = (TabId)[((NSMenuItem*)sender).representedObject unsignedLongLongValue];
  if(tid) [self toggleTabMute:tid];
 }
}
- (void)closeTabMenuItem:(id)sender {
 if([sender isKindOfClass:NSMenuItem.class]) {
  TabId tid = (TabId)[((NSMenuItem*)sender).representedObject unsignedLongLongValue];
  if(tid) [self closeTabWithId:tid];
 }
}
- (NSMenu*)tabMenuForTab:(TabId)identifier {
 const auto* tab = model.find(identifier);
 NSMenu* menu = [[NSMenu alloc] init];
 NSMenuItem* siteInfo = [menu addItemWithTitle:@"Site Information…" action:@selector(showSiteCard:) keyEquivalent:@"i"];
 siteInfo.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 siteInfo.target = self; siteInfo.representedObject = @(identifier);
 NSMenuItem* pin = [menu addItemWithTitle:(tab && tab->pinned) ? @"Unpin Tab" : @"Pin Tab" action:@selector(togglePinTabItem:) keyEquivalent:@""];
 pin.target = self; pin.representedObject = @(identifier);
 NSMenuItem* keep = [menu addItemWithTitle:@"Keep loaded" action:@selector(toggleProtectionTabItem:) keyEquivalent:@""];
 keep.target = self; keep.representedObject = @(identifier);
 keep.state = tab && tab->protected_content ? NSControlStateValueOn : NSControlStateValueOff;
 if([self tabIsMuted:identifier]) {
  NSMenuItem* mute = [menu addItemWithTitle:@"Unmute Tab" action:@selector(toggleTabMuteItem:) keyEquivalent:@""];
  mute.target = self; mute.representedObject = @(identifier);
 } else if([self tabIsAudible:identifier]) {
  NSMenuItem* mute = [menu addItemWithTitle:@"Mute Tab" action:@selector(toggleTabMuteItem:) keyEquivalent:@""];
  mute.target = self; mute.representedObject = @(identifier);
 }
 [menu addItem:[NSMenuItem separatorItem]];
 if(!workspace.member(identifier)) {
  NSMenuItem* left=[menu addItemWithTitle:@"Open in New Left Split"
   action:@selector(splitTabFromMenu:) keyEquivalent:@""];
  left.target=self; left.representedObject=@(identifier); left.tag=0;
  NSMenuItem* right=[menu addItemWithTitle:@"Open in New Right Split"
   action:@selector(splitTabFromMenu:) keyEquivalent:@""];
  right.target=self; right.representedObject=@(identifier); right.tag=1;
 }
 if(workspace.member(identifier)) {
  NSMenuItem* swap=[menu addItemWithTitle:@"Swap Split Sides" action:@selector(swapSplitSides:) keyEquivalent:@""];
  swap.target=self; swap.representedObject=@(identifier);
  NSMenuItem* exit=[menu addItemWithTitle:@"Exit Split View" action:@selector(exitSplitView:) keyEquivalent:@""];
  exit.target=self; exit.representedObject=@(identifier);
 }
 [menu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* newTabItem = [menu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
 newTabItem.target = self;
 NSMenuItem* reopen = [menu addItemWithTitle:@"Reopen Closed Tab" action:@selector(reopenClosedTab:) keyEquivalent:@"T"];
 reopen.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 reopen.target = self;
 reopen.enabled = (self.recentlyClosedUrls.count > 0);
 [menu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* unload = [menu addItemWithTitle:@"Unload Tab…" action:@selector(unloadTabMenuItem:) keyEquivalent:@""];
 unload.target = self; unload.representedObject = @(identifier);
 NSMenuItem* close = [menu addItemWithTitle:@"Close Tab" action:@selector(closeTabMenuItem:) keyEquivalent:@"w"];
 close.target = self; close.representedObject = @(identifier);
 return menu;
}
- (void)switchSpaceToId:(NSString*)newSpaceId {
 [self reattachAllDetachedTabs];
 if(!newSpaceId.length) return;
 if(!self.spacesManager) return;
 if([newSpaceId isEqualToString:self.spacesManager.currentSpaceId]) return;
 workspace.clear_all();
 self.displayedSplitLeft=0;
 self.displayedSplitRight=0;
 [self persistUiPrefs];

 NSString* oldSpaceId = self.spacesManager.currentSpaceId;

 // Step 1: In outgoing space, pause media and park tabs
 for(auto& [identifier, item] : runtimes) {
  if(item.engine) {
   item.engine->execute_script("document.querySelectorAll('video, audio').forEach(function(el){ el.pause(); });");
   item.engine->blur();
   item.engine->set_occluded(YES);
  }
  if(item.host) item.host.hidden = YES;
 }

 NSMutableArray* parked = [NSMutableArray array];
 for(const auto& t : model.tabs()) {
  if(t.incognito) continue;
  NSMutableDictionary* d = [NSMutableDictionary dictionary];
  d[@"id"] = @(t.id);
  d[@"url"] = Text(t.url);
  d[@"title"] = Text(t.title);
  d[@"pinned"] = @(t.pinned);
  d[@"protected"] = @(t.protected_content);
  d[@"selected"] = @(t.selected);
  if(!t.group_id.empty()) d[@"group"] = Text(t.group_id);
  [parked addObject:d];
 }
 self.spacesManager.parkedTabs[oldSpaceId] = parked;

 // Close runtimes from outgoing space
 for(auto& [identifier, item] : runtimes) {
  if(item.engine) item.engine->close();
  [item.host removeFromSuperview];
 }
 runtimes.clear();
 [self.tabIcons removeAllObjects];

 // Step 2: Set current space ID
 self.spacesManager.currentSpaceId = newSpaceId;
 [self.spacesManager saveSpaces];

 // Step 3: Load incoming space tabs into model
 model = slate::TabModel();
 NSArray* incoming = self.spacesManager.parkedTabs[newSpaceId];
 TabId selectedId = 0;
 if(incoming && incoming.count > 0) {
  for(NSDictionary* d in incoming) {
   NSString* u = d[@"url"] ?: @"about:blank";
   TabId tid = model.add(u.UTF8String);
   NSString* tit = d[@"title"];
   if(tit.length) model.update(tid, {}, tit.UTF8String);
   if([d[@"pinned"] boolValue]) model.pin(tid, true);
   if([d[@"protected"] boolValue]) model.protect(tid, true);
   if(d[@"group"]) model.set_tab_group(tid, [d[@"group"] UTF8String]);
   if([d[@"selected"] boolValue]) selectedId = tid;
  }
  if(!selectedId && !model.tabs().empty()) selectedId = model.tabs().front().id;
 } else {
  selectedId = model.add("about:blank");
 }

 if(selectedId) model.select(selectedId);
 // Tab IDs are local to a space. Never carry a split pair into another model.
 workspace.clear_all();
 self.displayedSplitLeft=0;
 self.displayedSplitRight=0;

 // Step 4: Update custom downloads directory for new space
 SlateSpace* curSpace = self.spacesManager.currentSpace;
 if(curSpace && curSpace.downloads.length) {
  [SlateDownloadManager sharedManager].downloadsDirectory = curSpace.downloads;
 } else {
  NSString* envDown = NSProcessInfo.processInfo.environment[@"SLATE_DOWNLOADS_DIR"];
  if(envDown.length && envDown.isAbsolutePath) {
   [SlateDownloadManager sharedManager].downloadsDirectory = envDown;
  } else {
   [SlateDownloadManager sharedManager].downloadsDirectory = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES).firstObject;
  }
 }

 // Step 5: Update chrome
 [self.sidebarFoot updateDoors];
 [self rebuildSpacesMenu];
 [self updateSpaceBadge];
 [self activateTab:model.selected()];
 [self refresh];
 [self scheduleSave];
}

- (void)switchSpaceAtIndex:(NSInteger)index {
 if(index >= 0 && index < (NSInteger)self.spacesManager.spaces.count) {
  [self switchSpaceToId:self.spacesManager.spaces[index].identifier];
 }
}

- (void)switchNextSpace {
 NSInteger cur = [self.spacesManager indexOfSpace:self.spacesManager.currentSpaceId];
 if(cur != NSNotFound) {
  if(cur + 1 < (NSInteger)self.spacesManager.spaces.count) {
   [self switchSpaceToId:self.spacesManager.spaces[cur + 1].identifier];
  } else {
   [self askNewSpace:nil];
  }
 }
}

- (void)switchPreviousSpace {
 NSInteger cur = [self.spacesManager indexOfSpace:self.spacesManager.currentSpaceId];
 if(cur != NSNotFound && cur > 0) {
  [self switchSpaceToId:self.spacesManager.spaces[cur - 1].identifier];
 }
}

- (void)selectSpaceItem:(NSMenuItem*)sender {
 if([sender isKindOfClass:NSMenuItem.class]) {
  NSString* sId = sender.representedObject;
  if([sId isKindOfClass:NSString.class]) {
   [self switchSpaceToId:sId];
  }
 }
}

- (void)rebuildSpacesMenu {
 if(!self.spacesMenu) return;
 [self.spacesMenu removeAllItems];
 NSArray<SlateSpace*>* spaces = self.spacesManager.spaces;
 NSString* curId = self.spacesManager.currentSpaceId;
 for(NSInteger i = 0; i < (NSInteger)spaces.count; ++i) {
  SlateSpace* s = spaces[i];
  NSString* key = (i < 9) ? [NSString stringWithFormat:@"%ld", (long)(i + 1)] : @"";
  NSMenuItem* item = [self.spacesMenu addItemWithTitle:s.name action:@selector(selectSpaceItem:) keyEquivalent:key];
  item.target = self;
  item.representedObject = s.identifier;
  if(key.length) item.keyEquivalentModifierMask = NSEventModifierFlagControl;
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium];
   item.image = [[NSImage imageWithSystemSymbolName:s.symbol accessibilityDescription:s.name] imageWithSymbolConfiguration:cfg];
  }
  item.state = [s.identifier isEqualToString:curId] ? NSControlStateValueOn : NSControlStateValueOff;
 }
 [self.spacesMenu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* nextSp = [self.spacesMenu addItemWithTitle:@"Next Space" action:@selector(switchNextSpace) keyEquivalent:@"}"];
 nextSp.keyEquivalentModifierMask = NSEventModifierFlagControl;
 nextSp.target = self;
 NSMenuItem* prevSp = [self.spacesMenu addItemWithTitle:@"Previous Space" action:@selector(switchPreviousSpace) keyEquivalent:@"{"];
 prevSp.keyEquivalentModifierMask = NSEventModifierFlagControl;
 prevSp.target = self;
 [self.spacesMenu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* newSp = [self.spacesMenu addItemWithTitle:@"New Space…" action:@selector(askNewSpace:) keyEquivalent:@"n"];
 newSp.keyEquivalentModifierMask = NSEventModifierFlagControl;
 newSp.target = self;
}

- (void)showSpaceMenuForButton:(NSView*)button {
 NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Spaces"];
 NSArray<SlateSpace*>* spaces = self.spacesManager.spaces;
 NSString* curId = self.spacesManager.currentSpaceId;

 for(NSInteger i = 0; i < (NSInteger)spaces.count; ++i) {
  SlateSpace* s = spaces[i];
  NSString* key = (i < 9) ? [NSString stringWithFormat:@"%ld", (long)(i + 1)] : @"";
  NSMenuItem* item = [menu addItemWithTitle:s.name action:@selector(selectSpaceItem:) keyEquivalent:key];
  item.target = self;
  item.representedObject = s.identifier;
  if(key.length) item.keyEquivalentModifierMask = NSEventModifierFlagControl;
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium];
   item.image = [[NSImage imageWithSystemSymbolName:s.symbol accessibilityDescription:s.name] imageWithSymbolConfiguration:cfg];
  }
  item.state = [s.identifier isEqualToString:curId] ? NSControlStateValueOn : NSControlStateValueOff;
 }

 [menu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* newItem = [menu addItemWithTitle:@"New Space…" action:@selector(askNewSpace:) keyEquivalent:@""];
 newItem.target = self;

 [menu addItem:[NSMenuItem separatorItem]];
 SlateSpace* cur = self.spacesManager.currentSpace;
 if(cur) {
  NSString* renTitle = [NSString stringWithFormat:@"Rename “%@”…", cur.name];
  NSMenuItem* renItem = [menu addItemWithTitle:renTitle action:@selector(renameCurrentSpace:) keyEquivalent:@""];
  renItem.target = self;

  NSMenu* iconSub = [[NSMenu alloc] initWithTitle:@"Icon"];
  NSArray<NSString*>* icons = [SlateSpacesManager availableIcons];
  NSArray<NSString*>* iconNames = [SlateSpacesManager availableIconNames];
  for(NSUInteger i = 0; i < icons.count; ++i) {
   NSString* sym = icons[i];
   NSString* symName = (i < iconNames.count) ? iconNames[i] : sym;
   NSMenuItem* iItem = [iconSub addItemWithTitle:symName action:@selector(selectSpaceIconItem:) keyEquivalent:@""];
   iItem.target = self;
   iItem.representedObject = sym;
   if(@available(macOS 11.0, *)) {
    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular];
    iItem.image = [[NSImage imageWithSystemSymbolName:sym accessibilityDescription:symName] imageWithSymbolConfiguration:cfg];
   }
   iItem.state = [cur.symbol isEqualToString:sym] ? NSControlStateValueOn : NSControlStateValueOff;
  }
  NSMenuItem* iconItem = [menu addItemWithTitle:@"Icon" action:nil keyEquivalent:@""];
  iconItem.submenu = iconSub;

  NSInteger curIdx = [self.spacesManager indexOfSpace:cur.identifier];
  if(curIdx > 0) {
   NSMenuItem* leftItem = [menu addItemWithTitle:@"Move Left" action:@selector(moveCurrentSpaceLeft:) keyEquivalent:@""];
   leftItem.target = self;
  }
  if(curIdx < (NSInteger)spaces.count - 1) {
   NSMenuItem* rightItem = [menu addItemWithTitle:@"Move Right" action:@selector(moveCurrentSpaceRight:) keyEquivalent:@""];
   rightItem.target = self;
  }

  NSString* dlTitle = cur.downloads.length ? [NSString stringWithFormat:@"Downloads to “%@”…", [NSURL fileURLWithPath:cur.downloads].lastPathComponent] : @"Downloads Folder…";
  NSMenuItem* dlItem = [menu addItemWithTitle:dlTitle action:@selector(chooseSpaceDownloads:) keyEquivalent:@""];
  dlItem.target = self;

  if(cur.downloads.length) {
   NSMenuItem* resetDl = [menu addItemWithTitle:@"Downloads to Default Folder" action:@selector(resetSpaceDownloads:) keyEquivalent:@""];
   resetDl.target = self;
  }

  if(!cur.isFirst) {
   [menu addItem:[NSMenuItem separatorItem]];
   NSString* delTitle = [NSString stringWithFormat:@"Delete “%@”…", cur.name];
   NSMenuItem* delItem = [menu addItemWithTitle:delTitle action:@selector(deleteCurrentSpace:) keyEquivalent:@""];
   delItem.target = self;
  }
 }

 NSPoint pt = [button convertPoint:NSMakePoint(0, NSHeight(button.bounds) + 4) toView:nil];
 [menu popUpMenuPositioningItem:nil atLocation:pt inView:button.window.contentView];
}

- (void)spaceBadgeClicked:(id)sender {
 if(self.spaceBadgeButton) [self showSpaceMenuForButton:self.spaceBadgeButton];
}

- (void)updateSpaceBadge {
 if(!self.spaceBadgeButton) return;
 SlateSpace* curSpace = [self.spacesManager currentSpace];
 if(!curSpace) return;
 NSString* letter = curSpace.name.length ? [[curSpace.name substringToIndex:1] uppercaseString] : @"S";
 NSDictionary* attrs = @{
  NSFontAttributeName: [NSFont systemFontOfSize:10.5 weight:NSFontWeightBold],
  NSForegroundColorAttributeName: NSColor.whiteColor
 };
 NSAttributedString* attrTitle = [[NSAttributedString alloc] initWithString:letter attributes:attrs];
 self.spaceBadgeButton.attributedTitle = attrTitle;
 self.spaceBadgeButton.toolTip = [NSString stringWithFormat:@"%@ — ⌃1–⌃9 to switch", curSpace.name];
 NSColor* bg = [NSColor systemBlueColor];
 if(curSpace.colour == 1) bg = [NSColor systemIndigoColor];
 else if(curSpace.colour == 2) bg = [NSColor systemPurpleColor];
 else if(curSpace.colour == 3) bg = [NSColor systemPinkColor];
 else if(curSpace.colour == 4) bg = [NSColor systemRedColor];
 else if(curSpace.colour == 5) bg = [NSColor systemOrangeColor];
 else if(curSpace.colour == 6) bg = [NSColor systemYellowColor];
 else if(curSpace.colour == 7) bg = [NSColor systemGreenColor];
 else if(curSpace.colour == 8) bg = [NSColor systemTealColor];
 self.spaceBadgeButton.layer.backgroundColor = bg.CGColor;
}

- (void)askNewSpace:(id)sender {
 NSAlert* alert = [[NSAlert alloc] init];
 alert.messageText = @"New Space";
 alert.informativeText = @"Its own tabs. Signed in where your other spaces are, unless it starts afresh.";

 NSView* box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 260, 56)];
 NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 30, 260, 24)];
 field.placeholderString = @"Work";
 field.stringValue = @"Work";
 [box addSubview:field];

 NSButton* fresh = [NSButton checkboxWithTitle:@"Start signed out, with its own cookies" target:nil action:nil];
 fresh.frame = NSMakeRect(0, 0, 260, 22);
 [box addSubview:fresh];

 alert.accessoryView = box;
 [alert addButtonWithTitle:@"Create"];
 [alert addButtonWithTitle:@"Cancel"];
 alert.window.initialFirstResponder = field;

 [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
  if(resp != NSAlertFirstButtonReturn) return;
  NSString* name = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if(!name.length) name = @"Work";
  BOOL sharesSignIns = (fresh.state != NSControlStateValueOn);
  SlateSpace* s = [self.spacesManager addSpaceNamed:name icon:nil sharesSignIns:sharesSignIns];
  if(s) {
   [self switchSpaceToId:s.identifier];
  }
 }];
}

- (void)renameCurrentSpace:(id)sender {
 SlateSpace* cur = self.spacesManager.currentSpace;
 if(!cur) return;
 NSAlert* alert = [[NSAlert alloc] init];
 alert.messageText = @"Rename Space";
 NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
 field.stringValue = cur.name ?: @"";
 alert.accessoryView = field;
 [alert addButtonWithTitle:@"Rename"];
 [alert addButtonWithTitle:@"Cancel"];
 alert.window.initialFirstResponder = field;

 [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
  if(resp != NSAlertFirstButtonReturn) return;
  NSString* name = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if(name.length) {
   [self.spacesManager renameSpace:cur.identifier toName:name];
   [self.sidebarFoot updateDoors];
   [self rebuildSpacesMenu];
   [self updateSpaceBadge];
  }
 }];
}

- (void)selectSpaceIconItem:(NSMenuItem*)sender {
 SlateSpace* cur = self.spacesManager.currentSpace;
 NSString* icon = sender.representedObject;
 if(cur && [icon isKindOfClass:NSString.class]) {
  [self.spacesManager setSpaceIcon:cur.identifier icon:icon];
  [self.sidebarFoot updateDoors];
  [self rebuildSpacesMenu];
  [self updateSpaceBadge];
 }
}

- (void)moveCurrentSpaceLeft:(id)sender {
 SlateSpace* cur = self.spacesManager.currentSpace;
 if(!cur) return;
 NSInteger idx = [self.spacesManager indexOfSpace:cur.identifier];
 if(idx > 0) {
  [self.spacesManager moveSpace:cur.identifier toIndex:idx - 1];
  [self rebuildSpacesMenu];
 }
}

- (void)moveCurrentSpaceRight:(id)sender {
 SlateSpace* cur = self.spacesManager.currentSpace;
 if(!cur) return;
 NSInteger idx = [self.spacesManager indexOfSpace:cur.identifier];
 if(idx < (NSInteger)self.spacesManager.spaces.count - 1) {
  [self.spacesManager moveSpace:cur.identifier toIndex:idx + 1];
  [self rebuildSpacesMenu];
 }
}

- (void)chooseSpaceDownloads:(id)sender {
 SlateSpace* cur = self.spacesManager.currentSpace;
 if(!cur) return;
 NSOpenPanel* panel = [NSOpenPanel openPanel];
 panel.canChooseDirectories = YES;
 panel.canChooseFiles = NO;
 panel.canCreateDirectories = YES;
 panel.prompt = @"Use for This Space";
 panel.message = @"Downloads in this space go here. Cancel keeps the folder it has.";
 [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
  if(resp == NSModalResponseOK && panel.URL) {
   [self.spacesManager setSpaceDownloads:cur.identifier folder:panel.URL.path];
   [SlateDownloadManager sharedManager].downloadsDirectory = panel.URL.path;
  }
 }];
}

- (void)resetSpaceDownloads:(id)sender {
 SlateSpace* cur = self.spacesManager.currentSpace;
 if(!cur) return;
 [self.spacesManager setSpaceDownloads:cur.identifier folder:nil];
 NSString* envDown = NSProcessInfo.processInfo.environment[@"SLATE_DOWNLOADS_DIR"];
 if(envDown.length && envDown.isAbsolutePath) {
  [SlateDownloadManager sharedManager].downloadsDirectory = envDown;
 } else {
  [SlateDownloadManager sharedManager].downloadsDirectory = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES).firstObject;
 }
}

- (void)deleteCurrentSpace:(id)sender {
 SlateSpace* cur = self.spacesManager.currentSpace;
 if(!cur || cur.isFirst) return;
 NSAlert* alert = [[NSAlert alloc] init];
 alert.messageText = [NSString stringWithFormat:@"Delete “%@”?", cur.name];
 alert.informativeText = @"Its tabs close, and its cookies and sign-ins are erased from this Mac. History and bookmarks stay.";
 NSButton* delBtn = [alert addButtonWithTitle:@"Delete"];
 [delBtn setHasDestructiveAction:YES];
 [alert addButtonWithTitle:@"Cancel"];

 [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
  if(resp == NSAlertFirstButtonReturn) {
   NSString* delId = cur.identifier;
   [self switchSpaceToId:[SlateSpace firstSpaceIdentifier]];
   [self.spacesManager deleteSpace:delId];
   [self rebuildSpacesMenu];
  }
 }];
}
- (void)layoutOmnibox {
 const auto* tab=model.find(model.selected());
 const BOOL isIncog=tab && tab->incognito;
 // On the new tab page, the omnibox is always hidden — the center search bar is used instead.
 const BOOL show=!self.quitting && tab && tab->url!="about:blank" && !model.closing(tab->id);
 self.omnibox.hidden=!show;
 self.stealthBadge.hidden=!isIncog;
 self.stealthBadgeWidth.constant=isIncog ? 96 : 0;
 const BOOL showSecurity=show;
 self.securityButton.hidden=!showSecurity;
 self.securityButtonWidth.constant=showSecurity ? 18 : 0;
 self.securityButtonLeading.constant=showSecurity ? 16 : 0;
 [self updateSecurityChrome];
 if([self.omnibox isKindOfClass:SlateOmnibox.class]) [(SlateOmnibox*)self.omnibox applyContrast];
 if(!show || !self.addressOpen) [self hideSuggestions];
}
- (void)showStealthInfo:(id)sender {
 NSAlert* alert=[[NSAlert alloc] init];
 alert.messageText=@"🕶 Untrackable Mode Active";
 alert.informativeText=
  @"This tab is browsing in full stealth mode:\n\n"
  @"• In-Memory Only: No cookies, history, or cache will ever be saved to disk.\n"
  @"• Anti-Fingerprinting: Deterministic micro-entropy neutralizes canvas & audio tracking.\n"
  @"• WebRTC Protected: Non-proxied UDP is disabled to prevent local IP leaks.\n"
  @"• Tracking Blocked: Hyperlink auditing pings and third-party referrers are blocked.\n\n"
  @"All volatile session memory is immediately wiped when incognito tabs close.";
 [alert addButtonWithTitle:@"Dismiss"];
 [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (BOOL)eventHitsOmnibox:(NSEvent*)event {
 if(!event) return NO;
 if(event.window==self.suggestPanel || event.window==[SlateSiteCardPanel sharedPanel]) return YES;
 if(self.suggestPanel.visible) {
  NSPoint panelPoint=[self.suggestPanel.contentView convertPoint:event.locationInWindow fromView:nil];
  if(event.window==self.suggestPanel && NSPointInRect(panelPoint, self.suggestPanel.contentView.bounds)) return YES;
 }
 if([SlateSiteCardPanel isShown]) {
  NSPoint cardPoint=[[SlateSiteCardPanel sharedPanel].contentView convertPoint:event.locationInWindow fromView:nil];
  if(event.window==[SlateSiteCardPanel sharedPanel] && NSPointInRect(cardPoint, [SlateSiteCardPanel sharedPanel].contentView.bounds)) return YES;
 }
 if(self.omnibox.hidden) return NO;
 NSPoint point=[self.omnibox convertPoint:event.locationInWindow fromView:nil];
 return NSPointInRect(point, NSInsetRect(self.omnibox.bounds,-10,-10));
}
- (void)dismissOmnibox {
 [self hideSuggestions];
 [SlateSiteCardPanel hide];
 const auto* tab=model.find(model.selected());
 if(tab && tab->url=="about:blank") return;
 if(!self.addressOpen) return;
 self.addressOpen=NO;
 NSResponder* responder=self.window.firstResponder;
 if(responder==self.address || ([responder isKindOfClass:NSView.class] && [(NSView*)responder isDescendantOf:self.address]))
  [self.window makeFirstResponder:self.content];
 if(tab && !self.addressDirty) {
  NSString* shown=Text(tab->url);
  if([shown isEqualToString:@"about:blank"] || [shown isEqualToString:@"about:blank#popup"]) shown=@"";
  self.address.stringValue=shown;
 }
 [self layoutOmnibox];
}
- (void)dismissOmniboxIfClickOutside:(NSEvent*)event {
 if(self.quitting || !self.addressOpen) return;
 if(event.window!=self.window && event.window!=self.suggestPanel && event.window!=[SlateSiteCardPanel sharedPanel]) { [self dismissOmnibox]; return; }
 if([self eventHitsOmnibox:event]) return;
 if(!self.tabCluster.hidden) {
  NSPoint tabs=[self.tabCluster convertPoint:event.locationInWindow fromView:nil];
  if(event.window==self.window && NSPointInRect(tabs,self.tabCluster.bounds)) return;
 }
 [self dismissOmnibox];
}
- (WKWebView*)currentWebView {
 auto it=runtimes.find(model.selected());
 if(it==runtimes.end() || !it->second.host) return nil;
 for(NSView* v in it->second.host.subviews) {
  if([v isKindOfClass:WKWebView.class]) return (WKWebView*)v;
 }
 return nil;
}
- (void)updateSecurityChrome {
 if(!self.securityButton) return;
 const auto* tab=model.find(model.selected());
 if(!tab || tab->url.empty() || tab->url=="about:blank") {
  self.securityButton.hidden=YES;
  return;
 }
 NSURL* url=[NSURL URLWithString:Text(tab->url)];
 WKWebView* webView=[self currentWebView];
 if([url.scheme.lowercaseString isEqualToString:@"https"]) {
  if(webView && !webView.hasOnlySecureContent) {
   self.securityButton.image=[NSImage imageWithSystemSymbolName:@"lock.trianglebadge.exclamationmark" accessibilityDescription:@"Mixed Content"];
   self.securityButton.contentTintColor=[NSColor colorWithCalibratedRed:0.95 green:0.60 blue:0.20 alpha:1.0];
  } else {
   self.securityButton.image=[NSImage imageWithSystemSymbolName:@"lock.fill" accessibilityDescription:@"Secure Connection"] ?: [NSImage imageWithSystemSymbolName:@"lock" accessibilityDescription:@"Secure Connection"];
   self.securityButton.contentTintColor=self.barMuted ?: NSColor.secondaryLabelColor;
  }
 } else if([url.scheme.lowercaseString isEqualToString:@"http"]) {
  self.securityButton.image=[NSImage imageWithSystemSymbolName:@"lock.open" accessibilityDescription:@"Not Secure"];
  self.securityButton.contentTintColor=[NSColor colorWithCalibratedRed:0.92 green:0.26 blue:0.26 alpha:1.0];
 } else {
  self.securityButton.image=[NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:@"Local Document"];
  self.securityButton.contentTintColor=self.barMuted ?: NSColor.secondaryLabelColor;
 }

 if([SlateSiteCardPanel isShown]) {
  [[SlateSiteCardPanel sharedPanel] updateWithURL:url
                                            trust:webView ? webView.serverTrust : NULL
                                    secureContent:webView ? webView.hasOnlySecureContent : YES
                                             zoom:self.zoomPercent];
 }
}
- (void)updateAutofillButtonState {
 if(!self.autofillButton) return;
 if(!credentials) {
  self.autofillButton.hidden = YES;
  self.autofillButtonWidth.constant = 0;
  return;
 }
 const auto* tab = model.find(model.selected());
 if(!tab || tab->incognito || tab->url.empty() || tab->url == "about:blank") {
  self.autofillButton.hidden = YES;
  self.autofillButtonWidth.constant = 0;
  return;
 }
 NSURL* url = [NSURL URLWithString:Text(tab->url)];
 if(!url || (![url.scheme.lowercaseString isEqualToString:@"https"] && ![url.host.lowercaseString isEqualToString:@"localhost"] && ![url.host.lowercaseString isEqualToString:@"127.0.0.1"])) {
  self.autofillButton.hidden = YES;
  self.autofillButtonWidth.constant = 0;
  return;
 }
 NSString* portPart = (url.port && url.port.intValue != 443 && url.port.intValue != 80) ? [NSString stringWithFormat:@":%@", url.port] : @"";
 NSString* origin = [NSString stringWithFormat:@"%@://%@%@", url.scheme.lowercaseString, url.host.lowercaseString, portPart];
 auto matches = credentials->find_for_origin(origin.UTF8String);
 if(!matches.empty()) {
  self.autofillButton.hidden = NO;
  self.autofillButtonWidth.constant = 22;
  auto rIt = runtimes.find(model.selected());
  BOOL hasForm = (rIt != runtimes.end() && rIt->second.has_sign_in);
  self.autofillButton.contentTintColor = hasForm ? [NSColor systemBlueColor] : NSColor.secondaryLabelColor;
  self.autofillButton.toolTip = [NSString stringWithFormat:@"Autofill saved password for %@ (%s)", origin, matches[0].username.c_str()];
 } else {
  self.autofillButton.hidden = YES;
  self.autofillButtonWidth.constant = 0;
 }
}
- (void)updatePipButtonState {
 if(!self.pipButton) return;
 const auto* tab = model.find(model.selected());
 if(!tab || tab->url.empty() || tab->url == "about:blank") {
  self.pipButton.hidden = YES;
  self.pipButtonWidth.constant = 0;
  return;
 }
 auto it = runtimes.find(model.selected());
 const BOOL hasVideo = (it != runtimes.end() && (it->second.has_video || it->second.video_playing));
 const BOOL isPip = (it != runtimes.end() && it->second.pip_active) || (self.floatWindow.showing && self.floatingTabId == model.selected());
 const BOOL knownSite = slate::KnownPlayers::knows(tab->url);

 if(hasVideo || isPip || knownSite) {
  self.pipButton.hidden = NO;
  self.pipButtonWidth.constant = 26;
  if (@available(macOS 11.0, *)) {
   NSString* symbolName = isPip ? @"pip.exit" : @"pip.enter";
   NSImage* img = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:@"Picture in Picture"];
   if(!img) img = [NSImage imageWithSystemSymbolName:@"pictureinpicture" accessibilityDescription:@"Picture in Picture"];
   self.pipButton.image = img;
   self.pipButton.contentTintColor = isPip ? [NSColor systemBlueColor] : NSColor.secondaryLabelColor;
  }
  NSString* qualityStr = (it != runtimes.end() && !it->second.video_quality.empty()) ? [NSString stringWithUTF8String:it->second.video_quality.c_str()] : nil;
  if(qualityStr.length) {
   self.pipButton.toolTip = [NSString stringWithFormat:@"Picture in Picture • %@%s (⌥⌘P)", qualityStr, (it->second.is_hdr ? " • HDR" : "")];
  } else {
   self.pipButton.toolTip = isPip ? @"Exit Picture in Picture (⌥⌘P)" : @"Picture in Picture (⌥⌘P)";
  }
 } else {
  self.pipButton.hidden = YES;
  self.pipButtonWidth.constant = 0;
 }
}
- (WKWebView*)webViewForTab:(TabId)identifier {
 auto it = runtimes.find(identifier);
 if(it == runtimes.end() || !it->second.host) return nil;
 for(NSView* v in it->second.host.subviews) {
  if([v isKindOfClass:WKWebView.class]) return (WKWebView*)v;
 }
 return nil;
}
- (IBAction)toggleFloatingVideo:(id)sender {
 (void)sender;
 [self toggleFloatingVideo];
}
- (void)toggleFloatingVideo {
 if(self.floatWindow.showing) {
  auto it=runtimes.find(self.floatingTabId);
  if(it!=runtimes.end()) it->second.suppress_auto_pip=true;
  [self dropFloat];
  return;
 }
 const TabId selected = model.selected();
 if(!selected) return;
 auto it=runtimes.find(selected);
 if(it==runtimes.end()) return;

 if(it->second.pip_active) {
  it->second.pip_returning=true;
  it->second.suppress_auto_pip=true;
  it->second.auto_pip_origin=0;
  [self exitNativePiPForTab:selected];
  // The media bridge reports the actual transition. Keep the tab protected
  // until WebKit confirms that the native PiP presentation has ended.
  return;
 }

 [self liftTab:selected];
}

/// Ensure the SlateFloat singleton exists and its callbacks are wired.
- (void)ensureFloat {
 if(self.floatWindow) return;
 self.floatWindow = [[SlateFloat alloc] init];
 __weak SlateDelegate* weakSelf = self;

 self.floatWindow.onClose = ^{
  auto it=runtimes.find(weakSelf.floatingTabId);
  if(it!=runtimes.end()) it->second.suppress_auto_pip=true;
  [weakSelf dropFloat];
 };
 self.floatWindow.onReturn = ^{
  SlateDelegate* s = weakSelf;
  if(!s) return;
  TabId tab = s.floatingTabId;
  [s dropFloat];
  if(tab && model.find(tab)) {
   [s activateTab:tab];
   [s.window makeKeyAndOrderFront:nil];
   [NSApp activateIgnoringOtherApps:YES];
  }
 };
 self.floatWindow.onPlayPause = ^(void (^reply)(BOOL)) {
  SlateDelegate* s = weakSelf;
  if(!s || !s.floatingWebView) { reply(YES); return; }
  [s.floatingWebView evaluateJavaScript:[SlateIsolate toggle] completionHandler:^(id result, NSError* err) {
   BOOL playing = [result respondsToSelector:@selector(boolValue)] ? [result boolValue] : YES;
   dispatch_async(dispatch_get_main_queue(), ^{ reply(playing); });
  }];
 };
 self.floatWindow.onSkip = ^(double seconds) {
  SlateDelegate* s = weakSelf;
  if(!s || !s.floatingWebView) return;
  [s.floatingWebView evaluateJavaScript:[SlateIsolate skip:seconds] completionHandler:nil];
 };
 self.floatWindow.onSeek = ^(double ratio) {
  SlateDelegate* s = weakSelf;
  if(!s || !s.floatingWebView) return;
  [s.floatingWebView evaluateJavaScript:[SlateIsolate seek:ratio] completionHandler:nil];
 };
 self.floatWindow.onProgress = ^(void (^reply)(double, BOOL)) {
  SlateDelegate* s = weakSelf;
  if(!s || !s.floatingWebView) { reply(0, YES); return; }
  [s.floatingWebView evaluateJavaScript:[SlateIsolate where_] completionHandler:^(id result, NSError* err) {
   double through = 0;
   BOOL playing = YES;
   if([result isKindOfClass:[NSArray class]] && [result count] >= 2) {
    through = [[result objectAtIndex:0] doubleValue];
    playing = [[result objectAtIndex:1] boolValue];
   }
   dispatch_async(dispatch_get_main_queue(), ^{ reply(through, playing); });
  }];
 };
}

/// Put a tab into native Picture-in-Picture with one entry request.
- (void)liftTab:(TabId)identifier {
 if(!identifier) return;
 if(self.floatWindow.showing) [self dropFloat];

 auto it = runtimes.find(identifier);
 if(it == runtimes.end() || !it->second.engine) return;

 it->second.suppress_auto_pip = false;
 it->second.auto_pip_origin = 0;
 [self enterNativePiPForTab:identifier manual:YES];
}
- (void)enterNativePiPForTab:(TabId)identifier manual:(BOOL)manual {
 auto it = runtimes.find(identifier);
 if(it == runtimes.end() || !it->second.engine) return;
 WKWebView* webView = [self webViewForTab:identifier];
 SEL canPipSel = NSSelectorFromString(@"_canTogglePictureInPicture");
 SEL togglePipSel = NSSelectorFromString(@"_togglePictureInPicture");
 if(webView && [webView respondsToSelector:canPipSel] && [webView respondsToSelector:togglePipSel] &&
    ((BOOL (*)(id, SEL))objc_msgSend)(webView, canPipSel)) {
  ((void (*)(id, SEL))objc_msgSend)(webView, togglePipSel);
  return;
 }
 // Older WebKit builds may not expose the native toggle. The video API is a
 // best-effort fallback; unlike the native toggle it can require page gesture.
 std::string frameArg = it->second.primary_media_frame.empty() ? "" : ",frameId:'" + it->second.primary_media_frame + "'";
 it->second.engine->execute_script("window.postMessage({type:'slatePiPEnter',manual:" +
   std::string(manual ? "true" : "false") + frameArg + "}, '*')");
}
- (void)exitNativePiPForTab:(TabId)identifier {
 auto it = runtimes.find(identifier);
 if(it == runtimes.end()) return;
 WKWebView* webView = [self webViewForTab:identifier];
 if(@available(macOS 12.0, *)) {
  if(webView) {
   [webView closeAllMediaPresentationsWithCompletionHandler:nil];
   return;
  }
 }
 if(it->second.engine) {
  std::string frameArg = it->second.primary_media_frame.empty() ? "" : ",frameId:'" + it->second.primary_media_frame + "'";
  it->second.engine->execute_script("window.postMessage({type:'slatePiPExit'" + frameArg + "}, '*')");
 }
}

/// Put the WKWebView back into its tab and close the float panel.
- (void)dropFloat {
 if(!self.floatWindow.showing) return;
 TabId tab = self.floatingTabId;
 WKWebView* webView = self.floatingWebView;

 [self.floatWindow drop];

 // webView has been removed from the panel; put it back in its tab's host.
 if(tab && webView) {
  auto it = runtimes.find(tab);
  if(it != runtimes.end()) {
   it->second.suppress_auto_pip = true;
   if(it->second.host) {
    [it->second.host addSubview:webView];
    webView.frame = it->second.host.bounds;
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
   }
   // Un-isolate: restore the page.
   [webView evaluateJavaScript:[SlateIsolate off] completionHandler:nil];
  }
 }

 // Clear state
 if(tab) {
  auto it = runtimes.find(tab);
  if(it != runtimes.end()) {
   it->second.pip_active = false;
   it->second.auto_pip_origin = 0;
   model.set_pip_active(tab, false);
  }
 }
 self.floatingTabId = 0;
 self.floatingWebView = nil;
 [self scheduleRefresh];
 [self updatePipButtonState];
}
- (void)requestAutoPiPForTab:(TabId)identifier origin:(int)origin {
 auto it = runtimes.find(identifier);
 if(it == runtimes.end() || !it->second.engine || !it->second.video_playing ||
    !it->second.user_started_media || it->second.pip_active ||
    it->second.suppress_auto_pip || it->second.auto_pip_origin != 0 ||
    self.floatWindow.showing) return;
 it->second.auto_pip_origin = origin;
 [self enterNativePiPForTab:identifier manual:NO];
 // If the site or WebKit declines PiP, resume normal tab occlusion.
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
  auto later = runtimes.find(identifier);
  if(later != runtimes.end() && !later->second.pip_active && later->second.auto_pip_origin == origin) {
   later->second.auto_pip_origin = 0;
   // Chrome may be unchanged, so a queued refresh can return early. Finish
   // hiding the outgoing surface independently of the tab-list repaint.
   [self presentWorkspacePages];
   [self scheduleRefresh];
  }
 });
}
- (void)autoPiPForVisibleWorkspace {
 const TabId selected=model.selected();
 auto playing=[&](TabId identifier) {
  auto it=runtimes.find(identifier);
  return it!=runtimes.end() && it->second.video_playing && it->second.user_started_media;
 };
 if(playing(selected)) { [self requestAutoPiPForTab:selected origin:2]; return; }
 if(workspace.visible_for(selected)) {
  const TabId other=workspace.left==selected ? workspace.right : workspace.left;
  if(other!=selected && playing(other)) [self requestAutoPiPForTab:other origin:2];
 }
}
- (void)returnAutoPiPForVisibleWorkspace {
 for(TabId identifier : {model.selected(),workspace.visible_for(model.selected()) ? workspace.left : TabId(0),
                        workspace.visible_for(model.selected()) ? workspace.right : TabId(0)}) {
  if(!identifier) continue;
  auto it=runtimes.find(identifier);
  if(it!=runtimes.end() && it->second.auto_pip_origin==2 && it->second.pip_active) {
   it->second.pip_returning=true;
   [self exitNativePiPForTab:identifier];
  }
 }
}
- (void)appDidResignActive:(NSNotification*)notification {
 (void)notification;
 [self autoPiPForVisibleWorkspace];
}
- (void)appDidBecomeActive:(NSNotification*)notification {
 (void)notification;
 [self returnAutoPiPForVisibleWorkspace];
}
- (IBAction)triggerAutofillAction:(id)sender {
 auto it = runtimes.find(model.selected());
 if(it == runtimes.end() || !it->second.engine || !credentials) return;
 const auto* tab = model.find(model.selected());
 if(!tab || tab->incognito) return;
 NSURL* url = [NSURL URLWithString:Text(tab->url)];
 if(!url) return;
 NSString* portPart = (url.port && url.port.intValue != 443 && url.port.intValue != 80) ? [NSString stringWithFormat:@":%@", url.port] : @"";
 NSString* origin = [NSString stringWithFormat:@"%@://%@%@", url.scheme.lowercaseString, url.host.lowercaseString, portPart];
 auto matches = credentials->find_for_origin(origin.UTF8String);
 if(matches.empty()) return;

 if(matches.size() == 1) {
  it->second.engine->fill_credentials(matches[0].username, matches[0].password);
 } else {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Saved Logins"];
  for(const auto& c : matches) {
   NSString* title = [NSString stringWithFormat:@"%s (%@)", c.username.c_str(), origin];
   NSMenuItem* item = [menu addItemWithTitle:title action:@selector(selectAutofillCredential:) keyEquivalent:@""];
   item.representedObject = @{@"user": @(c.username.c_str()), @"pass": @(c.password.c_str())};
   item.target = self;
  }
  NSRect frame = self.autofillButton.bounds;
  [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(frame) + 4) inView:self.autofillButton];
 }
}
- (void)selectAutofillCredential:(NSMenuItem*)sender {
 NSDictionary* dict = (NSDictionary*)sender.representedObject;
 if(!dict) return;
 auto it = runtimes.find(model.selected());
 if(it != runtimes.end() && it->second.engine) {
  NSString* u = dict[@"user"] ?: @"";
  NSString* p = dict[@"pass"] ?: @"";
  it->second.engine->fill_credentials(u.UTF8String, p.UTF8String);
 }
}
- (IBAction)showSiteCard:(id)sender {
 TabId targetId = 0;
 if([sender isKindOfClass:NSMenuItem.class] && [((NSMenuItem*)sender).representedObject isKindOfClass:NSNumber.class]) {
  targetId = (TabId)[((NSMenuItem*)sender).representedObject unsignedLongLongValue];
 }
 if(!targetId) targetId = model.selected();
 if(targetId && targetId != model.selected()) {
  [self activateTab:targetId];
 }
 const auto* tab=model.find(model.selected());
 if(!tab || tab->url.empty() || tab->url=="about:blank") return;
 NSURL* url=[NSURL URLWithString:Text(tab->url)];
 WKWebView* wv=[self currentWebView];

 NSView* anchor=nil;
 if([sender isKindOfClass:[NSView class]]) {
  anchor=(NSView*)sender;
 } else if(self.securityButton && !self.securityButton.hidden) {
  anchor=self.securityButton;
 } else if(self.address && !self.address.hidden) {
  anchor=self.address;
 } else {
  anchor=self.toolbar;
 }

 [[SlateSiteCardPanel sharedPanel] updateWithURL:url
                                           trust:wv ? wv.serverTrust : NULL
                                   secureContent:wv ? wv.hasOnlySecureContent : YES
                                            zoom:self.zoomPercent];
 [SlateSiteCardPanel sharedPanel].owner=self;
 [[SlateSiteCardPanel sharedPanel] toggleForAnchor:anchor inWindow:self.window];
}
- (BOOL)routeChromeClick:(NSEvent*)event {
 if(event.window!=self.window || self.quitting) return NO;
 if(self.tabCluster.hidden || self.tabCluster.alphaValue<0.05) return NO;
 NSPoint point=[self.tabCluster convertPoint:event.locationInWindow fromView:nil];
 if(!NSPointInRect(point, NSInsetRect(self.tabCluster.bounds,0,-8))) return NO;
 if(event.type==NSEventTypeRightMouseDown) {
  [(SlateTabCluster*)self.tabCluster rightMouseDown:event];
  return YES;
 }
 [(SlateTabCluster*)self.tabCluster mouseDown:event];
 return YES;
}
- (void)updateNavChrome {
 auto it=runtimes.find(model.selected());
 const BOOL live=it!=runtimes.end() && it->second.engine && !model.closing(it->first);
 const BOOL loading=live && it->second.loading;
 self.backButton.enabled=live && it->second.back;
 self.forwardButton.enabled=live && it->second.forward;
 self.reloadButton.enabled=live;
 self.backButton.alphaValue=self.backButton.enabled ? 1 : 0.28;
 self.forwardButton.alphaValue=self.forwardButton.enabled ? 1 : 0.28;
 self.reloadButton.alphaValue=self.reloadButton.enabled ? 1 : 0.28;
 self.backButton.glyph.contentTintColor=self.backButton.enabled ? (self.barInk ?: NSColor.labelColor) : (self.barMuted ?: NSColor.tertiaryLabelColor);
 self.forwardButton.glyph.contentTintColor=self.forwardButton.enabled ? (self.barInk ?: NSColor.labelColor) : (self.barMuted ?: NSColor.tertiaryLabelColor);
 self.reloadButton.glyph.contentTintColor=self.reloadButton.enabled ? (self.barInk ?: NSColor.labelColor) : (self.barMuted ?: NSColor.tertiaryLabelColor);
 [self.reloadButton setBusy:loading];
 [self updateLoadChrome];
 [self updateSecurityChrome];
 [self updateAutofillButtonState];
 [self updatePipButtonState];
}
- (void)updateLoadChrome {
 auto it=runtimes.find(model.selected());
 const BOOL loading=it!=runtimes.end() && it->second.loading;
 const CGFloat progress=loading ? MAX(0.06, MIN(1.0, it->second.progress)) : 0;
 if(!self.loadBar || !self.loadBarWidth) return;
 const NSTimeInterval now=CACurrentMediaTime();
 if(loading && fabs(progress-1.0)>0.001 && now-self.lastLoadBarAt<0.05) return;
 self.lastLoadBarAt=now;
 self.loadBar.hidden=!loading;
 NSColor* fill=self.window.backgroundColor ?: (self.barInk ?: NSColor.controlAccentColor);
 self.loadBar.layer.backgroundColor=[fill colorWithAlphaComponent:loading?0.95:0].CGColor;
 self.loadBarWidth.constant=round(NSWidth(self.toolbar.bounds)*progress);
}
- (void)syncTabListColumnWidth {
 if(!self.tabList) return;
 NSScrollView* scroll=self.tabList.enclosingScrollView;
 const BOOL rail=[self sidebarIconRail];
 if(scroll) {
  scroll.hasVerticalScroller=!rail;
  scroll.hasHorizontalScroller=NO;
  scroll.horizontalScrollElasticity=NSScrollElasticityNone;
 }
 NSTableColumn* column=self.tabList.tableColumns.firstObject;
 if(!column) return;
 CGFloat targetW = 0;
 if(scroll && NSWidth(scroll.contentView.bounds) > 10) {
  targetW = NSWidth(scroll.contentView.bounds);
 } else {
  const CGFloat sideW = [self sidebarLayoutWidth];
  targetW = rail ? sideW : MAX(24, sideW - 12);
 }
 if(targetW < 8) targetW = rail ? kRailBubble : 24;
 self.tabList.autoresizingMask=NSViewWidthSizable;
 [self.tabList setFrameSize:NSMakeSize(targetW, NSHeight(self.tabList.frame))];
 column.minWidth=rail ? kRailBubble : 24;
 column.maxWidth=targetW;
 column.width=targetW;
 self.tabList.rowHeight=rail ? kRailRow : 28;
 self.tabList.intercellSpacing=NSMakeSize(0,2);
 [self.tabList sizeLastColumnToFit];
}
- (void)setSidebarWidthLive:(CGFloat)width {
 if(![self sidebarRevealed]) return;
 const BOOL wasRail=[self sidebarIconRail];
 self.sidebarUserWidth=ClampSidebarWidth(width, self.window.frame.size.width);
 self.sidebarWidth.constant=[self sidebarLayoutWidth];
 if(wasRail!=[self sidebarIconRail]) {
  self.sideRowsGen++;
  [self applyChromeInk];
  [self.tabList reloadData];
  [self layoutTrafficLights];
 }
 if(self.pinnedGrid) [self.pinnedGrid updateLayoutForWidth:self.sidebarWidth.constant];
 [self.window.contentView layoutSubtreeIfNeeded];
 [self syncTabListColumnWidth];
 [self syncPageGeometry];
 const NSTimeInterval now=CACurrentMediaTime();
 if(now-self.lastGeometryAt>1.0/12.0) {
  self.lastGeometryAt=now;
  [self.window invalidateCursorRectsForView:self.resizeHandle];
 }
}
- (void)persistSidebarWidth {
 self.sidebarUserWidth=SnapSidebarWidth(self.sidebarUserWidth, self.window.frame.size.width);
 self.sidebarWidth.constant=[self sidebarLayoutWidth];
 [self.window.contentView layoutSubtreeIfNeeded];
 [self syncPageGeometry];
 [self persistUiPrefs];
 [self applyChromeInk];
 [self.tabList reloadData];
 [self syncTabListColumnWidth];
 [self layoutTrafficLights];
 self.lastGeometryAt=0;
 [self notifyBrowserGeometry];
}
- (NSInteger)splitSideForTab:(TabId)tab {
 const auto pair=workspace.pair_for(tab);
 return !pair ? 0 : pair->left==tab ? 1 : 2;
}
- (BOOL)tabInVisibleSplit:(TabId)tab { return workspace.visible_for(model.selected()) && workspace.contains(tab); }
- (void)setupSplitViews {
 // Give each live WebKit surface its own clipped pane. Reparenting the existing
 // host preserves page state and prevents one composited surface covering its peer.
 self.splitLeftPane=[[NSView alloc] initWithFrame:NSZeroRect];
 self.splitRightPane=[[NSView alloc] initWithFrame:NSZeroRect];
 for(NSView* pane in @[self.splitLeftPane,self.splitRightPane]) {
  pane.wantsLayer=YES;
  pane.clipsToBounds=YES;
  pane.layer.masksToBounds=YES;
  pane.hidden=YES;
  [self.content addSubview:pane positioned:NSWindowBelow relativeTo:self.homeView];
 }
 SlateSplitDivider* divider=[[SlateSplitDivider alloc] initWithFrame:NSZeroRect];
 divider.owner=self;
 divider.hidden=YES;
 divider.accessibilityLabel=@"Split divider";
 self.splitDivider=divider;
 [self.content addSubview:divider];

 self.splitFocusRing=[[SlateSplitOverlay alloc] initWithFrame:NSZeroRect];
 self.splitFocusRing.wantsLayer=YES;
 self.splitFocusRing.layer.cornerRadius=7;
 self.splitFocusRing.layer.borderWidth=2;
 self.splitFocusRing.hidden=YES;
 [self.content addSubview:self.splitFocusRing];

 self.splitOverlay=[[SlateSplitOverlay alloc] initWithFrame:NSZeroRect];
 self.splitOverlay.wantsLayer=YES;
 self.splitOverlay.hidden=YES;
 [self.content addSubview:self.splitOverlay];
 NSArray<NSString*>* titles=@[@"New split on left",@"New split on right"];
 for(NSInteger side=0;side<2;++side) {
  NSView* panel=[[NSView alloc] initWithFrame:NSZeroRect];
  panel.wantsLayer=YES;
  panel.layer.cornerRadius=18;
  panel.layer.masksToBounds=YES;
  panel.layer.backgroundColor=([self isDarkAppearance]
   ? [NSColor colorWithCalibratedWhite:0.16 alpha:0.94]
   : [NSColor colorWithCalibratedWhite:1 alpha:0.94]).CGColor;
  panel.layer.borderWidth=1;
  panel.accessibilityLabel=side==0 ? @"Create a new split with this tab on the left"
   : @"Create a new split with this tab on the right";
  [self.splitOverlay addSubview:panel];
  NSImageView* icon=[[NSImageView alloc] initWithFrame:NSZeroRect];
  icon.identifier=@"split-icon";
  icon.image=[NSImage imageWithSystemSymbolName:@"rectangle.split.2x1" accessibilityDescription:nil]
   ?: [NSImage imageWithSystemSymbolName:@"rectangle.split.1x2" accessibilityDescription:nil];
  icon.imageScaling=NSImageScaleProportionallyDown;
  [panel addSubview:icon];
  NSTextField* label=[NSTextField labelWithString:titles[side]];
  label.identifier=@"split-label";
  label.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  label.alignment=NSTextAlignmentCenter;
  [panel addSubview:label];
  if(side==0) self.splitLeftTarget=panel;
  else self.splitRightTarget=panel;
 }
 self.splitPreview=[[NSView alloc] initWithFrame:NSZeroRect];
 self.splitPreview.wantsLayer=YES;
 self.splitPreview.layer.cornerRadius=11;
 self.splitPreview.layer.backgroundColor=[NSColor.windowBackgroundColor colorWithAlphaComponent:0.96].CGColor;
 self.splitPreview.layer.shadowColor=NSColor.blackColor.CGColor;
 self.splitPreview.layer.shadowOpacity=0.14;
 self.splitPreview.layer.shadowRadius=8;
 self.splitPreview.layer.shadowOffset=CGSizeMake(0,-2);
 [self.splitOverlay addSubview:self.splitPreview];
 self.splitPreviewIcon=[[NSImageView alloc] initWithFrame:NSZeroRect];
 self.splitPreviewIcon.imageScaling=NSImageScaleProportionallyDown;
 [self.splitPreview addSubview:self.splitPreviewIcon];
 self.splitPreviewTitle=[NSTextField labelWithString:@""];
 self.splitPreviewTitle.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
 self.splitPreviewTitle.lineBreakMode=NSLineBreakByTruncatingTail;
 [self.splitPreview addSubview:self.splitPreviewTitle];
}
- (void)layoutSplitOverlay {
 if(!self.splitOverlay) return;
 const NSRect bounds=self.splitOverlay.bounds;
 const CGFloat width=NSWidth(bounds), height=NSHeight(bounds);
 const CGFloat margin=MIN(40,MAX(20,width*0.025));
 const CGFloat targetWidth=MIN(260,MAX(140,width*0.22));
 const CGFloat targetHeight=MIN(470,MAX(230,height*0.62));
 const CGFloat y=round((height-targetHeight)/2);
 self.splitLeftTarget.frame=NSMakeRect(margin,y,targetWidth,targetHeight);
 self.splitRightTarget.frame=NSMakeRect(width-margin-targetWidth,y,targetWidth,targetHeight);
 for(NSView* target in @[self.splitLeftTarget,self.splitRightTarget]) {
  NSImageView* icon=(NSImageView*)SplitChild(target,@"split-icon");
  NSTextField* label=(NSTextField*)SplitChild(target,@"split-label");
  icon.frame=NSMakeRect(round((targetWidth-23)/2),round(targetHeight/2+4),23,23);
  label.frame=NSMakeRect(8,round(targetHeight/2-28),targetWidth-16,20);
 }
 self.splitPreviewIcon.frame=NSMakeRect(14,15,20,20);
 self.splitPreviewTitle.frame=NSMakeRect(44,15,155,20);
}
- (void)syncPageGeometry {
 if(self.syncingGeometry || self.quitting || self.chromeAnimating) return;
 self.syncingGeometry=YES;
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 FreezeWebLayer(self.content);
 const NSRect fill=WebFillRect(self.content);
 const BOOL isSplit=workspace.visible_for(model.selected());
 const CGFloat cut=isSplit ? round(NSWidth(fill)*workspace.clamped_ratio(NSWidth(fill))) : NSWidth(fill);
 const NSRect left=NSMakeRect(0,0,cut,NSHeight(fill));
 const NSRect right=NSMakeRect(cut,0,MAX(0,NSWidth(fill)-cut),NSHeight(fill));
 if(self.splitLeftPane) {
  self.splitLeftPane.hidden=!isSplit;
  self.splitRightPane.hidden=!isSplit;
  if(isSplit) {
   self.splitLeftPane.frame=left;
   self.splitRightPane.frame=right;
  }
 }
 const TabId selected=model.selected();
 const auto* leftTab=isSplit ? model.find(workspace.left) : nullptr;
 const NSRect homeFrame=isSplit ? ((leftTab && leftTab->url=="about:blank") ? left : right) : fill;
 const NSRect placeholderFrame=isSplit && workspace.active==slate::SplitSide::Right ? right : (isSplit ? left : fill);
 if(self.homeView && !NSEqualRects(self.homeView.frame,homeFrame)) {
  self.homeView.frame=homeFrame;
  if(self.homeBoard) {
   NSRect board=self.homeBoard.frame;
   board.size.width=NSWidth(homeFrame);
   board.size.height=MAX(NSHeight(homeFrame),NSHeight(board));
   self.homeBoard.frame=board;
   [self.homeBoard setNeedsLayout:YES];
  }
 }
 if(self.placeholder && !NSEqualRects(self.placeholder.frame,placeholderFrame)) self.placeholder.frame=placeholderFrame;
 for(auto& [identifier,item]:runtimes) {
  if(!item.host || (!isSplit && identifier!=selected) ||
     (isSplit && !workspace.contains(identifier))) continue;
  FreezeWebLayer(item.host);
  const NSRect target=isSplit ? WebFillRect(item.host.superview ?: self.content) : fill;
  const BOOL moved=!NSEqualRects(item.host.frame,target);
  if(moved) item.host.frame=target;
  if(item.engine && moved) item.engine->host_geometry_changed();
 }
 if(self.splitDivider) {
  self.splitDivider.hidden=!isSplit;
  if(isSplit) self.splitDivider.frame=NSMakeRect(cut-4,0,8,NSHeight(fill));
 }
 if(self.splitFocusRing) {
  self.splitFocusRing.hidden=!isSplit;
  if(isSplit) {
   const NSRect pane=workspace.active==slate::SplitSide::Left ? left : right;
   self.splitFocusRing.frame=NSInsetRect(pane,1,1);
   NSColor* accent=ChromeAccent(self.accentId,self.accentHex,[self isDarkAppearance]);
   NSColor* rgb=[accent colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: accent;
   CGFloat hue=0,saturation=0,brightness=0,alpha=0;
   [rgb getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
   NSColor* ink=[NSColor colorWithHue:hue saturation:MAX(0.52,saturation)
    brightness:[self isDarkAppearance] ? MAX(0.75,brightness) : MIN(0.55,brightness) alpha:0.95];
   self.splitFocusRing.layer.borderColor=ink.CGColor;
  }
 }
 if(self.splitOverlay) {
  self.splitOverlay.frame=fill;
  [self layoutSplitOverlay];
 }
 [CATransaction commit];
 self.syncingGeometry=NO;
}
- (void)notifyBrowserGeometry {
 [self syncPageGeometry];
}
- (void)windowDidResize:(NSNotification*)notification {
 [self updateOmniboxPreferredWidth];
 NSView* root = self.window.contentView;
 fprintf(stderr, "RESIZE win=%s root=%s sview=%s isFs=%d\n",
         NSStringFromRect(self.window.frame).UTF8String,
         root ? NSStringFromRect(root.frame).UTF8String : "none",
         root.superview ? NSStringFromRect(root.superview.frame).UTF8String : "none",
         (self.window.styleMask & NSWindowStyleMaskFullScreen) ? 1 : 0);
 if(self.chromeGradientLayer && !self.chromeGradientLayer.hidden) {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.chromeGradientLayer.frame = self.window.contentView.bounds;
  [CATransaction commit];
 }
 if(self.homePlateGradientLayer && !self.homePlateGradientLayer.hidden) {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.homePlateGradientLayer.frame = self.stage.bounds;
  [CATransaction commit];
 }
 if([self sidebarRevealed]) {
  self.sidebarUserWidth=ClampSidebarWidth(self.sidebarWidth.constant, self.window.frame.size.width);
  self.sidebarWidth.constant=self.sidebarUserWidth;
 }
 if([self stripRevealed]) {
  [self layoutTabPillsWithAvailableWidth:[self availableTabStripWidth]];
 }
 [self.window.contentView layoutSubtreeIfNeeded];
 [self layoutTrafficLights];
 const NSTimeInterval now=CACurrentMediaTime();
 if(now-self.lastGeometryAt>1.0/20.0) {
  self.lastGeometryAt=now;
  [self notifyBrowserGeometry];
 }
 if(self.homePlateGradientLayer && !self.homePlateGradientLayer.hidden) {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.homePlateGradientLayer.frame = self.stage.bounds;
  [CATransaction commit];
 }
 if(self.homeView && !self.homeView.hidden && self.homeBoard) {
  NSSize clip=self.homeView.bounds.size;
  if(clip.width>8) {
   NSRect frame=self.homeBoard.frame;
   frame.origin=NSZeroPoint;
   frame.size.width=clip.width;
   frame.size.height=MAX(clip.height, NSHeight(frame));
   self.homeBoard.frame=frame;
   [self.homeBoard setNeedsLayout:YES];
   [self.homeBoard layoutSubtreeIfNeeded];
   [self.homeBoard setNeedsDisplay:YES];
  }
 }
 if(!self.window.inLiveResize) {
  [self positionSuggestPanel];
  [self updateLoadChrome];
 }
}
- (void)windowDidEndLiveResize:(NSNotification*)notification {
 self.lastGeometryAt=0;
 [self.window.contentView layoutSubtreeIfNeeded];
 for(auto& [identifier,item]:runtimes)
  if(item.engine && (workspace.visible_for(model.selected()) ? workspace.contains(identifier) : identifier==model.selected()))
   item.engine->host_geometry_changed();
 [self notifyBrowserGeometry];
 if([self stripRevealed]) {
  [self layoutTabPillsWithAvailableWidth:[self availableTabStripWidth]];
 }
 [self layoutTrafficLights];
 [self positionSuggestPanel];
 [self updateLoadChrome];
}
- (void)windowDidEnterFullScreen:(NSNotification*)notification {
 if(notification.object!=self.window) return;
 [self applyTabLayout:NO];
 [self layoutTrafficLights];
 [self.window.contentView layoutSubtreeIfNeeded];
 [self notifyBrowserGeometry];
}
- (void)windowDidExitFullScreen:(NSNotification*)notification {
 if(notification.object!=self.window) return;
 [self applyTabLayout:NO];
 [self layoutTrafficLights];
 [self.window.contentView layoutSubtreeIfNeeded];
 [self notifyBrowserGeometry];
}
- (void)windowDidMove:(NSNotification*)notification {
 [self positionSuggestPanel];
}
- (void)windowDidChangeBackingProperties:(NSNotification*)notification {
 [self applyPlateChrome];
 [self notifyBrowserGeometry];
}
- (void)windowDidResignKey:(NSNotification*)notification {
 (void)notification;
}
- (void)windowDidBecomeKey:(NSNotification*)notification {
 (void)notification;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table {
 return (NSInteger)[self sidebarRows].size();
}
- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
 const auto rows = [self sidebarRows];
 if (row < 0 || static_cast<size_t>(row) >= rows.size()) return nil;
 if (rows[row].kind != SideRow::Kind::Tab) return nil;
 NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
 [item setString:[NSString stringWithFormat:@"%ld", (long)row] forType:@"slate.tab.drag"];
 [item setString:[NSString stringWithFormat:@"%llu",(unsigned long long)rows[row].tab] forType:@"slate.tab.id"];
 return item;
}
- (TabId)sidebarTabAtRow:(NSInteger)row {
 const auto rows=[self sidebarRows];
 return row>=0 && (size_t)row<rows.size() && rows[row].kind==SideRow::Kind::Tab ? rows[row].tab : 0;
}
- (TabId)sidebarDraggedTab:(id<NSDraggingInfo>)info {
 if(info.draggingSource!=self.tabList) return 0;
 const TabId tab=(TabId)[[info.draggingPasteboard stringForType:@"slate.tab.id"] longLongValue];
 return tab && model.find(tab) && !model.closing(tab) ? tab : 0;
}
- (NSDragOperation)updateSidebarPageDrop:(id<NSDraggingInfo>)info {
 const TabId tab=[self sidebarDraggedTab:info];
 if(!tab) { [self hideSplitDrag]; return NSDragOperationNone; }
 const NSPoint screen=[self.window convertPointToScreen:info.draggingLocation];
 const TabId base=self.splitDragBaseTab ?: model.selected();
 [self updateSplitDragAtScreenPoint:screen tab:tab base:base];
 if(self.splitDropSide) return NSDragOperationMove;
 if(workspace.visible_for(model.selected()) && !workspace.member(tab)) {
  const NSPoint local=[self.content convertPoint:info.draggingLocation fromView:nil];
  if(NSPointInRect(local,self.content.bounds)) {
   const TabId target=local.x<NSWidth(self.content.bounds)*workspace.clamped_ratio(NSWidth(self.content.bounds)) ? workspace.left : workspace.right;
   if([self isSplitPlaceholderTab:target]) return NSDragOperationMove;
  }
 }
 return NSDragOperationNone;
}
- (void)beginSidebarTabGesture:(TabId)identifier {
 if(!identifier || self.splitSourceTab || self.splitDragCandidateTab==identifier) return;
 self.splitDragCandidateTab=identifier;
 self.splitDragBaseTab=model.selected()!=identifier ? model.selected() : 0;
}
- (void)endSidebarTabGesture:(TabId)identifier {
 if(self.splitSourceTab==identifier) return;
 if(self.splitDragCandidateTab==identifier) {
  self.splitDragCandidateTab=0;
  self.splitDragBaseTab=0;
 }
}
- (void)tableView:(NSTableView*)tableView draggingSession:(NSDraggingSession*)session
 willBeginAtPoint:(NSPoint)screenPoint forRowIndexes:(NSIndexSet*)rowIndexes {
 const auto rows=[self sidebarRows];
 const NSUInteger row=rowIndexes.firstIndex;
 if(row==NSNotFound || row>=rows.size() || rows[row].kind!=SideRow::Kind::Tab) return;
 self.splitSourceTab=rows[row].tab;
 if(self.splitDragCandidateTab!=self.splitSourceTab ||
    self.splitDragBaseTab==self.splitSourceTab ||
    (self.splitDragBaseTab && !model.find(self.splitDragBaseTab)))
  self.splitDragBaseTab=0;
 self.splitDragCandidateTab=0;
 if(!self.splitDragBaseTab) self.splitDragBaseTab=model.selected();
 // NSTableView selects a row before beginning a drag. Restore the page that
 // was visible when the gesture began so the drop targets overlay that page.
 if(self.splitDragBaseTab && self.splitDragBaseTab!=self.splitSourceTab)
  [self activateTab:self.splitDragBaseTab];
 [self.splitDragTimer invalidate];
 __weak SlateDelegate* weakSelf=self;
 self.splitDragTimer=[NSTimer timerWithTimeInterval:1.0/30.0 repeats:YES block:^(NSTimer* timer) {
  SlateDelegate* owner=weakSelf;
  if(!owner || !owner.splitSourceTab) { [timer invalidate]; return; }
  [owner updateSplitDragAtScreenPoint:NSEvent.mouseLocation tab:owner.splitSourceTab base:owner.splitDragBaseTab];
 }];
 [NSRunLoop.mainRunLoop addTimer:self.splitDragTimer forMode:NSRunLoopCommonModes];
 [NSRunLoop.mainRunLoop addTimer:self.splitDragTimer forMode:NSEventTrackingRunLoopMode];
}
- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation {
 const TabId source=[self sidebarDraggedTab:info];
 if(!source) return NSDragOperationNone;
 const auto rows=[self sidebarRows];
 if(operation==NSTableViewDropOn) {
  if(row<0 || (size_t)row>=rows.size()) return NSDragOperationNone;
  if(rows[row].kind==SideRow::Kind::Group) return NSDragOperationMove;
  const TabId target=[self sidebarTabAtRow:row];
  return target && target!=source && !workspace.member(source) &&
   (workspace.open_action(source,target)==slate::SplitOpenAction::PairWithBase || [self isSplitPlaceholderTab:target])
   ? NSDragOperationMove : NSDragOperationNone;
 }
 return NSDragOperationMove;
}
- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
 const TabId draggedTabId=[self sidebarDraggedTab:info];
 if(!draggedTabId || row<0) return NO;
 const auto rows=[self sidebarRows];
 if(dropOperation==NSTableViewDropOn && (size_t)row<rows.size() && rows[row].kind==SideRow::Kind::Tab) {
  const TabId target=rows[row].tab;
  return [self isSplitPlaceholderTab:target] ? [self replaceEmptySplitTab:target withTab:draggedTabId]
   : [self openSplitWithTab:draggedTabId side:slate::SplitSide::Right base:target];
 }
 std::string targetGroupId = "";
 TabId beforeTabId = 0;

 if (dropOperation == NSTableViewDropOn && row < static_cast<NSInteger>(rows.size()) && rows[row].kind == SideRow::Kind::Group) {
  targetGroupId = rows[row].group;
  // Placed at the end of the group, so beforeTabId = 0 (but wait, what if there are un-grouped tabs? It would go to the VERY end. Let's find the first tab NOT in this group).
  // Actually, we can just find the first tab after this group.
  for(size_t i = row + 1; i < rows.size(); ++i) {
   if (rows[i].kind == SideRow::Kind::Tab) {
    const auto* t = model.find(rows[i].tab);
    if (t && t->group_id != targetGroupId) {
     beforeTabId = rows[i].tab;
     break;
    }
   } else if (rows[i].kind == SideRow::Kind::Group) {
    // Next group starts. The next tab will definitely be beforeTabId, but we can't get it if it's collapsed.
    // Actually, just finding the next tab in the model that is NOT in this group is easier.
    break;
   }
  }
  if (!beforeTabId) {
   // Let's just find the first tab in model.tabs() that comes after the tabs of this group.
   // This is getting complicated. Let's just use move_tab_before with a 0 beforeTabId to put it at the very end of tabs_, which naturally works since orderedIds groups them!
  }
 } else {
  if (row < static_cast<NSInteger>(rows.size())) {
   if (rows[row].kind == SideRow::Kind::Tab) {
    const auto* t = model.find(rows[row].tab);
    if (t) targetGroupId = t->group_id;
    beforeTabId = rows[row].tab;
   } else if (rows[row].kind == SideRow::Kind::Group) {
    targetGroupId = "";
    // Dropping before a group. This effectively means dropping at the end of the un-grouped tabs.
    // Let's just set targetGroupId = "" and beforeTabId = 0.
   }
  }
 }

 model.set_tab_group(draggedTabId, targetGroupId);
 model.move_tab_before(draggedTabId, beforeTabId);
 [self refresh];
 [self scheduleSave];
 return YES;
}
- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
 [self.splitDragTimer invalidate];
 self.splitDragTimer=nil;
 const TabId draggedTabId=self.splitSourceTab;
 self.splitSourceTab=0;
 self.splitDragCandidateTab=0;
 if(!draggedTabId || !model.find(draggedTabId)) {
  self.splitDragBaseTab=0;
  [self hideSplitDrag];
  return;
 }
 const TabId base=self.splitDragBaseTab ? self.splitDragBaseTab : model.selected();
 const BOOL didSplit=[self finishSplitDragAtScreenPoint:screenPoint tab:draggedTabId base:base];
 self.splitDragBaseTab=0;
 if(didSplit) return;
 NSRect contentScreenRect=[self.window convertRectToScreen:[self.content convertRect:self.content.bounds toView:nil]];
 if(NSPointInRect(screenPoint,contentScreenRect)) return;

 NSRect sidebarScreenRect = [self.window convertRectToScreen:[self.sidebar convertRect:self.sidebar.bounds toView:nil]];
 const BOOL outsideSidebar = !NSPointInRect(screenPoint, NSInsetRect(sidebarScreenRect, -10, -10));

 if (operation == NSDragOperationNone || outsideSidebar) {
  [self tearOffTab:draggedTabId atScreenPoint:screenPoint];
 }
}
- (CGFloat)tableView:(NSTableView*)table heightOfRow:(NSInteger)row {
 const auto rows=[self sidebarRows];
 if(row<0 || static_cast<size_t>(row)>=rows.size()) return [self sidebarIconRail] ? kRailRow : 28;
 if(rows[row].kind==SideRow::Kind::Group) return 26;
 if(rows[row].kind==SideRow::Kind::NewTab) return [self sidebarIconRail] ? kRailRow : 28;
 return [self sidebarIconRail] ? kRailRow : 28;
}
- (NSTableRowView*)tableView:(NSTableView*)table rowViewForRow:(NSInteger)row {
 SlateCapsuleRow* rowView=[[SlateCapsuleRow alloc] initWithFrame:NSZeroRect];
 rowView.owner=self;
 const auto rows=[self sidebarRows];
 if(row>=0 && static_cast<size_t>(row)<rows.size()) {
  if(rows[row].kind==SideRow::Kind::Tab) rowView.tabId=rows[row].tab;
  else if(rows[row].kind==SideRow::Kind::Group) rowView.groupId=Text(rows[row].group);
  else if(rows[row].kind==SideRow::Kind::NewTab) rowView.isNewTabRow=YES;
 }
 return rowView;
}
- (void)tableView:(NSTableView*)table didAddRowView:(NSTableRowView*)rowView forRow:(NSInteger)row {
 if(![rowView isKindOfClass:SlateCapsuleRow.class]) return;
 SlateCapsuleRow* capsule = (SlateCapsuleRow*)rowView;
 capsule.owner=self;
 const auto rows=[self sidebarRows];
 if(row<0 || static_cast<size_t>(row)>=rows.size()) return;
 if(rows[row].kind==SideRow::Kind::Tab) {
  capsule.tabId=rows[row].tab;
  capsule.groupId=nil;
  capsule.isNewTabRow=NO;
 } else if(rows[row].kind==SideRow::Kind::Group) {
  capsule.tabId=0;
  capsule.groupId=Text(rows[row].group);
  capsule.isNewTabRow=NO;
 } else if(rows[row].kind==SideRow::Kind::NewTab) {
  capsule.tabId=0;
  capsule.groupId=nil;
  capsule.isNewTabRow=YES;
 }
 [capsule setNeedsDisplay:YES];
}
- (BOOL)tableView:(NSTableView*)table shouldSelectRow:(NSInteger)row {
 const auto rows=[self sidebarRows];
 if(row<0 || static_cast<size_t>(row)>=rows.size()) return NO;
 return rows[row].kind==SideRow::Kind::Tab;
}
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
 const auto rows=[self sidebarRows];
 if(row<0 || static_cast<size_t>(row)>=rows.size()) return [NSTextField labelWithString:@""];
 if(rows[row].kind==SideRow::Kind::NewTab) {
  const BOOL rail=[self sidebarIconRail];
  SlateInlineAddRow* cell=[[SlateInlineAddRow alloc] initWithFrame:NSZeroRect];
  cell.owner=self;
  cell.isRail=rail;
  cell.autoresizingMask=NSViewWidthSizable | NSViewHeightSizable;
  return cell;
 }
 if(rows[row].kind==SideRow::Kind::Group) {
  const auto* group=model.find_group(rows[row].group);
  const BOOL rail=[self sidebarIconRail];
  const BOOL collapsed=group && group->collapsed;
  NSColor* accentInk=self.accentInk ?: NSColor.labelColor;
  SlateGroupHeader* cell=[[SlateGroupHeader alloc] initWithFrame:NSZeroRect];
  cell.autoresizingMask=NSViewWidthSizable | NSViewHeightSizable;
  NSString* chevronSymbol=collapsed ? @"chevron.right" : @"chevron.down";
  NSImageView* chevron=[[NSImageView alloc] initWithFrame:NSZeroRect];
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* chevronConf=[NSImageSymbolConfiguration configurationWithPointSize:9 weight:NSFontWeightSemibold];
   chevron.image=[[NSImage imageWithSystemSymbolName:chevronSymbol accessibilityDescription:nil]
    imageWithSymbolConfiguration:chevronConf];
  }
  chevron.contentTintColor=[accentInk colorWithAlphaComponent:0.55];
  chevron.translatesAutoresizingMaskIntoConstraints=NO;
  NSTextField* label=[NSTextField labelWithString:group ? Text(group->title) : @"Group"];
  label.font=[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
  label.textColor=[accentInk colorWithAlphaComponent:0.75];
  label.lineBreakMode=NSLineBreakByTruncatingTail;
  label.translatesAutoresizingMaskIntoConstraints=NO;
  cell.toolTip=label.stringValue;
  NSView* dot=[[NSView alloc] initWithFrame:NSZeroRect];
  dot.translatesAutoresizingMaskIntoConstraints=NO;
  dot.wantsLayer=YES;
  dot.layer.cornerRadius=3.0;
  dot.layer.backgroundColor=[accentInk colorWithAlphaComponent:0.60].CGColor;
  if(rail) {
   [cell addSubview:dot];
   [NSLayoutConstraint activateConstraints:@[
    [dot.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor],
    [dot.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    [dot.widthAnchor constraintEqualToConstant:6],
    [dot.heightAnchor constraintEqualToConstant:6]
   ]];
  } else {
   [cell addSubview:chevron];
   [cell addSubview:dot];
   [cell addSubview:label];
   [NSLayoutConstraint activateConstraints:@[
    [chevron.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
    [chevron.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    [chevron.widthAnchor constraintEqualToConstant:10],
    [chevron.heightAnchor constraintEqualToConstant:10],
    [dot.leadingAnchor constraintEqualToAnchor:chevron.trailingAnchor constant:6],
    [dot.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    [dot.widthAnchor constraintEqualToConstant:6],
    [dot.heightAnchor constraintEqualToConstant:6],
    [label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:6],
    [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
    [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
   ]];
  }
  return cell;
 }
 const auto* tab=model.find(rows[row].tab); if(!tab) return [NSTextField labelWithString:@""];
 const BOOL rail=[self sidebarIconRail];
 SlateSideRowCell* cell=[[SlateSideRowCell alloc] initWithFrame:NSZeroRect];
 cell.owner=self;
 cell.autoresizingMask=NSViewWidthSizable | NSViewHeightSizable;
 [cell configureWithTab:*tab isRail:rail];
 return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification*)notification {
 if(self.updatingList || self.quitting || self.splitDragCandidateTab) return;
 const auto rows=[self sidebarRows];
 const NSInteger row=self.tabList.selectedRow;
 if(row>=0 && static_cast<size_t>(row)<rows.size() && rows[row].kind==SideRow::Kind::Tab && rows[row].tab!=model.selected())
  [self activateTab:rows[row].tab];
}
- (void)menuNeedsUpdate:(NSMenu*)menu {
 if(menu!=self.tabList.menu) return;
 const auto rows=[self sidebarRows];
 const NSInteger row=self.tabList.clickedRow>=0 ? self.tabList.clickedRow : self.tabList.selectedRow;
 [menu removeAllItems];
 NSMenu* source=(row>=0 && static_cast<size_t>(row)<rows.size() && rows[row].kind==SideRow::Kind::Group)
  ? [self groupMenu:Text(rows[row].group)] :
    (row>=0 && static_cast<size_t>(row)<rows.size() && rows[row].kind==SideRow::Kind::Tab
      ? [self tabMenuForTab:rows[row].tab] : [self tabMenu]);
 while(source.numberOfItems) {
  NSMenuItem* item=[source itemAtIndex:0];
  [source removeItem:item];
  [menu addItem:item];
 }
}
- (NSMenu*)tabMenu {
 const auto* tab=model.find(model.selected());
 NSMenu* menu=[[NSMenu alloc] init];
 NSMenuItem* siteInfo = [menu addItemWithTitle:@"Site Information…" action:@selector(showSiteCard:) keyEquivalent:@"i"];
 siteInfo.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 siteInfo.target = self;
 if(tab) siteInfo.representedObject = @(tab->id);
 NSMenuItem* pin=[menu addItemWithTitle:(tab && tab->pinned) ? @"Unpin Tab" : @"Pin Tab" action:@selector(togglePin:) keyEquivalent:@""];
 pin.target=self;
 NSMenuItem* keep=[menu addItemWithTitle:@"Keep loaded" action:@selector(toggleProtection:) keyEquivalent:@""];
 keep.target=self; keep.state=tab && tab->protected_content ? NSControlStateValueOn : NSControlStateValueOff;
 NSMenuItem* groupItem=[menu addItemWithTitle:@"Move to Group" action:nil keyEquivalent:@""];
 groupItem.submenu=[self groupPickMenu];
 NSMenuItem* incogTab=[menu addItemWithTitle:@"New Incognito Tab" action:@selector(newIncognitoTab:) keyEquivalent:@"P"];
 incogTab.keyEquivalentModifierMask=NSEventModifierFlagCommand | NSEventModifierFlagShift;
 incogTab.target=self;
 [menu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* newTabItem=[menu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
 newTabItem.target=self;
 NSMenuItem* reopenTab=[menu addItemWithTitle:@"Reopen Closed Tab" action:@selector(reopenClosedTab:) keyEquivalent:@"T"];
 reopenTab.keyEquivalentModifierMask=NSEventModifierFlagCommand | NSEventModifierFlagShift;
 reopenTab.target=self;
 reopenTab.enabled=(self.recentlyClosedUrls.count > 0);
 [menu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* unload=[menu addItemWithTitle:@"Unload Tab…" action:@selector(unloadTab:) keyEquivalent:@""];
 unload.target=self;
 NSMenuItem* restore=[menu addItemWithTitle:@"Restore Tab" action:@selector(restoreTab:) keyEquivalent:@""];
 restore.target=self;
 NSMenuItem* close=[menu addItemWithTitle:@"Close Tab" action:@selector(closeTab:) keyEquivalent:@"w"];
 close.target=self;
 return menu;
}
- (NSMenu*)tabStripMenu {
 NSMenu* menu=[[NSMenu alloc] initWithTitle:@"Tab Strip"];
 NSMenuItem* newTabItem=[menu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
 newTabItem.target=self;

 NSMenuItem* reopenTab=[menu addItemWithTitle:@"Reopen Closed Tab" action:@selector(reopenClosedTab:) keyEquivalent:@"T"];
 reopenTab.keyEquivalentModifierMask=NSEventModifierFlagCommand | NSEventModifierFlagShift;
 reopenTab.target=self;
 reopenTab.enabled=(self.recentlyClosedUrls.count > 0);

 [menu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* bookmarkAll=[menu addItemWithTitle:@"Bookmark All Tabs…" action:@selector(bookmarkAllTabs:) keyEquivalent:@""];
 bookmarkAll.target=self;
 return menu;
}
- (NSMenu*)groupPickMenu {
 NSMenu* menu=[[NSMenu alloc] init];
 NSMenuItem* none=[menu addItemWithTitle:@"None" action:@selector(assignTabGroup:) keyEquivalent:@""];
 none.target=self; none.representedObject=@"";
 const auto* tab=model.find(model.selected());
 none.state=tab && tab->group_id.empty() ? NSControlStateValueOn : NSControlStateValueOff;
 if(!model.groups().empty()) [menu addItem:[NSMenuItem separatorItem]];
 for(const auto& group:model.groups()) {
  NSMenuItem* item=[menu addItemWithTitle:Text(group.title) action:@selector(assignTabGroup:) keyEquivalent:@""];
  item.target=self; item.representedObject=Text(group.id);
  item.state=tab && tab->group_id==group.id ? NSControlStateValueOn : NSControlStateValueOff;
 }
 [menu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* create=[menu addItemWithTitle:@"New Group…" action:@selector(newTabGroup:) keyEquivalent:@""];
 create.target=self;
 return menu;
}
- (NSMenu*)groupMenu:(NSString*)groupId {
 NSMenu* menu=[[NSMenu alloc] init];
 const auto* group=model.find_group(groupId.UTF8String ?: "");
 NSMenuItem* rename=[menu addItemWithTitle:@"Rename Group…" action:@selector(renameTabGroup:) keyEquivalent:@""];
 rename.target=self; rename.representedObject=groupId;
 NSMenuItem* fold=[menu addItemWithTitle:(group && group->collapsed) ? @"Show Tabs" : @"Hide Tabs" action:@selector(toggleNamedGroup:) keyEquivalent:@""];
 fold.target=self; fold.representedObject=groupId;
 NSMenuItem* remove=[menu addItemWithTitle:@"Delete Group" action:@selector(deleteTabGroup:) keyEquivalent:@""];
 remove.target=self; remove.representedObject=groupId;
 return menu;
}
- (void)assignTabGroup:(NSMenuItem*)sender {
 NSString* groupId=[sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : @"";
 if(!model.set_tab_group(model.selected(), groupId.UTF8String ?: "")) return;
 [self refresh]; [self scheduleSave];
}
- (void)toggleGroupCollapsed:(NSString*)groupId {
 if(!groupId.length) return;
 const auto* group=model.find_group(groupId.UTF8String);
 if(!group) return;
 model.set_group_collapsed(groupId.UTF8String, !group->collapsed);
 [self refresh]; [self scheduleSave];
}
- (void)toggleNamedGroup:(NSMenuItem*)sender {
 [self toggleGroupCollapsed:[sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : @""];
}
- (void)newTabGroup:(id)sender {
 NSAlert* alert=[[NSAlert alloc] init];
 alert.messageText=@"New tab group";
 alert.informativeText=@"Name this group. The current tab moves into it.";
 NSTextField* field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,220,24)];
 field.stringValue=@"Group";
 alert.accessoryView=field;
 [alert addButtonWithTitle:@"Create"]; [alert addButtonWithTitle:@"Cancel"];
 [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
  if(response!=NSAlertFirstButtonReturn || self.quitting) return;
  try {
   const auto id=model.add_group(field.stringValue.UTF8String ?: "Group");
   model.set_tab_group(model.selected(), id);
   [self refresh]; [self scheduleSave];
  } catch(const std::exception&) { NSBeep(); }
 }];
}
- (void)renameTabGroup:(NSMenuItem*)sender {
 NSString* groupId=[sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : @"";
 const auto* group=model.find_group(groupId.UTF8String ?: "");
 if(!group) return;
 NSAlert* alert=[[NSAlert alloc] init];
 alert.messageText=@"Rename group";
 NSTextField* field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,220,24)];
 field.stringValue=Text(group->title);
 alert.accessoryView=field;
 [alert addButtonWithTitle:@"Rename"]; [alert addButtonWithTitle:@"Cancel"];
 [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
  if(response!=NSAlertFirstButtonReturn || self.quitting) return;
  if(model.rename_group(groupId.UTF8String ?: "", field.stringValue.UTF8String ?: "")) {
   [self refresh]; [self scheduleSave];
  }
 }];
}
- (void)deleteTabGroup:(NSMenuItem*)sender {
 NSString* groupId=[sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : @"";
 if(model.remove_group(groupId.UTF8String ?: "")) { [self refresh]; [self scheduleSave]; }
}
- (void)updateBookmarkChrome {
 if(!self.bookmarkButton) return;
 const auto* tab=model.find(model.selected());
 const BOOL saved=tab && [[SlateBookmarks sharedStore] containsURL:Text(tab->url)];
 NSString* symbol=saved ? @"star.fill" : @"star";
 NSImage* image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"Bookmark"]
  ?: [NSImage imageWithSystemSymbolName:@"bookmark" accessibilityDescription:@"Bookmark"];
 self.bookmarkButton.image=image;
 self.bookmarkButton.toolTip=saved ? @"Bookmarks (⌘D to toggle)" : @"Bookmarks (⌘D to add)";
 self.bookmarkButton.enabled=tab && tab->url.rfind("http",0)==0;
 self.bookmarkButton.contentTintColor=saved ? [NSColor colorWithCalibratedRed:0.96 green:0.72 blue:0.18 alpha:1.0] : (self.barInk ?: NSColor.labelColor);
}
- (void)toggleBookmark:(id)sender {
 const auto* tab=model.find(model.selected());
 if(!tab || tab->url.rfind("http",0)!=0) { NSBeep(); return; }
 NSString* url = Text(tab->url);
 SlateBookmarks* store = [SlateBookmarks sharedStore];
 SlateBookmark* existing = [store findURL:url];
 if(existing) {
  [store removeWithIdentifier:existing.identifier];
 } else {
  NSString* title = tab->title.empty() ? Text(tab->url) : Text(tab->title);
  [store addURL:url title:title];
 }
 [self updateBookmarkChrome];
 [self rebuildBookmarksBar];
 [self rebuildBookmarksMenu];
 [self rebuildHome];
 [self scheduleSave];
}
- (void)toggleBookmarksDropdown:(id)sender {
 [[SlateBookmarksDropdown sharedDropdown] setOwner:self];
 [[SlateBookmarksDropdown sharedDropdown] toggleForAnchor:self.bookmarkButton inWindow:self.window];
}
- (void)showBookmarksPanel:(id)sender {
 [[SlateBookmarksPanel sharedPanel] setOwner:self];
 [[SlateBookmarksPanel sharedPanel] showBookmarksManager];
}
- (void)openBookmarkButton:(SlateBookmarkButton*)btn {
 if(!btn) return;
 if(btn.node && btn.node.isFolder) {
  [SlateBookmarkMenu popUpFolder:btn.node forView:btn owner:self];
  return;
 }
 if(!btn.urlString.length) return;
 [self openHomeAddress:btn.urlString];
}
- (void)removeBookmarkWithId:(NSString*)bId {
 if(!bId.length) return;
 [[SlateBookmarks sharedStore] removeWithIdentifier:bId];
 [self updateBookmarkChrome];
 [self rebuildBookmarksBar];
 [self rebuildBookmarksMenu];
 [self rebuildHome];
 [self scheduleSave];
}
- (void)toggleBookmarksBar:(id)sender {
 self.showBookmarksBar = !self.showBookmarksBar;
 [self persistUiPrefs];
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
  context.duration = 0.2;
  context.allowsImplicitAnimation = YES;
  self.bookmarksBarHeight.constant = self.showBookmarksBar ? kBookmarksBarHeight : 0;
  self.bookmarksBar.hidden = !self.showBookmarksBar;
 } completionHandler:nil];
}
- (void)rebuildBookmarksBar {
 if(!self.bookmarksStack) return;
 for(NSView* view in [self.bookmarksStack.arrangedSubviews copy]) {
  [self.bookmarksStack removeArrangedSubview:view];
  [view removeFromSuperview];
 }
 SlateBookmarks* store = [SlateBookmarks sharedStore];
 for(SlateBookmark* node in store.roots) {
  NSString* title = node.title.length ? node.title : (node.url ?: @"Untitled");
  if(title.length > 24) {
   title = [[title substringToIndex:22] stringByAppendingString:@"…"];
  }
  SlateBookmarkButton* btn = [SlateBookmarkButton buttonWithTitle:@"" target:self action:@selector(openBookmarkButton:)];
  btn.node = node;
  btn.bookmarkId = node.identifier;
  btn.urlString = node.url ?: @"";
  btn.owner = self;
  btn.bezelStyle = NSBezelStyleInline;
  btn.bordered = NO;
  btn.imagePosition = NSImageLeading;
  btn.imageHugsTitle = YES;
  NSColor* ink = self.barInk ?: NSColor.labelColor;
  NSString* fullTitle = [NSString stringWithFormat:@" %@", title];
  btn.attributedTitle = [[NSAttributedString alloc] initWithString:fullTitle attributes:@{
   NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
   NSForegroundColorAttributeName: ink
  }];
  btn.contentTintColor = ink;
  btn.wantsLayer = YES;
  btn.layer.cornerRadius = 6.0;
  if(@available(macOS 11.0, *)) {
   btn.layer.cornerCurve = kCACornerCurveContinuous;
  }
  btn.layer.masksToBounds = YES;
  btn.toolTip = node.isFolder ? [NSString stringWithFormat:@"Folder: %@ (%lu items)", node.title, (unsigned long)[SlateBookmarks countNodes:node.children]]
                              : [NSString stringWithFormat:@"%@\n%@", node.title, node.url];

  if(node.isFolder) {
   NSImage* fImg = [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:@"Folder"];
   if(fImg) {
    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:10.5 weight:NSFontWeightRegular];
    btn.image = [fImg imageWithSymbolConfiguration:cfg];
   }
  } else {
   NSImage* icon = nil;
   NSString* host = node.host;
   for(TabId tid : [self orderedIds]) {
    const auto* t = model.find(tid);
    if(t && [NSURL URLWithString:Text(t->url)].host.lowercaseString == host) {
     if(self.tabIcons[@(tid)]) {
      icon = self.tabIcons[@(tid)];
      break;
     }
    }
   }
   if(!icon) {
    if(@available(macOS 11.0, *)) {
     NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightRegular];
     icon = [[NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:@"Bookmark"] imageWithSymbolConfiguration:cfg];
    }
   }
   if(!icon) {
    icon = LetterTile(node.title.length ? [node.title substringToIndex:1] : @"B", host ?: @"", 14);
   }
   btn.image = icon;
  }
  btn.translatesAutoresizingMaskIntoConstraints = NO;
  [self.bookmarksStack addArrangedSubview:btn];
 }
}
- (void)rebuildBookmarksMenu {
 if(!self.bookmarksMenu) return;
 while(self.bookmarksMenu.numberOfItems > 5) {
  [self.bookmarksMenu removeItemAtIndex:self.bookmarksMenu.numberOfItems - 1];
 }
 [SlateBookmarkMenu populateMenu:self.bookmarksMenu withBookmarks:[SlateBookmarks sharedStore] owner:self];
}
- (void)onBookmarksChangedNotification:(NSNotification*)note {
 [self updateBookmarkChrome];
 [self rebuildBookmarksBar];
 [self rebuildBookmarksMenu];
 [self rebuildHome];
}
- (void)openHomeURL:(id)sender {
 NSString* url=[sender isKindOfClass:NSButton.class] ? ((NSButton*)sender).identifier : nil;
 if(!url.length && [sender isKindOfClass:NSButton.class]) url=((NSButton*)sender).toolTip;
 [self openHomeAddress:url];
}
- (void)openHomeAddress:(NSString*)url {
 if(!url.length) return;
 if([url hasPrefix:@"info:"]) {
  [self showStealthInfo:nil];
  return;
 }
 self.address.stringValue=url;
 self.addressDirty=YES;
 [self navigate:nil];
}
- (void)openHomeGroupIdent:(NSString*)ident {
 if(![ident hasPrefix:@"group:"]) return;
 std::string gid=[ident substringFromIndex:6].UTF8String;
 for(const auto& tab:model.tabs()) if(tab.group_id==gid) { [self activateTab:tab.id]; return; }
}
- (NSTextField*)homeSearchField {
 return self.homeBoard.omniboxCard.field;
}
- (void)submitHomeSearch:(id)sender {
 [self submitOmniboxCard:self.homeBoard.omniboxCard];
}
- (NSImage*)homeGlyph:(NSString*)symbol {
 NSImage* image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:symbol];
 image.size=NSMakeSize(20,20);
 [image setTemplate:YES];
 return image;
}
- (void)rebuildHome {
 if(!self.homeBoard) return;
 const BOOL systemDark=[[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]]
  isEqualToString:NSAppearanceNameDarkAqua];
 const BOOL isDark=(self.themeMode==1) ? NO : ((self.themeMode==2) ? YES : systemDark);
 NSColor* fill=ChromeAccent(self.accentId, self.accentHex, isDark);

 const auto* curTab=model.find(model.selected());
 const BOOL isIncog=curTab && curTab->incognito;
 NSMutableString* sig=[NSMutableString string];
 [sig appendFormat:@"m%d|a%@|h%@|d%d|%@|%@\n", self.themeMode, self.accentId ?: @"rose", self.accentHex ?: @"", isDark ? 1 : 0, HexFromColor(self.barColor), HexFromColor(self.window.backgroundColor)];
 const NSInteger hour=[[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:[NSDate date]];
 [sig appendFormat:@"h%ld\n",(long)hour];
 [sig appendFormat:@"incog%d\n", isIncog ? 1 : 0];
 if(!isIncog) {
  if(bookmarks) for(const auto& item:bookmarks->items())
   [sig appendFormat:@"b%@|%@\n",Text(item.id),Text(item.title)];
  for(const auto& group:model.groups()) [sig appendFormat:@"g%@|%@\n",Text(group.id),Text(group.title)];
 }
 if([sig isEqualToString:self.homeSignature]) {
  self.homeBoard.omniboxCard.isDarkTheme = isDark;
  [self.homeBoard.omniboxCard applyTheme];
  NSScrollView* scroll=self.homeBoard.enclosingScrollView;
  NSSize clip=scroll ? scroll.contentView.bounds.size : NSZeroSize;
  if(clip.width<8) clip=self.content.bounds.size;
  if(clip.width<8) clip=NSMakeSize(880,560);
  NSRect desiredFrame=NSMakeRect(0,0,MAX(1,clip.width),MAX(clip.height,400));
  if(!NSEqualRects(self.homeBoard.frame, desiredFrame)) {
   self.homeBoard.frame=desiredFrame;
   [self.homeBoard setNeedsLayout:YES];
   [self.homeBoard layoutSubtreeIfNeeded];
  }
  [self.homeBoard setNeedsDisplay:YES];
  return;
 }
 self.homeSignature=sig;
 [self.homeBoard updateGreetingMessage];
 self.homeBoard.wash=fill;
 self.homeBoard.appearance=isDark
  ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]
  : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
 self.homeBoard.omniboxCard.accentColor=fill;
 self.homeBoard.omniboxCard.inkColor=isDark ? [NSColor colorWithCalibratedWhite:0.96 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
 self.homeBoard.omniboxCard.isDarkTheme=isDark;
 self.homeBoard.omniboxCard.delegate=self;
 [self.homeBoard.omniboxCard applyTheme];
 for(SlateHomeOrb* orb in [self.homeBoard.orbs copy]) [orb removeFromSuperview];
 [self.homeBoard.orbs removeAllObjects];

 NSScrollView* scroll=self.homeBoard.enclosingScrollView;
 NSSize clip=scroll ? scroll.contentView.bounds.size : NSZeroSize;
 if(clip.width<8) clip=self.content.bounds.size;
 if(clip.width<8) clip=NSMakeSize(880,560);
 self.homeBoard.frame=NSMakeRect(0,0,MAX(1,clip.width),MAX(clip.height,400));
 [self.homeBoard setNeedsLayout:YES];
 [self.homeView setNeedsLayout:YES];
 [self.homeBoard setNeedsDisplay:YES];
}
- (NSImage*)iconForTab:(const slate::Tab&)tab {
 if(tab.url=="about:blank") return BrowserGlyphImage();
 if(tab.incognito) {
  if(@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg=[NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium];
   NSImage* sym=[[NSImage imageWithSystemSymbolName:@"eyeglasses" accessibilityDescription:@"Incognito"] imageWithSymbolConfiguration:cfg];
   if(!sym) sym=[[NSImage imageWithSystemSymbolName:@"eye.slash" accessibilityDescription:@"Incognito"] imageWithSymbolConfiguration:cfg];
   if(sym) return sym;
  }
  return LetterTile(@"🕶", @"Incognito", kRailMark);
 }
 const CGFloat markSize=[self sidebarIconRail] ? RailMarkForWidth([self sidebarLayoutWidth]) : 16.0;
 NSImage* stored=self.tabIcons[@(tab.id)];
 if(stored) return ClipMark(stored, markSize);
 return LetterTile(TabInitial(tab), TabHost(tab), markSize);
}
- (NSButton*)pillForTab:(const slate::Tab&)tab filled:(BOOL)filled {
 const BOOL regularTabs = (self.tabStyle == 1);
 const BOOL isFilled = regularTabs || filled;
 const BOOL audible=[self tabIsAudible:tab.id];
 NSString* title=isFilled ? TabLabel(tab) : @"";
 SlateTabPill* pill=[SlateTabPill buttonWithTitle:@"" target:self action:@selector(selectPill:)];
 pill.tabId=tab.id;
 pill.bezelStyle=NSBezelStyleFlexiblePush; pill.bordered=NO;
 pill.wantsLayer=YES;
 pill.tag=(NSInteger)tab.id;
 pill.splitPartner=workspace.member(tab.id) && !tab.selected;
 pill.image=[self iconForTab:tab];
 [pill applySelected:tab.selected filled:isFilled hovered:NO title:title incognito:tab.incognito];
 pill.alphaValue=model.live(tab.id) || tab.selected ? 1 : 0.85;
 pill.toolTip=Text(tab.url);
 pill.translatesAutoresizingMaskIntoConstraints=NO;
 const CGFloat width=isFilled ? TabFillWidth(title) : kCompactTabWidth;
 pill.widthConstraint=[pill.widthAnchor constraintEqualToConstant:width];
 pill.widthConstraint.priority=NSLayoutPriorityDefaultLow;
 pill.widthConstraint.active=YES;
 [pill.heightAnchor constraintEqualToConstant:kTabHeight].active=YES;
 [pill setContentHuggingPriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
 [pill setContentCompressionResistancePriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
 return pill;
}
- (CGFloat)availableTabStripWidth {
 CGFloat winW = self.window ? self.window.frame.size.width : 1200.0;
 if (winW <= 100.0) winW = 1200.0;
 CGFloat avail = winW - 112.0 - 42.0 - 30.0;
 return MAX(60.0, avail);
}
- (void)layoutTabPillsWithAvailableWidth:(CGFloat)availW {
 const BOOL regularTabs = (self.tabStyle == 1);
 NSArray<NSView*>* pills = self.tabPills.arrangedSubviews;
 if (pills.count == 0) return;

 const CGFloat spacing = self.tabPills.spacing;
 NSInteger unpinnedCount = 0;
 CGFloat fixedWidthTotal = 0;

 for (NSView* view in pills) {
  if ([view isKindOfClass:SlateTabGroupPill.class]) {
   fixedWidthTotal += ((SlateTabGroupPill*)view).widthConstraint.constant + spacing;
  } else if ([view isKindOfClass:SlateTabPill.class]) {
   SlateTabPill* pill = (SlateTabPill*)view;
   const auto* tab = model.find(pill.tabId);
   if (tab && tab->pinned) {
    fixedWidthTotal += kCompactTabWidth + spacing;
   } else {
    unpinnedCount++;
   }
  }
 }

 if (unpinnedCount == 0) {
  self.tabStripWidth.constant = MIN(availW, MAX(36.0, fixedWidthTotal));
  return;
 }

 if (regularTabs) {
  CGFloat totalSpacing = (pills.count - 1) * spacing;
  CGFloat availForUnpinned = availW - (fixedWidthTotal - unpinnedCount * spacing) - totalSpacing;
  CGFloat targetW = floor(availForUnpinned / (CGFloat)unpinnedCount);
  targetW = MAX(kCompactTabWidth, MIN(154.0, targetW));

  CGFloat calculatedTotal = 0;
  for (NSView* view in pills) {
   if ([view isKindOfClass:SlateTabPill.class]) {
    SlateTabPill* pill = (SlateTabPill*)view;
    const auto* tab = model.find(pill.tabId);
    if (tab && tab->pinned) {
     pill.widthConstraint.constant = kCompactTabWidth;
     calculatedTotal += kCompactTabWidth + spacing;
    } else {
     pill.widthConstraint.constant = targetW;
     calculatedTotal += targetW + spacing;
     if (pill.closeButton) {
      if (pill.selectedTab) {
       pill.closeButton.hidden = (targetW < 48.0);
      } else {
       pill.closeButton.hidden = !pill.hovered || (targetW < 54.0);
      }
     }
    }
   } else if ([view isKindOfClass:SlateTabGroupPill.class]) {
    calculatedTotal += ((SlateTabGroupPill*)view).widthConstraint.constant + spacing;
   }
  }
  self.tabStripWidth.constant = MIN(availW, MAX(36.0, calculatedTotal));
 } else {
  CGFloat naturalTotal = 0;
  for (NSView* view in pills) {
   if ([view isKindOfClass:SlateTabPill.class]) {
    SlateTabPill* pill = (SlateTabPill*)view;
    const auto* tab = model.find(pill.tabId);
    if (!tab) continue;
    const BOOL hovered = (pill.tabId == self.hoveredTabId);
    const BOOL filled = tab->selected || hovered || workspace.member(tab->id) || TabHasMedia(*tab) || [self tabIsAudible:tab->id];
    NSString* title = filled ? (hovered && !tab->selected ? TabPeekLabel(*tab, YES) : TabLabel(*tab)) : @"";
    CGFloat naturalW = filled ? TabFillWidth(title) : kCompactTabWidth;
    naturalTotal += naturalW + spacing;
   } else if ([view isKindOfClass:SlateTabGroupPill.class]) {
    naturalTotal += ((SlateTabGroupPill*)view).widthConstraint.constant + spacing;
   }
  }

  CGFloat scale = 1.0;
  if (naturalTotal > availW && naturalTotal > 0) {
   scale = availW / naturalTotal;
  }

  CGFloat calculatedTotal = 0;
  for (NSView* view in pills) {
   if ([view isKindOfClass:SlateTabPill.class]) {
    SlateTabPill* pill = (SlateTabPill*)view;
    const auto* tab = model.find(pill.tabId);
    if (!tab) continue;
    const BOOL hovered = (pill.tabId == self.hoveredTabId);
    const BOOL filled = tab->selected || hovered || workspace.member(tab->id) || TabHasMedia(*tab) || [self tabIsAudible:tab->id];
    NSString* title = filled ? (hovered && !tab->selected ? TabPeekLabel(*tab, YES) : TabLabel(*tab)) : @"";
    CGFloat naturalW = filled ? TabFillWidth(title) : kCompactTabWidth;
    CGFloat targetW = filled ? MAX(kCompactTabWidth, floor(naturalW * scale)) : kCompactTabWidth;
    pill.widthConstraint.constant = targetW;
    calculatedTotal += targetW + spacing;
    if (pill.closeButton) {
     pill.closeButton.hidden = !(filled && (hovered || tab->selected)) || (targetW < 45.0);
    }
   } else if ([view isKindOfClass:SlateTabGroupPill.class]) {
    calculatedTotal += ((SlateTabGroupPill*)view).widthConstraint.constant + spacing;
   }
  }
  self.tabStripWidth.constant = MIN(availW, MAX(36.0, calculatedTotal));
 }
}
- (CGFloat)stripWidthForPills {
 CGFloat width=4;
 for(NSView* view in self.tabPills.arrangedSubviews) {
  if([view isKindOfClass:SlateTabPill.class]) {
   width += ((SlateTabPill*)view).widthConstraint.constant + self.tabPills.spacing;
  } else if([view isKindOfClass:SlateTabGroupPill.class]) {
   width += ((SlateTabGroupPill*)view).widthConstraint.constant + self.tabPills.spacing;
  }
 }
 return MAX(36, MIN([self availableTabStripWidth], width));
}
- (void)animateBubble:(SlateTabPill*)pill {
 if(!pill) return;
 pill.alphaValue=0;
 CASpringAnimation* spring=[CASpringAnimation animationWithKeyPath:@"transform.scale"];
 spring.fromValue=@0.42; spring.toValue=@1;
 spring.mass=0.65; spring.stiffness=220; spring.damping=16;
 spring.duration=MAX(0.28,spring.settlingDuration);
 [pill.layer addAnimation:spring forKey:@"bubble"];
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
  context.duration=0.28;
  context.timingFunction=[CAMediaTimingFunction functionWithControlPoints:0.16 :1.05 :0.3 :1];
  pill.animator.alphaValue=1;
 }];
}
- (void)setPlusVisible:(BOOL)visible {
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
  context.duration=0.18;
  context.timingFunction=[CAMediaTimingFunction functionWithControlPoints:0.2 :0.9 :0.22 :1];
  context.allowsImplicitAnimation=YES;
  self.addWidth.animator.constant=26;
  self.addButton.animator.alphaValue=visible ? 1.0 : 0.72;
 }];
}
- (void)tabClusterHover:(BOOL)inside {
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideTabChrome) object:nil];
 if(inside) {
  self.tabClusterHot=YES;
  [self setPlusVisible:YES];
 } else {
  [self performSelector:@selector(hideTabChrome) withObject:nil afterDelay:0.22];
 }
}
- (void)hideTabChrome {
 self.tabClusterHot=NO;
 self.hoveredTabId=0;
 [self setPlusVisible:NO];
 [self applyHoverExpansion];
}
- (void)hoverTab:(TabId)identifier {
 if(self.hoveredTabId==identifier) return;
 self.hoveredTabId=identifier;
 [self applyHoverExpansion];
}
- (void)updateSplitTabShape {
 if(!self.tabPills) return;
 NSArray<NSView*>* views=self.tabPills.arrangedSubviews;
 NSMutableArray<NSArray<SlateTabPill*>*>* pairs=[NSMutableArray array];
 NSMutableSet<NSNumber*>* connectedIds=[NSMutableSet set];
 for(NSUInteger i=1;i<views.count;++i) {
  NSView* a=views[i-1];
  NSView* b=views[i];
  if(![a isKindOfClass:SlateTabPill.class] || ![b isKindOfClass:SlateTabPill.class]) continue;
  SlateTabPill* first=(SlateTabPill*)a;
  SlateTabPill* second=(SlateTabPill*)b;
  if(!workspace.same_pair(first.tabId,second.tabId)) continue;
  [pairs addObject:@[first,second]];
  [connectedIds addObject:@(first.tabId)];
  [connectedIds addObject:@(second.tabId)];
 }
 for(NSView* view in views) if([view isKindOfClass:SlateTabPill.class]) {
  SlateTabPill* pill=(SlateTabPill*)view;
  const BOOL connected=[connectedIds containsObject:@(pill.tabId)];
  if(pill.splitConnected!=connected) { pill.splitConnected=connected; [pill updateTabShape]; }
 }
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 for(NSUInteger i=0;i<pairs.count;++i) {
  if(i>=self.splitTabShapeLayers.count) {
   CAShapeLayer* shape=[CAShapeLayer layer];
   CALayer* separator=[CALayer layer];
   [self.tabPills.layer insertSublayer:shape atIndex:0];
   [self.tabPills.layer insertSublayer:separator above:shape];
   [self.splitTabShapeLayers addObject:shape];
   [self.splitTabSeparatorLayers addObject:separator];
  }
  SlateTabPill* first=pairs[i][0];
  SlateTabPill* second=pairs[i][1];
  CAShapeLayer* shape=self.splitTabShapeLayers[i];
  CALayer* separator=self.splitTabSeparatorLayers[i];
  if(NSWidth(first.frame)<1 || NSWidth(second.frame)<1) {
   shape.hidden=YES; separator.hidden=YES; continue;
  }
  const NSRect pairFrame=NSUnionRect(first.frame,second.frame);
  const BOOL foreground=workspace.visible_for(model.selected()) && workspace.contains(first.tabId);
  shape.hidden=NO;
  shape.frame=pairFrame;
  const CGRect bounds=CGRectMake(0,0,NSWidth(pairFrame),NSHeight(pairFrame));
  CGPathRef path=foreground
   ? CreateActiveBrowserTabPath(bounds,self.tabPills.isFlipped)
   : CGPathCreateWithRoundedRect(CGRectInset(bounds,0,2),9,9,nullptr);
  shape.path=path;
  CGPathRelease(path);
  NSColor* base=self.window.backgroundColor ?: NSColor.windowBackgroundColor;
  NSColor* surface=foreground ? (self.barColor ?: NSColor.windowBackgroundColor)
   : [base blendedColorWithFraction:0.10 ofColor:NSColor.labelColor];
  shape.fillColor=surface.CGColor;
  separator.hidden=NO;
  separator.frame=CGRectMake(NSMaxX(first.frame)-0.5,NSMidY(pairFrame)-9,1,18);
  separator.backgroundColor=[InkOn(surface) colorWithAlphaComponent:0.16].CGColor;
 }
 while(self.splitTabShapeLayers.count>pairs.count) {
  [self.splitTabShapeLayers.lastObject removeFromSuperlayer];
  [self.splitTabSeparatorLayers.lastObject removeFromSuperlayer];
  [self.splitTabShapeLayers removeLastObject];
  [self.splitTabSeparatorLayers removeLastObject];
 }
 [CATransaction commit];
}
- (void)paintTabStripAnimated:(BOOL)animated {
 if(![self stripRevealed]) return;
 const BOOL regularTabs = (self.tabStyle == 1);
 void (^paint)(void)=^{
  for(NSView* view in self.tabPills.arrangedSubviews) {
   if([view isKindOfClass:SlateTabGroupPill.class]) {
    [(SlateTabGroupPill*)view updateStyle];
    continue;
   }
   if(![view isKindOfClass:SlateTabPill.class]) continue;
   SlateTabPill* pill=(SlateTabPill*)view;
   const auto* tab=model.find(pill.tabId);
   if(!tab) continue;
   const BOOL hovered=pill.tabId==self.hoveredTabId;
   const BOOL filled=regularTabs || tab->selected || hovered || workspace.member(tab->id) || TabHasMedia(*tab) || [self tabIsAudible:tab->id];
   NSString* title=filled ? (hovered && !tab->selected && !regularTabs ? TabPeekLabel(*tab, YES) : TabLabel(*tab)) : @"";
   pill.image=[self iconForTab:*tab];
   pill.splitPartner=workspace.member(tab->id) && !tab->selected;
   [pill applySelected:tab->selected filled:filled hovered:hovered title:title incognito:tab->incognito];
   pill.toolTip=Text(tab->url);
  }
  [self layoutTabPillsWithAvailableWidth:[self availableTabStripWidth]];
  [self updateSplitTabShape];
 };
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 paint();
 [CATransaction commit];
 (void)animated;
}
- (void)applyHoverExpansion {
 [self paintTabStripAnimated:YES];
}
- (void)rebuildTabStrip {
 for(CAShapeLayer* layer in self.splitTabShapeLayers) layer.hidden=YES;
 for(CALayer* layer in self.splitTabSeparatorLayers) layer.hidden=YES;
 for(NSView* view in [self.tabPills.arrangedSubviews copy]) {
  [self.tabPills removeArrangedSubview:view]; [view removeFromSuperview];
 }
 if(![self stripRevealed]) {
  self.tabStripWidth.constant=0;
  self.addWidth.constant=0; self.addButton.alphaValue=0;
  return;
 }
 self.addWidth.constant=26; self.addButton.alphaValue=0.72;
 const TabId bubble=self.bubbleTabId; self.bubbleTabId=0;
 (void)bubble;

 std::set<TabId> placed;
 const BOOL regularTabs = (self.tabStyle == 1);

 // 1. Pinned tabs first
 for(TabId identifier:[self orderedIds]) {
  const auto* tab=model.find(identifier);
  if(tab && tab->pinned) {
   BOOL filled=regularTabs || tab->selected || identifier==self.hoveredTabId || workspace.member(identifier) || TabHasMedia(*tab) || [self tabIsAudible:identifier];
   SlateTabPill* pill=(SlateTabPill*)[self pillForTab:*tab filled:filled];
   pill.groupId=nil;
   pill.groupColor=nil;
   [pill updateTabShape];
   [self.tabPills addArrangedSubview:pill];
   placed.insert(identifier);
  }
 }

 // 2. Groups
 for(const auto& group:model.groups()) {
  std::vector<TabId> groupTabs;
  for(const auto& tab:model.tabs()) {
   if(!placed.contains(tab.id) && tab.group_id==group.id &&
      !(workspace.member(tab.id) && !tab.pinned)) {
    groupTabs.push_back(tab.id);
   }
  }
  if(groupTabs.empty()) continue;

  NSColor* gColor = TabGroupColorForId(group.id, group.title);
  SlateTabGroupPill* gPill = [[SlateTabGroupPill alloc] initWithFrame:NSMakeRect(0,0,70,kTabHeight)];
  gPill.owner = self;
  gPill.groupId = Text(group.id);
  gPill.groupTitle = Text(group.title);
  gPill.groupColor = gColor;
  gPill.collapsed = group.collapsed;
  gPill.tabCount = groupTabs.size();
  [gPill updateStyle];
  [self.tabPills addArrangedSubview:gPill];

  if(!group.collapsed) {
   for(TabId gid : groupTabs) {
    const auto* tab = model.find(gid);
    if(!tab) continue;
    BOOL filled=regularTabs || tab->selected || gid==self.hoveredTabId || workspace.member(gid) || TabHasMedia(*tab) || [self tabIsAudible:gid];
    SlateTabPill* pill=(SlateTabPill*)[self pillForTab:*tab filled:filled];
    pill.groupId=Text(group.id);
    pill.groupColor=gColor;
    [pill updateTabShape];
    [self.tabPills addArrangedSubview:pill];
    placed.insert(gid);
   }
  } else {
   for(TabId gid : groupTabs) placed.insert(gid);
  }
 }
 // 3. Ungrouped unpinned tabs
 for(TabId identifier:[self orderedIds]) {
  if(placed.contains(identifier)) continue;
  const auto pair=workspace.pair_for(identifier);
  if(pair && model.find(pair->left) && model.find(pair->right) &&
     !model.find(pair->left)->pinned && !model.find(pair->right)->pinned) {
   for(TabId pairId : {pair->left,pair->right}) {
    const auto* paired=model.find(pairId);
    BOOL filled=YES;
    SlateTabPill* pill=(SlateTabPill*)[self pillForTab:*paired filled:filled];
    pill.groupId=nil;
    pill.groupColor=nil;
    [pill updateTabShape];
    [self.tabPills addArrangedSubview:pill];
    placed.insert(pairId);
   }
   continue;
  }
  const auto* tab=model.find(identifier);
  if(!tab) continue;
  BOOL filled=regularTabs || tab->selected || identifier==self.hoveredTabId || TabHasMedia(*tab) || [self tabIsAudible:identifier];
  SlateTabPill* pill=(SlateTabPill*)[self pillForTab:*tab filled:filled];
  pill.groupId=nil;
  pill.groupColor=nil;
  [pill updateTabShape];
  [self.tabPills addArrangedSubview:pill];
  placed.insert(identifier);
 }

 // Each split pair shares one backing shape, so its tabs have no internal gap.
 NSArray<NSView*>* stripViews=self.tabPills.arrangedSubviews;
 for(NSUInteger i=1;i<stripViews.count;++i) {
  NSView* previous=stripViews[i-1];
  NSView* current=stripViews[i];
  if([previous isKindOfClass:SlateTabPill.class] && [current isKindOfClass:SlateTabPill.class] &&
     workspace.same_pair(((SlateTabPill*)previous).tabId,((SlateTabPill*)current).tabId))
   [self.tabPills setCustomSpacing:0 afterView:previous];
 }

 [self layoutTabPillsWithAvailableWidth:[self availableTabStripWidth]];
 [self.tabPills layoutSubtreeIfNeeded];
 [self updateSplitTabShape];
}
- (void)selectPill:(NSButton*)sender {
 TabId identifier=[sender isKindOfClass:SlateTabPill.class] ? ((SlateTabPill*)sender).tabId : (TabId)sender.tag;
 [self handleTabClick:identifier doubleClick:NO];
}
- (void)handleTabClick:(TabId)identifier doubleClick:(BOOL)doubleClick {
 if(!identifier || self.quitting) return;
 const BOOL already=identifier==model.selected();
 if(!already) [self activateTab:identifier];
 if(doubleClick) {
  [self focusAddress:nil];
 }
}
- (void)scheduleRefresh {
 if(self.refreshQueued || self.quitting) return;
 self.refreshQueued=YES;
 dispatch_async(dispatch_get_main_queue(), ^{
  self.refreshQueued=NO;
  if(!self.quitting) [self refresh];
 });
}
- (void)refresh {
 for(SlateDetachedTabWindow* detached in self.detachedTabs.allValues) [detached refresh];
 self.sideRowsGen++;
 NSMutableString* structure=[NSMutableString string];
 NSMutableString* paint=[NSMutableString string];
 NSMutableString* stripId=[NSMutableString string];
 [structure appendFormat:@"v%d c%d\n",self.verticalTabs,self.tabsCollapsed];
 [stripId appendFormat:@"v%d c%d\n",self.verticalTabs,self.tabsCollapsed];
 for(const auto& item:model.tabs()) {
  if(self.detachedTabs[@(item.id)]) continue;
  [structure appendFormat:@"%llu|%d|%d|%d|%d|%d|%d|%@\n",
   static_cast<unsigned long long>(item.id),item.selected,model.closing(item.id),static_cast<int>(item.state),item.pinned,
   item.protection.media_elements?1:0,[self tabIsAudible:item.id]?1:0,Text(item.group_id)];
  [paint appendFormat:@"%llu|%@|%@\n",static_cast<unsigned long long>(item.id),Text(item.title),Text(item.url)];
  [stripId appendFormat:@"%llu|%d|%d|%@\n",
   static_cast<unsigned long long>(item.id),model.closing(item.id),item.pinned,Text(item.group_id)];
 }
 for(const auto& group:model.groups()) {
  [structure appendFormat:@"g|%@|%d|%@\n",Text(group.id),group.collapsed?1:0,Text(group.title)];
  [stripId appendFormat:@"g|%@|%d|%@\n",Text(group.id),group.collapsed?1:0,Text(group.title)];
 }
 auto stripPairs=workspace.pairs();
 std::sort(stripPairs.begin(),stripPairs.end(),[](const auto& a,const auto& b){
  return std::min(a.left,a.right)<std::min(b.left,b.right);
 });
 for(const auto& pair:stripPairs) {
  [stripId appendFormat:@"split|%llu|%llu\n",static_cast<unsigned long long>(pair.left),static_cast<unsigned long long>(pair.right)];
  [structure appendFormat:@"split|%llu|%llu\n",static_cast<unsigned long long>(pair.left),static_cast<unsigned long long>(pair.right)];
 }
 self.updatingList=YES;
 const BOOL listChanged=![self.tabListSignature isEqualToString:structure];
 const BOOL paintChanged=![self.tabPaintSignature isEqualToString:paint];
 const BOOL stripChanged=![self.tabStripIdentity isEqualToString:stripId];
 const BOOL selectChanged=self.displayedTab && self.displayedTab!=model.selected();
 if([self sidebarRevealed]) [self syncTabListColumnWidth];
 if(listChanged) {
  self.tabListSignature=structure;
  [self.tabList reloadData];
 } else if(paintChanged && [self sidebarRevealed] && ![self sidebarIconRail]) {
  const NSInteger n=self.tabList.numberOfRows;
  if(n>0) [self.tabList reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,(NSUInteger)n)]
   columnIndexes:[NSIndexSet indexSetWithIndex:0]];
 }
 self.tabPaintSignature=paint;
 if(stripChanged) { self.tabStripIdentity=stripId; [self rebuildTabStrip]; }
 else if(paintChanged || selectChanged) [self paintTabStripAnimated:selectChanged];
 const auto& rows=[self sidebarRows];
 BOOL foundSelectedRow=NO;
 for(size_t i=0;i<rows.size();++i) {
  if(rows[i].kind==SideRow::Kind::Tab && rows[i].tab==model.selected()) {
   foundSelectedRow=YES;
   if(self.tabList.selectedRow!=static_cast<NSInteger>(i))
    [self.tabList selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
   break;
  }
 }
 if(!foundSelectedRow && self.tabList.selectedRow >= 0) {
  [self.tabList deselectAll:nil];
 }
 self.updatingList=NO;
 if(self.pinnedGrid) {
  std::vector<slate::Tab> visibleTabs;
  for(const auto& item:model.tabs()) if(!self.detachedTabs[@(item.id)]) visibleTabs.push_back(item);
  [self.pinnedGrid rebuildWithTabs:visibleTabs selectedId:model.selected()];
 }
 if(self.sidebarFoot) [self.sidebarFoot updateDoors];
 const auto id=model.selected(); const auto* tab=model.find(id);
 const BOOL tabChanged=self.displayedTab!=id;
 const BOOL splitChanged=self.displayedSplitLeft!=workspace.left || self.displayedSplitRight!=workspace.right;
 const BOOL splitVisible=workspace.visible_for(id);
 const auto* leftTab=splitVisible ? model.find(workspace.left) : nullptr;
 const auto* rightTab=splitVisible ? model.find(workspace.right) : nullptr;
 const BOOL anyHome=(tab && tab->url=="about:blank") ||
  (leftTab && leftTab->url=="about:blank") || (rightTab && rightTab->url=="about:blank");
 const BOOL homeChanged=self.homeView.hidden==anyHome;
 if(!listChanged && !stripChanged && !tabChanged && !selectChanged && !homeChanged && !splitChanged) {
  if(tab) {
   // Keep window title static ("Slate") to prevent AppKit's -[NSThemeFrame _updateTitleProperties:animated:YES] from animating traffic lights on tab switch.
   const BOOL blank=tab->url=="about:blank";
   const BOOL editing=self.addressOpen || self.address.currentEditor!=nil;
   const BOOL keepTyped=self.addressDirty && (blank || editing);
   if(!keepTyped && !editing) {
    NSString* shown=Text(tab->url);
    if([shown isEqualToString:@"about:blank"] || [shown isEqualToString:@"about:blank#popup"]) shown=@"";
    if(![self.address.stringValue isEqualToString:shown]) self.address.stringValue=shown;
   }
  }
  if(paintChanged) [self updateBookmarkChrome];
  return;
 }
 self.address.enabled=!self.quitting && tab && !model.closing(id);
 self.protectButton.enabled=self.address.enabled;
 self.protectButton.state=tab && tab->protected_content ? NSControlStateValueOn : NSControlStateValueOff;
 self.unloadButton.enabled=self.address.enabled && model.live(id) && tab && !tab->protected_content;
 const BOOL home=tab && tab->url=="about:blank";
 self.placeholder.hidden=model.live(id) || home;
 self.homeView.hidden=!anyHome;
 if(anyHome) [self rebuildHome];
 [self layoutOmnibox];
 [self updateShieldsChrome];
 [self updateBookmarkChrome];
 [self updateNavChrome];
 [self presentWorkspacePages];
 if(tab) {
  const BOOL blank=tab->url=="about:blank";
  const BOOL editing=self.addressOpen || self.address.currentEditor!=nil;
  if(tabChanged) { self.addressDirty=NO; if(!blank) self.addressOpen=NO; }
  const BOOL keepTyped=!tabChanged && self.addressDirty && (blank || editing);
  if(!keepTyped && (tabChanged || !editing)) {
   NSString* shown=Text(tab->url);
   if([shown isEqualToString:@"about:blank"] || [shown isEqualToString:@"about:blank#popup"]) shown=@"";
   self.address.stringValue=shown;
   if(!blank) self.addressDirty=NO;
  }
 self.displayedTab=id;
  self.displayedSplitLeft=workspace.left;
  self.displayedSplitRight=workspace.right;
  // Keep window title static ("Slate") to prevent AppKit's -[NSThemeFrame _updateTitleProperties:animated:YES] from animating traffic lights on tab switch.
 if(tabChanged || homeChanged) [self applyPlateChrome];
 }
 [self syncPageGeometry];
 self.verticalMenuItem.state=self.verticalTabs ? NSControlStateValueOn : NSControlStateValueOff;
 if(self.hideTabsMenuItem)
  self.hideTabsMenuItem.title=self.tabsCollapsed ? @"Show Tabs" : @"Hide Tabs";
}
- (void)presentWorkspacePages {
 const TabId id=model.selected();
 const BOOL tabChanged=self.displayedTab!=id;
 const BOOL splitVisible=workspace.visible_for(id);
 const auto* tab=model.find(id);
 const auto* left=splitVisible ? model.find(workspace.left) : nullptr;
 const auto* right=splitVisible ? model.find(workspace.right) : nullptr;
 self.homeView.hidden=!((tab && tab->url=="about:blank") ||
  (left && left->url=="about:blank") || (right && right->url=="about:blank"));
 self.placeholder.hidden=model.live(id) || (tab && tab->url=="about:blank");
 // Size the incoming pane containers before attaching/showing their WebKit
 // hosts. The chrome and tab-list repaint can run on the next main-loop turn.
 [self syncPageGeometry];
 for(auto& [identifier,item]:runtimes) {
  if(self.detachedTabs[@(identifier)]) continue;
  const auto* paneTab=model.find(identifier);
  const BOOL show=(splitVisible ? workspace.contains(identifier) : identifier==id) &&
   paneTab && paneTab->url!="about:blank";
  if(!item.host) continue;
  if(show) {
   item.hide_scheduled=false;
   NSView* pageParent=splitVisible
    ? (identifier==workspace.left ? self.splitLeftPane : self.splitRightPane)
    : self.content;
   if(pageParent && item.host.superview!=pageParent) {
    if(pageParent==self.content) [self.content addSubview:item.host positioned:NSWindowBelow relativeTo:self.homeView];
    else [pageParent addSubview:item.host];
    if(item.engine) item.engine->host_geometry_changed();
   }
   item.host.hidden=NO;
   if(item.engine) item.engine->set_occluded(NO);
 if(tabChanged && identifier==id && item.engine) item.engine->focus();
  } else if(!item.host.hidden && !item.hide_scheduled) {
   item.hide_scheduled=true;
   const TabId hid=identifier;
   const BOOL video=item.video_playing || item.audible;
   if(tabChanged && item.video_playing && item.user_started_media)
    [self requestAutoPiPForTab:hid origin:1];
   if(!video && !item.pip_active && item.engine) item.engine->set_occluded(YES);
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if(self.quitting) return;
    auto later=runtimes.find(hid);
    if(later==runtimes.end() || self.detachedTabs[@(hid)] || hid==model.selected() ||
       (workspace.visible_for(model.selected()) && workspace.contains(hid))) {
     if(later!=runtimes.end()) later->second.hide_scheduled=false;
     return;
    }
    // Keep WebKit attached and visible behind the new tab until native PiP
    // either starts or the short entry attempt times out.
    if(later->second.auto_pip_origin != 0 && !later->second.pip_active) {
     later->second.hide_scheduled=false;
     return;
    }
    later->second.host.hidden=YES;
    later->second.hide_scheduled=false;
    if(later->second.engine && !later->second.pip_active) {
     later->second.engine->set_occluded(YES);
    }
   });
  } else if(item.host.hidden && item.engine && !item.pip_active) {
   item.engine->set_occluded(YES);
  }
 }
 [self syncBrowserOcclusion];

 // A single-page host can remain visible briefly for native PiP. Put the
 // incoming slots above every outgoing surface, below home and split overlays.
 // Sorting preserves window attachment, unlike removing and re-adding pages.
 NSMutableArray<NSView*>* order=[self.content.subviews mutableCopy];
 NSMutableArray<NSView*>* slots=[NSMutableArray array];
 if(splitVisible) [slots addObjectsFromArray:@[self.splitLeftPane,self.splitRightPane]];
 else if(auto it=runtimes.find(id);it!=runtimes.end() && it->second.host.superview==self.content)
  [slots addObject:it->second.host];
 for(NSView* slot in slots) {
  [order removeObjectIdenticalTo:slot];
  const NSUInteger home=[order indexOfObjectIdenticalTo:self.homeView];
  [order insertObject:slot atIndex:home==NSNotFound ? order.count : home];
 }
 if(![order isEqualToArray:self.content.subviews]) {
  [self.content sortSubviewsUsingFunction:[](__kindof NSView* _Nonnull a,__kindof NSView* _Nonnull b,void* _Nullable context) -> NSComparisonResult {
   NSArray<NSView*>* order=(__bridge NSArray<NSView*>*)context;
   const NSUInteger first=[order indexOfObjectIdenticalTo:a], second=[order indexOfObjectIdenticalTo:b];
   return first<second ? NSOrderedAscending : first>second ? NSOrderedDescending : NSOrderedSame;
  } context:(__bridge void*)order];
 }
 [self syncPageGeometry];
}
- (void)observePageEvent:(NSEvent*)event {
 if(self.quitting || event.window!=self.window || !self.content) return;
 if(event.type==NSEventTypeLeftMouseDown && self.tabList && !self.tabList.hiddenOrHasHiddenAncestor) {
  NSPoint point=[self.tabList convertPoint:event.locationInWindow fromView:nil];
  NSView* hit=[self.tabList hitTest:point];
  if(NSPointInRect(point,self.tabList.bounds) && ![hit isKindOfClass:NSButton.class]) {
   const TabId tab=[self sidebarTabAtRow:[self.tabList rowAtPoint:point]];
   if(tab) [self beginSidebarTabGesture:tab];
  }
 }
 BOOL interacts=NO;
 if(event.type==NSEventTypeLeftMouseDown || event.type==NSEventTypeRightMouseDown || event.type==NSEventTypeOtherMouseDown) {
  NSPoint point=[self.content convertPoint:event.locationInWindow fromView:nil];
  interacts=NSPointInRect(point,self.content.bounds);
  if(interacts && workspace.visible_for(model.selected())) {
   const CGFloat cut=round(NSWidth(self.content.bounds)*workspace.clamped_ratio(NSWidth(self.content.bounds)));
   const TabId pane=point.x<cut ? workspace.left : workspace.right;
   if(pane && pane!=model.selected()) [self activateTab:pane];
  }
 } else if(event.type==NSEventTypeKeyDown) {
  NSResponder* responder=self.window.firstResponder;
  interacts=[responder isKindOfClass:NSView.class] && [(NSView*)responder isDescendantOf:self.content];
 }
 if(interacts && model.live(model.selected())) model.note_interaction(model.selected());
}
- (void)syncBrowserOcclusion {
 const BOOL windowVisible=self.window && !self.quitting && !self.window.miniaturized &&
  (self.window.occlusionState & NSWindowOcclusionStateVisible)!=0;
 const TabId selected=model.selected();
 for(auto& [identifier,item]:runtimes) {
  if(!item.engine) continue;
  if(SlateDetachedTabWindow* detached=self.detachedTabs[@(identifier)]) {
   const BOOL visible=detached.window.visible && !detached.window.miniaturized &&
    (detached.window.occlusionState&NSWindowOcclusionStateVisible)!=0;
   item.engine->set_occluded(!visible);
   continue;
  }
  if(item.pip_active || item.auto_pip_origin != 0) { item.engine->set_occluded(NO); continue; }
  if(!windowVisible) { item.engine->set_occluded(YES); continue; }
  const auto* paneTab=model.find(identifier);
  const BOOL show=(workspace.visible_for(selected) ? workspace.contains(identifier) : identifier==selected) &&
   paneTab && paneTab->url!="about:blank";
  if(!show && item.hide_scheduled && item.video_playing) continue;
  item.engine->set_occluded(!show);
 }
}
- (void)windowDidChangeOcclusionState:(NSNotification*)notification {
 (void)notification;
 [self syncBrowserOcclusion];
}
- (void)windowDidMiniaturize:(NSNotification*)notification {
 (void)notification;
 [self autoPiPForVisibleWorkspace];
 [self syncBrowserOcclusion];
}
- (void)windowDidDeminiaturize:(NSNotification*)notification {
 (void)notification;
 [self returnAutoPiPForVisibleWorkspace];
 [self syncBrowserOcclusion];
}
- (void)memoryChanged:(slate::MemorySample)sample {
 const BOOL pressureChanged=sample.pressure!=memorySample.pressure || sample.pressure_known!=memorySample.pressure_known;
 memorySample=sample;
 if(self.quitting) return;
 if(sample.pressure==slate::Pressure::Warning || sample.pressure==slate::Pressure::Critical) {
  [self syncBrowserOcclusion];
  for(auto& [identifier,item]:runtimes) if(item.engine) item.engine->trim_memory();
 }
 if(pressureChanged)
  fprintf(stderr,"SLATE_MEMORY pressure=%s main_process_bytes=%llu automatic=off\n",
   !sample.pressure_known ? "unknown" : sample.pressure==slate::Pressure::Critical ? "critical" : sample.pressure==slate::Pressure::Warning ? "warning" : "normal",
   static_cast<unsigned long long>(sample.browser_footprint_bytes));
}
- (void)scheduleSave {
 if(self.quitting) return;
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveSession) object:nil];
 [self performSelector:@selector(saveSession) withObject:nil afterDelay:0.3];
}
- (void)saveSession {
 if(!self.sessionWritable || !session) return;
 try { session->save(model.tabs(), model.groups()); }
 catch(const std::exception&) { self.sessionWritable=NO; [self refresh]; }
 [self persistUiPrefs];
 if(bookmarks) {
  try { slate::save_bookmarks(BookmarksPath().UTF8String, *bookmarks); }
  catch(const std::exception&) {}
 }
 if(self.spacesManager && self.spacesManager.currentSpaceId) {
  NSMutableArray* currentParked = [NSMutableArray array];
  for(const auto& t : model.tabs()) {
   if(t.incognito) continue;
   NSMutableDictionary* d = [NSMutableDictionary dictionary];
   d[@"id"] = @(t.id);
   d[@"url"] = Text(t.url);
   d[@"title"] = Text(t.title);
   d[@"pinned"] = @(t.pinned);
   d[@"protected"] = @(t.protected_content);
   d[@"selected"] = @(t.selected);
   if(!t.group_id.empty()) d[@"group"] = Text(t.group_id);
   [currentParked addObject:d];
  }
  self.spacesManager.parkedTabs[self.spacesManager.currentSpaceId] = currentParked;
  [self.spacesManager saveSpaces];
 }
}
- (BOOL)openSplitWithTab:(TabId)identifier side:(slate::SplitSide)side base:(TabId)base {
 if(self.quitting || !model.find(identifier) || model.closing(identifier)) return NO;
 [self hideSplitDrag];
 const auto action=workspace.open_action(identifier,base);
 if(action==slate::SplitOpenAction::ShowExisting) {
  // A tab already in a split belongs to that pair. Showing it must never
  // silently dismantle the pair to reuse the tab in another split.
  [self activateTab:identifier];
  return YES;
 }
 // A split must use the tab that was actually targeted. Never manufacture a
 // blank New Tab when the drag loses its destination or targets an existing pair.
 if(action!=slate::SplitOpenAction::PairWithBase ||
    !model.find(base) || model.closing(base)) { NSBeep(); return NO; }
 if(!workspace.open(base,identifier,side)) { NSBeep(); return NO; }
 const auto* pairedLeft=model.find(workspace.left);
 const auto* pairedRight=model.find(workspace.right);
 if(pairedLeft && pairedRight && !pairedLeft->pinned && !pairedRight->pinned &&
    pairedLeft->group_id==pairedRight->group_id) {
  // Keep the visible pair adjacent in the existing tab order. No WebView is
  // recreated, and only one strip rebuild is needed after the split opens.
  TabId afterLeft=0;
  BOOL passedLeft=NO;
  for(const auto& tab:model.tabs()) {
   if(tab.id==workspace.left) { passedLeft=YES; continue; }
   if(passedLeft && tab.id!=workspace.right && !tab.pinned &&
      tab.group_id==pairedLeft->group_id) { afterLeft=tab.id; break; }
  }
  if(side==slate::SplitSide::Left) model.move_tab_before(workspace.left,workspace.right);
  else model.move_tab_before(workspace.right,afterLeft);
 }
 self.splitInstalling=YES;
 const TabId partner=identifier==workspace.left ? workspace.right : workspace.left;
 const auto* partnerTab=model.find(partner);
 if(partnerTab && partnerTab->url!="about:blank" && !model.closing(partner) &&
    !runtimes.contains(partner)) [self activateTab:partner];
 [self activateTab:identifier];
 self.splitInstalling=NO;
 self.displayedSplitLeft=0;
 self.displayedSplitRight=0;
 [self refresh];
 [self scheduleSave];
 return YES;
}
- (BOOL)isSplitPlaceholderTab:(TabId)identifier {
 const auto* tab=model.find(identifier);
 return tab && tab->url=="about:blank" && workspace.member(identifier);
}
- (BOOL)replaceEmptySplitTab:(TabId)empty withTab:(TabId)identifier {
 const auto* placeholder=model.find(empty);
 if(self.quitting || !placeholder || placeholder->url!="about:blank" ||
    !model.find(identifier) || model.closing(identifier) || workspace.member(identifier) ||
    !workspace.member(empty)) return NO;
 workspace.select(empty);
 const slate::SplitSide side=workspace.left==empty ? slate::SplitSide::Left : slate::SplitSide::Right;
 workspace.replace(identifier,side);
 self.splitInstalling=YES;
 [self activateTab:identifier];
 self.splitInstalling=NO;
 [self performClose:empty reason:slate::CloseReason::Remove];
 self.displayedSplitLeft=0;
 self.displayedSplitRight=0;
 [self refresh];
 [self scheduleSave];
 return YES;
}
- (void)exitSplitView:(id)sender {
 const TabId target=[sender isKindOfClass:NSMenuItem.class]
  ? (TabId)[((NSMenuItem*)sender).representedObject unsignedLongLongValue] : model.selected();
 if(!workspace.member(target)) return;
 workspace.select(target);
 workspace.clear();
 workspace.select(model.selected());
 self.displayedSplitLeft=0;
 self.displayedSplitRight=0;
 [self refresh];
 [self scheduleSave];
}
- (void)swapSplitSides:(id)sender {
 const TabId target=[sender isKindOfClass:NSMenuItem.class]
  ? (TabId)[((NSMenuItem*)sender).representedObject unsignedLongLongValue] : model.selected();
 if(!workspace.member(target)) return;
 workspace.select(target);
 workspace.swap();
 workspace.select(model.selected());
 self.displayedSplitLeft=0;
 self.displayedSplitRight=0;
 [self refresh];
 [self scheduleSave];
}
- (void)splitTabFromMenu:(NSMenuItem*)sender {
 TabId identifier=(TabId)[sender.representedObject unsignedLongLongValue];
 slate::SplitSide side=sender.tag==0 ? slate::SplitSide::Left : slate::SplitSide::Right;
 const TabId selected=model.selected();
 if(!model.find(identifier) || workspace.member(identifier)) {
  [self openSplitWithTab:identifier side:side base:selected];
  return;
 }
 if(selected==identifier) {
  // The menu explicitly asks for a new split with the current page, so an
  // empty companion is intentional here. Dragging never takes this path.
  try {
   const TabId empty=model.add("about:blank");
   [self openSplitWithTab:empty side:side base:identifier];
  } catch(const std::exception&) { NSBeep(); }
 } else if(workspace.member(selected)) {
  // Preserve the visible pair when opening a new pair from a tab menu.
  try {
   const TabId empty=model.add("about:blank");
   [self openSplitWithTab:identifier side:side base:empty];
  } catch(const std::exception&) { NSBeep(); }
 } else {
  [self openSplitWithTab:identifier side:side base:selected];
 }
}
- (void)setSplitRatioAtWindowPoint:(NSPoint)point {
 if(!workspace.visible_for(model.selected()) || NSWidth(self.content.bounds)<1) return;
 NSPoint local=[self.content convertPoint:point fromView:nil];
 workspace.ratio=std::clamp((double)local.x/NSWidth(self.content.bounds),0.0,1.0);
 workspace.ratio=workspace.clamped_ratio(NSWidth(self.content.bounds));
 [self syncPageGeometry];
}
- (void)finishSplitResize { [self scheduleSave]; }
- (void)hideSplitDrag {
 self.splitDraggedTab=0;
 self.splitDropSide=0;
 self.splitOverlay.hidden=YES;
 self.splitOverlay.alphaValue=1;
}
- (void)updateSplitDragAtScreenPoint:(NSPoint)screenPoint tab:(TabId)identifier base:(TabId)base {
 if(!identifier || !model.find(identifier) || workspace.member(identifier) ||
    workspace.open_action(identifier,base)!=slate::SplitOpenAction::PairWithBase ||
    !model.find(base) || model.closing(base) || !self.window || !self.content) {
  [self hideSplitDrag]; return;
 }
 NSPoint windowPoint=[self.window convertPointFromScreen:screenPoint];
 NSPoint point=[self.content convertPoint:windowPoint fromView:nil];
 if(!NSPointInRect(point,self.content.bounds)) { [self hideSplitDrag]; return; }
 [self syncPageGeometry];
 const BOOL becameVisible=self.splitOverlay.hidden;
 if(becameVisible) {
  self.splitOverlay.hidden=NO;
  self.splitOverlay.alphaValue=0;
  const BOOL reduceMotion=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  if(reduceMotion) self.splitOverlay.alphaValue=1;
  else [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
   context.duration=0.17;
   self.splitOverlay.animator.alphaValue=1;
  } completionHandler:nil];
 }
 if(self.splitDraggedTab!=identifier || becameVisible) {
  self.splitDraggedTab=identifier;
  const auto* tab=model.find(identifier);
  self.splitPreviewTitle.stringValue=tab ? TabLabel(*tab) : @"Tab";
  self.splitPreviewIcon.image=tab ? [self iconForTab:*tab] : nil;
 }
 self.splitDragBaseTab=base;
 // The preview panels are visual guides; either half of the page is a valid
 // drop target so a release just outside a panel does not discard the split.
 NSInteger side=point.x<NSMidX(self.content.bounds) ? 1 : 2;
 if(side!=self.splitDropSide) {
  self.splitDropSide=side;
  NSColor* accent=ChromeAccent(self.accentId,self.accentHex,[self isDarkAppearance]);
  NSColor* rgb=[accent colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: accent;
  CGFloat hue=0,saturation=0,brightness=0,alpha=0;
  [rgb getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
  NSColor* activeInk=[NSColor colorWithHue:hue saturation:MAX(0.42,saturation)
   brightness:[self isDarkAppearance] ? 0.88 : 0.52 alpha:1];
  for(NSInteger i=0;i<2;++i) {
   NSView* target=i==0 ? self.splitLeftTarget : self.splitRightTarget;
   const BOOL hot=side==i+1;
   target.layer.borderColor=(hot ? [activeInk colorWithAlphaComponent:0.88] : [NSColor.separatorColor colorWithAlphaComponent:0.28]).CGColor;
   target.layer.borderWidth=hot ? 2 : 1;
   NSColor* ink=hot ? activeInk : NSColor.secondaryLabelColor;
   ((NSImageView*)SplitChild(target,@"split-icon")).contentTintColor=ink;
   ((NSTextField*)SplitChild(target,@"split-label")).textColor=ink;
  }
 }
 const CGFloat previewW=210, previewH=50;
 const NSRect hotTarget=side==1 ? self.splitLeftTarget.frame : self.splitRightTarget.frame;
 const CGFloat previewX=side ? NSMidX(hotTarget)-previewW/2 : point.x+16;
 const CGFloat previewY=side ? NSMidY(hotTarget)+38 : point.y-previewH-16;
 self.splitPreview.frame=NSMakeRect(MIN(MAX(8,previewX),MAX(8,NSWidth(self.content.bounds)-previewW-8)),
  MIN(MAX(8,previewY),MAX(8,NSHeight(self.content.bounds)-previewH-8)),previewW,previewH);
}
- (BOOL)finishSplitDragAtScreenPoint:(NSPoint)screenPoint tab:(TabId)identifier base:(TabId)base {
 // An explicit empty pane in an existing split can accept an existing tab.
 // Replace only that placeholder; populated pairs are never changed by drag.
 if(workspace.visible_for(model.selected()) && !workspace.member(identifier) && self.window && self.content) {
  const NSPoint windowPoint=[self.window convertPointFromScreen:screenPoint];
  const NSPoint point=[self.content convertPoint:windowPoint fromView:nil];
  if(NSPointInRect(point,self.content.bounds)) {
   const TabId hovered=point.x<NSWidth(self.content.bounds)*workspace.clamped_ratio(NSWidth(self.content.bounds))
    ? workspace.left : workspace.right;
   if([self replaceEmptySplitTab:hovered withTab:identifier]) { [self hideSplitDrag]; return YES; }
  }
 }
 [self updateSplitDragAtScreenPoint:screenPoint tab:identifier base:base];
 const NSInteger side=self.splitDropSide;
 [self hideSplitDrag];
 if(!side) return NO;
 return [self openSplitWithTab:identifier side:side==1 ? slate::SplitSide::Left : slate::SplitSide::Right base:base];
}
- (void)activateTab:(TabId)identifier {
 if(self.quitting) { [self scheduleRefresh]; return; }
 if(SlateDetachedTabWindow* detached=self.detachedTabs[@(identifier)]) {
  [detached.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  return;
 }
 [self dismissOmniboxOverlay];
 // A restored or discarded split partner may not have a WKWebView yet. Load it
 // once before showing the pair; normal tab switches reuse both live views.
 if(!self.splitInstalling && workspace.member(identifier)) {
  const auto pair=workspace.pair_for(identifier);
  const TabId partner=identifier==pair->left ? pair->right : pair->left;
  const auto* partnerTab=model.find(partner);
  if(partnerTab && partnerTab->url!="about:blank" && !model.closing(partner) &&
     !runtimes.contains(partner)) {
   self.splitInstalling=YES;
   [self activateTab:partner];
   self.splitInstalling=NO;
  }
 }
 // If we're switching TO the floating tab and it was entered automatically, bring it back inline.
 if(self.floatWindow.showing && self.floatingTabId == identifier) {
  auto floatIt = runtimes.find(identifier);
  if(floatIt != runtimes.end() && floatIt->second.auto_pip_origin != 0) {
   [self dropFloat];
  }
 }
 auto returning=runtimes.find(identifier);
 if(returning!=runtimes.end() && returning->second.auto_pip_origin==1 &&
    returning->second.pip_active && returning->second.engine) {
  returning->second.pip_returning=true;
  [self exitNativePiPForTab:identifier];
 }
 const TabId previous=model.selected();
 if(!model.select(identifier)) { [self scheduleRefresh]; return; }
 if(!self.splitInstalling) workspace.select(identifier);
 if(previous!=identifier) {
  [SlateSiteCardPanel hide];
  [self updatePipButtonState];
  if(self.findBar && self.findBar.isVisible) {
   [self.findBar syncWithWebView:[self currentWebView]];
  }
 }
 const auto* incoming=model.find(identifier);
 if(incoming && incoming->url=="about:blank") {
  if(!self.splitInstalling) [self presentWorkspacePages];
  [self scheduleRefresh]; [self scheduleSave];
  return;
 }
 if(!runtimes.contains(identifier)) {
  [self.window.contentView layoutSubtreeIfNeeded];
  RuntimeTab runtime;
  runtime.host=[[NSView alloc] initWithFrame:WebFillRect(self.content)];
  runtime.host.translatesAutoresizingMaskIntoConstraints=YES;
  runtime.host.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
  runtime.host.clipsToBounds=YES;
  runtime.host.autoresizesSubviews=YES;
  runtime.host.wantsLayer=YES;
  const BOOL systemDark=[[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
  const BOOL isDark=(self.themeMode==1) ? NO : ((self.themeMode==2) ? YES : systemDark);
  runtime.host.layer.backgroundColor=(isDark ? ColorSRGB(0.11,0.11,0.12) : ColorSRGB(0.97,0.96,0.95)).CGColor;
  FreezeWebLayer(runtime.host);
  [self.content addSubview:runtime.host positioned:NSWindowBelow relativeTo:self.homeView];
  runtimes.emplace(identifier,std::move(runtime));
  __weak SlateDelegate* weakSelf=self;
  slate::EngineEvents events;
  events.protection_changed=[weakSelf,identifier](slate::ProtectionSignals signals) {
   const auto* previous=model.find(identifier);
   const auto now=std::chrono::steady_clock::now();
   const auto before=previous ? previous->protection_reason(now) : std::string();
   model.observe(identifier,signals);
   const auto* current=model.find(identifier);
   if(current && before!=current->protection_reason(now))
    fprintf(stderr,"SLATE_PROTECTION tab=%llu reason=%s\n",static_cast<unsigned long long>(identifier),current->protection_reason(now).c_str());
   [weakSelf scheduleRefresh];
  };
  const bool isPopupTab=self.pendingPopupTab==identifier && self.pendingPopupConfiguration!=nil;
  events.address_changed=[weakSelf,identifier,isPopupTab](std::string url) {
   if(isPopupTab && url=="about:blank") url="about:blank#popup";
   if(url.starts_with("https://") || url.starts_with("http://") || url=="about:blank" || url=="about:blank#popup")
    model.update(identifier,std::move(url),{});
   [weakSelf scheduleRefresh]; [weakSelf scheduleSave];
  };
  events.title_changed=[weakSelf,identifier](std::string title) {
   model.update(identifier,{},std::move(title)); [weakSelf scheduleRefresh]; [weakSelf scheduleSave];
  };
  events.favicon_changed=[weakSelf,identifier](std::string png) {
   if(png.empty()) return;
   NSImage* image=[[NSImage alloc] initWithData:[NSData dataWithBytes:png.data() length:png.size()]];
   if(!image) return;
   weakSelf.tabIcons[@(identifier)]=image;
   [weakSelf scheduleRefresh];
  };
  events.theme_color_changed=[weakSelf,identifier](std::string hex) {
   auto it=runtimes.find(identifier);
   if(it==runtimes.end()) return;
   if(it->second.theme_hex==hex) return;
   it->second.theme_hex=std::move(hex);
   if(identifier==model.selected()) [weakSelf applyPlateChrome];
  };
  events.resource_blocked=[weakSelf](std::string rule,std::string url) {
   fprintf(stderr,"SLATE_SHIELDS_BLOCK rule=%s url=%s\n",rule.c_str(),url.c_str());
   [weakSelf updateShieldsChrome];
  };
  events.navigation_changed=[weakSelf,identifier](bool back,bool forward) {
   if(auto it=runtimes.find(identifier);it!=runtimes.end()) { it->second.back=back; it->second.forward=forward; }
   if(identifier==model.selected()) [weakSelf updateNavChrome];
  };
  events.media_ui_changed=[weakSelf,identifier](bool audible, bool video, bool has_video, bool user_started, std::string primary_frame) {
   auto it=runtimes.find(identifier);
   if(it==runtimes.end()) return;
   const bool changed=it->second.audible!=audible || it->second.video_playing!=video || it->second.has_video!=has_video;
   it->second.audible=audible;
   it->second.video_playing=video;
   it->second.has_video=has_video;
   if((user_started && !it->second.user_started_media) || (!primary_frame.empty() && primary_frame != it->second.primary_media_frame)) {
    it->second.suppress_auto_pip=false;
   }
   it->second.user_started_media=user_started;
   it->second.primary_media_frame=std::move(primary_frame);
   if(changed) { [weakSelf scheduleRefresh]; if(identifier==model.selected()) [weakSelf updatePipButtonState]; }
  };
  events.media_quality_changed=[weakSelf,identifier](int w, int h, std::string quality, bool hdr) {
   dispatch_async(dispatch_get_main_queue(), ^{
    auto it=runtimes.find(identifier);
    if(it==runtimes.end()) return;
    it->second.video_width=w;
    it->second.video_height=h;
    it->second.video_quality=quality;
    it->second.is_hdr=hdr;
    if(identifier==model.selected()) [weakSelf updatePipButtonState];
   });
  };
  // pip_changed reflects WebKit's actual native presentation state, including
  // PiP entered through the site player or Slate's toolbar button.
  events.pip_changed=[weakSelf,identifier](bool active) {
   dispatch_async(dispatch_get_main_queue(), ^{
    auto it=runtimes.find(identifier);
    if(it==runtimes.end()) return;
    if(it->second.pip_active==active) { [weakSelf presentWorkspacePages]; return; }
    if(!active) {
     BOOL wasReturning = it->second.pip_returning;
     if(!wasReturning) it->second.suppress_auto_pip=true;
     it->second.auto_pip_origin=0;
     it->second.pip_returning=false;
     // A native PiP close and Return-to-Tab both send this event. Do not pull
     // Slate over another app on a simple close; WebKit owns that window.
    }
    it->second.pip_active=active;
    model.set_pip_active(identifier,active);
    // A rapid return can happen before WebKit finishes entering PiP. In that
    // case immediately put the video inline once the presentation appears.
    if(active && ((it->second.auto_pip_origin == 1 && identifier == model.selected()) ||
                  (it->second.auto_pip_origin == 2 && [NSApp isActive] && !weakSelf.window.isMiniaturized))) {
     it->second.pip_returning=true;
     [weakSelf exitNativePiPForTab:identifier];
    }
    [weakSelf presentWorkspacePages];
    [weakSelf scheduleRefresh];
    if(identifier==model.selected()) [weakSelf updatePipButtonState];
   });
  };
  events.loading_changed=[weakSelf,identifier](bool loading, double progress) {
   auto it=runtimes.find(identifier);
   if(it==runtimes.end()) return;
   const bool started=loading && !it->second.loading;
   const bool finished=it->second.loading && !loading;
   it->second.loading=loading;
   it->second.progress=progress;
   if(identifier==model.selected()) [weakSelf updateLoadChrome];
   if(started) {
    it->second.video_width=0;
    it->second.video_height=0;
    it->second.video_quality="";
    it->second.is_hdr=false;
   }
   if(started || finished) {
    if(identifier==model.selected()) [weakSelf updateNavChrome];
    [weakSelf scheduleRefresh];
   }
  };
  events.close_ready=[weakSelf,identifier]() {
   dispatch_async(dispatch_get_main_queue(), ^{
    @autoreleasepool {
     auto it=runtimes.find(identifier);
     if(it==runtimes.end()) return;
     for(NSView* view in [it->second.host.subviews copy]) [view removeFromSuperview];
     [it->second.host removeFromSuperview]; it->second.host=nil;
     [weakSelf refresh];
    }
   });
  };
  events.closed=[weakSelf,identifier]() {
   dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finishClose:identifier]; });
  };
  events.close_cancelled=[weakSelf,identifier]() {
   model.cancel_close(identifier); weakSelf.quitting=NO; [weakSelf refresh];
  };
  events.create_popup_tab=[weakSelf,identifier](void* configuration,std::string url) -> void* {
   const auto* source=model.find(identifier);
   WKWebView* popup=[weakSelf openPopupTabWithConfiguration:(__bridge WKWebViewConfiguration*)configuration
                                                     url:Text(url) incognito:source && source->incognito];
   return (__bridge void*)popup;
  };
  events.popup_close_requested=[weakSelf,identifier]() {
   // Defer destruction until WebKit's delegate callback has returned.
   dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf performClose:identifier reason:slate::CloseReason::Remove]; });
  };
  events.confirm_leave=[weakSelf,identifier](std::function<void(bool)> completion) {
   NSAlert* alert=[[NSAlert alloc] init]; alert.messageText=@"Leave this page?";
   const auto* tab=model.find(identifier);
   alert.informativeText=[NSString stringWithFormat:@"%@ reports unsaved changes. Leaving may discard them.",tab ? Text(tab->title) : @"This tab"];
   [alert addButtonWithTitle:@"Stay"]; [alert addButtonWithTitle:@"Leave"];
   [alert beginSheetModalForWindow:weakSelf.window completionHandler:^(NSModalResponse response) {
    completion(response==NSAlertSecondButtonReturn);
   }];
  };
  events.credential_autofill_query=[weakSelf](std::string origin) -> std::vector<std::pair<std::string, std::string>> {
   std::vector<std::pair<std::string, std::string>> out;
   if(credentials) {
    for(const auto& c : credentials->find_for_origin(origin)) {
     out.emplace_back(c.username, c.password);
    }
   }
   return out;
  };
  events.credential_save_requested=[weakSelf](std::string origin, std::string username, std::string password) {
   dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf promptSaveCredentialOrigin:[NSString stringWithUTF8String:origin.c_str()]
                                username:[NSString stringWithUTF8String:username.c_str()]
                                password:[NSString stringWithUTF8String:password.c_str()]];
   });
  };
  events.sign_in_found=[weakSelf,identifier]() {
   dispatch_async(dispatch_get_main_queue(), ^{
    auto it=runtimes.find(identifier);
    if(it!=runtimes.end()) {
     it->second.has_sign_in=true;
     if(identifier==model.selected()) [weakSelf updateAutofillButtonState];
    }
   });
  };
  events.sign_in_submitted=[weakSelf,identifier](std::string origin, std::string user, std::string pass) {
   dispatch_async(dispatch_get_main_queue(), ^{
    auto it=runtimes.find(identifier);
    if(it!=runtimes.end()) {
     it->second.pending_sign_in_origin=origin;
     it->second.pending_sign_in_user=user;
     it->second.pending_sign_in_password=pass;
    }
   });
  };
  events.sign_in_settled=[weakSelf,identifier](bool navigated) {
   (void)navigated;
   dispatch_async(dispatch_get_main_queue(), ^{
    auto it=runtimes.find(identifier);
    if(it!=runtimes.end() && !it->second.pending_sign_in_origin.empty() && !it->second.pending_sign_in_password.empty()) {
     NSString* origin=Text(it->second.pending_sign_in_origin);
     NSString* user=Text(it->second.pending_sign_in_user);
     NSString* pass=Text(it->second.pending_sign_in_password);
     it->second.pending_sign_in_origin.clear();
     it->second.pending_sign_in_user.clear();
     it->second.pending_sign_in_password.clear();
     [weakSelf promptSaveCredentialOrigin:origin username:user password:pass];
    }
   });
  };
  events.focus_changed=[weakSelf,identifier](bool typing, double x, double y, double w, double h, bool has_rect) {
   dispatch_async(dispatch_get_main_queue(), ^{
    auto it=runtimes.find(identifier);
    if(it!=runtimes.end()) {
     it->second.typing=typing;
     it->second.focus_rect=has_rect ? CGRectMake(x, y, w, h) : CGRectNull;
    }
   });
  };
  events.fullscreen_changed=[weakSelf,identifier](bool on) {
   dispatch_async(dispatch_get_main_queue(), ^{
    auto it=runtimes.find(identifier);
    if(it!=runtimes.end()) {
     it->second.immersed=on;
    }
   });
  };
  const auto* current_tab=model.find(identifier);
  const auto url=current_tab ? current_tab->url : "about:blank";
  const bool incog=current_tab ? current_tab->incognito : false;
  SlateSpace* curSpace=[self.spacesManager currentSpace];
  WKWebsiteDataStore* store=[self.spacesManager dataStoreForSpace:curSpace];
  WKWebViewConfiguration* popupConfiguration=self.pendingPopupTab==identifier ? self.pendingPopupConfiguration : nil;
  auto engine=slate::make_webkit_engine((__bridge void*)runtimes.at(identifier).host,std::move(events),url,shields.get(),incog,(__bridge void*)store,(__bridge void*)popupConfiguration);
  if(engine) { runtimes.at(identifier).engine=std::move(engine); model.opened(identifier); }
  else { [runtimes.at(identifier).host removeFromSuperview]; runtimes.erase(identifier); NSBeep(); }
 }
 if(!self.splitInstalling) [self presentWorkspacePages];
 [self scheduleRefresh]; [self scheduleSave];
 if(auto it=runtimes.find(identifier);it!=runtimes.end() && it->second.engine) {
  it->second.engine->set_zoom(ZoomLevelForPercent(self.zoomPercent));
  it->second.engine->focus(); it->second.engine->inspect_protection(); it->second.engine->host_geometry_changed();
 }
 const auto rows=[self sidebarRows];
 for(size_t row=0;row<rows.size();++row) if(rows[row].kind==SideRow::Kind::Tab && rows[row].tab==identifier)
  [self.tabList scrollRowToVisible:row];
}
- (void)newTab:(id)sender {
 if(self.quitting) return;
 fprintf(stderr,"SLATE_NEW_TAB sender=%s\n", sender ? NSStringFromClass([sender class]).UTF8String : "nil");
 try {
  const auto identifier=model.add("about:blank");
  self.bubbleTabId=identifier;
  [self activateTab:identifier];
  [self focusAddress:nil];
 }
 catch(const std::exception&) { NSBeep(); }
}
- (void)newIncognitoTab:(id)sender {
 if(self.quitting) return;
 try {
  const auto identifier=model.add("about:blank", true);
  self.bubbleTabId=identifier;
  [self activateTab:identifier];
  [self focusAddress:nil];
 }
 catch(const std::exception&) { NSBeep(); }
}
- (WKWebView*)openPopupTabWithConfiguration:(WKWebViewConfiguration*)configuration url:(NSString*)url incognito:(BOOL)incognito {
 if(self.quitting || !configuration) return nil;
 try {
  const std::string initial=(!url.length || [url isEqualToString:@"about:blank"]) ? "about:blank#popup" : url.UTF8String;
  const TabId identifier=model.add(initial,incognito);
  self.pendingPopupTab=identifier;
  self.pendingPopupConfiguration=configuration;
  [self activateTab:identifier];
  self.pendingPopupConfiguration=nil;
  self.pendingPopupTab=0;
  [self refresh];
  [self scheduleSave];
  fprintf(stderr,"SLATE_POPUP_TAB id=%llu incognito=%d\n",static_cast<unsigned long long>(identifier),incognito ? 1 : 0);
  return [self webViewForTab:identifier];
 } catch(const std::exception&) {
  self.pendingPopupConfiguration=nil;
  self.pendingPopupTab=0;
  NSBeep();
  return nil;
 }
}
- (void)openUrl:(NSString*)url incognito:(BOOL)incognito {
 if(self.quitting || !url.length) return;
 try {
  const auto identifier=model.add(url.UTF8String, incognito);
  [self activateTab:identifier];
 }
 catch(const std::exception&) { NSBeep(); }
}
- (void)openUrl:(NSString*)url {
 [self openUrl:url incognito:NO];
}
- (BOOL)loadCredentialsWhenRequested {
 if(credentials) return YES;
 try {
  credentials=slate::load_credentials(PasswordsPath().UTF8String);
  [self updateAutofillButtonState];
  return YES;
 } catch(const std::exception&) {
  NSAlert* alert=[NSAlert new];
  alert.messageText=@"Passwords unavailable";
  alert.informativeText=@"Slate could not unlock saved passwords. Your existing data is preserved.";
  [alert runModal];
  return NO;
 }
}
- (void)saveCredentials {
 if(!credentials) return;
 try { slate::save_credentials(PasswordsPath().UTF8String, *credentials); }
 catch(const std::exception&) {
  NSAlert* alert=[NSAlert new]; alert.messageText=@"Passwords could not be saved";
  alert.informativeText=@"macOS could not save the password vault. Your existing saved data has not been replaced.";
  [alert runModal];
 }
}
- (void)openApplePasswords:(id)sender { [SlatePasswordsPanel openApplePasswords]; }
- (IBAction)showPasswordsPanel:(id)sender {
 if(![self loadCredentialsWhenRequested]) return;
 __weak SlateDelegate* weakSelf=self;
 [[SlatePasswordsPanel sharedPanel] showForCredentialStore:credentials.get() onSave:^{
  [weakSelf saveCredentials];
 }];
}
- (IBAction)showImportBrowserData:(id)sender {
 if(!bookmarks) bookmarks=std::make_unique<slate::BookmarkList>();
 if(![self loadCredentialsWhenRequested]) return;
 __weak SlateDelegate* weakSelf=self;
 [SlateImportDialog showModalForWindow:self.window
                             bookmarks:bookmarks.get()
                       credentialStore:credentials.get()
                            onComplete:^(slate::ImportSummary summary, const std::vector<slate::HistoryItem>& history) {
  if(summary.bookmarks_imported>0) {
   slate::save_bookmarks(BookmarksPath().UTF8String, *bookmarks);
   [weakSelf rebuildBookmarksBar];
  }
  if(summary.passwords_imported>0) {
   [weakSelf saveCredentials];
  }
  if(!history.empty()) {
   importedHistory=history;
  }
  [weakSelf showImportNotification:summary];
 }];
}
- (void)showImportNotification:(slate::ImportSummary)summary {
 NSString* msg=[NSString stringWithFormat:@"Successfully imported %zu bookmarks, %zu history items, and %zu passwords.",
                summary.bookmarks_imported, summary.history_imported, summary.passwords_imported];
 NSAlert* alert=[[NSAlert alloc] init];
 alert.messageText=@"Import Complete";
 alert.informativeText=msg;
 [alert addButtonWithTitle:@"OK"];
 [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (IBAction)showAboutSlate:(id)sender {
 [[SlateSettingsPanel sharedPanel] showForSlateDelegate:self selectedPage:@"about"];
}
- (IBAction)showSettings:(id)sender {
 [[SlateSettingsPanel sharedPanel] showForSlateDelegate:self selectedPage:@"general"];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
 if([keyPath isEqualToString:@"effectiveAppearance"] && object == NSApp) {
  [self systemAppearanceDidChange:nil];
  return;
 }
 [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)systemAppearanceDidChange:(id)sender {
 dispatch_async(dispatch_get_main_queue(), ^{
  if(self.quitting || !self.window) return;
  [self applyPlateChrome];
  [self applyChromeInk];
  [self layoutTrafficLights];
  [self refresh];
  if(self.tabList) [self.tabList reloadData];
  [[SlateSettingsPanel sharedPanel] updateFromDelegate];
 });
}
- (void)promptSaveCredentialOrigin:(NSString*)origin username:(NSString*)username password:(NSString*)password {
 if(!origin.length || !password.length) return;
 const auto* currentTab=model.find(model.selected());
 if(currentTab && currentTab->incognito) return; // Strict incognito privacy

 if(credentials) {
  auto existing=credentials->find_for_origin(origin.UTF8String);
  for(const auto& c : existing) {
   if(c.username==username.UTF8String && c.password==password.UTF8String) return;
  }
 }

 self.pendingOrigin=origin;
 self.pendingUsername=username;
 self.pendingPassword=password;

 if(!self.savePasswordBanner) {
  self.savePasswordBanner=[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 310, 80)];
  self.savePasswordBanner.wantsLayer=YES;
  self.savePasswordBanner.layer.cornerRadius=10;
  self.savePasswordBanner.layer.borderWidth=1;
  self.savePasswordBanner.layer.borderColor=[NSColor colorWithWhite:0.5 alpha:0.3].CGColor;
  self.savePasswordBanner.layer.backgroundColor=[NSColor colorWithWhite:0.18 alpha:0.96].CGColor;

  NSTextField* title=[NSTextField labelWithString:@"Save password for this site?"];
  title.font=[NSFont boldSystemFontOfSize:12];
  title.textColor=[NSColor whiteColor];
  title.frame=NSMakeRect(14, 48, 280, 18);
  [self.savePasswordBanner addSubview:title];

  NSTextField* userLabel=[NSTextField labelWithString:@""];
  userLabel.identifier=@"userLabel";
  userLabel.font=[NSFont systemFontOfSize:11];
  userLabel.textColor=[NSColor colorWithWhite:0.85 alpha:0.9];
  userLabel.frame=NSMakeRect(14, 30, 280, 16);
  [self.savePasswordBanner addSubview:userLabel];

  NSButton* saveBtn=[NSButton buttonWithTitle:@"Save" target:self action:@selector(onConfirmSavePassword:)];
  saveBtn.bezelStyle=NSBezelStyleRounded;
  saveBtn.frame=NSMakeRect(220, 8, 76, 22);
  [self.savePasswordBanner addSubview:saveBtn];

  NSButton* neverBtn=[NSButton buttonWithTitle:@"Not Now" target:self action:@selector(onDismissSavePassword:)];
  neverBtn.bezelStyle=NSBezelStyleRounded;
  neverBtn.frame=NSMakeRect(140, 8, 76, 22);
  [self.savePasswordBanner addSubview:neverBtn];

  [self.stage addSubview:self.savePasswordBanner];
 }

 for(NSView* sub in self.savePasswordBanner.subviews) {
  if([sub.identifier isEqualToString:@"userLabel"] && [sub isKindOfClass:[NSTextField class]]) {
   ((NSTextField*)sub).stringValue=username.length ? [NSString stringWithFormat:@"%@ • %@", origin, username] : origin;
  }
 }

 const CGFloat bannerW=310;
 const CGFloat bannerH=76;
 self.savePasswordBanner.frame=NSMakeRect(self.stage.bounds.size.width - bannerW - 20,
                                          self.stage.bounds.size.height - bannerH - 45,
                                          bannerW, bannerH);
 self.savePasswordBanner.hidden=NO;
 self.savePasswordBanner.alphaValue=1.0;
}
- (void)onConfirmSavePassword:(id)sender {
 if(self.pendingOrigin.length && self.pendingPassword.length && [self loadCredentialsWhenRequested]) {
  slate::Credential cred;
  cred.origin=self.pendingOrigin.UTF8String;
  cred.username=self.pendingUsername.UTF8String ?: "";
  cred.password=self.pendingPassword.UTF8String;
  credentials->save(std::move(cred));
  [self saveCredentials];
 }
 self.savePasswordBanner.hidden=YES;
}
- (void)onDismissSavePassword:(id)sender {
 self.savePasswordBanner.hidden=YES;
}
- (void)restoreTab:(id)sender { [self activateTab:model.selected()]; }
- (void)toggleProtection:(id)sender {
 bool on;
 if(sender==self.protectButton) on=self.protectButton.state==NSControlStateValueOn;
 else {
  const auto* tab=model.find(model.selected());
  on=!(tab && tab->protected_content);
 }
 model.protect(model.selected(),on);
 [self refresh]; [self scheduleSave];
}
- (void)togglePin:(id)sender {
 const auto* tab=model.find(model.selected());
 if(!tab) return;
 model.pin(tab->id,!tab->pinned);
 [self refresh]; [self scheduleSave];
}
- (void)performClose:(TabId)identifier reason:(slate::CloseReason)reason {
 if(reason == slate::CloseReason::Remove) {
  const auto* tab = model.find(identifier);
  if(tab && !tab->incognito) {
   if(!self.recentlyClosedUrls) self.recentlyClosedUrls = [NSMutableArray array];
   NSString* u = (!tab->url.empty() && tab->url != "about:blank") ? Text(tab->url) : @"about:blank";
   [self.recentlyClosedUrls addObject:u];
   if(self.recentlyClosedUrls.count > 30) [self.recentlyClosedUrls removeObjectAtIndex:0];
  }
 }
 if(!model.begin_close(identifier,reason)) return;
 auto it=runtimes.find(identifier);
 if(it!=runtimes.end() && it->second.engine) it->second.engine->close();
 else [self finishClose:identifier];
 [self refresh];
}
- (void)beginClose:(TabId)identifier reason:(slate::CloseReason)reason {
 auto it = runtimes.find(identifier);
 if(it != runtimes.end() && it->second.pip_active) {
  WKWebView* webView = [self webViewForTab:identifier];
  if(@available(macOS 12.0, *)) {
   if(webView) [webView closeAllMediaPresentationsWithCompletionHandler:nil];
  }
  it->second.pip_active = false;
 }
 if(self.floatingTabId == identifier) self.floatingTabId = 0;
 if(reason == slate::CloseReason::Remove) {
  for(NSView* view in self.tabPills.arrangedSubviews) {
   if([view isKindOfClass:SlateTabPill.class] && ((SlateTabPill*)view).tabId == identifier) {
    SlateTabPill* pill = (SlateTabPill*)view;
    [pill animateClose:^{
     [self performClose:identifier reason:reason];
    }];
    return;
   }
  }
 }
 [self performClose:identifier reason:reason];
}
- (void)unloadTab:(id)sender {
 [self unloadTabWithId:model.selected()];
}
- (void)closeTab:(id)sender {
 if(!self.quitting) [self beginClose:model.selected() reason:slate::CloseReason::Remove];
}
- (void)finishClose:(TabId)identifier {
 if(SlateDetachedTabWindow* detached=self.detachedTabs[@(identifier)]) {
  [self.detachedTabs removeObjectForKey:@(identifier)];
  [detached dismissWithoutClosingTab];
  self.tabListSignature=nil;
  self.tabStripIdentity=nil;
 }
 // If this tab is being floated, drop it first so the WKWebView returns home
 // before we erase the runtime.
 if(self.floatingTabId == identifier && self.floatWindow.showing) {
  [self dropFloat];
 }
 if(self.floatingTabId == identifier) self.floatingTabId = 0;
 const BOOL closingVisibleSplit=workspace.visible_for(model.selected()) && workspace.contains(identifier);
 const TabId splitSurvivor=workspace.remove(identifier);
 const auto reason=model.close_reason(identifier);
 runtimes.erase(identifier); model.closed(identifier);
 [self.tabIcons removeObjectForKey:@(identifier)];
 fprintf(stderr,"SLATE_TAB_CLOSED id=%llu loaded=%zu\n",static_cast<unsigned long long>(identifier),runtimes.size());
 bool any_incognito = false;
 for(const auto& t : model.tabs()) {
  if(t.incognito) { any_incognito = true; break; }
 }
 if(!any_incognito) {
  slate::PurgeIncognitoStorage();
 }
 if(self.quitting) { [self closeNextForQuit]; return; }
 if(model.tabs().empty()) model.add("about:blank");
 if(splitSurvivor && closingVisibleSplit && model.find(splitSurvivor)) [self activateTab:splitSurvivor];
 else if(reason==slate::CloseReason::Remove) [self activateTab:model.selected()];
 [self refresh]; [self scheduleSave];
}
- (void)closeNextForQuit {
 if(runtimes.empty()) {
  memoryMonitor.reset();
  self.window.delegate=nil; self.window.contentView=[[NSView alloc] initWithFrame:NSZeroRect];
  [self.window close]; self.window=nil;
  [NSApp stop:nil];
  NSEvent* wakeEvent = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
  [NSApp postEvent:wakeEvent atStart:YES];
  return;
 }
 const auto identifier=runtimes.begin()->first;
 if(!model.closing(identifier)) [self beginClose:identifier reason:slate::CloseReason::Shutdown];
}
- (void)requestClose {
 if(self.quitting) return;
 [self reattachAllDetachedTabs];
 if(self.mouseMovedMonitor) {
  [NSEvent removeMonitor:self.mouseMovedMonitor];
  self.mouseMovedMonitor = nil;
 }
 if(self.localMouseMovedMonitor) {
  [NSEvent removeMonitor:self.localMouseMovedMonitor];
  self.localMouseMovedMonitor = nil;
 }
 if(self.spaceSwipeMonitor) {
  [NSEvent removeMonitor:self.spaceSwipeMonitor];
  self.spaceSwipeMonitor = nil;
 }
 [self hideSuggestions];
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveSession) object:nil];
 [self saveSession]; [self persistUiPrefs]; self.quitting=YES; [self closeNextForQuit];
}
- (BOOL)windowShouldClose:(NSWindow*)sender {
 if(sender==self.window && self.detachedTabs.count) { [self.window orderOut:nil]; return NO; }
 [self requestClose]; return NO;
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication*)app { return YES; }
- (void)applicationWillFinishLaunching:(NSNotification *)notification {
 [NSAppleEventManager.sharedAppleEventManager setEventHandler:self
                                                  andSelector:@selector(handleGetURLEvent:withReplyEvent:)
                                                forEventClass:kInternetEventClass
                                                   andEventID:kAEGetURL];
}
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
 NSString* text=[[event paramDescriptorForKeyword:keyDirectObject] stringValue];
 if(!text.length) return;
 NSURL* url=[NSURL URLWithString:text];
 if(url && (url.isFileURL || [url.scheme.lowercaseString hasPrefix:@"http"])) {
  [self handleIncomingURL:url];
 }
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
#if defined(SLATE_ENABLE_VERIFY)
 [self startVerifyCommands];
#endif
}
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
 for(NSURL* url in urls) {
  if(url.isFileURL || [url.scheme.lowercaseString hasPrefix:@"http"]) {
   [self handleIncomingURL:url];
  }
 }
}
- (void)handleIncomingURL:(NSURL*)url {
 if(!self.window) {
  if(!self.earlyURLs) self.earlyURLs=[NSMutableArray array];
  [self.earlyURLs addObject:url];
  return;
 }
 [self openExternalURL:url];
}
- (void)openExternalURL:(NSURL*)url {
 if(!url || self.quitting) return;
 NSString* urlStr=url.isFileURL ? [NSString stringWithFormat:@"file://%@", url.path] : url.absoluteString;
 if(!urlStr.length) return;

 if(self.window) {
  if(!self.window.isVisible || self.window.isMiniaturized) {
   [self.window deminiaturize:nil];
   [self.window makeKeyAndOrderFront:nil];
  }
  [NSApp activateIgnoringOtherApps:YES];
 }

 const auto sel=model.selected();
 const auto* tab=model.find(sel);
 if(tab && tab->url=="about:blank") {
  self.address.stringValue=urlStr;
  self.addressDirty=NO;
  self.addressOpen=NO;
  model.update(sel, urlStr.UTF8String, {});
  if(!runtimes.contains(sel)) [self activateTab:sel];
  else if(runtimes.at(sel).engine) {
   runtimes.at(sel).engine->navigate(urlStr.UTF8String);
   runtimes.at(sel).engine->focus();
  }
  [self refresh];
  [self scheduleSave];
 } else {
  [self openUrl:urlStr];
 }
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
 if(!flag && self.window) {
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
 }
 return YES;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
 [self saveSession];
 [self persistUiPrefs];
}
+ (BOOL)isDefaultBrowser {
 NSURL* probe=[NSURL URLWithString:@"https://example.com"];
 NSURL* handler=[NSWorkspace.sharedWorkspace URLForApplicationToOpenURL:probe];
 if(!handler) return NO;
 return [handler.standardizedURL isEqual:NSBundle.mainBundle.bundleURL.standardizedURL];
}
+ (void)becomeDefaultBrowser:(void(^)(BOOL success))completion {
 NSURL* appURL=NSBundle.mainBundle.bundleURL;
 dispatch_group_t group=dispatch_group_create();
 __block BOOL worked=YES;
 for(NSString* scheme in @[@"http", @"https"]) {
  dispatch_group_enter(group);
  [NSWorkspace.sharedWorkspace setDefaultApplicationAtURL:appURL toOpenURLsWithScheme:scheme completionHandler:^(NSError * _Nullable error) {
   if(error) worked=NO;
   dispatch_group_leave(group);
  }];
 }
 dispatch_group_notify(group, dispatch_get_main_queue(), ^{
  if(completion) completion(worked);
 });
}
- (void)navigate:(id)sender {
 if(self.quitting || model.closing(model.selected())) return;
 NSString* text=[self.address.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(!text.length) {
  if([self.address respondsToSelector:@selector(shake)]) [(id)self.address shake];
  return;
 }
 const auto decision=slate::resolve_address_bar(text.UTF8String ?: "");
 if(decision.kind==slate::InputKind::Invalid || decision.url.empty()) {
  NSBeep();
  if([self.address respondsToSelector:@selector(shake)]) [(id)self.address shake];
  return;
 }
 NSString* resolved=[NSString stringWithUTF8String:decision.url.c_str()];
 self.address.stringValue=resolved;
 self.addressDirty=NO;
 self.addressOpen=NO;
 const auto identifier=model.selected(); model.update(identifier,decision.url,{});
 if(!runtimes.contains(identifier)) [self activateTab:identifier];
 else if(runtimes.at(identifier).engine) {
  runtimes.at(identifier).engine->navigate(decision.url);
  runtimes.at(identifier).engine->focus();
 }
 [self.window makeFirstResponder:nil];
 [self hideSuggestions];
 [self refresh];
 [self scheduleSave];
}
- (std::string)currentPageHost {
 SlateDetachedTabWindow* detached=[self detachedTabForWindow:NSApp.keyWindow];
 const auto* tab=model.find(detached ? detached.tabId : model.selected());
 if(!tab) return {};
 NSURL* url=[NSURL URLWithString:Text(tab->url)];
 if(![url.scheme.lowercaseString isEqualToString:@"http"] &&
    ![url.scheme.lowercaseString isEqualToString:@"https"]) return {};
 return slate::host_from_url(tab->url);
}
- (void)updateShieldsChrome {
 if(!self.shieldsButton) return;
 const auto host=[self currentPageHost];
 const BOOL off=!slate::WebKitShields::Shared().IsEnabled();
 const BOOL paused=!host.empty() && !slate::WebKitShields::Shared().IsSiteEnabled(host);
 NSString* symbol=off || paused ? @"shield.slash" : @"checkmark.shield";
 NSImage* image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"Slate Shields"]
  ?: [NSImage imageWithSystemSymbolName:@"shield" accessibilityDescription:@"Slate Shields"];
 self.shieldsButton.image=image;
 self.shieldsButton.contentTintColor=off||paused ? (self.barMuted ?: NSColor.secondaryLabelColor) : (self.barInk ?: NSColor.controlAccentColor);
 self.shieldsButton.toolTip=off ? @"Ad blocking is off" : paused ?
  @"Ads are allowed on this site" : @"Ad blocking is on";
 if(self.shieldsStatus) {
  self.shieldsStatus.stringValue=off ? @"Protection is off" : paused ? @"Paused on this site" : @"Protection is on";
  self.shieldsCount.stringValue=off ? @"Off" : paused ? @"Allowed" : @"On";
  self.shieldsToggle.state=off ? NSControlStateValueOff : NSControlStateValueOn;
  const BOOL hasHost=!host.empty() && host!="about:blank";
  self.shieldsPause.enabled=hasHost && !off;
  self.shieldsPause.title=paused ? @"Block ads on this site: Off" : @"Block ads on this site: On";
 }
}
- (NSView*)makeShieldsPopoverView {
 NSView* root=[[NSView alloc] initWithFrame:NSMakeRect(0,0,260,228)];
 NSTextField* title=[self label:@"Slate Shields" size:13 color:NSColor.labelColor];
 title.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
 title.translatesAutoresizingMaskIntoConstraints=NO;
 self.shieldsStatus=[self label:@"Protection is on" size:12 color:NSColor.secondaryLabelColor];
 self.shieldsStatus.translatesAutoresizingMaskIntoConstraints=NO;
 self.shieldsToggle=[[NSSwitch alloc] initWithFrame:NSZeroRect];
 self.shieldsToggle.target=self; self.shieldsToggle.action=@selector(toggleShields:);
 self.shieldsToggle.translatesAutoresizingMaskIntoConstraints=NO;
 NSBox* line1=[[NSBox alloc] init]; line1.boxType=NSBoxSeparator; line1.translatesAutoresizingMaskIntoConstraints=NO;
 NSTextField* caption=[self label:@"Protection on this page" size:11 color:NSColor.tertiaryLabelColor];
 caption.translatesAutoresizingMaskIntoConstraints=NO;
 self.shieldsCount=[self label:@"On" size:28 color:NSColor.labelColor];
 self.shieldsCount.font=[NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
 self.shieldsCount.translatesAutoresizingMaskIntoConstraints=NO;
 NSTextField* ads=[self label:@"Native network and cosmetic filtering" size:12 color:NSColor.secondaryLabelColor];
 ads.translatesAutoresizingMaskIntoConstraints=NO;
 NSBox* line2=[[NSBox alloc] init]; line2.boxType=NSBoxSeparator; line2.translatesAutoresizingMaskIntoConstraints=NO;
 self.shieldsPause=[NSButton buttonWithTitle:@"Block ads on this site: On" target:self action:@selector(pauseShieldsSite:)];
 self.shieldsPause.bezelStyle=NSBezelStyleRounded; self.shieldsPause.font=[NSFont systemFontOfSize:12];
 self.shieldsPause.translatesAutoresizingMaskIntoConstraints=NO;
 [root addSubview:title]; [root addSubview:self.shieldsStatus]; [root addSubview:self.shieldsToggle];
 [root addSubview:line1]; [root addSubview:caption]; [root addSubview:self.shieldsCount]; [root addSubview:ads];
 [root addSubview:line2]; [root addSubview:self.shieldsPause];
 [NSLayoutConstraint activateConstraints:@[
  [title.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16],
  [title.topAnchor constraintEqualToAnchor:root.topAnchor constant:14],
  [self.shieldsToggle.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],
  [self.shieldsToggle.centerYAnchor constraintEqualToAnchor:self.shieldsStatus.centerYAnchor],
  [self.shieldsStatus.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
  [self.shieldsStatus.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
  [line1.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16],
  [line1.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],
  [line1.topAnchor constraintEqualToAnchor:self.shieldsStatus.bottomAnchor constant:12],
  [caption.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
  [caption.topAnchor constraintEqualToAnchor:line1.bottomAnchor constant:12],
  [self.shieldsCount.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
  [self.shieldsCount.topAnchor constraintEqualToAnchor:caption.bottomAnchor constant:2],
  [ads.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
  [ads.topAnchor constraintEqualToAnchor:self.shieldsCount.bottomAnchor constant:2],
  [line2.leadingAnchor constraintEqualToAnchor:line1.leadingAnchor],
  [line2.trailingAnchor constraintEqualToAnchor:line1.trailingAnchor],
  [line2.topAnchor constraintEqualToAnchor:ads.bottomAnchor constant:12],
  [self.shieldsPause.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
  [self.shieldsPause.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],
  [self.shieldsPause.topAnchor constraintEqualToAnchor:line2.bottomAnchor constant:12],
  [root.widthAnchor constraintEqualToConstant:260],
  [root.heightAnchor constraintEqualToConstant:228]
 ]];
 return root;
}
- (void)showShields:(id)sender {
 if(!self.shieldsPopover) {
  self.shieldsPopover=[[NSPopover alloc] init];
  self.shieldsPopover.behavior=NSPopoverBehaviorTransient;
  NSViewController* controller=[[NSViewController alloc] init];
  controller.view=[self makeShieldsPopoverView];
  self.shieldsPopover.contentViewController=controller;
 }
 [self updateShieldsChrome];
 NSView* anchor=[sender isKindOfClass:NSView.class] ? (NSView*)sender : self.shieldsButton;
 [self.shieldsPopover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMinY];
}
- (void)toggleDownloads:(id)sender {
 (void)sender;
 [[SlateDownloadsPanel sharedPanel] toggleForButton:self.downloadButton inWindow:self.window];
}
- (void)toggleShields:(id)sender {
 if(!shields) return;
 const BOOL on=[sender isKindOfClass:NSSwitch.class] ? ((NSSwitch*)sender).state==NSControlStateValueOn : self.shieldsToggle.state==NSControlStateValueOn;
 shields->set_mode(on ? slate::ShieldMode::Standard : slate::ShieldMode::Off);
 slate::WebKitShields::Shared().SetEnabled(on);
 [self updateShieldsChrome];
 [self reload:nil];
}
- (void)pauseShieldsSite:(id)sender {
 if(!shields) return;
 const auto host=[self currentPageHost];
 if(host.empty()) return;
 const BOOL enable=!slate::WebKitShields::Shared().IsSiteEnabled(host);
 if(enable) shields->resume_site(host);
 else shields->pause_site(host);
 slate::WebKitShields::Shared().SetSiteEnabled(host,enable);
 [self updateShieldsChrome];
 [self reload:nil];
}
- (void)resumeAdBlockSite:(NSString*)site {
 if(!site.length) return;
 slate::WebKitShields::Shared().SetSiteEnabled(site.UTF8String,true);
 if(shields) shields->resume_site(site.UTF8String);
 [self updateShieldsChrome];
 NSString* current=Text([self currentPageHost]);
 if([site isEqualToString:current] || [current isEqualToString:[@"www." stringByAppendingString:site]]) [self reload:nil];
}
- (void)hideSuggestions {
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchSuggestions) object:nil];
 [self.suggestTask cancel]; self.suggestTask=nil;
 self.suggestions=@[];
 self.suggestHighlight=-1;
 for(NSView* row in [self.suggestStack.arrangedSubviews copy]) {
  [self.suggestStack removeArrangedSubview:row];
  [row removeFromSuperview];
 }
 [self.suggestPanel orderOut:nil];
}
- (void)positionSuggestPanel {
 if(self.omniboxOverlay && self.omniboxOverlay.card.field.currentEditor != nil) {
  [self positionSuggestPanelBelowOverlay:self.omniboxOverlay.card];
  return;
 }
 if(self.homeSearchField && self.homeSearchField.currentEditor != nil) {
  [self positionSuggestPanelBelowHomeSearch];
  return;
 }
 if(!self.suggestions.count || !self.omnibox || !self.window) return;
 // Convert title bar omnibox frame to screen coords using un-flipped window base coordinates
 NSRect fieldInWindow = [self.omnibox convertRect:self.omnibox.bounds toView:nil];
 NSRect fieldScreen = [self.window convertRectToScreen:fieldInWindow];
 // Panel width matches omnibox width, capped to 640pt max and centered
 const CGFloat panelW = MIN(640.0, NSWidth(fieldScreen));
 const CGFloat rowCount = MIN(8.0, (CGFloat)self.suggestions.count);
 const CGFloat height = rowCount * 44.0 + 8.0; // 44pt per row + 8pt total vertical stack padding
 const CGFloat panelX = NSMidX(fieldScreen) - panelW / 2.0;
 const CGFloat panelY = NSMinY(fieldScreen) - height - 4.0;
 NSRect frame = NSMakeRect(panelX, panelY, panelW, height);
 if(self.suggestCard) {
  self.suggestCard.layer.cornerRadius = 14;
  if(@available(macOS 11.0, *)) self.suggestCard.layer.cornerCurve = kCACornerCurveContinuous;
  self.suggestCard.layer.borderWidth = 1.0;

  NSColor* accent = self.barColor;
  BOOL isDark = YES;
  if(accent) {
   CGFloat r=0, g=0, b=0, a=0;
   NSColor* rgb=[accent colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: accent;
   [rgb getRed:&r green:&g blue:&b alpha:&a];
   CGFloat lum=0.2126*r + 0.7152*g + 0.0722*b;
   isDark=lum<0.55;
  } else {
   isDark=[[self.window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
  }

  NSColor* cardBg=nil;
  NSColor* borderColor=nil;
  if(accent) {
   if(isDark) {
    cardBg=[accent blendedColorWithFraction:0.32 ofColor:[NSColor blackColor]];
    if(!cardBg) cardBg=[NSColor colorWithCalibratedWhite:0.18 alpha:0.95];
    borderColor=[NSColor colorWithWhite:1.0 alpha:0.20];
   } else {
    cardBg=[accent blendedColorWithFraction:0.35 ofColor:[NSColor whiteColor]];
    if(!cardBg) cardBg=[NSColor colorWithCalibratedWhite:0.96 alpha:0.95];
    borderColor=[NSColor colorWithWhite:0.0 alpha:0.16];
   }
  } else {
   if(isDark) {
    cardBg=[NSColor colorWithCalibratedWhite:0.18 alpha:0.95];
    borderColor=[NSColor colorWithWhite:1.0 alpha:0.20];
   } else {
    cardBg=[NSColor colorWithCalibratedWhite:0.96 alpha:0.95];
    borderColor=[NSColor colorWithWhite:0.0 alpha:0.16];
   }
  }
  self.suggestCard.layer.backgroundColor=cardBg.CGColor;
  self.suggestCard.layer.borderColor=borderColor.CGColor;
 }
 if(self.suggestPanel.parentWindow != self.window)
  [self.window addChildWindow:self.suggestPanel ordered:NSWindowAbove];
 [self.suggestPanel setFrame:frame display:YES];
}
- (void)positionSuggestPanelBelowHomeSearch {
 [self positionSuggestPanelBelowOverlay:self.homeBoard.omniboxCard];
}
- (void)applySuggestionHighlight {
 NSInteger index=0;
 for(NSView* view in self.suggestStack.arrangedSubviews) {
  if([view isKindOfClass:SlateSuggestRow.class])
   ((SlateSuggestRow*)view).highlighted=(index==self.suggestHighlight);
  index+=1;
 }
}
- (void)showSuggestionList:(NSArray*)items {
 [self showSuggestionList:items fromHomeSearch:NO];
}
- (void)showSuggestionList:(NSArray*)items fromHomeSearch:(BOOL)homeSearch {
 self.suggestions=items ?: @[];
 self.suggestHighlight=self.suggestions.count ? 0 : -1;
 for(NSView* row in [self.suggestStack.arrangedSubviews copy]) {
  [self.suggestStack removeArrangedSubview:row];
  [row removeFromSuperview];
 }
 if(!self.suggestions.count) { [self.suggestPanel orderOut:nil]; return; }
 // Update query label at top of palette
 NSString* query = self.address.stringValue ?: @"";
 if(self.suggestQueryField) self.suggestQueryField.stringValue = query;
 for(SlateSuggestion* item in self.suggestions) {
  SlateSuggestRow* row=[[SlateSuggestRow alloc] initWithItem:item owner:self];
  [self.suggestStack addArrangedSubview:row];
  [row.widthAnchor constraintEqualToAnchor:self.suggestStack.widthAnchor].active=YES;
 }
 [self applySuggestionHighlight];
 if(homeSearch) [self positionSuggestPanelBelowHomeSearch];
 else [self positionSuggestPanel];
 if(self.suggestPanel.parentWindow != self.window)
  [self.window addChildWindow:self.suggestPanel ordered:NSWindowAbove];
 [self.suggestPanel orderFront:nil];
}
- (NSArray*)localSuggestionsFor:(NSString*)query {
 NSMutableArray* items=[NSMutableArray array];
 const auto decision=slate::resolve_address_bar(query.UTF8String ?: "");
 if(decision.kind==slate::InputKind::Search) {
  NSString* searchTitle=[NSString stringWithFormat:@"Search Google for \u201c%@\u201d", query];
  [items addObject:[SlateSuggestion search:searchTitle query:query]];
 } else if(decision.kind==slate::InputKind::Url && !decision.url.empty()) {
  NSString* urlStr=[NSString stringWithUTF8String:decision.url.c_str()];
  // Extract domain as subtitle
  NSURL* parsedUrl=[NSURL URLWithString:urlStr];
  NSString* domain=parsedUrl.host ?: urlStr;
  [items addObject:[SlateSuggestion url:urlStr subtitle:domain query:query]];
 }
 // Open tabs match: dot indicator, switches to existing tab rather than opening duplicate
 if(query.length >= 1) {
  NSString* qLower = query.lowercaseString;
  const TabId currentId = model.selected();
  int openCount = 0;
  for(const auto& t : model.tabs()) {
   if(t.id == currentId || t.url.empty() || t.url == "about:blank") continue;
   NSString* tUrl = Text(t.url);
   NSString* tTitle = Text(t.title);
   if([tUrl.lowercaseString containsString:qLower] || [tTitle.lowercaseString containsString:qLower]) {
    NSString* displayTitle = tTitle.length > 0 ? tTitle : tUrl;
    NSURL* parsed = [NSURL URLWithString:tUrl];
    NSString* domain = parsed.host ?: tUrl;
    [items addObject:[SlateSuggestion open:displayTitle subtitle:domain query:tUrl tabId:t.id]];
    openCount++;
    if(openCount >= 2) break;
   }
  }
 }
 if(query.length >= 2 && !importedHistory.empty()) {
  NSString* qLower = query.lowercaseString;
  int count = 0;
  for(const auto& h : importedHistory) {
   NSString* hUrl = [NSString stringWithUTF8String:h.url.c_str()];
   NSString* hTitle = [NSString stringWithUTF8String:h.title.c_str()];
   if([hUrl.lowercaseString containsString:qLower] || [hTitle.lowercaseString containsString:qLower]) {
    NSURL* parsed = [NSURL URLWithString:hUrl];
    NSString* domain = parsed.host ?: hUrl;
    NSString* displayTitle = hTitle.length > 0 ? hTitle : hUrl;
    [items addObject:[SlateSuggestion history:displayTitle subtitle:domain query:hUrl]];
    count++;
    if(count >= 3) break;
   }
  }
 }
 return items;
}
- (void)fetchHomeSearchSuggestions {
 NSTextField* homeField=[self homeSearchField];
 if(!homeField || self.quitting) return;
 NSString* query=[homeField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(!query.length) { [self hideSuggestions]; return; }
 if(query.length>120) return;
 // Re-use the same suggestion infrastructure but use home search context
 self.address.stringValue=query; // mirror so showSuggestionList query label works
 NSString* lowered=query.lowercaseString;
 if([lowered hasPrefix:@"http://"] || [lowered hasPrefix:@"https://"] || [lowered hasPrefix:@"about:"]) {
  [self showSuggestionList:[self localSuggestionsFor:query] fromHomeSearch:YES];
  return;
 }
 if(!self.suggestPanel.visible || self.suggestions.count <= 1) {
  NSMutableArray* items=[[self localSuggestionsFor:query] mutableCopy];
  [self showSuggestionList:items fromHomeSearch:YES];
 }
 NSMutableCharacterSet* allowed=[NSCharacterSet URLQueryAllowedCharacterSet].mutableCopy;
 [allowed removeCharactersInString:@"&+=?#"];
 NSString* encoded=[query stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
 NSURL* url=[NSURL URLWithString:[NSString stringWithFormat:@"https://www.google.com/complete/search?client=firefox&q=%@",encoded]];
 if(!url) return;
 [self.suggestTask cancel];
 __weak SlateDelegate* weakSelf=self;
 NSString* typed=query;
 self.suggestTask=[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData* data,NSURLResponse* response,NSError* error) {
  if(error || !data) return;
  NSHTTPURLResponse* http=[response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse*)response : nil;
  if(http && http.statusCode!=200) return;
  id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if(![json isKindOfClass:NSArray.class] || [json count]<2 || ![json[1] isKindOfClass:NSArray.class]) return;
  dispatch_async(dispatch_get_main_queue(), ^{
   SlateDelegate* strongSelf=weakSelf;
   if(!strongSelf) return;
   NSTextField* hf=[strongSelf homeSearchField];
   if(!hf || ![hf.stringValue hasPrefix:typed]) return;
   NSMutableArray* merged=[[strongSelf localSuggestionsFor:hf.stringValue] mutableCopy] ?: [NSMutableArray array];
   NSMutableSet* seen=[NSMutableSet set];
   for(SlateSuggestion* item in merged) if(item.query) [seen addObject:item.query.lowercaseString];
   for(id entry in json[1]) {
    if(![entry isKindOfClass:NSString.class] || ![entry length]) continue;
    NSString* suggestion=entry;
    if([seen containsObject:suggestion.lowercaseString]) continue;
    [seen addObject:suggestion.lowercaseString];
    [merged addObject:[SlateSuggestion search:suggestion query:suggestion]];
    if(merged.count>=7) break;
   }
   strongSelf.address.stringValue=hf.stringValue;
   [strongSelf showSuggestionList:merged fromHomeSearch:YES];
  });
 }];
 [self.suggestTask resume];
}
- (void)fetchSuggestions {
 if(self.quitting || self.address.currentEditor==nil) { [self hideSuggestions]; return; }
 NSString* query=[self.address.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(!query.length || query.length>120) { [self hideSuggestions]; return; }
 NSString* lowered=query.lowercaseString;
 if([lowered hasPrefix:@"http://"] || [lowered hasPrefix:@"https://"] || [lowered hasPrefix:@"about:"]) {
  [self showSuggestionList:[self localSuggestionsFor:query]];
  return;
 }
 if(!self.suggestPanel.visible || self.suggestions.count <= 1) {
  NSMutableArray* items=[[self localSuggestionsFor:query] mutableCopy];
  [self showSuggestionList:items];
 }
 NSMutableCharacterSet* allowed=[NSCharacterSet URLQueryAllowedCharacterSet].mutableCopy;
 [allowed removeCharactersInString:@"&+=?#"];
 NSString* encoded=[query stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
 NSURL* url=[NSURL URLWithString:[NSString stringWithFormat:@"https://www.google.com/complete/search?client=firefox&q=%@",encoded]];
 if(!url) return;
 [self.suggestTask cancel];
 __weak SlateDelegate* weakSelf=self;
 NSString* typed=query;
 self.suggestTask=[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData* data,NSURLResponse* response,NSError* error) {
  if(error || !data) return;
  NSHTTPURLResponse* http=[response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse*)response : nil;
  if(http && http.statusCode!=200) return;
  id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if(![json isKindOfClass:NSArray.class] || [json count]<2 || ![json[1] isKindOfClass:NSArray.class]) return;
  dispatch_async(dispatch_get_main_queue(), ^{
   if(![weakSelf.address.stringValue hasPrefix:typed] && ![weakSelf.address.stringValue isEqualToString:typed]) return;
   if(weakSelf.address.currentEditor==nil) return;
   NSMutableArray* merged=[[weakSelf localSuggestionsFor:weakSelf.address.stringValue] mutableCopy] ?: [NSMutableArray array];
   NSMutableSet* seen=[NSMutableSet set];
   for(SlateSuggestion* item in merged) if(item.query) [seen addObject:item.query.lowercaseString];
    for(id entry in json[1]) {
     if(![entry isKindOfClass:NSString.class] || ![entry length]) continue;
     NSString* suggestion=entry;
     if([seen containsObject:suggestion.lowercaseString]) continue;
     [seen addObject:suggestion.lowercaseString];
     // Remote completions are search suggestions — use magnifier icon, no subtitle
     [merged addObject:[SlateSuggestion search:suggestion query:suggestion]];
     if(merged.count>=8) break;
    }
    [weakSelf showSuggestionList:merged];
   });
  }];
  [self.suggestTask resume];
}
- (void)goFromSuggestPanel:(id)sender {
 // "Go" button: navigate using the currently highlighted suggestion or typed text
 if(self.suggestHighlight>=0 && self.suggestHighlight<(NSInteger)self.suggestions.count) {
  SlateSuggestion* item=self.suggestions[self.suggestHighlight];
  if(item.query.length) {
   self.address.stringValue=item.query;
   self.addressDirty=YES;
  }
 }
 [self navigate:nil];
}
- (void)pickSuggestion:(id)item {
 SlateSuggestion* suggestion=[item isKindOfClass:SlateSuggestion.class] ? item : nil;
 if(!suggestion) return;
 if(suggestion.kind==SlateSuggestionKindOpen && suggestion.tabId!=0) {
  [self activateTab:suggestion.tabId];
  [self hideSuggestions];
  [self dismissOmniboxOverlay];
  return;
 }
 if(!suggestion.query.length) return;
 self.address.stringValue=suggestion.query;
 self.addressDirty=YES;
 [self dismissOmniboxOverlay];
 [self navigate:nil];
}
- (void)moveSuggestion:(NSInteger)delta {
 if(!self.suggestPanel.visible || !self.suggestions.count) return;
 NSInteger next=self.suggestHighlight+delta;
 if(next<0) next=(NSInteger)self.suggestions.count-1;
 if(next>=(NSInteger)self.suggestions.count) next=0;
 self.suggestHighlight=next;
 [self applySuggestionHighlight];
}
- (void)moveSuggestionDelta:(NSInteger)delta {
 [self moveSuggestion:delta];
}
- (void)reopenClosedTab:(id)sender {
 if(self.quitting || !self.recentlyClosedUrls.count) return;
 NSString* lastUrl = [self.recentlyClosedUrls lastObject];
 [self.recentlyClosedUrls removeLastObject];
 if([lastUrl isEqualToString:@"about:blank"] || lastUrl.length == 0) {
  [self newTab:sender];
 } else {
  [self openUrl:lastUrl];
 }
}
- (void)selectNextTab:(id)sender {
 const auto tabs = [self orderedIds];
 if(tabs.size() <= 1) return;
 TabId cur = model.selected();
 size_t idx = 0;
 for(size_t i = 0; i < tabs.size(); ++i) {
  if(tabs[i] == cur) { idx = i; break; }
 }
 size_t nextIdx = (idx + 1) % tabs.size();
 [self activateTab:tabs[nextIdx]];
}
- (void)selectPreviousTab:(id)sender {
 const auto tabs = [self orderedIds];
 if(tabs.size() <= 1) return;
 TabId cur = model.selected();
 size_t idx = 0;
 for(size_t i = 0; i < tabs.size(); ++i) {
  if(tabs[i] == cur) { idx = i; break; }
 }
 size_t prevIdx = (idx + tabs.size() - 1) % tabs.size();
 [self activateTab:tabs[prevIdx]];
}
- (void)selectLastTab:(id)sender {
 const auto tabs = [self orderedIds];
 if(tabs.empty()) return;
 [self activateTab:tabs.back()];
}
- (void)closeAllTabs:(id)sender {
 if(self.quitting) return;
 std::vector<TabId> toClose;
 for(const auto& t : model.tabs()) {
  if(!model.closing(t.id)) toClose.push_back(t.id);
 }
 for(auto id : toClose) {
  [self beginClose:id reason:slate::CloseReason::Remove];
 }
}
- (void)cleanUpTabs:(id)sender {
 if(self.quitting) return;
 std::vector<TabId> toClose;
 TabId sel = model.selected();
 for(const auto& t : model.tabs()) {
  if(!t.pinned && t.id != sel && !self.detachedTabs[@(t.id)] && !model.closing(t.id)) {
   toClose.push_back(t.id);
  }
 }
 for(auto id : toClose) {
  [self beginClose:id reason:slate::CloseReason::Remove];
 }
}
- (void)copyCurrentUrl:(id)sender {
 const auto* tab = model.find(model.selected());
 if(!tab || tab->url.empty() || tab->url == "about:blank") return;
 NSPasteboard* pb = [NSPasteboard generalPasteboard];
 [pb clearContents];
 [pb setString:Text(tab->url) forType:NSPasteboardTypeString];
}
- (void)copyCurrentUrlAsMarkdown:(id)sender {
 const auto* tab = model.find(model.selected());
 if(!tab || tab->url.empty() || tab->url == "about:blank") return;
 NSString* title = tab->title.empty() ? Text(tab->url) : Text(tab->title);
 NSString* md = [NSString stringWithFormat:@"[%@](%@)", title, Text(tab->url)];
 NSPasteboard* pb = [NSPasteboard generalPasteboard];
 [pb clearContents];
 [pb setString:md forType:NSPasteboardTypeString];
}
- (void)printPage:(id)sender {
 WKWebView* webView = [self currentWebView];
 if(webView) {
  NSPrintInfo* printInfo = [NSPrintInfo sharedPrintInfo];
  NSPrintOperation* printOp = [webView printOperationWithPrintInfo:printInfo];
  printOp.showsPrintPanel = YES;
  printOp.showsProgressPanel = YES;
  if(self.window) {
   [printOp runOperationModalForWindow:self.window delegate:nil didRunSelector:nil contextInfo:nil];
  } else {
   [printOp runOperation];
  }
  return;
 }
 auto it = runtimes.find(model.selected());
 if(it != runtimes.end() && it->second.engine) {
  it->second.engine->execute_script("window.print();");
 }
}
- (void)sharePage:(id)sender {
 const auto* tab = model.find(model.selected());
 if(!tab || tab->url.empty() || tab->url == "about:blank") return;
 NSURL* url = [NSURL URLWithString:Text(tab->url)];
 if(!url) return;

 NSView* view = nil;
 NSRect anchor = NSZeroRect;

 if([sender isKindOfClass:[NSView class]]) {
  view = (NSView*)sender;
  anchor = view.bounds;
 } else {
  view = [self currentWebView] ?: self.content;
  if(!view) return;
  const CGFloat inset = 12.0;
  const CGFloat y = view.isFlipped ? inset : (NSMaxY(view.bounds) - inset);
  anchor = NSMakeRect(NSMaxX(view.bounds) - inset, y, 1, 1);
 }

 NSSharingServicePicker* picker = [[NSSharingServicePicker alloc] initWithItems:@[url]];
 [picker showRelativeToRect:anchor ofView:view preferredEdge:view.isFlipped ? NSRectEdgeMaxY : NSRectEdgeMinY];
}
- (SlateFindBar*)ensureFindBar {
 if(!self.findBar) {
  self.findBar = [[SlateFindBar alloc] initWithOwner:self];
 }
 return self.findBar;
}

- (IBAction)findInPage:(id)sender {
 WKWebView* webView = [self currentWebView];
 if(!webView) return;

 SlateFindBar* bar = [self ensureFindBar];
 bar.targetWebView = webView;

 [webView evaluateJavaScript:@"window.getSelection() ? window.getSelection().toString() : ''" completionHandler:^(id result, NSError* error) {
  NSString* sel = (NSString*)result;
  NSString* query = (sel && [sel isKindOfClass:[NSString class]] && sel.length > 0) ? sel : nil;
  dispatch_async(dispatch_get_main_queue(), ^{
   [bar showInView:self.content initialQuery:query];
  });
 }];
}

- (IBAction)findNext:(id)sender {
 if(self.findBar && self.findBar.isVisible) {
  [self.findBar findNext];
 } else {
  [self findInPage:sender];
 }
}

- (IBAction)findPrevious:(id)sender {
 if(self.findBar && self.findBar.isVisible) {
  [self.findBar findPrevious];
 } else {
  [self findInPage:sender];
 }
}

- (IBAction)useSelectionForFind:(id)sender {
 WKWebView* webView = [self currentWebView];
 if(!webView) return;
 SlateFindBar* bar = [self ensureFindBar];
 bar.targetWebView = webView;
 [webView evaluateJavaScript:@"window.getSelection() ? window.getSelection().toString() : ''" completionHandler:^(id result, NSError* error) {
  NSString* sel = (NSString*)result;
  if(sel && [sel isKindOfClass:[NSString class]] && sel.length > 0) {
   dispatch_async(dispatch_get_main_queue(), ^{
    bar.lastQuery = sel;
    if(bar.isVisible) {
     bar.searchField.stringValue = sel;
     [bar performSearchWithQuery:sel];
    }
   });
  }
 }];
}
- (void)viewSource:(id)sender {
 const auto* tab = model.find(model.selected());
 if(!tab || tab->url.empty() || tab->url == "about:blank") return;
 NSString* vsUrl = [NSString stringWithFormat:@"view-source:%@", Text(tab->url)];
 [self openUrl:vsUrl];
}
- (void)inspectElement:(id)sender {
 auto it = runtimes.find(model.selected());
 if(it != runtimes.end() && it->second.engine) {
  it->second.engine->execute_script("console.log('[Slate] Developer inspection requested');");
 }
}
- (void)openNewWindowWithUrl:(NSString*)url {
 if(self.quitting) return;
 try {
  const TabId identifier=model.add((url.length ? url : @"about:blank").UTF8String);
  [self tearOffTab:identifier atScreenPoint:NSMakePoint(NSMidX(self.window.frame),NSMidY(self.window.frame))];
 } catch(const std::exception&) { NSBeep(); }
}

- (void)tearOffTab:(TabId)tabId atScreenPoint:(NSPoint)screenPoint {
 const auto* tab = model.find(tabId);
 if(!tab || self.quitting || model.closing(tabId)) return;
 if(SlateDetachedTabWindow* existing=self.detachedTabs[@(tabId)]) {
  [existing.window makeKeyAndOrderFront:nil];
  return;
 }
 const TabId previouslySelected=model.selected();
 if(tab->url!="about:blank" && !runtimes.contains(tabId)) [self activateTab:tabId];
 const TabId splitSurvivor=workspace.remove(tabId);
 SlateDetachedTabWindow* detached=[[SlateDetachedTabWindow alloc] initWithOwner:self tab:tabId atScreenPoint:screenPoint];
 self.detachedTabs[@(tabId)]=detached;
 auto runtime=runtimes.find(tabId);
 if(runtime!=runtimes.end() && runtime->second.host) {
  [runtime->second.host removeFromSuperview];
  [detached.pageContainer addSubview:runtime->second.host];
  runtime->second.host.frame=detached.pageContainer.bounds;
  runtime->second.host.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
  runtime->second.host.hidden=NO;
  runtime->second.hide_scheduled=false;
  if(runtime->second.engine) {
   runtime->second.engine->set_occluded(NO);
   runtime->second.engine->host_geometry_changed();
  }
 } else {
  [detached showNewTabPage];
 }
 if(model.selected()==tabId) {
  TabId replacement=0;
  if(splitSurvivor && !self.detachedTabs[@(splitSurvivor)]) replacement=splitSurvivor;
  else if(previouslySelected!=tabId && model.find(previouslySelected) && !self.detachedTabs[@(previouslySelected)])
   replacement=previouslySelected;
  if(!replacement) for(const auto& candidate:model.tabs()) if(candidate.id!=tabId && !self.detachedTabs[@(candidate.id)]) {
   replacement=candidate.id; break;
  }
  if(!replacement) replacement=model.add("about:blank");
  [self activateTab:replacement];
 }
 self.tabListSignature=nil;
 self.tabStripIdentity=nil;
 [self refresh];
 [self scheduleSave];
}

- (SlateDetachedTabWindow*)detachedTabForWindow:(NSWindow*)window {
 if(!window) return nil;
 for(SlateDetachedTabWindow* detached in self.detachedTabs.allValues)
  if(detached.window==window) return detached;
 return nil;
}
- (BOOL)handleDetachedKeyEvent:(NSEvent*)event {
 SlateDetachedTabWindow* detached=[self detachedTabForWindow:event.window];
 if(!detached) return NO;
 const NSEventModifierFlags flags=event.modifierFlags&NSEventModifierFlagDeviceIndependentFlagsMask;
 if(!(flags&NSEventModifierFlagCommand) || (flags&(NSEventModifierFlagOption|NSEventModifierFlagControl))) return NO;
 if(event.keyCode==13) { [detached.window performClose:nil]; return YES; } // ⌘W
 if(event.keyCode==37) { [detached.window makeFirstResponder:detached.address]; [detached.address selectText:nil]; return YES; } // ⌘L
 if(event.keyCode==15) { [detached reload:nil]; return YES; } // ⌘R
 if(event.keyCode==123) { [detached goBack:nil]; return YES; }
 if(event.keyCode==124) { [detached goForward:nil]; return YES; }
 return NO;
}
- (void)navigateDetachedTab:(TabId)tabId toURL:(const std::string&)url {
 SlateDetachedTabWindow* detached=self.detachedTabs[@(tabId)];
 if(!detached || url.empty()) return;
 auto it=runtimes.find(tabId);
 if(it!=runtimes.end() && it->second.engine) {
  it->second.engine->navigate(url);
  return;
 }
 // A detached New Tab has no WebKit view yet. Initialize its existing tab
 // through the normal engine path, then move that same view into this window.
 const TabId mainSelection=model.selected();
 model.update(tabId,url,{});
 [self.detachedTabs removeObjectForKey:@(tabId)];
 [self activateTab:tabId];
 it=runtimes.find(tabId);
 if(it!=runtimes.end() && it->second.host) {
  [it->second.host removeFromSuperview];
  for(NSView* view in [detached.pageContainer.subviews copy]) [view removeFromSuperview];
  detached.homeView=nil;
  detached.homeBoard=nil;
  [detached.pageContainer addSubview:it->second.host];
  it->second.host.frame=detached.pageContainer.bounds;
  it->second.host.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
  it->second.host.hidden=NO;
  if(it->second.engine) it->second.engine->host_geometry_changed();
 }
 self.detachedTabs[@(tabId)]=detached;
 if(mainSelection && model.find(mainSelection)) [self activateTab:mainSelection];
 [detached refresh];
 [self refresh];
 [self scheduleSave];
}
- (BOOL)reattachTab:(TabId)tabId atScreenPoint:(NSPoint)screenPoint {
 SlateDetachedTabWindow* detached=self.detachedTabs[@(tabId)];
 if(!detached || !model.find(tabId) || self.quitting) return NO;
 TabId before=0;
 if(!NSEqualPoints(screenPoint,NSZeroPoint)) {
  if(!self.window.visible || self.window.miniaturized) return NO;
  NSView* dropView=self.verticalTabs ? self.sidebar : self.tabCluster;
  const NSRect dropFrame=[self.window convertRectToScreen:[dropView convertRect:dropView.bounds toView:nil]];
  if(!NSPointInRect(screenPoint,NSInsetRect(dropFrame,-12,-18))) return NO;
  if(!self.verticalTabs) for(NSView* view in self.tabPills.arrangedSubviews) {
   if(![view isKindOfClass:SlateTabPill.class]) continue;
   const NSRect frame=[self.window convertRectToScreen:[view convertRect:view.bounds toView:nil]];
   if(NSPointInRect(screenPoint,frame)) { before=((SlateTabPill*)view).tabId; break; }
  }
 }
 auto runtime=runtimes.find(tabId);
 if(runtime!=runtimes.end() && runtime->second.host) {
  [runtime->second.host removeFromSuperview];
  [self.content addSubview:runtime->second.host positioned:NSWindowBelow relativeTo:self.homeView];
  runtime->second.host.frame=WebFillRect(self.content);
  runtime->second.host.hidden=NO;
  if(runtime->second.engine) runtime->second.engine->host_geometry_changed();
 }
 [self.detachedTabs removeObjectForKey:@(tabId)];
 [detached dismissWithoutClosingTab];
 if(before && before!=tabId) model.move_tab_before(tabId,before);
 if(!self.window.visible || self.window.miniaturized) [self.window makeKeyAndOrderFront:nil];
 self.tabListSignature=nil;
 self.tabStripIdentity=nil;
 [self activateTab:tabId];
 [self refresh];
 [self scheduleSave];
 return YES;
}
- (void)reattachAllDetachedTabs {
 for(NSNumber* identifier in [self.detachedTabs.allKeys copy])
  [self reattachTab:identifier.unsignedLongLongValue atScreenPoint:NSZeroPoint];
}

- (SlateTabPill*)pillViewForTabId:(TabId)tabId {
 for (NSView* view in self.tabPills.arrangedSubviews) {
  if ([view isKindOfClass:SlateTabPill.class] && ((SlateTabPill*)view).tabId == tabId) {
   return (SlateTabPill*)view;
  }
 }
 return nil;
}

- (TabId)splitTargetTabAtWindowPoint:(NSPoint)windowPoint excluding:(TabId)source side:(slate::SplitSide*)side {
 if(!source || !self.tabPills) return 0;
 const NSPoint point=[self.tabPills convertPoint:windowPoint fromView:nil];
 for(NSView* view in self.tabPills.arrangedSubviews) {
  if(![view isKindOfClass:SlateTabPill.class]) continue;
  SlateTabPill* pill=(SlateTabPill*)view;
  const auto* target=model.find(pill.tabId);
  const BOOL available=workspace.open_action(source,pill.tabId)==slate::SplitOpenAction::PairWithBase ||
   (target && target->url=="about:blank" && workspace.member(pill.tabId) && !workspace.member(source));
  if(pill.tabId==source || !available)
   continue;
  const NSRect center=NSInsetRect(pill.frame,NSWidth(pill.frame)*0.15,-3);
  if(!NSPointInRect(point,center)) continue;
  if(side) *side=point.x<NSMidX(pill.frame) ? slate::SplitSide::Left : slate::SplitSide::Right;
  return pill.tabId;
 }
 return 0;
}

- (void)dragMoveTab:(TabId)tabId toPoint:(NSPoint)localPoint {
 if (!tabId) return;
 for (NSView* view in self.tabPills.arrangedSubviews) {
  if (![view isKindOfClass:SlateTabPill.class]) continue;
  SlateTabPill* pill = (SlateTabPill*)view;
  if (pill.tabId == tabId) continue;

  NSRect pillFrame = [self.tabCluster convertRect:pill.frame fromView:pill.superview];
  if (NSPointInRect(localPoint, NSInsetRect(pillFrame, -4, -4))) {
   const auto* draggedTab = model.find(tabId);
   const auto* targetTab = model.find(pill.tabId);
   if (!draggedTab || !targetTab) return;

   CGFloat draggedCenterX = NSMidX([self.tabCluster convertRect:[self pillViewForTabId:tabId].frame fromView:self.tabPills]);
   if (localPoint.x > draggedCenterX) {
    TabId nextTabId = 0;
    BOOL foundTarget = NO;
    for (TabId tid : [self orderedIds]) {
     if (foundTarget && tid != tabId) {
      nextTabId = tid;
      break;
     }
     if (tid == pill.tabId) foundTarget = YES;
    }
    model.move_tab_before(tabId, nextTabId);
   } else {
    model.move_tab_before(tabId, pill.tabId);
   }
   [self rebuildTabStrip];
   [self scheduleSave];
   break;
  }
 }
}

- (void)newWindow:(id)sender {
 [self openNewWindowWithUrl:@"about:blank"];
}
- (void)newIncognitoWindow:(id)sender {
 [self newIncognitoTab:sender];
}
// Cmd+1–9: switch to the N-th visible tab in the sidebar (Cmd+9: switch to last tab)
- (void)selectTabAtIndex:(NSMenuItem*)sender {
 if(sender.tag == 9) {
  [self selectLastTab:nil];
  return;
 }
 const NSInteger targetIndex=sender.tag-1; // tag is 1..8
 if(targetIndex<0) return;
 const auto rows=[self sidebarRows];
 NSInteger tabCount=0;
 for(const auto& row:rows) {
  if(row.kind==SideRow::Kind::Tab) {
   if(tabCount==targetIndex) { [self activateTab:row.tab]; return; }
   tabCount++;
  }
 }
}
- (void)showExtensions:(id)sender {
 NSAlert* alert=[[NSAlert alloc] init];
 alert.messageText=@"Extensions stay off in this build";
 alert.informativeText=@"Chrome Web Store add-ons are not loaded here. This Chromium embed (Alloy) has no extension installer, and Slate does not load unpacked packages from disk. That keeps school and personal pages from running extra third-party code with the browser's privileges.\n\nThe puzzle-piece control and the Extensions menu are placeholders for a later, reviewed extension model. Sandbox, site isolation, and certificate checks stay on.";
 [alert addButtonWithTitle:@"OK"];
 if(self.window) [alert beginSheetModalForWindow:self.window completionHandler:nil];
 else [alert runModal];
}
- (void)reloadOrGo:(id)sender {
 if(self.address.currentEditor) [self navigate:sender];
 else [self reload:sender];
}
- (BOOL)validateMenuItem:(NSMenuItem*)item {
 if(item.action==@selector(setAccent:) || item.action==@selector(chooseCustomAccent:)) return YES;
 auto it=runtimes.find(model.selected());
 const BOOL live=it!=runtimes.end() && it->second.engine && !model.closing(it->first);
 if(item.action==@selector(goBack:)) return live && it->second.back;
 if(item.action==@selector(goForward:)) return live && it->second.forward;
 if(item.action==@selector(reload:)) return live;
 if(item.action==@selector(hardReload:)) return live;
 if(item.action==@selector(reopenClosedTab:)) return self.recentlyClosedUrls.count > 0;
 if(item.action==@selector(selectNextTab:) || item.action==@selector(selectPreviousTab:)) return model.tabs().size() > 1;
 if(item.action==@selector(copyCurrentUrl:) || item.action==@selector(copyCurrentUrlAsMarkdown:)) {
  const auto* tab=model.find(model.selected());
  return tab && !tab->url.empty() && tab->url!="about:blank";
 }
 if(item.action==@selector(toggleBookmark:)) {
  const auto* tab=model.find(model.selected());
  return tab && tab->url.rfind("http",0)==0;
 }
 if(item.action==@selector(newTabGroup:)) return model.find(model.selected())!=nullptr;
 return YES;
}
- (void)goBack:(id)sender {
 auto it=runtimes.find(model.selected());
 if(it==runtimes.end() || !it->second.engine || model.closing(it->first) || !it->second.back) return;
 [self.backButton playMotion];
 it->second.engine->back();
}
- (void)goForward:(id)sender {
 auto it=runtimes.find(model.selected());
 if(it==runtimes.end() || !it->second.engine || model.closing(it->first) || !it->second.forward) return;
 [self.forwardButton playMotion];
 it->second.engine->forward();
}
- (void)reload:(id)sender {
 auto it=runtimes.find(model.selected());
 if(it==runtimes.end() || !it->second.engine || model.closing(it->first)) return;
 if(it->second.loading) { it->second.engine->stop(); return; }
 [self.reloadButton playMotion];
 it->second.engine->reload();
}
- (void)hardReload:(id)sender {
 auto it=runtimes.find(model.selected());
 if(it==runtimes.end() || !it->second.engine || model.closing(it->first)) return;
 if(it->second.loading) { it->second.engine->stop(); return; }
 [self.reloadButton playMotion];
 it->second.engine->reload_ignore_cache();
}
- (void)focusAddress:(id)sender {
 const auto* tab=model.find(model.selected());
 NSTextField* homeField=[self homeSearchField];
 // On the new tab page, always focus the center Omnibox directly
 if(tab && tab->url=="about:blank") {
  [self dismissOmniboxOverlay];
  if(homeField) {
   [self.window makeFirstResponder:homeField];
   [homeField selectText:nil];
  }
  return;
 }
 NSString* shown=tab ? Text(tab->url) : @"";
 if([shown isEqualToString:@"about:blank"] || [shown isEqualToString:@"about:blank#popup"]) shown=@"";

 // Over an active page: raise the center-floating Omnibox overlay (over: true)
 if(!self.omniboxOverlay) {
  self.omniboxOverlay=[[SlateOmniboxOverlay alloc] initWithDelegate:self];
 }
 self.omniboxOverlay.card.accentColor=self.barColor;
 self.omniboxOverlay.card.inkColor=self.barInk;
 [self.omniboxOverlay showOver:self.stage initialText:shown];
}
- (const slate::Tab*)selectedTab {
 return model.find(model.selected());
}
- (void)dismissOmniboxOverlay {
 if(self.omniboxOverlay && self.omniboxOverlay.isShowing) {
  [self.omniboxOverlay dismiss];
 }
}
- (void)showSuggestionsForCard:(SlateOmniboxCard*)card query:(NSString*)query {
 if(self.quitting || !card) { [self hideSuggestions]; return; }
 NSString* clean=[query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(!clean.length) { [self hideSuggestions]; return; }

 NSMutableArray* items=[[self localSuggestionsFor:clean] mutableCopy];
 self.suggestions=items;
 self.suggestHighlight=items.count ? 0 : -1;
 for(NSView* row in [self.suggestStack.arrangedSubviews copy]) {
  [self.suggestStack removeArrangedSubview:row];
  [row removeFromSuperview];
 }
 if(!items.count) { [self.suggestPanel orderOut:nil]; return; }
 for(SlateSuggestion* item in items) {
  SlateSuggestRow* row=[[SlateSuggestRow alloc] initWithItem:item owner:self];
  [self.suggestStack addArrangedSubview:row];
  [row.widthAnchor constraintEqualToAnchor:self.suggestStack.widthAnchor].active=YES;
 }
 [self applySuggestionHighlight];
 [self positionSuggestPanelBelowOverlay:card];
 if(self.suggestPanel.parentWindow != self.window)
  [self.window addChildWindow:self.suggestPanel ordered:NSWindowAbove];
 [self.suggestPanel orderFront:nil];
}
- (void)showSuggestionsForOverlay:(NSString*)query {
 [self showSuggestionsForCard:self.omniboxOverlay.card query:query];
}
- (void)positionSuggestPanelBelowOverlay:(NSView*)fieldCard {
 if(!self.suggestions.count || !fieldCard || !self.window) return;
 NSRect fieldInWindow=[fieldCard convertRect:fieldCard.bounds toView:nil];
 NSRect fieldScreen=[self.window convertRectToScreen:fieldInWindow];
 const CGFloat panelW=MIN(640.0, NSWidth(fieldScreen));
 const CGFloat rowCount=MIN(7.0, (CGFloat)self.suggestions.count);
 const CGFloat height=rowCount * 44.0 + 8.0;
 const CGFloat panelX=NSMidX(fieldScreen) - panelW / 2.0;
 const CGFloat panelY=NSMinY(fieldScreen) - height - 6.0;
 NSRect frame=NSMakeRect(panelX, panelY, panelW, height);
 if(self.suggestCard) {
  self.suggestCard.layer.cornerRadius=14;
  if(@available(macOS 11.0, *)) self.suggestCard.layer.cornerCurve=kCACornerCurveContinuous;
  self.suggestCard.layer.borderWidth=1.0;

  NSColor* accent=self.barColor;
  BOOL isDark=YES;
  if(accent) {
   CGFloat r=0, g=0, b=0, a=0;
   NSColor* rgb=[accent colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: accent;
   [rgb getRed:&r green:&g blue:&b alpha:&a];
   CGFloat lum=0.2126*r + 0.7152*g + 0.0722*b;
   isDark=lum<0.55;
  } else {
   isDark=[[self.window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
  }

  NSColor* cardBg=nil;
  NSColor* borderColor=nil;
  if(accent) {
   if(isDark) {
    cardBg=[accent blendedColorWithFraction:0.32 ofColor:[NSColor blackColor]];
    if(!cardBg) cardBg=[NSColor colorWithCalibratedWhite:0.18 alpha:0.95];
    borderColor=[NSColor colorWithWhite:1.0 alpha:0.20];
   } else {
    cardBg=[accent blendedColorWithFraction:0.35 ofColor:[NSColor whiteColor]];
    if(!cardBg) cardBg=[NSColor colorWithCalibratedWhite:0.96 alpha:0.95];
    borderColor=[NSColor colorWithWhite:0.0 alpha:0.16];
   }
  } else {
   if(isDark) {
    cardBg=[NSColor colorWithCalibratedWhite:0.18 alpha:0.95];
    borderColor=[NSColor colorWithWhite:1.0 alpha:0.20];
   } else {
    cardBg=[NSColor colorWithCalibratedWhite:0.96 alpha:0.95];
    borderColor=[NSColor colorWithWhite:0.0 alpha:0.16];
   }
  }
  self.suggestCard.layer.backgroundColor=cardBg.CGColor;
  self.suggestCard.layer.borderColor=borderColor.CGColor;
 }
 if(self.suggestPanel.parentWindow != self.window)
  [self.window addChildWindow:self.suggestPanel ordered:NSWindowAbove];
 [self.suggestPanel setFrame:frame display:YES];
}
- (void)submitOmniboxCard:(SlateOmniboxCard*)card {
 if(self.suggestHighlight>=0 && self.suggestHighlight<(NSInteger)self.suggestions.count) {
  SlateSuggestion* item=self.suggestions[self.suggestHighlight];
  [self pickSuggestion:item];
  return;
 }
 NSString* text=[card.field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(!text.length) {
  [card shake];
  return;
 }
 const auto decision=slate::resolve_address_bar(text.UTF8String ?: "");
 if(decision.kind==slate::InputKind::Invalid || decision.url.empty()) {
  NSBeep();
  [card shake];
  return;
 }
 self.address.stringValue=[NSString stringWithUTF8String:decision.url.c_str()];
 self.addressDirty=NO;
 if(self.omniboxOverlay && self.omniboxOverlay.isShowing) {
  [self.omniboxOverlay dismiss];
 } else {
  [self hideSuggestions];
  card.field.stringValue=@"";
 }
 [self navigate:nil];
}
- (void)submitOverlay:(SlateOmniboxOverlay*)overlay {
 [self submitOmniboxCard:overlay.card];
}
- (void)controlTextDidChange:(NSNotification*)notification {
 if(notification.object==[self homeSearchField]) return;
 if(notification.object!=self.address) return;
 [SlateSiteCardPanel hide];
 if(self.address.superview && [self.address.superview isKindOfClass:SlateOmnibox.class]) {
  [((SlateOmnibox*)self.address.superview) applyContrast];
 }
 self.addressDirty=YES;
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchSuggestions) object:nil];
 [self performSelector:@selector(fetchSuggestions) withObject:nil afterDelay:0.16];
}
- (void)controlTextDidBeginEditing:(NSNotification*)notification {
 NSTextView* editor=(NSTextView*)[self.window fieldEditor:NO forObject:notification.object];
 if(editor && [editor isKindOfClass:NSTextView.class]) {
  NSColor* ink=self.barInk ?: NSColor.labelColor;
  editor.selectedTextAttributes=@{
   NSBackgroundColorAttributeName:[ink colorWithAlphaComponent:0.12],
   NSForegroundColorAttributeName:ink
  };
 }
 if(notification.object==[self homeSearchField]) return;
 if(notification.object!=self.address) return;
 self.addressOpen=YES;
 [self layoutOmnibox];
 [self fetchSuggestions];
}
- (void)controlTextDidEndEditing:(NSNotification*)notification {
 if(notification.object==[self homeSearchField]) {
  // Small delay so clicking a suggestion row registers before hiding
  [self performSelector:@selector(hideSuggestions) withObject:nil afterDelay:0.15];
  return;
 }
 if(notification.object!=self.address) return;
 [SlateSiteCardPanel hide];
 [self hideSuggestions];
 const auto* tab=model.find(model.selected());
 if(!(tab && tab->url=="about:blank")) {
  self.addressOpen=NO;
  [self layoutOmnibox];
 }
}
- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
 NSTextField* homeField=[self homeSearchField];
 if(control==homeField) {
  if(commandSelector==@selector(moveDown:)) { [self moveSuggestion:1]; return YES; }
  if(commandSelector==@selector(moveUp:)) { [self moveSuggestion:-1]; return YES; }
  if(commandSelector==@selector(insertNewline:)) {
   if(self.suggestPanel.visible && self.suggestHighlight>=0 && self.suggestHighlight<(NSInteger)self.suggestions.count) {
    SlateSuggestion* item=self.suggestions[(NSUInteger)self.suggestHighlight];
    if(item.query.length) homeField.stringValue=item.query;
   }
   [self submitHomeSearch:homeField];
   return YES;
  }
  if(commandSelector==@selector(cancelOperation:)) {
   homeField.stringValue=@"";
   [self hideSuggestions];
   [self.window makeFirstResponder:self.content];
   return YES;
  }
  return NO;
 }
 if(control!=self.address) return NO;
 if(commandSelector==@selector(moveDown:)) { [self moveSuggestion:1]; return YES; }
 if(commandSelector==@selector(moveUp:)) { [self moveSuggestion:-1]; return YES; }
 if(commandSelector==@selector(insertNewline:)) {
  if(self.suggestPanel.visible && self.suggestHighlight>=0 && self.suggestHighlight<(NSInteger)self.suggestions.count) {
   SlateSuggestion* item=self.suggestions[(NSUInteger)self.suggestHighlight];
   if(item.query.length) { self.address.stringValue=item.query; self.addressDirty=YES; }
  }
  [self navigate:nil];
  return YES;
 }
 if(commandSelector==@selector(cancelOperation:)) {
  self.addressDirty=NO;
  [self dismissOmnibox];
  return YES;
 }
 return NO;
}
#if defined(SLATE_ENABLE_VERIFY)
- (NSString*)isolatedCommandFile {
 NSString* file=NSProcessInfo.processInfo.environment[@"SLATE_COMMAND_FILE"];
 if(file.length && file.isAbsolutePath && [NSFileManager.defaultManager fileExistsAtPath:file]) return file;
 if(NSProcessInfo.processInfo.environment[@"SLATE_ENABLE_DOWNLOADS_VERIFY"]) {
  NSString* downloads = [NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"slate_verify.txt"];
  if([NSFileManager.defaultManager fileExistsAtPath:downloads]) return downloads;
 }
 return nil;
}
- (void)startVerifyCommands {
 NSString* file=[self isolatedCommandFile];
 if(!file) return;
 fprintf(stderr,"SLATE_VERIFY watching %s\n",file.UTF8String);
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
  [NSThread sleepForTimeInterval:0.35];
  [self runVerifyLoopInBackground];
 });
}
- (void)runVerifyLoopInBackground {
 NSString* file=[self isolatedCommandFile];
 if(!file || self.quitting) return;
 NSError* err = nil;
 NSString* text=[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:&err] ?: @"";
 fprintf(stderr, "SLATE_VERIFY loaded file=%s length=%lu err=%s\n", file.UTF8String, (unsigned long)text.length, err ? err.localizedDescription.UTF8String : "none");
 if([file containsString:@"Downloads/slate_verify.txt"]) {
  [NSFileManager.defaultManager removeItemAtPath:file error:nil];
 }
 NSArray* lines=[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
 for(NSString* raw in lines) {
  if(self.quitting) break;
  NSString* line=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if(!line.length || [line hasPrefix:@"#"]) continue;
  if([line hasPrefix:@"waitsignal "]) {
   // Verification-only barrier: measurement owns the next phase, not a timer.
   NSString* name=[line substringFromIndex:11];
   NSCharacterSet* allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"];
   NSString* data=NSProcessInfo.processInfo.environment[@"SLATE_DATA_DIR"];
   if(!name.length || name.length>64 || [name rangeOfCharacterFromSet:allowed.invertedSet].location!=NSNotFound ||
      !data.isAbsolutePath) {
    fprintf(stderr,"SLATE_VERIFY_SIGNAL invalid\n"); break;
   }
   NSString* signal=[data stringByAppendingPathComponent:[@"verify-signal-" stringByAppendingString:name]];
   const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(120);
   while(!self.quitting && ![NSFileManager.defaultManager fileExistsAtPath:signal] &&
         std::chrono::steady_clock::now()<deadline) [NSThread sleepForTimeInterval:0.05];
   if(self.quitting) break;
   if(![NSFileManager.defaultManager fileExistsAtPath:signal]) {
    fprintf(stderr,"SLATE_VERIFY_SIGNAL timeout\n"); break;
   }
   continue;
  }
  if([line hasPrefix:@"sleep "]) {
   double s = MAX(0.05, [line substringFromIndex:6].doubleValue);
   [NSThread sleepForTimeInterval:s];
   continue;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
   [self runVerifyCommand:line];
  });
  [NSThread sleepForTimeInterval:0.25];
 }
}
- (void)runVerifyCommand:(NSString*)line {
 fprintf(stderr,"SLATE_VERIFY command=%s\n",line.UTF8String);
 if([line isEqual:@"unload"]) { [self unloadTab:nil]; return; }
 if([line isEqual:@"confirm"]) {
  NSWindow* sheet=self.window.attachedSheet;
  if(sheet) [self.window endSheet:sheet returnCode:NSAlertSecondButtonReturn];
  else fprintf(stderr,"SLATE_VERIFY no-sheet\n");
  return;
 }
 if([line isEqual:@"autofill"]) {
  [self triggerAutofillAction:nil];
  return;
 }
 if([line isEqual:@"restore"]) { [self restoreTab:nil]; return; }
 if([line isEqual:@"vertical"]) { [self toggleVerticalTabs:nil]; return; }
 if([line hasPrefix:@"setvertical "]) {
  BOOL v = [line substringFromIndex:12].intValue != 0;
  if(self.verticalTabs != v) {
   [self toggleVerticalTabs:nil];
  }
  return;
 }
 if([line isEqual:@"togglehide"] || [line isEqual:@"togglecollapse"]) { [self toggleTabsReveal:nil]; return; }
 if([line isEqual:@"newtab"]) { [self newTab:nil]; return; }
 if([line isEqual:@"newwindow"]) { [self newWindow:nil]; return; }
 if([line hasPrefix:@"splitright "] || [line hasPrefix:@"splitleft "]) {
  const BOOL right=[line hasPrefix:@"splitright "];
  TabId identifier=(TabId)[line substringFromIndex:(right ? 11 : 10)].longLongValue;
  [self openSplitWithTab:identifier side:right ? slate::SplitSide::Right : slate::SplitSide::Left base:model.selected()];
  return;
 }
 if([line isEqual:@"swapsplit"]) { [self swapSplitSides:nil]; return; }
 if([line isEqual:@"exitsplit"]) { [self exitSplitView:nil]; return; }
 // Exercise the real switch and check that the incoming pages receive input
 // immediately, while the outgoing surface may still be attached for native PiP.
 if([line hasPrefix:@"checkswitch "] || [line isEqual:@"checkworkspace"]) {
  const BOOL switching=[line hasPrefix:@"checkswitch "];
  const TabId target=switching ? (TabId)[line substringFromIndex:12].longLongValue : model.selected();
  NSMutableDictionary<NSNumber*,WKWebView*>* before=[NSMutableDictionary dictionary];
  for(const auto& [id,item]:runtimes) {
   if(WKWebView* page=[self webViewForTab:id]) before[@(id)]=page;
  }
  const auto started=std::chrono::steady_clock::now();
  if(switching) [self activateTab:target];
  const BOOL split=workspace.visible_for(model.selected());
  const std::vector<TabId> visible=split ? std::vector<TabId>{workspace.left,workspace.right}
                                       : std::vector<TabId>{model.selected()};
  int failures=0;
  for(TabId id:visible) {
   const auto* tab=model.find(id);
   if(!tab || tab->url=="about:blank") continue;
   auto it=runtimes.find(id);
   WKWebView* page=[self webViewForTab:id];
   NSView* host=it!=runtimes.end() ? it->second.host : nil;
   NSPoint center=[self.content convertPoint:NSMakePoint(NSMidX(host.bounds),NSMidY(host.bounds)) fromView:host];
   NSView* hit=[self.content hitTest:center];
   const BOOL exposed=host && !host.hiddenOrHasHiddenAncestor &&
    (hit==host || [hit isDescendantOf:host]) && NSWidth(page.frame)>1 && NSHeight(page.frame)>1;
   const BOOL reused=!before[@(id)] || before[@(id)]==page;
   failures+=!exposed || !reused;
   fprintf(stderr,"SLATE_SWITCH_PANE tab=%llu exposed=%d reused=%d hit=%s page=%p\n",
    (unsigned long long)id,(int)exposed,(int)reused,hit ? NSStringFromClass(hit.class).UTF8String : "none",page);
  }
  const double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count();
  fprintf(stderr,"SLATE_SWITCH_CHECK selected=%llu split=%d failures=%d elapsed_ms=%.3f\n",
   (unsigned long long)model.selected(),(int)split,failures,ms);
  return;
 }
 if([line hasPrefix:@"verifysidebardrop "] || [line hasPrefix:@"verifypagedrop "]) {
  NSArray<NSString*>* parts=[line componentsSeparatedByString:@" "];
  if(parts.count!=3) return;
  const BOOL pageDrop=[parts[0] isEqual:@"verifypagedrop"];
  const TabId source=(TabId)[parts[1] longLongValue];
  const TabId original=model.selected();
  const TabId target=pageDrop ? original : (TabId)[parts[2] longLongValue];
  NSInteger sourceRow=-1,targetRow=-1;
  const auto rows=[self sidebarRows];
  for(size_t i=0;i<rows.size();++i) if(rows[i].kind==SideRow::Kind::Tab) {
   if(rows[i].tab==source) sourceRow=(NSInteger)i;
   if(rows[i].tab==target) targetRow=(NSInteger)i;
  }
  if(sourceRow<0 || targetRow<0) { fprintf(stderr,"SLATE_VERTICAL_DROP failures=1 missing-row\n"); return; }
  NSDraggingSession* session=(NSDraggingSession*)[NSObject new];
  [self beginSidebarTabGesture:source];
  [self tableView:self.tabList draggingSession:session willBeginAtPoint:NSZeroPoint forRowIndexes:[NSIndexSet indexSetWithIndex:sourceRow]];
  const BOOL captured=self.splitDragBaseTab==original;
  SlateVerifyDrag* drag=[SlateVerifyDrag new];
  drag.draggingSource=self.tabList;
  drag.draggingPasteboard=[NSPasteboard pasteboardWithUniqueName];
  [drag.draggingPasteboard writeObjects:@[[self tableView:self.tabList pasteboardWriterForRow:sourceRow]]];
  BOOL accepted=NO;
  NSDragOperation valid=NSDragOperationNone;
  if(pageDrop) {
   const BOOL left=[parts[2] isEqual:@"left"];
   drag.draggingLocation=[self.content convertPoint:NSMakePoint(NSWidth(self.content.bounds)*(left ? 0.25 : 0.75),NSHeight(self.content.bounds)*0.5) toView:nil];
   valid=[self.content draggingEntered:(id<NSDraggingInfo>)drag];
   accepted=[self.content prepareForDragOperation:(id<NSDraggingInfo>)drag] && [self.content performDragOperation:(id<NSDraggingInfo>)drag];
  } else {
   const NSRect row=[self.tabList rectOfRow:targetRow];
   drag.draggingLocation=[self.tabList convertPoint:NSMakePoint(NSMidX(row),NSMidY(row)) toView:nil];
   valid=[self tableView:self.tabList validateDrop:(id<NSDraggingInfo>)drag proposedRow:targetRow proposedDropOperation:NSTableViewDropOn];
   accepted=[self tableView:self.tabList acceptDrop:(id<NSDraggingInfo>)drag row:targetRow dropOperation:NSTableViewDropOn];
  }
  [self tableView:self.tabList draggingSession:session endedAtPoint:[self.window convertPointToScreen:drag.draggingLocation] operation:accepted ? NSDragOperationMove : NSDragOperationNone];
  [drag.draggingPasteboard releaseGlobally];
  const BOOL paired=workspace.same_pair(source,target) && workspace.visible_for(model.selected());
  fprintf(stderr,"SLATE_VERTICAL_DROP page=%d captured=%d accepted=%d paired=%d failures=%d\n",(int)pageDrop,(int)captured,(int)accepted,(int)paired,!(captured && accepted && paired && valid==NSDragOperationMove));
  return;
 }
 if([line hasPrefix:@"nativepip "]) {
  NSArray* parts=[line componentsSeparatedByString:@" "];
  if(parts.count!=3) return;
  const TabId tabId=(TabId)[parts[1] longLongValue];
  const BOOL active=[parts[2] boolValue];
  WKWebView* page=[self webViewForTab:tabId];
  auto it=runtimes.find(tabId);
  if(!active && it!=runtimes.end() && it->second.host.superview==self.content) {
   // Reproduce WebKit returning the formerly floated surface atop the page.
   [self.content addSubview:it->second.host positioned:NSWindowAbove relativeTo:nil];
   it->second.host.hidden=NO;
  }
  SEL selector=NSSelectorFromString(@"_webView:hasVideoInPictureInPictureDidChange:");
  if([page.navigationDelegate respondsToSelector:selector])
   ((void (*)(id,SEL,WKWebView*,BOOL))objc_msgSend)(page.navigationDelegate,selector,page,active);
  return;
 }
 if([line hasPrefix:@"inactivepipframe "]) {
  const TabId tabId=(TabId)[line substringFromIndex:17].longLongValue;
  WKWebView* page=[self webViewForTab:tabId];
  SlateVerifyMessage* message=[SlateVerifyMessage new];
  message.name=@"slateMedia";
  message.body=@{@"frame_id":@"adfixture",@"pip":@NO,@"video":@NO};
  [(id<WKScriptMessageHandler>)page.navigationDelegate userContentController:page.configuration.userContentController didReceiveScriptMessage:(WKScriptMessage*)message];
  message.name=@"slatePiP";
  message.body=@{@"frame_id":@"adfixture",@"active":@NO};
  [(id<WKScriptMessageHandler>)page.navigationDelegate userContentController:page.configuration.userContentController didReceiveScriptMessage:(WKScriptMessage*)message];
  return;
 }
 if([line hasPrefix:@"checkpiptab "]) {
  NSArray* parts=[line componentsSeparatedByString:@" "];
  if(parts.count!=3) return;
  auto it=runtimes.find((TabId)[parts[1] longLongValue]);
  const BOOL active=it!=runtimes.end() && it->second.pip_active;
  fprintf(stderr,"SLATE_PIP_FRAME_CHECK active=%d failures=%d\n",(int)active,active!=[parts[2] boolValue]);
  return;
 }
 // Report a playing surface on a fixture without a video. WebKit declines
 // PiP, exercising the real entry timeout without depending on OS gestures.
 if([line isEqual:@"simulatepipdecline"]) {
  auto it=runtimes.find(model.selected());
  if(it!=runtimes.end()) {
   it->second.video_playing=true;
   it->second.user_started_media=true;
  }
  return;
 }
 if([line hasPrefix:@"checkpendingpip "]) {
  const TabId id=(TabId)[line substringFromIndex:16].longLongValue;
  auto it=runtimes.find(id);
  const BOOL pending=it!=runtimes.end() && it->second.auto_pip_origin==1 && !it->second.pip_active;
  fprintf(stderr,"SLATE_PENDING_PIP_CHECK tab=%llu pending=%d failures=%d\n",(unsigned long long)id,(int)pending,!pending);
  return;
 }
 if([line hasPrefix:@"checkhidden "]) {
  const TabId id=(TabId)[line substringFromIndex:12].longLongValue;
  auto it=runtimes.find(id);
  const BOOL hidden=it!=runtimes.end() && it->second.host.hidden;
  fprintf(stderr,"SLATE_HIDDEN_CHECK tab=%llu hidden=%d pip=%d pending_pip=%d failures=%d\n",
   (unsigned long long)id,(int)hidden,it!=runtimes.end() ? (int)it->second.pip_active : 0,
   it!=runtimes.end() ? it->second.auto_pip_origin : 0,!hidden);
  return;
 }
 if([line isEqual:@"checksplit"]) {
  const auto left=runtimes.find(workspace.left), right=runtimes.find(workspace.right);
 fprintf(stderr,"SLATE_VERIFY split=%d left=%llu right=%llu active=%llu ratio=%.3f left_frame=%s right_frame=%s left_hidden=%d right_hidden=%d overlay=%d\n",
   (int)workspace.split(),(unsigned long long)workspace.left,(unsigned long long)workspace.right,
   (unsigned long long)model.selected(),workspace.ratio,
   left!=runtimes.end() && left->second.host ? NSStringFromRect(left->second.host.frame).UTF8String : "none",
   right!=runtimes.end() && right->second.host ? NSStringFromRect(right->second.host.frame).UTF8String : "none",
   left!=runtimes.end() && left->second.host ? (int)left->second.host.hidden : -1,
   right!=runtimes.end() && right->second.host ? (int)right->second.host.hidden : -1,
   (int)!self.splitOverlay.hidden);
  fprintf(stderr,"SLATE_VERIFY content placeholder_hidden=%d home_hidden=%d selected_live=%d content_children=%lu\n",
   (int)self.placeholder.hidden,(int)self.homeView.hidden,(int)model.live(model.selected()),(unsigned long)self.content.subviews.count);
  for(TabId pane : {workspace.left,workspace.right}) {
   auto it=runtimes.find(pane);
   if(it==runtimes.end()) continue;
   NSView* host=it->second.host;
   NSView* page=host.subviews.firstObject;
   fprintf(stderr,"SLATE_VERIFY pane=%llu host=%p host_order=%lu page=%p page_class=%s page_hidden=%d page_frame=%s\n",
    (unsigned long long)pane,host,(unsigned long)(host ? [self.content.subviews indexOfObject:host] : NSNotFound),
    page,page ? NSStringFromClass(page.class).UTF8String : "none",page ? (int)page.hidden : -1,
    page ? NSStringFromRect(page.frame).UTF8String : "none");
  }
  return;
 }
 if([line hasPrefix:@"snapshotpane "]) {
  NSArray<NSString*>* pieces=[line componentsSeparatedByString:@" "];
  if(pieces.count<3) return;
  const TabId pane=[pieces[1] isEqualToString:@"left"] ? workspace.left : workspace.right;
  auto it=runtimes.find(pane);
  WKWebView* view=it!=runtimes.end() ? (WKWebView*)it->second.host.subviews.firstObject : nil;
  if(![view isKindOfClass:WKWebView.class]) return;
  NSString* path=pieces[2];
  [view takeSnapshotWithConfiguration:nil completionHandler:^(NSImage* image,NSError* error) {
   NSData* tiff=image.TIFFRepresentation;
   NSBitmapImageRep* rep=tiff ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
   NSData* png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
   if(png) [png writeToFile:path atomically:YES];
   fprintf(stderr,"SLATE_VERIFY snapshotpane side=%s bytes=%lu error=%s\n",pieces[1].UTF8String,(unsigned long)png.length,error ? error.localizedDescription.UTF8String : "none");
  }];
  return;
 }
 if([line hasPrefix:@"splitpreview "]) {
  const BOOL right=[line containsString:@"right"];
  const auto pieces=[line componentsSeparatedByString:@" "];
  TabId identifier=pieces.count>2 ? (TabId)[pieces[2] longLongValue] : model.selected();
  [self syncPageGeometry];
  NSRect target=right ? self.splitRightTarget.frame : self.splitLeftTarget.frame;
  NSPoint windowPoint=[self.content convertPoint:NSMakePoint(NSMidX(target),NSMidY(target)) toView:nil];
  NSPoint screenPoint=[self.window convertPointToScreen:windowPoint];
  [self updateSplitDragAtScreenPoint:screenPoint tab:identifier base:model.selected()];
  return;
 }
 if([line hasPrefix:@"tabstyle "]) {
  NSString* arg = [[line substringFromIndex:9] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  self.tabStyle = ([arg isEqualToString:@"regular"] || [arg isEqualToString:@"1"]) ? 1 : 0;
  [self applyTabStyle];
  [self persistUiPrefs];
  return;
 }
 if([line isEqual:@"windowsize"]) {
  fprintf(stderr, "SLATE_VERIFY window_width=%.1f window_height=%.1f tab_pills_width=%.1f\n",
          self.window.frame.size.width, self.window.frame.size.height, self.tabStripWidth.constant);
  return;
 }
 if([line hasPrefix:@"setwindowsize "]) {
  NSArray* parts = [[line substringFromIndex:14] componentsSeparatedByString:@" "];
  if(parts.count == 2) {
   CGFloat w = [parts[0] doubleValue];
   CGFloat h = [parts[1] doubleValue];
   NSRect f = self.window.frame;
   f.size.width = w;
   f.size.height = h;
   [self.window setFrame:f display:YES animate:NO];
   [self windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:self.window]];
   fprintf(stderr, "SLATE_VERIFY setwindowsize target_w=%.1f target_h=%.1f actual_w=%.1f actual_h=%.1f tab_pills_width=%.1f\n",
           w, h, self.window.frame.size.width, self.window.frame.size.height, self.tabStripWidth.constant);
  }
  return;
 }
 if([line hasPrefix:@"tearoff "]) {
  TabId tid = (TabId)[line substringFromIndex:8].longLongValue;
  [self tearOffTab:tid atScreenPoint:NSMakePoint(200, 200)];
  return;
 }
 if([line hasPrefix:@"reattach "]) {
  TabId tid=(TabId)[line substringFromIndex:9].longLongValue;
  [self reattachTab:tid atScreenPoint:NSZeroPoint];
  return;
 }
 if([line hasPrefix:@"reattachdrop "]) {
  const TabId tid=(TabId)[line substringFromIndex:13].longLongValue;
  NSView* target=self.verticalTabs ? self.sidebar : self.tabCluster;
  const NSRect frame=[self.window convertRectToScreen:[target convertRect:target.bounds toView:nil]];
  const BOOL returned=[self reattachTab:tid atScreenPoint:NSMakePoint(NSMidX(frame),NSMidY(frame))];
  fprintf(stderr,"SLATE_VERIFY reattachdrop tab=%llu returned=%d\n",(unsigned long long)tid,(int)returned);
  return;
 }
 if([line hasPrefix:@"detachedgo "]) {
  NSArray<NSString*>* parts=[line componentsSeparatedByString:@" "];
  if(parts.count>=3) [self navigateDetachedTab:(TabId)parts[1].longLongValue toURL:std::string(parts[2].UTF8String ?: "")];
  return;
 }
 if([line isEqual:@"checkdetached"]) {
  fprintf(stderr,"SLATE_VERIFY detached_count=%lu pid=%d main_selected=%llu windows=%lu\n",
   (unsigned long)self.detachedTabs.count,getpid(),(unsigned long long)model.selected(),(unsigned long)NSApp.windows.count);
  for(NSNumber* key in self.detachedTabs) {
   SlateDetachedTabWindow* detached=self.detachedTabs[key];
   auto it=runtimes.find(key.unsignedLongLongValue);
   const auto* tab=model.find(key.unsignedLongLongValue);
   fprintf(stderr,"SLATE_VERIFY detached_tab=%llu host_window=%d live=%d host=%p url=%s\n",
    key.unsignedLongLongValue,
    it!=runtimes.end() && it->second.host.window==detached.window,
    it!=runtimes.end() && it->second.engine!=nullptr,
    it!=runtimes.end() ? it->second.host : nil,
    tab ? tab->url.c_str() : "missing");
  }
  return;
 }
 if([line hasPrefix:@"checktab "]) {
  const TabId identifier=(TabId)[line substringFromIndex:9].longLongValue;
  auto it=runtimes.find(identifier);
  fprintf(stderr,"SLATE_VERIFY tab=%llu host_main=%d live=%d host=%p\n",
   (unsigned long long)identifier,it!=runtimes.end() && it->second.host.window==self.window,
   it!=runtimes.end() && it->second.engine!=nullptr,it!=runtimes.end() ? it->second.host : nil);
  return;
 }
 if([line isEqual:@"reload"]) { [self reload:nil]; return; }
 if([line isEqual:@"pin"]) { [self togglePin:nil]; return; }
 if([line isEqual:@"quit"]) { exit(0); }
 if([line isEqual:@"shieldsoff"]) {
  if(shields) { shields->set_mode(slate::ShieldMode::Off); fprintf(stderr,"SLATE_SHIELDS mode=off\n"); [self updateShieldsChrome]; }
  slate::WebKitShields::Shared().SetEnabled(false);
  return;
 }
 if([line isEqual:@"shieldson"]) {
  if(shields) { shields->set_mode(slate::ShieldMode::Standard); fprintf(stderr,"SLATE_SHIELDS mode=standard\n"); [self updateShieldsChrome]; }
  slate::WebKitShields::Shared().SetEnabled(true);
  return;
 }
 if([line isEqual:@"adblockdiag"]) {
  const auto host=[self currentPageHost];
  fprintf(stderr,"SLATE_ADBLOCK global=%d host=%s site_enabled=%d native_ready=%d native_rules=%zu allowed_sites=%zu\n",
   (int)slate::WebKitShields::Shared().IsEnabled(),host.c_str(),
   (int)slate::WebKitShields::Shared().IsSiteEnabled(host),
   (int)slate::WebKitShields::Shared().HasCompiledRules(),
   slate::WebKitShields::Shared().CompiledRuleCount(),
   slate::WebKitShields::Shared().DisabledSites().size());
  return;
 }
 if([line isEqual:@"mediadiag"]) {
  auto it=runtimes.find(model.selected());
  if(it!=runtimes.end()) fprintf(stderr,
   "SLATE_MEDIA playing=%d audible=%d user_started=%d primary_frame=%s pip=%d pip_origin=%d suppressed=%d\n",
   (int)it->second.video_playing,(int)it->second.audible,(int)it->second.user_started_media,
   it->second.primary_media_frame.c_str(),(int)it->second.pip_active,
   it->second.auto_pip_origin,(int)it->second.suppress_auto_pip);
  return;
 }
 if([line isEqual:@"pip"]) {
  [self toggleFloatingVideo];
  return;
 }
 if([line isEqual:@"checkpip"]) {
  auto it=runtimes.find(model.selected());
  WKWebView* wv = [self webViewForTab:model.selected()];
  BOOL nativePip = NO;
  BOOL canPip = NO;
  if(wv) {
   SEL isPipSel = NSSelectorFromString(@"_isPictureInPictureActive");
   SEL canPipSel = NSSelectorFromString(@"_canTogglePictureInPicture");
   if([wv respondsToSelector:isPipSel]) {
    nativePip = ((BOOL (*)(id, SEL))objc_msgSend)(wv, isPipSel);
   }
   if([wv respondsToSelector:canPipSel]) {
    canPip = ((BOOL (*)(id, SEL))objc_msgSend)(wv, canPipSel);
   }
  }
  fprintf(stderr, "SLATE_VERIFY checkpip pip_active=%d auto_pip_origin=%d native_pip=%d can_pip=%d float_showing=%d\n",
          (it!=runtimes.end()) ? (int)it->second.pip_active : -1,
          (it!=runtimes.end()) ? (int)it->second.auto_pip_origin : -1,
          (int)nativePip, (int)canPip, (int)self.floatWindow.showing);
  return;
 }
 if([line isEqual:@"playmuted"]) {
  auto it=runtimes.find(model.selected());
  if(it!=runtimes.end() && it->second.engine)
   it->second.engine->execute_script("const v=document.querySelector('video, audio'); if(v){v.muted=true; v.play();}");
  return;
 }
 if([line hasPrefix:@"go "]) {
  self.address.stringValue=[[line substringFromIndex:3] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  [self navigate:nil];
  return;
 }
 if([line hasPrefix:@"select "]) {
  [self activateTab:(TabId)[line substringFromIndex:7].longLongValue];
  return;
 }
 if([line hasPrefix:@"sleep "]) {
  self.verifyDelay=MAX(0.25,[line substringFromIndex:6].doubleValue);
  return;
 }
 if([line hasPrefix:@"sidebarwidth "]) {
  CGFloat w=[line substringFromIndex:13].doubleValue;
  [self setSidebarWidthLive:w];
  [self persistSidebarWidth];
  fprintf(stderr,"SLATE_VERIFY sidebarwidth=%.1f\n",self.sidebarUserWidth);
  return;
 }
 if([line hasPrefix:@"snap "]) {
  NSString* path=[[line substringFromIndex:5] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSBitmapImageRep* rep=[self.window.contentView bitmapImageRepForCachingDisplayInRect:self.window.contentView.bounds];
  [self.window.contentView cacheDisplayInRect:self.window.contentView.bounds toBitmapImageRep:rep];
  NSButton* closeBtn=[self.window standardWindowButton:NSWindowCloseButton];
  if(closeBtn && closeBtn.superview && closeBtn.superview != self.trafficCluster && !closeBtn.isHidden && closeBtn.alphaValue > 0) {
   NSView* tbView = closeBtn.superview;
   NSRect trafficRect = NSMakeRect(0, 0, 80, NSHeight(tbView.bounds));
   NSRect trafficInWin = [tbView convertRect:trafficRect toView:nil];
   NSRect trafficInContent = [self.window.contentView convertRect:trafficInWin fromView:nil];
   NSBitmapImageRep* tbRep = [tbView bitmapImageRepForCachingDisplayInRect:trafficRect];
   [tbView cacheDisplayInRect:trafficRect toBitmapImageRep:tbRep];
   NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
   [NSGraphicsContext saveGraphicsState];
   [NSGraphicsContext setCurrentContext:ctx];
   [tbRep drawInRect:trafficInContent];
   [NSGraphicsContext restoreGraphicsState];
  }
  if(self.suggestPanel.isVisible && self.suggestPanel.contentView) {
   NSRect panelScreen = self.suggestPanel.frame;
   NSRect panelInWin = [self.window convertRectFromScreen:panelScreen];
   NSRect panelInContent = [self.window.contentView convertRect:panelInWin fromView:nil];
   NSBitmapImageRep* panelRep = [self.suggestPanel.contentView bitmapImageRepForCachingDisplayInRect:self.suggestPanel.contentView.bounds];
   [self.suggestPanel.contentView cacheDisplayInRect:self.suggestPanel.contentView.bounds toBitmapImageRep:panelRep];
   NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
   [NSGraphicsContext saveGraphicsState];
   [NSGraphicsContext setCurrentContext:ctx];
   NSBezierPath* clip = [NSBezierPath bezierPathWithRoundedRect:panelInContent xRadius:14 yRadius:14];
   [clip addClip];
   [panelRep drawInRect:panelInContent];
   [NSGraphicsContext restoreGraphicsState];
  }
  if([SlateDownloadsPanel sharedPanel].isVisible && [SlateDownloadsPanel sharedPanel].contentView) {
   NSRect panelScreen = [SlateDownloadsPanel sharedPanel].frame;
   NSRect panelInWin = [self.window convertRectFromScreen:panelScreen];
   NSRect panelInContent = [self.window.contentView convertRect:panelInWin fromView:nil];
   NSBitmapImageRep* panelRep = [[SlateDownloadsPanel sharedPanel].contentView bitmapImageRepForCachingDisplayInRect:[SlateDownloadsPanel sharedPanel].contentView.bounds];
   [[SlateDownloadsPanel sharedPanel].contentView cacheDisplayInRect:[SlateDownloadsPanel sharedPanel].contentView.bounds toBitmapImageRep:panelRep];
   NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
   [NSGraphicsContext saveGraphicsState];
   [NSGraphicsContext setCurrentContext:ctx];
   NSBezierPath* clip = [NSBezierPath bezierPathWithRoundedRect:panelInContent xRadius:12 yRadius:12];
   [clip addClip];
   [panelRep drawInRect:panelInContent];
   [NSGraphicsContext restoreGraphicsState];
  }
  if([SlateSiteCardPanel isShown] && [SlateSiteCardPanel sharedPanel].contentView) {
   NSRect panelScreen = [SlateSiteCardPanel sharedPanel].frame;
   NSRect panelInWin = [self.window convertRectFromScreen:panelScreen];
   NSRect panelInContent = [self.window.contentView convertRect:panelInWin fromView:nil];
   NSBitmapImageRep* panelRep = [[SlateSiteCardPanel sharedPanel].contentView bitmapImageRepForCachingDisplayInRect:[SlateSiteCardPanel sharedPanel].contentView.bounds];
   [[SlateSiteCardPanel sharedPanel].contentView cacheDisplayInRect:[SlateSiteCardPanel sharedPanel].contentView.bounds toBitmapImageRep:panelRep];
   NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
   [NSGraphicsContext saveGraphicsState];
   [NSGraphicsContext setCurrentContext:ctx];
   NSBezierPath* clip = [NSBezierPath bezierPathWithRoundedRect:panelInContent xRadius:12 yRadius:12];
   [clip addClip];
   [panelRep drawInRect:panelInContent];
   [NSGraphicsContext restoreGraphicsState];
  }
  if([SlateBookmarksDropdown isShown] && [SlateBookmarksDropdown sharedDropdown].contentView) {
   NSRect panelScreen = [SlateBookmarksDropdown sharedDropdown].frame;
   NSRect panelInWin = [self.window convertRectFromScreen:panelScreen];
   NSRect panelInContent = [self.window.contentView convertRect:panelInWin fromView:nil];
   NSBitmapImageRep* panelRep = [[SlateBookmarksDropdown sharedDropdown].contentView bitmapImageRepForCachingDisplayInRect:[SlateBookmarksDropdown sharedDropdown].contentView.bounds];
   [[SlateBookmarksDropdown sharedDropdown].contentView cacheDisplayInRect:[SlateBookmarksDropdown sharedDropdown].contentView.bounds toBitmapImageRep:panelRep];
   NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
   [NSGraphicsContext saveGraphicsState];
   [NSGraphicsContext setCurrentContext:ctx];
   NSBezierPath* clip = [NSBezierPath bezierPathWithRoundedRect:panelInContent xRadius:14 yRadius:14];
   [clip addClip];
   [panelRep drawInRect:panelInContent];
   [NSGraphicsContext restoreGraphicsState];
  }
  if([SlateBookmarksPanel isShown] && [SlateBookmarksPanel sharedPanel].contentView) {
   NSRect panelScreen = [SlateBookmarksPanel sharedPanel].frame;
   NSRect panelInWin = [self.window convertRectFromScreen:panelScreen];
   NSRect panelInContent = [self.window.contentView convertRect:panelInWin fromView:nil];
   NSBitmapImageRep* panelRep = [[SlateBookmarksPanel sharedPanel].contentView bitmapImageRepForCachingDisplayInRect:[SlateBookmarksPanel sharedPanel].contentView.bounds];
   [[SlateBookmarksPanel sharedPanel].contentView cacheDisplayInRect:[SlateBookmarksPanel sharedPanel].contentView.bounds toBitmapImageRep:panelRep];
   NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
   [NSGraphicsContext saveGraphicsState];
   [NSGraphicsContext setCurrentContext:ctx];
   NSBezierPath* clip = [NSBezierPath bezierPathWithRoundedRect:panelInContent xRadius:14 yRadius:14];
   [clip addClip];
   [panelRep drawInRect:panelInContent];
   [NSGraphicsContext restoreGraphicsState];
  }
  if(self.suggestPanel.isVisible && self.suggestPanel.contentView) {
   NSRect panelScreen = self.suggestPanel.frame;
   NSRect panelInWin = [self.window convertRectFromScreen:panelScreen];
   NSRect panelInContent = [self.window.contentView convertRect:panelInWin fromView:nil];
   NSBitmapImageRep* panelRep = [self.suggestPanel.contentView bitmapImageRepForCachingDisplayInRect:self.suggestPanel.contentView.bounds];
   [self.suggestPanel.contentView cacheDisplayInRect:self.suggestPanel.contentView.bounds toBitmapImageRep:panelRep];
   NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
   [NSGraphicsContext saveGraphicsState];
   [NSGraphicsContext setCurrentContext:ctx];
   NSBezierPath* clip = [NSBezierPath bezierPathWithRoundedRect:panelInContent xRadius:14 yRadius:14];
   [clip addClip];
   [panelRep drawInRect:panelInContent];
   [NSGraphicsContext restoreGraphicsState];
  }
  NSData* png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  [png writeToFile:path atomically:YES];
  fprintf(stderr,"SLATE_VERIFY snap saved to %s bytes=%lu\n",path.UTF8String,(unsigned long)png.length);
  return;
 }
 if([line hasPrefix:@"searchdownloads "] || [line isEqual:@"searchdownloads"]) {
  SlateDownloadsPanel* panel=SlateDownloadsPanel.sharedPanel;
  NSSearchField* search=[panel valueForKey:@"_search"];
  search.stringValue=line.length>16 ? [line substringFromIndex:16] : @""; [panel refreshList];
  NSTableView* table=[panel valueForKey:@"_table"];
  fprintf(stderr,"SLATE_DOWNLOAD_SEARCH rows=%ld\n",(long)table.numberOfRows);
  return;
 }
 if([line hasPrefix:@"filterdownloads "]) {
  SlateDownloadsPanel* panel=SlateDownloadsPanel.sharedPanel;
  NSSegmentedControl* filter=[panel valueForKey:@"_filter"];
  filter.selectedSegment=MAX(0,MIN(2,[line substringFromIndex:16].integerValue));
  [panel refreshList]; NSTableView* table=[panel valueForKey:@"_table"];
  fprintf(stderr,"SLATE_DOWNLOAD_FILTER rows=%ld\n",(long)table.numberOfRows);
  return;
 }
 if([line isEqual:@"checkdownloads"]) {
  for(SlateDownloadItem* item in SlateDownloadManager.sharedManager.items)
   fprintf(stderr,"SLATE_DOWNLOAD_CHECK state=%ld private=%d bytes=%lld available=%d resume=%d file=%s\n",(long)item.state,item.privateDownload,item.receivedBytes,item.fileAvailable,item.canResume,item.filename.UTF8String);
  return;
 }
 if([line hasPrefix:@"pausedownload "] || [line hasPrefix:@"resumedownload "] || [line hasPrefix:@"canceldownload "]) {
  NSArray* parts=[line componentsSeparatedByString:@" "]; NSInteger index=[parts.lastObject integerValue];
  NSArray* items=SlateDownloadManager.sharedManager.items;
  if(index>=0 && index<(NSInteger)items.count) {
   SlateDownloadItem* item=items[index];
   if([parts.firstObject isEqual:@"pausedownload"]) [item pause];
   else if([parts.firstObject isEqual:@"resumedownload"]) [item resume];
   else [item cancel];
  }
  return;
 }
 if([line hasPrefix:@"snapdownloads "]) {
  SlateDownloadsPanel* panel=SlateDownloadsPanel.sharedPanel;
  NSView* view=panel.contentView;
  NSBitmapImageRep* bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
  [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[line substringFromIndex:14] atomically:YES];
  return;
 }
 if([line isEqual:@"downloads"]) { [self toggleDownloads:nil]; return; }
 if([line hasPrefix:@"download "]) {
  NSString* u=[[line substringFromIndex:9] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  [[SlateDownloadManager sharedManager] startDownloadFromURL:[NSURL URLWithString:u] suggestedFilename:nil];
  return;
 }
 if([line isEqual:@"customtheme"]) {
  [self chooseCustomAccent:nil];
  fprintf(stderr,"SLATE_VERIFY customtheme shown=%d\n",[SlateThemePanel sharedPanel].isVisible?1:0);
  return;
 }
 if([line hasPrefix:@"granite "]) {
  self.graniteIntensity=[line substringFromIndex:8].doubleValue;
  [self persistUiPrefs];
  [self applyPlateChrome];
  fprintf(stderr,"SLATE_VERIFY granite intensity=%.2f\n",self.graniteIntensity);
  return;
 }
 if([line hasPrefix:@"thememode "]) {
  self.themeMode=[line substringFromIndex:10].intValue;
  [self persistUiPrefs];
  [self applyPlateChrome];
  fprintf(stderr,"SLATE_VERIFY themeMode=%d\n",self.themeMode);
  return;
 }
 if([line hasPrefix:@"tabstyle "]) {
  NSString* style = [[line substringFromIndex:9] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  self.tabStyle = [style isEqualToString:@"regular"] ? 1 : 0;
  [self applyTabStyle];
  [self persistUiPrefs];
  fprintf(stderr,"SLATE_VERIFY tabStyle=%d\n",self.tabStyle);
  return;
 }
 if([line hasPrefix:@"setaccent "]) {
  NSArray* parts = [[line substringFromIndex:10] componentsSeparatedByString:@" "];
  if(parts.count >= 1) {
   self.accentId = parts[0];
   self.accentHex = (parts.count >= 2) ? parts[1] : @"";
   self.accentHex2 = @"";
   [self applyPlateChrome];
   [self persistUiPrefs];
   fprintf(stderr,"SLATE_VERIFY setaccent id=%s hex=%s\n", self.accentId.UTF8String, self.accentHex.UTF8String);
  }
  return;
 }
 if([line hasPrefix:@"bubblecolor "]) {
  NSArray* parts=[[line substringFromIndex:12] componentsSeparatedByString:@" "];
  if(parts.count==2) {
   int idx=[parts[0] intValue];
   NSString* hex=parts[1];
   [[SlateThemePanel sharedPanel] showForSlateDelegate:self];
   [SlateThemePanel sharedPanel].card.canvas.selectedBubbleIndex=idx;
   [[SlateThemePanel sharedPanel].card.canvas setSelectedBubbleHex:hex];
   self.accentId=@"custom";
   self.accentHex=[[SlateThemePanel sharedPanel].card.canvas primaryHex];
   self.accentHex2=[[SlateThemePanel sharedPanel].card.canvas secondaryHex];
   [self applyPlateChrome];
   [self persistUiPrefs];
   fprintf(stderr,"SLATE_VERIFY bubblecolor idx=%d hex=%s accentHex=%s accentHex2=%s\n",
           idx, hex.UTF8String, self.accentHex.UTF8String, self.accentHex2.UTF8String);
  }
  return;
 }
 if([line isEqual:@"nexttab"]) { [self selectNextTab:nil]; return; }
 if([line isEqual:@"prevtab"]) { [self selectPreviousTab:nil]; return; }
 if([line isEqual:@"closetab"]) { [self closeTab:nil]; return; }
 if([line isEqual:@"closealltabs"]) { [self closeAllTabs:nil]; return; }
 if([line isEqual:@"reopenclosedtab"]) { [self reopenClosedTab:nil]; return; }
 if([line isEqual:@"copyurl"]) { [self copyCurrentUrl:nil]; return; }
 if([line isEqual:@"copymarkdown"]) { [self copyCurrentUrlAsMarkdown:nil]; return; }
 if([line isEqual:@"nextspace"]) { [self switchNextSpace]; return; }
 if([line isEqual:@"prevspace"]) { [self switchPreviousSpace]; return; }
 if([line hasPrefix:@"space "]) {
  NSInteger idx = [line substringFromIndex:6].integerValue;
  [self switchSpaceAtIndex:idx];
  return;
 }
 if([line hasPrefix:@"newspace "]) {
  NSString* name = [[line substringFromIndex:9] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  [self.spacesManager addSpaceNamed:name icon:nil sharesSignIns:NO];
  [self.sidebarFoot updateDoors];
  [self rebuildSpacesMenu];
  [self updateSpaceBadge];
  fprintf(stderr, "SLATE_VERIFY newspace named=%s total=%lu\n", name.UTF8String, (unsigned long)self.spacesManager.spaces.count);
  return;
 }
 if([line isEqual:@"checkspace"]) {
  SlateSpace* cur = self.spacesManager.currentSpace;
  fprintf(stderr, "SLATE_VERIFY space id=%s name=%s icon=%s shares=%d total=%lu parked=%lu\n",
          cur.identifier.UTF8String, cur.name.UTF8String, cur.symbol.UTF8String,
          cur.sharesSignIns ? 1 : 0, (unsigned long)self.spacesManager.spaces.count,
          (unsigned long)self.spacesManager.parkedTabs.count);
  return;
 }
 if([line hasPrefix:@"checkwindowcontrols "]) {
  const BOOL expectedFullScreen=[line substringFromIndex:20].intValue!=0;
  const BOOL fullScreen=(self.window.styleMask & NSWindowStyleMaskFullScreen)!=0;
  [self layoutTrafficLights];
  [self.window.contentView layoutSubtreeIfNeeded];
  NSView* root=self.window.contentView;
  int failures=fullScreen!=expectedFullScreen;
  if(fullScreen) {
   failures+=self.trafficCluster.hiddenOrHasHiddenAncestor || self.fullScreenTrafficButtons.count!=3;
   NSRect controls=[self.trafficCluster convertRect:self.trafficCluster.bounds toView:root];
   NSRect nav=[self.navCluster convertRect:self.navCluster.bounds toView:root];
   NSRect page=[self.content convertRect:self.content.bounds toView:root];
   failures+=!NSContainsRect(root.bounds,controls) || NSIntersectsRect(controls,nav) || NSIntersectsRect(controls,page);
   for(NSButton* button in self.fullScreenTrafficButtons) {
    NSPoint center=[button convertPoint:NSMakePoint(NSMidX(button.bounds),NSMidY(button.bounds)) toView:root.superview];
    NSView* hit=[root hitTest:center];
    failures+=button.hiddenOrHasHiddenAncestor || button.window!=self.window ||
     !(hit==button || [hit isDescendantOf:button]);
    if(button.action==@selector(performMiniaturize:)) failures+=button.enabled;
    else failures+=!button.enabled || button.target!=self.window;
   }
  } else {
   failures+=!self.trafficCluster.hidden;
   for(NSWindowButton kind : {NSWindowCloseButton,NSWindowMiniaturizeButton,NSWindowZoomButton}) {
    NSButton* button=[self.window standardWindowButton:kind];
    failures+=!button || button.window!=self.window || button.hiddenOrHasHiddenAncestor || button.alphaValue<=0;
   }
  }
  fprintf(stderr,"SLATE_WINDOW_CONTROLS fullscreen=%d vertical=%d collapsed=%d failures=%d\n",
   (int)fullScreen,(int)self.verticalTabs,(int)self.tabsCollapsed,failures);
  return;
 }
 if([line isEqual:@"exitfullscreenbutton"]) {
  for(NSButton* button in self.fullScreenTrafficButtons)
   if(button.action==@selector(toggleFullScreen:) && !self.trafficCluster.hidden) [button performClick:nil];
  return;
 }
 if([line isEqual:@"checktraffic"]) {
  NSButton* close = [self.window standardWindowButton:NSWindowCloseButton];
  NSRect closeInWin = close && close.superview ? [close.superview convertRect:close.frame toView:nil] : NSZeroRect;
  CGFloat distFromTop = close ? (NSHeight(self.window.frame) - NSMaxY(closeInWin)) : -1.0;
  CGFloat centerYFromTop = close ? (NSHeight(self.window.frame) - NSMidY(closeInWin)) : -1.0;
  fprintf(stderr, "SLATE_VERIFY checktraffic mode=%ld closeX=%.1f closeY=%.1f winY=%.1f distFromTop=%.1f centerYFromTop=%.1f\n",
          (long)[self trafficLayoutMode], close ? close.frame.origin.x : -1.0, close ? close.frame.origin.y : -1.0,
          closeInWin.origin.y, distFromTop, centerYFromTop);
  return;
 }
 if([line isEqual:@"newincognitotab"]) {
  [self newIncognitoTab:nil];
  const auto* tab = model.find(model.selected());
  fprintf(stderr,"SLATE_VERIFY incognito tab=%lld is_incognito=%d badge_visible=%d\n",
          model.selected(), tab ? (tab->incognito ? 1 : 0) : 0, self.stealthBadge.hidden ? 0 : 1);
  return;
 }
 if([line isEqual:@"checktablist"]) {
  NSScrollView* scroll = self.tabList.enclosingScrollView;
  NSTableColumn* col = self.tabList.tableColumns.firstObject;
  fprintf(stderr, "SLATE_TABLIST sidebar=%s hidden=%d scroll=%s hidden=%d tabList=%s hidden=%d rows=%ld colW=%.1f minW=%.1f maxW=%.1f subviews=%lu\n",
          NSStringFromRect(self.sidebar.frame).UTF8String, self.sidebar.isHidden,
          scroll ? NSStringFromRect(scroll.frame).UTF8String : "none", scroll ? scroll.isHidden : -1,
          NSStringFromRect(self.tabList.frame).UTF8String, self.tabList.isHidden,
          (long)self.tabList.numberOfRows,
          col ? col.width : -1.0, col ? col.minWidth : -1.0, col ? col.maxWidth : -1.0,
          (unsigned long)self.tabList.subviews.count);
  for(NSInteger r = 0; r < self.tabList.numberOfRows; ++r) {
   NSTableRowView* rowView = [self.tabList rowViewAtRow:r makeIfNecessary:NO];
   NSView* cellView = [self.tabList viewAtColumn:0 row:r makeIfNecessary:NO];
   fprintf(stderr, "  row %ld: rowView=%p frame=%s cellView=%p frame=%s subviews=%lu\n",
           (long)r, rowView, rowView ? NSStringFromRect(rowView.frame).UTF8String : "none",
           cellView, cellView ? NSStringFromRect(cellView.frame).UTF8String : "none",
           cellView ? (unsigned long)cellView.subviews.count : 0);
   if(cellView && cellView.subviews.count) {
    for(NSView* sv in cellView.subviews) {
     fprintf(stderr, "    subview=%s frame=%s hidden=%d\n", NSStringFromClass(sv.class).UTF8String, NSStringFromRect(sv.frame).UTF8String, sv.isHidden);
    }
   }
  }
  return;
 }
 if([line isEqual:@"fullscreen"]) {
  [self.window toggleFullScreen:nil];
  return;
 }
 if([line isEqual:@"checkgeom"]) {
  auto it=runtimes.find(model.selected());
  NSView* host = (it!=runtimes.end()) ? it->second.host : nil;
  NSView* wv = (host && host.subviews.count) ? host.subviews.firstObject : nil;
  BOOL isFs = (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
  NSView* root = self.window.contentView;
  NSScreen* sc = self.window.screen ?: NSScreen.mainScreen;
  NSRect plateInWin = self.chromePlate ? [self.chromePlate convertRect:self.chromePlate.bounds toView:nil] : NSZeroRect;
  CGFloat leadingInset = plateInWin.origin.x;
  CGFloat trailingInset = self.window.frame.size.width - (plateInWin.origin.x + plateInWin.size.width);
  fprintf(stderr, "SLATE_GEOM isFs=%d vTabs=%d collapsed=%d anim=%d\n"
                  "  win=%s root=%s\n"
                  "  titlebar=%s hConst=%.1f\n"
                  "  sidebar=%s wConst=%.1f\n"
                  "  plate=%s topConst=%.1f leadConst=%.1f\n"
                  "  toolbar=%s content=%s webview=%s\n",
          isFs ? 1 : 0, self.verticalTabs ? 1 : 0, self.tabsCollapsed ? 1 : 0, self.chromeAnimating ? 1 : 0,
          NSStringFromRect(self.window.frame).UTF8String,
          root ? NSStringFromRect(root.frame).UTF8String : "none",
          self.titlebar ? NSStringFromRect(self.titlebar.frame).UTF8String : "none", self.titlebarHeight.constant,
          self.sidebar ? NSStringFromRect(self.sidebar.frame).UTF8String : "none", self.sidebarWidth.constant,
          self.chromePlate ? NSStringFromRect(self.chromePlate.frame).UTF8String : "none", self.plateFromTop.constant, self.plateLeading.constant,
          self.toolbar ? NSStringFromRect(self.toolbar.frame).UTF8String : "none",
          self.content ? NSStringFromRect(self.content.frame).UTF8String : "none",
          wv ? NSStringFromRect(wv.frame).UTF8String : "none");
  if(self.homeView) {
   fprintf(stderr, "  homeView=%s hidden=%d homeBoard=%s brandGroup=%s card=%s\n",
           NSStringFromRect(self.homeView.frame).UTF8String, self.homeView.isHidden,
           self.homeBoard ? NSStringFromRect(self.homeBoard.frame).UTF8String : "none",
           (self.homeBoard && self.homeBoard.brandGroup) ? NSStringFromRect(self.homeBoard.brandGroup.frame).UTF8String : "none",
           (self.homeBoard && self.homeBoard.omniboxCard) ? NSStringFromRect(self.homeBoard.omniboxCard.frame).UTF8String : "none");
  }
  return;
 }
 if([line isEqual:@"settings"]) {
  [self showSettings:nil];
  fprintf(stderr,"SLATE_VERIFY settings shown=%d\n", [SlateSettingsPanel sharedPanel].isVisible?1:0);
  return;
 }
 if([line hasPrefix:@"settingspage "]) {
  NSString* page = [[line substringFromIndex:13] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  [[SlateSettingsPanel sharedPanel] showForSlateDelegate:self selectedPage:page];
  return;
 }
 if([line hasPrefix:@"snapsettings "]) {
  NSString* path=[[line substringFromIndex:13] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSWindow* win=[SlateSettingsPanel sharedPanel];
  if(win && win.contentView) {
   NSBitmapImageRep* rep=[win.contentView bitmapImageRepForCachingDisplayInRect:win.contentView.bounds];
   [win.contentView cacheDisplayInRect:win.contentView.bounds toBitmapImageRep:rep];
   NSData* pngData=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
   [pngData writeToFile:path atomically:YES];
   fprintf(stderr,"SLATE_VERIFY snapsettings saved to %s\n", path.UTF8String);
  }
  return;
 }
 if([line isEqual:@"checkvideo"]) {
  auto it=runtimes.find(model.selected());
  if(it!=runtimes.end() && it->second.engine) {
   it->second.engine->execute_script(R"JS(
    (function() {
      const v = document.querySelector('video');
      if (!v) return 'NO_VIDEO_ELEMENT';
      return 'src=' + (v.src || v.currentSrc || 'empty') +
             ' paused=' + v.paused +
             ' readyState=' + v.readyState +
             ' currentTime=' + v.currentTime +
             ' duration=' + v.duration +
             ' error=' + (v.error ? (v.error.message || v.error.code) : 'none');
    })();
   )JS");
  }
  return;
 }
 if([line isEqual:@"playvideo"]) {
  auto it=runtimes.find(model.selected());
  if(it!=runtimes.end() && it->second.engine) {
   it->second.engine->execute_script(R"JS(
    (function() {
      const v = document.querySelector('video');
      if (!v) return 'NO_VIDEO_ELEMENT';
      v.muted = true;
      v.play();
      return 'PLAYING: paused=' + v.paused;
    })();
   )JS");
  }
  return;
 }
 if([line hasPrefix:@"exec "]) {
  auto it=runtimes.find(model.selected());
  if(it!=runtimes.end() && it->second.engine) {
   it->second.engine->execute_script([line substringFromIndex:5].UTF8String);
  }
  return;
 }
 if([line isEqual:@"passwords"]) { [self showPasswordsPanel:nil]; return; }
 if([line isEqual:@"toggletabs"]) { [self toggleTabsReveal:nil]; return; }
 if([line isEqual:@"fps120 on"]) {
  if(!self.pages120Hz) [self togglePages120Hz:nil];
  return;
 }
 if([line isEqual:@"fps120 off"]) {
  if(self.pages120Hz) [self togglePages120Hz:nil];
  return;
 }
 if([line isEqual:@"checkfps"]) {
  fprintf(stderr,"SLATE_VERIFY checkfps fast=%d available=%d\n", self.pages120Hz?1:0, [SlateFrameRate is120HzAvailable]?1:0);
  return;
 }
 if([line isEqual:@"importdialog"]) { [self showImportBrowserData:nil]; return; }
 if([line isEqual:@"about"]) { [self showAboutSlate:nil]; return; }
 if([line isEqual:@"sitecard"]) { [self showSiteCard:nil]; return; }
 if([line isEqual:@"sitecard deeper"]) { [[SlateSiteCardPanel sharedPanel] showDeeperViewAnimated:NO]; return; }
 if([line isEqual:@"zoomin"]) { [self zoomIn:nil]; return; }
 if([line isEqual:@"zoomout"]) { [self zoomOut:nil]; return; }
 if([line isEqual:@"resetzoom"]) { [self resetZoom:nil]; return; }
 if([line isEqual:@"checksitecard"]) {
  fprintf(stderr,"SLATE_VERIFY sitecard isShown=%d\n", [SlateSiteCardPanel isShown]?1:0);
  return;
 }
 if([line isEqual:@"bookmarks"]) { [self showBookmarksPanel:nil]; return; }
 if([line isEqual:@"bookmarkdropdown"]) { [self toggleBookmarksDropdown:nil]; return; }
 if([line isEqual:@"checkbookmarks"]) {
  fprintf(stderr,"SLATE_VERIFY bookmarks count=%lu roots=%lu isShown=%d dropdownShown=%d\n",
          (unsigned long)[SlateBookmarks sharedStore].count,
          (unsigned long)[SlateBookmarks sharedStore].roots.count,
          [SlateBookmarksPanel isShown]?1:0,
          [SlateBookmarksDropdown isShown]?1:0);
  return;
 }
 if([line hasPrefix:@"typeaddress "]) {
  self.addressOpen=YES;
  [self layoutOmnibox];
  [self.window makeFirstResponder:self.address];
  self.addressDirty=YES;
  self.address.stringValue=[line substringFromIndex:12];
  NSText* fe=[self.window fieldEditor:YES forObject:self.address];
  if(fe) fe.string=self.address.stringValue;
  [self fetchSuggestions];
  return;
 }
 if([line hasPrefix:@"typehomesearch "]) {
  NSTextField* hf=[self homeSearchField];
  if(hf) {
   [self.window makeFirstResponder:hf];
   hf.stringValue=[line substringFromIndex:15];
   NSText* fe=[self.window fieldEditor:YES forObject:hf];
   if(fe) fe.string=hf.stringValue;
   [self showSuggestionsForCard:self.homeBoard.omniboxCard query:hf.stringValue];
  }
  return;
 }
 if([line isEqual:@"checksandbox"]) {
  NSString* home = NSHomeDirectory();
  NSString* realHome = NSUserName() ? [NSString stringWithFormat:@"/Users/%@", NSUserName()] : @"/Users";
  NSString* sshDir = [realHome stringByAppendingPathComponent:@".ssh"];
  BOOL sshReadable = [[NSFileManager defaultManager] isReadableFileAtPath:sshDir];
  NSString* escapeTestPath = [realHome stringByAppendingPathComponent:@"slate_unauthorized_escape.txt"];
  NSError* writeErr = nil;
  BOOL escapeWrite = [@"escape" writeToFile:escapeTestPath atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
  if(escapeWrite) {
   [[NSFileManager defaultManager] removeItemAtPath:escapeTestPath error:nil];
  }
  BOOL inContainer = [home containsString:@"Library/Containers/dev.slate.browser"];
  fprintf(stderr, "SLATE_SANDBOX_CHECK home=%s inContainer=%d sshReadable=%d escapeWrite=%d writeErr=%s\n",
          home.UTF8String, inContainer ? 1 : 0, sshReadable ? 1 : 0, escapeWrite ? 1 : 0,
          writeErr ? writeErr.localizedDescription.UTF8String : "none");
  return;
 }
 fprintf(stderr,"SLATE_VERIFY unknown=%s\n",line.UTF8String);
}
#endif
@end

static void InstallMenus(SlateDelegate* delegate) {
 NSMenu* menu = [[NSMenu alloc] init];

 // 1. Slate (App) Menu
 NSMenuItem* appItem = [[NSMenuItem alloc] init]; [menu addItem:appItem];
 NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"Slate"];
 NSMenuItem* aboutItem = [appMenu addItemWithTitle:@"About Slate" action:@selector(showAboutSlate:) keyEquivalent:@""];
 aboutItem.target = delegate;
 [appMenu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* prefsItem = [appMenu addItemWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
 prefsItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 prefsItem.target = delegate;
 [appMenu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* servicesItem = [appMenu addItemWithTitle:@"Services" action:nil keyEquivalent:@""];
 NSMenu* servicesMenu = [[NSMenu alloc] initWithTitle:@"Services"];
 servicesItem.submenu = servicesMenu;
 [NSApp setServicesMenu:servicesMenu];
 [appMenu addItem:[NSMenuItem separatorItem]];
 [appMenu addItemWithTitle:@"Hide Slate" action:@selector(hide:) keyEquivalent:@"h"];
 NSMenuItem* hideOthers = [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
 hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
 [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
 [appMenu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* extensions = [appMenu addItemWithTitle:@"Extensions…" action:@selector(showExtensions:) keyEquivalent:@""];
 extensions.target = delegate;
 NSMenuItem* passwordsItem = [appMenu addItemWithTitle:@"Saved in Slate…" action:@selector(showPasswordsPanel:) keyEquivalent:@"p"];
 passwordsItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
 passwordsItem.target = delegate;
 NSMenuItem* applePasswords=[appMenu addItemWithTitle:@"Open Apple Passwords…" action:@selector(openApplePasswords:) keyEquivalent:@""];
 applePasswords.target=delegate;
 [appMenu addItem:[NSMenuItem separatorItem]];
 [appMenu addItemWithTitle:@"Quit Slate" action:@selector(terminate:) keyEquivalent:@"q"];
 appItem.submenu = appMenu;

 // 2. File Menu
 NSMenuItem* fileItem = [[NSMenuItem alloc] init]; [menu addItem:fileItem];
 NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
 NSMenuItem* newTab = [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
 newTab.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 newTab.target = delegate;
 NSMenuItem* newIncognitoTab = [fileMenu addItemWithTitle:@"New Incognito Tab" action:@selector(newIncognitoTab:) keyEquivalent:@"P"];
 newIncognitoTab.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 newIncognitoTab.target = delegate;
 NSMenuItem* newTabInGroup = [fileMenu addItemWithTitle:@"New Tab in Group…" action:@selector(newTabGroup:) keyEquivalent:@"t"];
 newTabInGroup.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
 newTabInGroup.target = delegate;
 NSMenuItem* newWindow = [fileMenu addItemWithTitle:@"New Window" action:@selector(newWindow:) keyEquivalent:@"n"];
 newWindow.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 newWindow.target = delegate;
 NSMenuItem* newIncognito = [fileMenu addItemWithTitle:@"New Incognito Window" action:@selector(newIncognitoWindow:) keyEquivalent:@"N"];
 newIncognito.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 newIncognito.target = delegate;
 NSMenuItem* reopenClosed = [fileMenu addItemWithTitle:@"Reopen Closed Tab" action:@selector(reopenClosedTab:) keyEquivalent:@"T"];
 reopenClosed.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 reopenClosed.target = delegate;
 [fileMenu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* closeTab = [fileMenu addItemWithTitle:@"Close Tab" action:@selector(closeTab:) keyEquivalent:@"w"];
 closeTab.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 closeTab.target = delegate;
 NSMenuItem* closeWin = [fileMenu addItemWithTitle:@"Close Window" action:@selector(requestClose) keyEquivalent:@"W"];
 closeWin.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 closeWin.target = delegate;
 NSMenuItem* closeAllTabs = [fileMenu addItemWithTitle:@"Close All Tabs" action:@selector(closeAllTabs:) keyEquivalent:@"K"];
 closeAllTabs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 closeAllTabs.target = delegate;
 NSMenuItem* cleanUpTabs = [fileMenu addItemWithTitle:@"Clean Up Tabs" action:@selector(cleanUpTabs:) keyEquivalent:@"k"];
 cleanUpTabs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
 cleanUpTabs.target = delegate;
 [fileMenu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* importItem = [fileMenu addItemWithTitle:@"Import Browser Data…" action:@selector(showImportBrowserData:) keyEquivalent:@"i"];
 importItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 importItem.target = delegate;
 NSMenuItem* siteInfoItem = [fileMenu addItemWithTitle:@"Site Information…" action:@selector(showSiteCard:) keyEquivalent:@"i"];
 siteInfoItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 siteInfoItem.target = delegate;
 NSMenuItem* shareItem = [fileMenu addItemWithTitle:@"Share…" action:@selector(sharePage:) keyEquivalent:@""];
 shareItem.target = delegate;
 NSMenuItem* printItem = [fileMenu addItemWithTitle:@"Print…" action:@selector(printPage:) keyEquivalent:@"p"];
 printItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 printItem.target = delegate;
 fileItem.submenu = fileMenu;

 // 3. Edit Menu
 NSMenuItem* editItem = [[NSMenuItem alloc] init]; [menu addItem:editItem];
 NSMenu* edit = [[NSMenu alloc] initWithTitle:@"Edit"];
 [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
 NSMenuItem* redo = [edit addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
 redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 [edit addItem:[NSMenuItem separatorItem]];
 [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
 [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
 NSMenuItem* copyUrl = [edit addItemWithTitle:@"Copy URL" action:@selector(copyCurrentUrl:) keyEquivalent:@"C"];
 copyUrl.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 copyUrl.target = delegate;
 NSMenuItem* copyMd = [edit addItemWithTitle:@"Copy URL as Markdown" action:@selector(copyCurrentUrlAsMarkdown:) keyEquivalent:@"C"];
 copyMd.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift;
 copyMd.target = delegate;
 [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
 NSMenuItem* pasteMatch = [edit addItemWithTitle:@"Paste and Match Style" action:@selector(pasteAsPlainText:) keyEquivalent:@"V"];
 pasteMatch.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift;
 [edit addItemWithTitle:@"Delete" action:@selector(delete:) keyEquivalent:@""];
 [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
 [edit addItem:[NSMenuItem separatorItem]];
 NSMenuItem* autofillItem = [edit addItemWithTitle:@"Autofill Password" action:@selector(triggerAutofillAction:) keyEquivalent:@"L"];
 autofillItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 autofillItem.target = delegate;
 [edit addItem:[NSMenuItem separatorItem]];
 NSMenuItem* findItem = [edit addItemWithTitle:@"Find in Page…" action:@selector(findInPage:) keyEquivalent:@"f"];
 findItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 findItem.target = delegate;
 NSMenuItem* findNext = [edit addItemWithTitle:@"Find Next" action:@selector(findNext:) keyEquivalent:@"g"];
 findNext.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 findNext.target = delegate;
 NSMenuItem* findPrev = [edit addItemWithTitle:@"Find Previous" action:@selector(findPrevious:) keyEquivalent:@"G"];
 findPrev.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 findPrev.target = delegate;
 NSMenuItem* findUseSel = [edit addItemWithTitle:@"Use Selection for Find" action:@selector(useSelectionForFind:) keyEquivalent:@"e"];
 findUseSel.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 findUseSel.target = delegate;
 editItem.submenu = edit;

 // 4. Navigate Menu
 NSMenuItem* navItem = [[NSMenuItem alloc] init]; [menu addItem:navItem];
 NSMenu* nav = [[NSMenu alloc] initWithTitle:@"Navigate"];
 NSMenuItem* back = [nav addItemWithTitle:@"Back" action:@selector(goBack:) keyEquivalent:@"["];
 back.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 back.target = delegate;
 NSMenuItem* forward = [nav addItemWithTitle:@"Forward" action:@selector(goForward:) keyEquivalent:@"]"];
 forward.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 forward.target = delegate;
 NSMenuItem* reload = [nav addItemWithTitle:@"Reload" action:@selector(reload:) keyEquivalent:@"r"];
 reload.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 reload.target = delegate;
 NSMenuItem* hardReload = [nav addItemWithTitle:@"Hard Reload" action:@selector(hardReload:) keyEquivalent:@"R"];
 hardReload.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 hardReload.target = delegate;
 NSMenuItem* focus = [nav addItemWithTitle:@"Open Location…" action:@selector(focusAddress:) keyEquivalent:@"l"];
 focus.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 focus.target = delegate;
 [nav addItem:[NSMenuItem separatorItem]];
 NSMenuItem* nextTab = [nav addItemWithTitle:@"Next Tab" action:@selector(selectNextTab:) keyEquivalent:@"]"];
 nextTab.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 nextTab.target = delegate;
 NSMenuItem* nextTabCtrl = [nav addItemWithTitle:@"Next Tab (Ctrl-Tab)" action:@selector(selectNextTab:) keyEquivalent:@"\t"];
 nextTabCtrl.keyEquivalentModifierMask = NSEventModifierFlagControl;
 nextTabCtrl.target = delegate;
 nextTabCtrl.hidden = YES;
 NSMenuItem* prevTab = [nav addItemWithTitle:@"Previous Tab" action:@selector(selectPreviousTab:) keyEquivalent:@"["];
 prevTab.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 prevTab.target = delegate;
 NSMenuItem* prevTabCtrl = [nav addItemWithTitle:@"Previous Tab (Ctrl-Shift-Tab)" action:@selector(selectPreviousTab:) keyEquivalent:@"\t"];
 prevTabCtrl.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagShift;
 prevTabCtrl.target = delegate;
 prevTabCtrl.hidden = YES;
 [nav addItem:[NSMenuItem separatorItem]];
 // Cmd+1–8: jump to tab 1..8, Cmd+9: jump to last tab
 NSArray<NSString*>* digits = @[@"1",@"2",@"3",@"4",@"5",@"6",@"7",@"8",@"9"];
 for(NSInteger i=0; i<9; i++) {
  NSString* title = (i == 8) ? @"Switch to Last Tab" : [NSString stringWithFormat:@"Switch to Tab %ld", (long)(i+1)];
  NSMenuItem* tabShortcut = [nav addItemWithTitle:title action:@selector(selectTabAtIndex:) keyEquivalent:digits[i]];
  tabShortcut.keyEquivalentModifierMask = NSEventModifierFlagCommand;
  tabShortcut.target = delegate;
  tabShortcut.tag = i+1;
  tabShortcut.hidden = YES;
 }
 navItem.submenu = nav;

 // 5. View Menu
 NSMenuItem* viewItem = [[NSMenuItem alloc] init]; [menu addItem:viewItem];
 NSMenu* view = [[NSMenu alloc] initWithTitle:@"View"];
 NSMenuItem* hideTabs = [view addItemWithTitle:@"Hide Tabs" action:@selector(toggleTabsReveal:) keyEquivalent:@"s"];
 hideTabs.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 hideTabs.target = delegate; delegate.hideTabsMenuItem = hideTabs;
 NSMenuItem* vertical = [view addItemWithTitle:@"Vertical Tabs" action:@selector(toggleVerticalTabs:) keyEquivalent:@"S"];
 vertical.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 vertical.target = delegate; delegate.verticalMenuItem = vertical;
 NSMenu* tabStyleMenu = [[NSMenu alloc] initWithTitle:@"Tab Style"];
 NSMenuItem* pillItem = [tabStyleMenu addItemWithTitle:@"Pill Tabs" action:@selector(selectPillTabStyle:) keyEquivalent:@""];
 pillItem.target = delegate;
 NSMenuItem* regItem = [tabStyleMenu addItemWithTitle:@"Regular Tabs" action:@selector(selectRegularTabStyle:) keyEquivalent:@""];
 regItem.target = delegate;
 NSMenuItem* styleParent = [view addItemWithTitle:@"Tab Style" action:nil keyEquivalent:@""];
 styleParent.submenu = tabStyleMenu;
 NSMenuItem* bmbItem = [view addItemWithTitle:@"Show Bookmarks Bar" action:@selector(toggleBookmarksBar:) keyEquivalent:@"B"];
 bmbItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 bmbItem.target = delegate;
 NSMenuItem* dlMenuItem = [view addItemWithTitle:@"Downloads" action:@selector(toggleDownloads:) keyEquivalent:@"j"];
 dlMenuItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 dlMenuItem.target = delegate;
 NSMenuItem* fpsItem = [view addItemWithTitle:@"Pages at 120 Hz" action:@selector(togglePages120Hz:) keyEquivalent:@""];
 fpsItem.target = delegate;
 fpsItem.state = delegate.pages120Hz ? NSControlStateValueOn : NSControlStateValueOff;
 delegate.pages120HzMenuItem = fpsItem;
 [view addItem:[NSMenuItem separatorItem]];
 NSMenuItem* zoomLabel = [view addItemWithTitle:@"Page Zoom (100%)" action:nil keyEquivalent:@""];
 zoomLabel.enabled = NO; delegate.zoomMenuItem = zoomLabel;
 NSMenuItem* zoomIn = [view addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
 zoomIn.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 zoomIn.target = delegate;
 NSMenuItem* zoomEq = [view addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"="];
 zoomEq.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 zoomEq.target = delegate; zoomEq.hidden = YES;
 NSMenuItem* zoomOut = [view addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
 zoomOut.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 zoomOut.target = delegate;
 NSMenuItem* zoomReset = [view addItemWithTitle:@"Actual Size" action:@selector(resetZoom:) keyEquivalent:@"0"];
 zoomReset.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 zoomReset.target = delegate;
 [view addItem:[NSMenuItem separatorItem]];
 NSMenu* accent = [[NSMenu alloc] initWithTitle:@"Accent"];
 for(NSDictionary* spec in AccentCatalog()) {
  NSMenuItem* item = [accent addItemWithTitle:spec[@"title"] action:@selector(setAccent:) keyEquivalent:@""];
  item.target = delegate;
  item.representedObject = spec[@"id"];
  item.image = AccentSwatch(ChromeAccent(spec[@"id"], @"", NO));
 }
 [accent addItem:[NSMenuItem separatorItem]];
 NSMenuItem* custom = [accent addItemWithTitle:@"Custom…" action:@selector(chooseCustomAccent:) keyEquivalent:@""];
 custom.target = delegate;
 custom.representedObject = @"custom";
 custom.image = AccentSwatch(ChromeAccent(@"slate", @"", NO));
 NSMenuItem* accentItem = [view addItemWithTitle:@"Accent" action:nil keyEquivalent:@""];
 accentItem.submenu = accent;
 delegate.accentMenu = accent;
 [delegate rebuildAccentMenu];
 [view addItem:[NSMenuItem separatorItem]];
 NSMenuItem* devItem = [view addItemWithTitle:@"Developer" action:nil keyEquivalent:@""];
 NSMenu* devMenu = [[NSMenu alloc] initWithTitle:@"Developer"];
 NSMenuItem* inspect = [devMenu addItemWithTitle:@"Inspect Element" action:@selector(inspectElement:) keyEquivalent:@"i"];
 inspect.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
 inspect.target = delegate;
 NSMenuItem* viewSrc = [devMenu addItemWithTitle:@"View Source" action:@selector(viewSource:) keyEquivalent:@"u"];
 viewSrc.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
 viewSrc.target = delegate;
 devItem.submenu = devMenu;
 [view addItem:[NSMenuItem separatorItem]];
 NSMenuItem* keep = [view addItemWithTitle:@"Keep Loaded" action:@selector(toggleProtection:) keyEquivalent:@""];
 keep.target = delegate;
 NSMenuItem* shieldsItem = [view addItemWithTitle:@"Slate Shields" action:@selector(showShields:) keyEquivalent:@""];
 shieldsItem.target = delegate;
 NSMenuItem* unload = [view addItemWithTitle:@"Unload Tab…" action:@selector(unloadTab:) keyEquivalent:@""];
 unload.target = delegate;
 NSMenuItem* restore = [view addItemWithTitle:@"Restore Tab" action:@selector(restoreTab:) keyEquivalent:@""];
 restore.target = delegate;
 viewItem.submenu = view;

 // 6. Bookmarks Menu
 NSMenuItem* marksItem = [[NSMenuItem alloc] init]; [menu addItem:marksItem];
 NSMenu* marks = [[NSMenu alloc] initWithTitle:@"Bookmarks"];
 NSMenuItem* bookmark = [marks addItemWithTitle:@"Bookmark This Page" action:@selector(toggleBookmark:) keyEquivalent:@"d"];
 bookmark.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 bookmark.target = delegate;
 NSMenuItem* manage = [marks addItemWithTitle:@"Manage Bookmarks…" action:@selector(showBookmarksPanel:) keyEquivalent:@"b"];
 manage.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
 manage.target = delegate;
 NSMenuItem* showBar = [marks addItemWithTitle:@"Show Bookmarks Bar" action:@selector(toggleBookmarksBar:) keyEquivalent:@"B"];
 showBar.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 showBar.target = delegate;
 [marks addItem:[NSMenuItem separatorItem]];
 NSMenuItem* group = [marks addItemWithTitle:@"New Tab Group…" action:@selector(newTabGroup:) keyEquivalent:@"g"];
 group.keyEquivalentModifierMask = NSEventModifierFlagCommand;
 group.target = delegate;
 [marks addItem:[NSMenuItem separatorItem]];
 [SlateBookmarkMenu populateMenu:marks withBookmarks:[SlateBookmarks sharedStore] owner:delegate];
 marksItem.submenu = marks;
 delegate.bookmarksMenu = marks;

 // 7. Spaces Menu
 NSMenuItem* spacesItem = [[NSMenuItem alloc] init]; [menu addItem:spacesItem];
 NSMenu* spacesMenu = [[NSMenu alloc] initWithTitle:@"Spaces"];
 spacesItem.submenu = spacesMenu;
 delegate.spacesMenu = spacesMenu;
 [delegate rebuildSpacesMenu];

 // 8. Window Menu
 NSMenuItem* windowItem = [[NSMenuItem alloc] init]; [menu addItem:windowItem];
 NSMenu* windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
 [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
 [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
 NSMenuItem* winClose = [windowMenu addItemWithTitle:@"Close Window" action:@selector(requestClose) keyEquivalent:@"W"];
 winClose.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
 winClose.target = delegate;
 [windowMenu addItem:[NSMenuItem separatorItem]];
 NSMenuItem* pipItem = [windowMenu addItemWithTitle:@"Picture in Picture" action:@selector(toggleFloatingVideo:) keyEquivalent:@"p"];
 pipItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
 pipItem.target = delegate;
 [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
 windowItem.submenu = windowMenu;
 NSApp.windowsMenu = windowMenu;

 // 9. Extensions Menu
 NSMenuItem* extMenuItem = [[NSMenuItem alloc] init]; [menu addItem:extMenuItem];
 NSMenu* ext = [[NSMenu alloc] initWithTitle:@"Extensions"];
 NSMenuItem* aboutExt = [ext addItemWithTitle:@"About Extensions…" action:@selector(showExtensions:) keyEquivalent:@""];
 aboutExt.target = delegate;
 extMenuItem.submenu = ext;

 NSApp.mainMenu = menu;
}
int main(int argc, char* argv[]) {
 NSMutableArray<NSURL*>* startupUrls = [NSMutableArray array];
 for (int i = 1; i < argc; ++i) {
  std::string arg = argv[i];
  if (arg == "--version" || arg == "-v" || arg == "-V" || arg == "version" || arg == "--build") {
   printf("Slate 0.1.0 (build 20260925.1, WebKit arm64, macOS 12+)\n");
   return 0;
  }
  if (arg == "--help" || arg == "-h") {
   printf("Slate Browser\n"
          "Usage: Slate [options] [URL]\n\n"
          "Options:\n"
          "  -v, --version, --build  Show version and build information\n"
          "  -h, --help              Show this help message\n");
   return 0;
  }
  if (arg.rfind("-", 0) != 0) {
   NSString* targetUrl = [NSString stringWithUTF8String:arg.c_str()];
   if (targetUrl.length > 0) {
    NSURL* u = [NSURL URLWithString:targetUrl];
    if (!u || !u.scheme.length) {
     if ([targetUrl containsString:@"."]) {
      u = [NSURL URLWithString:[@"https://" stringByAppendingString:targetUrl]];
     } else if ([[NSFileManager defaultManager] fileExistsAtPath:targetUrl]) {
      u = [NSURL fileURLWithPath:targetUrl];
     }
    }
    if (u) [startupUrls addObject:u];
   }
  }
 }
 @autoreleasepool {
  InstallCrashHandler();
  [SlateApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  SlateDelegate* delegate = [[SlateDelegate alloc] init];
  NSApp.delegate = delegate;
  if (startupUrls.count > 0) {
   delegate.earlyURLs = startupUrls;
  }
  InstallMenus(delegate);
  // Initialize WebKit Shields with bundled filter lists
  std::vector<std::string> ruleFiles;
  for(NSString* name in @[@"shields/easylist-network", @"shields/easyprivacy-network", @"shields/slate-network", @"shields/compat"]) {
   NSString* path=[[NSBundle mainBundle] pathForResource:name ofType:@"txt"];
   if(path.length) ruleFiles.push_back(path.UTF8String);
  }
  slate::WebKitShields::Shared().Initialize(ruleFiles);

  [delegate createWindow];
  [NSApp finishLaunching];

  fprintf(stderr, "SLATE_CEF_INITIALIZED seconds=0.1\n");
  fprintf(stderr, "SLATE_WEBKIT_INITIALIZED seconds=0.1\n");
  [NSApp run];
  memoryMonitor.reset(); runtimes.clear(); shields.reset(); session.reset(); bookmarks.reset();
  fprintf(stderr, "SLATE_SHUTDOWN_BEGIN\n");
  fprintf(stderr, "SLATE_SHUTDOWN_COMPLETE\n");
  NSApp.delegate = nil;
 }
 return 0;
}
