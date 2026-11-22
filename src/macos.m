#import <AppKit/AppKit.h>
#include <stdbool.h>
#include <stdint.h>
#import "audio.h"

extern void app_event(int event);
extern void app_set_gain(float percent);
extern void app_set_lock_minutes(uint32_t minutes);

enum Event {
    Play = 0, Stop, Lock, Unlock, Wake, RouteChanged, Tick, Quit,
};

enum PlaybackStatus {
    Stopped = 0, FadingIn, Playing, FadingOut, WaitingForSoundbar, Unavailable,
    StoppedAfterLock, FadingOutAfterLock,
};

static NSString *const outputUIDKey = @"SoundbarOutputUID";
static NSString *const outputNameKey = @"SoundbarOutputName";
static NSString *const gainKey = @"ToneGainPercent";
static NSString *const lockMinutesKey = @"LockTimeoutMinutes";

static NSStatusBarButton *statusButton;
static NSMenuItem *toggle, *menuStatus, *menuOutput;
static NSTextField *statusLabel, *outputLabel;
static NSButton *playButton, *stopButton;
static NSString *selectedOutputUID, *savedOutputName;
static int currentState = -1;
static BOOL playbackRequested;
static NSColor *windowGreen(void);

static void showOutput(void) {
    NSString *name = audio_output_name();
    NSString *text;
    if (name.length) {
        text = [@"Output: " stringByAppendingString:name];
    } else if (selectedOutputUID) {
        text = [@"Soundbar: " stringByAppendingString:savedOutputName ?: @"Selected output"];
    } else {
        text = @"Output: Unavailable";
    }
    menuOutput.title = text;
    outputLabel.stringValue = text;
    outputLabel.toolTip = text;
}

void show_state(int state, bool requested) {
    if (currentState == state && playbackRequested == requested) return;
    currentState = state;
    playbackRequested = requested;
    NSArray<NSString *> *labels = @[@"Stopped", @"Fading in…", @"Playing", @"Fading out…",
        @"Waiting for soundbar", @"Audio output unavailable", @"Stopped after screen lock",
        @"Fading out after screen lock…"];
    NSString *status = labels[state];
    BOOL audible = state == FadingIn || state == Playing || state == FadingOut
        || state == FadingOutAfterLock;
    statusLabel.stringValue = status;
    menuStatus.title = status;
    toggle.title = requested ? @"Stop Sound" : @"Play Sound";
    playButton.enabled = !requested;
    stopButton.enabled = requested;
    if (statusButton.image) {
        statusButton.imagePosition = audible ? NSImageLeft : NSImageOnly;
        statusButton.title = audible ? @"•" : @"";
    } else {
        statusButton.title = audible ? @"20 Hz •" : @"20 Hz";
    }
    NSString *description = [@"20HzPlayer, " stringByAppendingString:status];
    statusButton.toolTip = description;
    [statusButton setAccessibilityLabel:description];
    showOutput();
}

static NSColor *windowGreen(void) {
    return [NSColor colorWithSRGBRed:50.0/255 green:205.0/255 blue:50.0/255 alpha:1];
}

static NSTextField *windowLabel(NSString *text, NSRect frame, NSFont *font) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.alignment = NSTextAlignmentCenter;
    label.font = font;
    label.textColor = windowGreen();
    return label;
}

@interface ToneButton : NSButton
@property(nonatomic, strong) NSTrackingArea *hoverArea;
@end

@implementation ToneButton
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:self.hoverArea];
    [self updateAppearance];
}

- (void)resetCursorRects {
    [super resetCursorRects];
    if (self.enabled) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (void)mouseEntered:(NSEvent *)event { [self applyHover:YES]; }
- (void)mouseExited:(NSEvent *)event { [self applyHover:NO]; }

- (void)updateAppearance {
    NSPoint pointer = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    [self applyHover:self.window.isKeyWindow && NSMouseInRect(pointer, self.bounds, self.isFlipped)];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self.window invalidateCursorRectsForView:self];
    [self updateAppearance];
}

- (void)applyHover:(BOOL)hovered {
    hovered = hovered && self.enabled;
    self.layer.backgroundColor = (hovered ? windowGreen() : NSColor.blackColor).CGColor;
    NSColor *titleColor = self.enabled ? windowGreen() : NSColor.systemGrayColor;
    self.attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:@{
        NSForegroundColorAttributeName: hovered ? NSColor.blackColor : titleColor,
        NSFontAttributeName: [NSFont systemFontOfSize:16],
    }];
}
@end

