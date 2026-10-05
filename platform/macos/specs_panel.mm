#import "platform/macos/specs_panel.h"

@interface SlateBarView : NSView
@property (nonatomic, assign) CGFloat fraction;
@property (nonatomic, strong) NSColor* barColor;
@end

@implementation SlateBarView

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  NSRect bounds = self.bounds;
  const CGFloat trackHeight = 7.0;
  NSRect trackRect = NSMakeRect(0, (bounds.size.height - trackHeight) / 2.0, bounds.size.width, trackHeight);

  // Background track
  NSBezierPath* trackPath = [NSBezierPath bezierPathWithRoundedRect:trackRect xRadius:3.5 yRadius:3.5];
  [[NSColor colorWithWhite:0.75 alpha:0.25] setFill];
  [trackPath fill];

  // Filled bar
  CGFloat fillWidth = MAX(6.0, bounds.size.width * MAX(0.01, MIN(1.0, self.fraction)));
  NSRect fillRect = NSMakeRect(0, (bounds.size.height - trackHeight) / 2.0, fillWidth, trackHeight);
  NSBezierPath* fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:3.5 yRadius:3.5];
  [(self.barColor ?: [NSColor labelColor]) setFill];
  [fillPath fill];
}

@end

@interface SlateSpecCard : NSView
@end

@implementation SlateSpecCard

