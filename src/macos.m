#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdio.h>

extern void app_event(int event);
extern void *tone_create(void);
extern void tone_destroy(void *tone);
extern void tone_render(void *tone, float *buffer, size_t frames, double rate);

static AVAudioEngine *engine;
static AVAudioSourceNode *source;
static AudioObjectPropertyListenerBlock routeListener;
static NSMenuItem *toggle;
static NSTextField *statusLabel;
static NSButton *playButton, *stopButton;
static int currentState = -1;
static NSColor *windowGreen(void);

@interface ToneContext : NSObject
@property(nonatomic, readonly) void *tone;
@end

@implementation ToneContext
- (instancetype)init {
    if ((self = [super init])) _tone = tone_create();
    return self;
}
- (void)dealloc { tone_destroy(_tone); }
@end

void stop_audio(void) {
    [engine stop];
    if (source) [engine detachNode:source];
    source = nil;
    engine = nil;
}

bool start_audio(void) {
    engine = [AVAudioEngine new];
    AVAudioFormat *output = [engine.outputNode outputFormatForBus:0];
    double rate = output.sampleRate;
    if (rate <= 0 || output.channelCount == 0) {
        stop_audio();
        return false;
    }
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate
                                                                        channels:output.channelCount];
    if (!format) {
        stop_audio();
        return false;
    }
    ToneContext *context = [ToneContext new];
    source = [[AVAudioSourceNode alloc] initWithFormat:format
        renderBlock:^OSStatus(BOOL *silence, const AudioTimeStamp *time,
                              AVAudioFrameCount frames, AudioBufferList *buffers) {
        if (!frames || !buffers->mNumberBuffers) return noErr;
        float *first = buffers->mBuffers[0].mData;
        tone_render(context.tone, first, frames, rate);
        for (UInt32 channel = 1; channel < buffers->mNumberBuffers; channel++) {
            memcpy(buffers->mBuffers[channel].mData, first, frames * sizeof(float));
        }
        return noErr;
    }];
    [engine attachNode:source];
    [engine connect:source to:engine.mainMixerNode format:format];

    NSError *error = nil;
    if (![engine startAndReturnError:&error]) {
        NSLog(@"Audio output unavailable: %@", error);
        stop_audio();
        return false;
    }
    return true;
}

void show_state(int state) {
    if (currentState == state) return;
    currentState = state;
    NSArray<NSString *> *labels = @[@"Stopped", @"Fading in…", @"Playing", @"Fading out…", @"Audio output unavailable"];
    BOOL playing = state == 1 || state == 2;
    statusLabel.stringValue = [[@"Status: " stringByAppendingString:labels[state]] uppercaseString];
    statusLabel.textColor = playing ? NSColor.systemRedColor : windowGreen();
    statusLabel.font = playing ? [NSFont boldSystemFontOfSize:18] : [NSFont systemFontOfSize:18];
    toggle.title = playing ? @"Stop Sound" : @"Play Sound";
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
    [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (void)mouseEntered:(NSEvent *)event { [self applyHover:YES]; }
- (void)mouseExited:(NSEvent *)event { [self applyHover:NO]; }

- (void)updateAppearance {
    NSPoint pointer = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    [self applyHover:self.window.isKeyWindow && NSMouseInRect(pointer, self.bounds, self.isFlipped)];
}

- (void)applyHover:(BOOL)hovered {
    self.layer.backgroundColor = (hovered ? windowGreen() : NSColor.blackColor).CGColor;
    self.attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:@{
        NSForegroundColorAttributeName: hovered ? NSColor.blackColor : windowGreen(),
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

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic, strong) NSStatusItem *item;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTimer *timer;
- (void)quit:(id)sender;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSString *icon = [NSBundle.mainBundle pathForResource:@"tray" ofType:@"png"];
    NSImage *image = icon ? [[NSImage alloc] initWithContentsOfFile:icon] : nil;
    self.item.button.image = image;
    if (!image) self.item.button.title = @"20 Hz";
    self.item.button.toolTip = @"20HzPlayer";
    NSMenu *menu = [NSMenu new];
    toggle = [menu addItemWithTitle:@"Play Sound" action:@selector(toggle:) keyEquivalent:@""];
    toggle.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Show Window" action:@selector(showWindow:) keyEquivalent:@""].target = self;
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
    statusLabel = windowLabel(@"", NSMakeRect(20, 146, 310, 26), [NSFont systemFontOfSize:18]);
    playButton = windowButton(@"Play", NSMakeRect(87, 84, 76, 42), self, @selector(play:));
    stopButton = windowButton(@"Stop", NSMakeRect(187, 84, 76, 42), self, @selector(stop:));
    [self.window.contentView addSubview:heading];
    [self.window.contentView addSubview:statusLabel];
    [self.window.contentView addSubview:playButton];
    [self.window.contentView addSubview:stopButton];

    NSDistributedNotificationCenter *distributed = NSDistributedNotificationCenter.defaultCenter;
    [distributed addObserver:self selector:@selector(locked:) name:@"com.apple.screenIsLocked"
        object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [distributed addObserver:self selector:@selector(unlocked:) name:@"com.apple.screenIsUnlocked"
        object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(woke:)
        name:NSWorkspaceDidWakeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(engineChanged:)
        name:AVAudioEngineConfigurationChangeNotification object:nil];

    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    routeListener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
        app_event(5);
    };
    OSStatus result = AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &address,
        dispatch_get_main_queue(), routeListener);
    if (result != noErr) NSLog(@"Default audio output monitoring unavailable: %d", (int)result);

    self.timer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
        app_event(6);
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    app_event(6);
}

- (void)toggle:(id)sender { app_event(currentState == 1 || currentState == 2 ? 1 : 0); }
- (void)play:(id)sender { if (currentState != 1 && currentState != 2) app_event(0); }
- (void)stop:(id)sender { if (currentState == 1 || currentState == 2) app_event(1); }
- (void)locked:(NSNotification *)note { dispatch_async(dispatch_get_main_queue(), ^{ app_event(2); }); }
- (void)unlocked:(NSNotification *)note { dispatch_async(dispatch_get_main_queue(), ^{ app_event(3); }); }
- (void)woke:(NSNotification *)note { dispatch_async(dispatch_get_main_queue(), ^{ app_event(4); }); }
- (void)engineChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{ if (note.object == engine) app_event(5); });
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
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &address,
        dispatch_get_main_queue(), routeListener);
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    app_event(7);
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