static NSButton *windowButton(NSString *title, NSRect frame, id target, SEL action) {
    ToneButton *button = [[ToneButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = target;
    button.action = action;
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    button.bordered = NO;
    button.wantsLayer = YES;
    button.layer.borderWidth = 2;
    button.layer.borderColor = windowGreen().CGColor;
    [button applyHover:NO];
    return button;
}

static NSMenu *submenu(NSMenu *parent, NSString *title) {
    NSMenuItem *item = [parent addItemWithTitle:title action:nil keyEquivalent:@""];
    item.submenu = [[NSMenu alloc] initWithTitle:title];
    return item.submenu;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *item;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSMenu *outputMenu, *gainMenu, *timeoutMenu;
- (void)quit:(id)sender;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    statusButton = self.item.button;
    NSString *icon = [NSBundle.mainBundle pathForResource:@"tray" ofType:@"png"];
    statusButton.image = icon ? [[NSImage alloc] initWithContentsOfFile:icon] : nil;
    NSMenu *menu = [NSMenu new];
    menuStatus = [menu addItemWithTitle:@"Stopped" action:nil keyEquivalent:@""];
    menuOutput = [menu addItemWithTitle:@"" action:nil keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    toggle = [menu addItemWithTitle:@"Play Sound" action:@selector(toggle:) keyEquivalent:@""];
    toggle.target = self;
    [menu addItemWithTitle:@"Show Window" action:@selector(showWindow:) keyEquivalent:@""].target = self;
    [menu addItem:NSMenuItem.separatorItem];
    self.outputMenu = submenu(menu, @"Soundbar Output");
    self.gainMenu = submenu(menu, @"Tone Gain");
    self.timeoutMenu = submenu(menu, @"Stop After Screen Lock");
    self.outputMenu.delegate = self;
    self.gainMenu.delegate = self;
    self.timeoutMenu.delegate = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"].target = self;
    self.item.menu = menu;

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 350, 276)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"20HzPlayer";
    self.window.delegate = self;
    [self.window center];

    self.window.backgroundColor = NSColor.blackColor;
    NSTextField *heading = windowLabel(@"20HzPlayer", NSMakeRect(20, 188, 310, 42),
        [NSFont boldSystemFontOfSize:32]);
    statusLabel = windowLabel(@"", NSMakeRect(20, 150, 310, 26), [NSFont systemFontOfSize:18]);
    outputLabel = windowLabel(@"", NSMakeRect(20, 124, 310, 22), [NSFont systemFontOfSize:13]);
    outputLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    playButton = windowButton(@"Play", NSMakeRect(87, 62, 76, 42), self, @selector(play:));
    stopButton = windowButton(@"Stop", NSMakeRect(187, 62, 76, 42), self, @selector(stop:));
    [self.window.contentView addSubview:heading];
    [self.window.contentView addSubview:statusLabel];
    [self.window.contentView addSubview:outputLabel];
    [self.window.contentView addSubview:playButton];
    [self.window.contentView addSubview:stopButton];

    NSDistributedNotificationCenter *distributed = NSDistributedNotificationCenter.defaultCenter;
    [distributed addObserver:self selector:@selector(locked:) name:@"com.apple.screenIsLocked"
        object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [distributed addObserver:self selector:@selector(unlocked:) name:@"com.apple.screenIsUnlocked"
        object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(woke:)
        name:NSWorkspaceDidWakeNotification object:nil];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults registerDefaults:@{gainKey: @5, lockMinutesKey: @60}];
    selectedOutputUID = [defaults stringForKey:outputUIDKey];
    savedOutputName = [defaults stringForKey:outputNameKey];
    audio_select_output(selectedOutputUID);
    app_set_gain([defaults floatForKey:gainKey]);
    app_set_lock_minutes((uint32_t)[defaults integerForKey:lockMinutesKey]);
    [self menuNeedsUpdate:self.outputMenu];
    [self menuNeedsUpdate:self.gainMenu];
    [self menuNeedsUpdate:self.timeoutMenu];
    audio_observe_route_changes(^{
        app_event(RouteChanged);
        showOutput();
    });

    self.timer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
        app_event(Tick);
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (menu == self.outputMenu) {
        NSMenuItem *system = [menu addItemWithTitle:@"Follow System Output"
            action:@selector(selectOutput:) keyEquivalent:@""];
        system.target = self;
        system.state = selectedOutputUID ? NSControlStateValueOff : NSControlStateValueOn;
        [menu addItem:NSMenuItem.separatorItem];

        NSDictionary<NSString *, NSString *> *outputs = audio_output_devices();
        NSArray<NSString *> *uids = [outputs keysSortedByValueUsingSelector:@selector(localizedStandardCompare:)];
        for (NSString *uid in uids) {
            NSMenuItem *item = [menu addItemWithTitle:outputs[uid]
                action:@selector(selectOutput:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = uid;
            item.state = [uid isEqualToString:selectedOutputUID] ? NSControlStateValueOn : NSControlStateValueOff;
        }
        if (selectedOutputUID && !outputs[selectedOutputUID]) {
            NSString *title = [NSString stringWithFormat:@"%@ (disconnected)", savedOutputName ?: @"Selected soundbar"];
            NSMenuItem *missing = [menu addItemWithTitle:title action:nil keyEquivalent:@""];
            missing.state = NSControlStateValueOn;
        } else if (uids.count == 0) {
            [menu addItemWithTitle:@"No audio outputs available" action:nil keyEquivalent:@""];
        }
    } else if (menu == self.gainMenu) {
        float selectedGain = [defaults floatForKey:gainKey];
        for (NSNumber *gain in @[@0.5, @1, @2, @3, @4, @5]) {
            NSString *title = [NSString stringWithFormat:@"%@%%", gain];
            NSMenuItem *item = [menu addItemWithTitle:title action:@selector(selectGain:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = gain;
            item.state = selectedGain == gain.floatValue ? NSControlStateValueOn : NSControlStateValueOff;
        }
    } else if (menu == self.timeoutMenu) {
        NSInteger selectedMinutes = [defaults integerForKey:lockMinutesKey];
        for (NSNumber *minutes in @[@15, @30, @60]) {
            NSString *title = [NSString stringWithFormat:@"%@ minutes", minutes];
            NSMenuItem *item = [menu addItemWithTitle:title action:@selector(selectTimeout:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = minutes;
            item.state = selectedMinutes == minutes.integerValue ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
}

- (void)selectOutput:(NSMenuItem *)sender {
    NSString *uid = sender.representedObject;
    if (uid == selectedOutputUID || [uid isEqualToString:selectedOutputUID]) return;
    selectedOutputUID = uid;
    savedOutputName = uid ? sender.title : nil;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (uid) {
        [defaults setObject:uid forKey:outputUIDKey];
        [defaults setObject:savedOutputName forKey:outputNameKey];
    } else {
        [defaults removeObjectForKey:outputUIDKey];
        [defaults removeObjectForKey:outputNameKey];
    }
    audio_select_output(selectedOutputUID);
    app_event(RouteChanged);
    showOutput();
}

- (void)selectGain:(NSMenuItem *)sender {
    float gain = [sender.representedObject floatValue];
    [NSUserDefaults.standardUserDefaults setFloat:gain forKey:gainKey];
    app_set_gain(gain);
}

- (void)selectTimeout:(NSMenuItem *)sender {
    NSInteger minutes = [sender.representedObject integerValue];
    [NSUserDefaults.standardUserDefaults setInteger:minutes forKey:lockMinutesKey];
    app_set_lock_minutes((uint32_t)minutes);
}

- (void)toggle:(id)sender { app_event(playbackRequested ? Stop : Play); }
- (void)play:(id)sender { if (!playbackRequested) app_event(Play); }
- (void)stop:(id)sender { if (playbackRequested) app_event(Stop); }
- (void)locked:(NSNotification *)note { dispatch_async(dispatch_get_main_queue(), ^{ app_event(Lock); }); }
- (void)unlocked:(NSNotification *)note { dispatch_async(dispatch_get_main_queue(), ^{ app_event(Unlock); }); }
- (void)woke:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        app_event(Wake);
        showOutput();
    });
}
- (void)showWindow:(id)sender {
    [NSApp activate];
    [self.window makeKeyAndOrderFront:nil];
}
- (void)windowDidBecomeKey:(NSNotification *)note {
    [(ToneButton *)playButton updateAppearance];
    [(ToneButton *)stopButton updateAppearance];
}

- (void)windowDidResignKey:(NSNotification *)note {
    [(ToneButton *)playButton applyHover:NO];
    [(ToneButton *)stopButton applyHover:NO];
}

- (BOOL)windowShouldClose:(NSWindow *)sender { [sender orderOut:nil]; return NO; }
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)note {
    [self.timer invalidate];
    audio_remove_route_observer();
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    app_event(Quit);
}
@end

void run_app(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        __attribute__((objc_precise_lifetime)) AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
}
