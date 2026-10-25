//
//  ControlsPreviewViewController.m
//  Moonlight
//
//  Copyright © 2026 Moonlight Stream. All rights reserved.
//

#import "ControlsPreviewViewController.h"

#if DEBUG && !TARGET_OS_TV

#import "StreamView.h"
#import "ControllerSupport.h"
#import "Controller.h"
#import "DataManager.h"
#include "Limelight.h"

@import AVFoundation;

// The iPhone Duo stream resolution, at half size for the test pattern
static const int PREVIEW_WIDTH = 2034;
static const int PREVIEW_HEIGHT = 1398;
static const size_t PATTERN_WIDTH = PREVIEW_WIDTH / 2;
static const size_t PATTERN_HEIGHT = PREVIEW_HEIGHT / 2;

@interface ControlsPreviewViewController () <ControllerSupportDelegate, UserInteractionDelegate>
@end

@implementation ControlsPreviewViewController {
    ControllerSupport* _controllerSupport;
    StreamView* _streamView;
    AVSampleBufferDisplayLayer* _videoLayer;
    CVPixelBufferPoolRef _patternPool;
    CMVideoFormatDescriptionRef _patternFormat;
    CADisplayLink* _displayLink;
    CFTimeInterval _startTime;
    UILabel* _hingeLabel;
    UISlider* _hingeSlider;
    UILabel* _inputLabel;
}

static UIWindow* previewWindow;

+ (void)showInScene:(UIWindowScene*)scene {
    if (previewWindow != nil) {
        return;
    }
    previewWindow = [[UIWindow alloc] initWithWindowScene:scene];
    previewWindow.windowLevel = UIWindowLevelNormal + 1;
    previewWindow.rootViewController = [[ControlsPreviewViewController alloc] init];
    [previewWindow makeKeyAndVisible];
}

- (void)dealloc {
    CVPixelBufferPoolRelease(_patternPool);
    if (_patternFormat != NULL) {
        CFRelease(_patternFormat);
    }
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    StreamConfiguration* config = [[StreamConfiguration alloc] init];
    config.width = PREVIEW_WIDTH;
    config.height = PREVIEW_HEIGHT;
    config.frameRate = 120;
    config.swapABXYButtons = [[[DataManager alloc] init] getSettings].swapABXYButtons;

    _controllerSupport = [[ControllerSupport alloc] initWithConfig:config delegate:self];
    _streamView = [[StreamView alloc] initWithFrame:self.view.bounds];
    _streamView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_streamView];
    [_streamView setupStreamView:_controllerSupport interactionDelegate:self config:config];

    _videoLayer = [[AVSampleBufferDisplayLayer alloc] init];
    _videoLayer.videoGravity = AVLayerVideoGravityResize;
    _videoLayer.backgroundColor = UIColor.blackColor.CGColor;
    [_streamView.layer insertSublayer:_videoLayer atIndex:0];
    _streamView.videoLayer = _videoLayer;

    [_streamView setPreviewControlsLevel:OnScreenControlsLevelFull];
    [_streamView showOnScreenControls];
    [_streamView setPreviewHingeAngle:M_PI];

    [self addPanel];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _startTime = CACurrentMediaTime();
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

#pragma mark - Panel

- (void)addPanel {
    UIVisualEffectView* panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    panel.layer.cornerRadius = 18;
    panel.layer.cornerCurve = kCACornerCurveContinuous;
    panel.clipsToBounds = YES;
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:panel];

    UILabel* title = [[UILabel alloc] init];
    title.text = @"Controls Preview";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.textColor = UIColor.whiteColor;

    UIButton* close = [UIButton buttonWithType:UIButtonTypeClose];
    [close addTarget:self action:@selector(close) forControlEvents:UIControlEventPrimaryActionTriggered];
    [close setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView* header = [[UIStackView alloc] initWithArrangedSubviews:@[title, close]];
    header.alignment = UIStackViewAlignmentCenter;

    _hingeLabel = [[UILabel alloc] init];
    _hingeLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
    _hingeLabel.textColor = UIColor.secondaryLabelColor;

    // 180 degrees is flat, and smaller angles fold the device
    _hingeSlider = [[UISlider alloc] init];
    _hingeSlider.minimumValue = 30;
    _hingeSlider.maximumValue = 180;
    _hingeSlider.value = 180;
    [_hingeSlider addTarget:self action:@selector(hingeChanged) forControlEvents:UIControlEventValueChanged];

    _inputLabel = [[UILabel alloc] init];
    _inputLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    _inputLabel.textColor = UIColor.whiteColor;
    _inputLabel.numberOfLines = 2;

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[header, _hingeLabel, _hingeSlider, _inputLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel.contentView addSubview:stack];

    UILayoutGuide* safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [panel.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:12],
        [panel.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:12],
        [panel.widthAnchor constraintLessThanOrEqualToConstant:360],
        [panel.trailingAnchor constraintLessThanOrEqualToAnchor:safeArea.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:panel.contentView.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-12],
    ]];
    [self hingeChanged];
}

- (void)hingeChanged {
    float degrees = roundf(_hingeSlider.value);
    _hingeLabel.text = degrees >= 180 ? @"Hinge: 180° (flat)" : [NSString stringWithFormat:@"Hinge: %.0f°", degrees];
    [_streamView setPreviewHingeAngle:degrees * M_PI / 180];
}

- (void)close {
    [_displayLink invalidate];
    _displayLink = nil;
    [_controllerSupport cleanup];
    previewWindow.hidden = YES;
    previewWindow = nil;
}

#pragma mark - Test pattern and input readout