- (instancetype)initWithIcon:(NSString*)symbolName
                       title:(NSString*)title
                    subtitle:(NSString*)subtitle
                        rows:(NSArray<NSDictionary*>*)rows {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // Header container: Icon + Title + Subtitle
    NSImageView* icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    NSImageSymbolConfiguration* iconConf = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightMedium];
    icon.image = [[NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil] imageWithSymbolConfiguration:iconConf];
    icon.contentTintColor = [NSColor labelColor];

    NSMutableAttributedString* headerText = [[NSMutableAttributedString alloc] init];
    NSDictionary* boldAttr = @{
      NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightBold],
      NSForegroundColorAttributeName: [NSColor labelColor]
    };
    NSDictionary* subAttr = @{
      NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
      NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };
    [headerText appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ ", title] attributes:boldAttr]];
    [headerText appendAttributedString:[[NSAttributedString alloc] initWithString:subtitle attributes:subAttr]];

    NSTextField* headerLabel = [NSTextField labelWithAttributedString:headerText];
    headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    headerLabel.lineBreakMode = NSLineBreakByWordWrapping;

    [self addSubview:icon];
    [self addSubview:headerLabel];

    [NSLayoutConstraint activateConstraints:@[
      [icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
      [icon.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
      [icon.widthAnchor constraintEqualToConstant:18],
      [icon.heightAnchor constraintEqualToConstant:18],
      [headerLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
      [headerLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
      [headerLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:11]
    ]];

    NSView* previousAnchor = headerLabel;
    for (NSDictionary* r in rows) {
      NSString* name = r[@"name"];
      NSString* val = r[@"val"];
      CGFloat frac = [r[@"frac"] doubleValue];
      BOOL isPrimary = [r[@"primary"] boolValue];

      NSView* rowView = [[NSView alloc] initWithFrame:NSZeroRect];
      rowView.translatesAutoresizingMaskIntoConstraints = NO;

      NSTextField* nameLabel = [NSTextField labelWithString:name];
      nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
      nameLabel.font = [NSFont systemFontOfSize:12 weight:isPrimary ? NSFontWeightSemibold : NSFontWeightRegular];
      nameLabel.textColor = isPrimary ? [NSColor labelColor] : [NSColor secondaryLabelColor];

      SlateBarView* bar = [[SlateBarView alloc] initWithFrame:NSZeroRect];
      bar.translatesAutoresizingMaskIntoConstraints = NO;
      bar.fraction = frac;
      bar.barColor = isPrimary ? [NSColor labelColor] : [NSColor colorWithWhite:0.65 alpha:0.4];

      NSTextField* valLabel = [NSTextField labelWithString:val];
      valLabel.translatesAutoresizingMaskIntoConstraints = NO;
      valLabel.font = [NSFont systemFontOfSize:12 weight:isPrimary ? NSFontWeightSemibold : NSFontWeightRegular];
      valLabel.textColor = isPrimary ? [NSColor labelColor] : [NSColor secondaryLabelColor];
      valLabel.alignment = NSTextAlignmentRight;

      [rowView addSubview:nameLabel];
      [rowView addSubview:bar];
      [rowView addSubview:valLabel];

      [NSLayoutConstraint activateConstraints:@[
        [rowView.heightAnchor constraintEqualToConstant:22],
        [nameLabel.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor],
        [nameLabel.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
        [nameLabel.widthAnchor constraintEqualToConstant:68],
        [bar.leadingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor constant:8],
        [bar.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:valLabel.leadingAnchor constant:-10],
        [bar.heightAnchor constraintEqualToConstant:14],
        [valLabel.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor],
        [valLabel.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
        [valLabel.widthAnchor constraintEqualToConstant:72]
      ]];

      [self addSubview:rowView];
      [NSLayoutConstraint activateConstraints:@[
        [rowView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:36],
        [rowView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [rowView.topAnchor constraintEqualToAnchor:previousAnchor.bottomAnchor constant:(previousAnchor == headerLabel ? 12 : 4)]
      ]];
      previousAnchor = rowView;
    }

    [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:previousAnchor.bottomAnchor constant:12].active = YES;
  }
  return self;
}

@end

@implementation SlateSpecsPanel

+ (instancetype)sharedPanel {
  static SlateSpecsPanel* instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[SlateSpecsPanel alloc] init];
  });
  return instance;
}

- (instancetype)init {
  const NSRect frame = NSMakeRect(0, 0, 780, 480);
  NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView;
  self = [super initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
  if (self) {
    self.title = @"About Slate";
    self.titlebarAppearsTransparent = YES;
    self.titleVisibility = NSWindowTitleHidden;
    self.movableByWindowBackground = YES;

    NSVisualEffectView* visualEffect = [[NSVisualEffectView alloc] initWithFrame:frame];
    visualEffect.material = NSVisualEffectMaterialUnderWindowBackground;
    visualEffect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    visualEffect.state = NSVisualEffectStateActive;
    visualEffect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.contentView = visualEffect;

    NSView* root = [[NSView alloc] initWithFrame:frame];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [visualEffect addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
      [root.leadingAnchor constraintEqualToAnchor:visualEffect.leadingAnchor],
      [root.trailingAnchor constraintEqualToAnchor:visualEffect.trailingAnchor],
      [root.topAnchor constraintEqualToAnchor:visualEffect.topAnchor],
      [root.bottomAnchor constraintEqualToAnchor:visualEffect.bottomAnchor]
    ]];

    // Top Lead Banner
    NSTextField* titleLabel = [NSTextField labelWithString:@"Light enough to forget it's there."];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    titleLabel.textColor = [NSColor labelColor];

    NSTextField* buildLabel = [NSTextField labelWithString:@"v0.1.0 (Build 20260925.1)"];
    buildLabel.translatesAutoresizingMaskIntoConstraints = NO;
    buildLabel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    buildLabel.textColor = [NSColor tertiaryLabelColor];
    buildLabel.alignment = NSTextAlignmentRight;

    NSTextField* subLabel = [NSTextField labelWithString:@"Measured against Chrome and Safari on the same Mac, the same afternoon, the same pages. Medians of three runs."];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    subLabel.textColor = [NSColor secondaryLabelColor];

    NSBox* sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    [root addSubview:titleLabel];
    [root addSubview:buildLabel];
    [root addSubview:subLabel];
    [root addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
      [titleLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:28],
      [titleLabel.topAnchor constraintEqualToAnchor:root.topAnchor constant:28],
      [buildLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-28],
      [buildLabel.firstBaselineAnchor constraintEqualToAnchor:titleLabel.firstBaselineAnchor],
      [subLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
      [subLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4],
      [sep.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
      [sep.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
      [sep.topAnchor constraintEqualToAnchor:subLabel.bottomAnchor constant:14]
    ]];

    // 4 Comparison Cards (2x2 grid)
    SlateSpecCard* cardDisk = [[SlateSpecCard alloc] initWithIcon:@"internaldrive"
                                                           title:@"2.5 MB on disk."
                                                        subtitle:@"No engine of its own to carry."
                                                            rows:@[
      @{@"name": @"Slate",  @"val": @"2.5 MB",   @"frac": @(0.01), @"primary": @YES},
      @{@"name": @"Safari", @"val": @"36 MB",    @"frac": @(0.03), @"primary": @NO},
      @{@"name": @"Dia",    @"val": @"1,321 MB", @"frac": @(0.92), @"primary": @NO},
      @{@"name": @"Chrome", @"val": @"1,429 MB", @"frac": @(1.00), @"primary": @NO}
    ]];

    SlateSpecCard* cardSpeed = [[SlateSpecCard alloc] initWithIcon:@"bolt.fill"
                                                            title:@"180 ms to the first window."
                                                         subtitle:@"Launched cold, no page open."
                                                             rows:@[
      @{@"name": @"Slate",  @"val": @"180 ms", @"frac": @(0.25), @"primary": @YES},
      @{@"name": @"Chrome", @"val": @"526 ms", @"frac": @(0.72), @"primary": @NO},
      @{@"name": @"Safari", @"val": @"730 ms", @"frac": @(1.00), @"primary": @NO}
    ]];

    SlateSpecCard* cardRam = [[SlateSpecCard alloc] initWithIcon:@"cpu"
                                                          title:@"48 MB before the first page."
                                                       subtitle:@"Every process the app owns."
                                                           rows:@[
      @{@"name": @"Slate",  @"val": @"48 MB",  @"frac": @(0.07), @"primary": @YES},
      @{@"name": @"Safari", @"val": @"203 MB", @"frac": @(0.31), @"primary": @NO},
      @{@"name": @"Chrome", @"val": @"663 MB", @"frac": @(1.00), @"primary": @NO}
    ]];

    SlateSpecCard* cardProcs = [[SlateSpecCard alloc] initWithIcon:@"square.grid.2x2"
                                                             title:@"6 processes with five tabs open."
                                                          subtitle:@"Where Chrome runs 29."
                                                              rows:@[
      @{@"name": @"Slate",  @"val": @"6",  @"frac": @(0.20), @"primary": @YES},
      @{@"name": @"Safari", @"val": @"21", @"frac": @(0.72), @"primary": @NO},
      @{@"name": @"Chrome", @"val": @"29", @"frac": @(1.00), @"primary": @NO}
    ]];

    [root addSubview:cardDisk];
    [root addSubview:cardSpeed];
    [root addSubview:cardRam];
    [root addSubview:cardProcs];

    [NSLayoutConstraint activateConstraints:@[
      // Card Disk (Top Left)
      [cardDisk.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
      [cardDisk.topAnchor constraintEqualToAnchor:sep.bottomAnchor constant:14],
      [cardDisk.widthAnchor constraintEqualToAnchor:root.widthAnchor multiplier:0.48],

      // Card Speed (Top Right)
      [cardSpeed.leadingAnchor constraintEqualToAnchor:cardDisk.trailingAnchor constant:12],
      [cardSpeed.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
      [cardSpeed.topAnchor constraintEqualToAnchor:sep.bottomAnchor constant:14],

      // Card RAM (Bottom Left)
      [cardRam.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
      [cardRam.topAnchor constraintEqualToAnchor:cardDisk.bottomAnchor constant:16],
      [cardRam.widthAnchor constraintEqualToAnchor:root.widthAnchor multiplier:0.48],

      // Card Procs (Bottom Right)
      [cardProcs.leadingAnchor constraintEqualToAnchor:cardRam.trailingAnchor constant:12],
      [cardProcs.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
      [cardProcs.topAnchor constraintEqualToAnchor:cardDisk.bottomAnchor constant:16]
    ]];
  }
  return self;
}

- (void)showForWindow:(NSWindow*)parentWindow {
  [self center];
  [self makeKeyAndOrderFront:nil];
}

@end