- (void)tick:(CADisplayLink*)link {
    [self enqueuePatternAtTime:link.timestamp - _startTime];
    [self updateInputLabel];
}

// Color bars, a grid, and a sweeping band, so the reflection and its light visibly change
- (void)enqueuePatternAtTime:(CFTimeInterval)time {
    if (_patternPool == NULL) {
        NSDictionary* attributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @(PATTERN_WIDTH),
            (id)kCVPixelBufferHeightKey: @(PATTERN_HEIGHT),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        };
        CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attributes, &_patternPool);
    }
    CVPixelBufferRef pixelBuffer = NULL;
    if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _patternPool, &pixelBuffer) != kCVReturnSuccess) {
        return;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer), PATTERN_WIDTH, PATTERN_HEIGHT, 8,
                                                 CVPixelBufferGetBytesPerRow(pixelBuffer), colorSpace,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);
    // Draw with the origin at the top left, as on screen
    CGContextTranslateCTM(context, 0, PATTERN_HEIGHT);
    CGContextScaleCTM(context, 1, -1);

    CGFloat width = PATTERN_WIDTH, height = PATTERN_HEIGHT;
    CGContextSetRGBFillColor(context, .04, .07, .16, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));

    CGContextSetRGBStrokeColor(context, 1, 1, 1, .12);
    CGContextSetLineWidth(context, 1);
    for (CGFloat x = 0; x <= width; x += width / 12) {
        CGContextMoveToPoint(context, x, 0);
        CGContextAddLineToPoint(context, x, height);
    }
    for (CGFloat y = 0; y <= height; y += height / 8) {
        CGContextMoveToPoint(context, 0, y);
        CGContextAddLineToPoint(context, width, y);
    }
    CGContextStrokePath(context);

    // A band sweeping across the middle
    CGFloat bandX = fmod(time * width / 4, width + 160) - 160;
    CGContextSetRGBFillColor(context, .35, .6, 1, .9);
    CGContextFillRect(context, CGRectMake(bandX, height * .3, 160, height * .3));

    // Color bars along the bottom, nearest the hinge, cycling slowly
    NSArray<UIColor*>* bars = @[UIColor.systemRedColor, UIColor.systemOrangeColor, UIColor.systemYellowColor,
                                UIColor.systemGreenColor, UIColor.systemTealColor, UIColor.systemBlueColor,
                                UIColor.systemIndigoColor, UIColor.systemPinkColor];
    int shift = (int)(time / 1.5);
    CGFloat barWidth = width / bars.count;
    for (NSUInteger i = 0; i < bars.count; i++) {
        CGContextSetFillColorWithColor(context, bars[(i + shift) % bars.count].CGColor);
        CGContextFillRect(context, CGRectMake(i * barWidth, height * .8, barWidth, height * .2));
    }

    UIGraphicsPushContext(context);
    NSDictionary* attributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:44 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: UIColor.whiteColor,
    };
    [@"Controls Preview" drawAtPoint:CGPointMake(40, height * .12) withAttributes:attributes];
    UIGraphicsPopContext();
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    if (_patternFormat == NULL) {
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &_patternFormat);
    }
    CMSampleTimingInfo timing = {kCMTimeInvalid, CMTimeMakeWithSeconds(time, 1000000), kCMTimeInvalid};
    CMSampleBufferRef sampleBuffer = NULL;
    if (CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixelBuffer, _patternFormat, &timing, &sampleBuffer) == noErr) {
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        CFMutableDictionaryRef attachment = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(attachment, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        [_videoLayer enqueueSampleBuffer:sampleBuffer];
        CFRelease(sampleBuffer);
    }
    CVPixelBufferRelease(pixelBuffer);
}

- (void)updateInputLabel {
    Controller* controller = [_controllerSupport getOscController];
    int flags = controller.lastButtonFlags;
    struct { int flag; const char* name; } names[] = {
        {A_FLAG, "A"}, {B_FLAG, "B"}, {X_FLAG, "X"}, {Y_FLAG, "Y"},
        {UP_FLAG, "Up"}, {DOWN_FLAG, "Down"}, {LEFT_FLAG, "Left"}, {RIGHT_FLAG, "Right"},
        {LB_FLAG, "LB"}, {RB_FLAG, "RB"}, {LS_CLK_FLAG, "LS"}, {RS_CLK_FLAG, "RS"},
        {BACK_FLAG, "View"}, {PLAY_FLAG, "Menu"}, {SPECIAL_FLAG, "Xbox"},
    };
    NSMutableArray* pressed = [[NSMutableArray alloc] init];
    for (size_t i = 0; i < sizeof(names) / sizeof(*names); i++) {
        if (flags & names[i].flag) {
            [pressed addObject:@(names[i].name)];
        }
    }
    if (controller.lastLeftTrigger) [pressed addObject:@"LT"];
    if (controller.lastRightTrigger) [pressed addObject:@"RT"];
    _inputLabel.text = [NSString stringWithFormat:@"Pressed: %@\nLS %+.2f %+.2f   RS %+.2f %+.2f",
                        pressed.count ? [pressed componentsJoinedByString:@" "] : @"—",
                        controller.lastLeftStickX / 32766.0, controller.lastLeftStickY / 32766.0,
                        controller.lastRightStickX / 32766.0, controller.lastRightStickY / 32766.0];
}

#pragma mark - ControllerSupportDelegate and UserInteractionDelegate

- (void)gamepadPresenceChanged {}
- (void)mousePresenceChanged {}
- (void)streamExitRequested {}
- (void)userInteractionBegan {}
- (void)userInteractionEnded {}

@end

#endif
