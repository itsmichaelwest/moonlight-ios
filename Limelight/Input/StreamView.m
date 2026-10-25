//
//  StreamView.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamView.h"
#include <Limelight.h>
#import "DataManager.h"
#import "ControllerSupport.h"
#import "KeyboardSupport.h"
#import "RelativeTouchHandler.h"
#import "AbsoluteTouchHandler.h"
#import "KeyboardInputField.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>

static const double X1_MOUSE_SPEED_DIVISOR = 2.5;

// Space kept clear on each side of the hinge
static const CGFloat HINGE_CLEARANCE = 16;
#if !TARGET_OS_TV
static const CGFloat DECK_CORNER_RADIUS = 22;
static const int EASED_FADE_STOPS = 16;
static const int MASK_STOPS = 32;
// Eased fades of the deck, the reflection, and the cast light where they meet the gap at the hinge
static const CGFloat DECK_FEATHER = 48;
static const CGFloat REFLECTION_FEATHER = 56;
static const CGFloat LIGHT_FEATHER = 32;
// About 30 cm from the hinge, at roughly 6 points per millimeter
static const CGFloat EYE_DISTANCE = 1800;
// For slight folds, the eye's elevation above the lower panel as a fraction of the fold. A real eye
// would only see a reflection there from a grazing angle.
static const CGFloat SLIGHT_FOLD_EYE_ELEVATION = .6;
// Range over which the reflection hands over from the slight-fold view to the physical one
static const CGFloat EYE_CROSSOVER = 80;
static const NSTimeInterval REFLECTION_FADE_DURATION = .35;
// Time constants that smooth out steps in hinge readings and changes in the cast light
static const CFTimeInterval HINGE_EASING = .05;
static const CFTimeInterval LIGHT_EASING = .08;
static const CFTimeInterval LIGHT_SAMPLE_INTERVAL = 1.0 / 30;
// Light from the upper panel is sampled in vertical bands across the video
static const int LIGHT_BANDS = 8;
static const CGFloat REFLECTION_OPACITY = .7;
static const CGFloat LIGHT_OPACITY = .65;
// Distance at which the reflection falls to half strength, as a fraction of the reflected video's
// length, so it reaches farther as the reflection grows
static const CGFloat REFLECTION_HALF_DISTANCE = .3;
// Distances at which the cast light, and the backstop that keeps the far end of the deck black,
// fall to half strength, as fractions of the deck height
static const CGFloat LIGHT_HALF_DISTANCE = .14;
static const CGFloat DECK_LIGHT_HALF_DISTANCE = .4;
static const CGFloat REFLECTION_SAMPLE_WIDTH = 160;
static const CGFloat REFLECTION_BLUR_SIGMA = 4;

typedef struct {
    CGFloat colors[LIGHT_BANDS][3];
} LightSample;
#endif

@implementation StreamView {
#if !TARGET_OS_TV
    CALayer* reflectionClip;
    CALayer* reflectionImage;
    UIView* controlDeck;
    CAGradientLayer* controlDeckGradient;
    CGSize controlDeckMaskSize;
    BOOL hasControlDeckTint;
    BOOL isHingeFolded;
    BOOL isPreviewingHinge;
    BOOL isReflecting;
    BOOL isReflectionFadingOut;
    CGFloat hingeAngle;
    CGFloat targetHingeAngle;
    CGFloat reflectionStrength;
    CADisplayLink* reflectionLink;
    CALayer* reflectionLight;
    CAGradientLayer* reflectionLightGradient;
    CIContext* reflectionContext;
    dispatch_queue_t reflectionQueue;
    BOOL isRenderingReflection;
    CFTimeInterval lastLightSample;
    CGFloat lightColors[LIGHT_BANDS][3];
    CGFloat targetLightColors[LIGHT_BANDS][3];
#endif

    OnScreenControls* onScreenControls;
    
    KeyboardInputField* keyInputField;
    BOOL isInputingText;
    NSMutableSet* keysDown;
    
    float streamAspectRatio;
    BOOL hasOpenHinge;
    
    // iOS 13.4 mouse support
    NSInteger lastMouseButtonMask;
    float lastMouseX;
    float lastMouseY;
    CGPoint lastScrollTranslation;
    
    // Citrix X1 mouse support
    X1Mouse* x1mouse;
    double accumulatedMouseDeltaX;
    double accumulatedMouseDeltaY;
    
    UIResponder* touchHandler;
    
    id<UserInteractionDelegate> interactionDelegate;
    NSTimer* interactionTimer;
    BOOL hasUserInteracted;
    
    NSDictionary<NSString *, NSNumber *> *dictCodes;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    // Use the same aspect-fit rectangle as absolute mouse and touch input.
    CGRect videoRect = [self videoAreaRect];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.videoLayer.bounds = CGRectMake(0, 0, videoRect.size.width, videoRect.size.height);
    self.videoLayer.position = CGPointMake(CGRectGetMidX(videoRect), CGRectGetMidY(videoRect));
#if !TARGET_OS_TV
    // Round the video to match the control deck when the panels are separate
    CGFloat videoCornerRadius = [self usesSeparateControlArea] ? DECK_CORNER_RADIUS : 0;
    self.videoLayer.cornerRadius = videoCornerRadius;
    self.videoLayer.cornerCurve = kCACornerCurveContinuous;
    self.videoLayer.masksToBounds = videoCornerRadius > 0;
    [self layoutControlDeck];
    [self layoutReflection];
    [onScreenControls layoutControls];
#endif
    [CATransaction commit];
}

#if !TARGET_OS_TV
static NSArray<NSNumber*>* EasedFadeLocations(void) {
    NSMutableArray* locations = [[NSMutableArray alloc] init];
    for (int i = 0; i < EASED_FADE_STOPS; i++) {
        [locations addObject:@((CGFloat)i / (EASED_FADE_STOPS - 1))];
    }
    return locations;
}

static NSArray* EasedFadeColors(UIColor* color, CGFloat fromAlpha, CGFloat toAlpha) {
    NSMutableArray* colors = [[NSMutableArray alloc] init];
    for (NSNumber* location in EasedFadeLocations()) {
        CGFloat t = location.doubleValue;
        CGFloat eased = t * t * (3 - 2 * t);
        [colors addObject:(id)[color colorWithAlphaComponent:fromAlpha + (toAlpha - fromAlpha) * eased].CGColor];
    }
    return colors;
}

// Light reaching a point at the given distance from the hinge, falling off with the square of the
// distance. It halves at halfDistance and is scaled to reach zero at length.
static CGFloat LightFalloff(CGFloat distance, CGFloat halfDistance, CGFloat length) {
    CGFloat atLength = 1 / (1 + pow(length / halfDistance, 2));
    CGFloat light = 1 / (1 + pow(distance / halfDistance, 2));
    return MAX(0, (light - atLength) / (1 - atLength));
}

// A rounded card, eased in over feather from its top edge, then falling off with distance like
// light when halfDistance is set
static UIImage* CardMask(CGSize size, CGFloat feather, CGFloat halfDistance) {
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
        CGContextRef cg = context.CGContext;
        [UIColor.blackColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:DECK_CORNER_RADIUS] fill];
        if (feather <= 0 && halfDistance <= 0) {
            return;
        }

        NSMutableArray* colors = [[NSMutableArray alloc] init];
        CGFloat locations[MASK_STOPS];
        for (int i = 0; i < MASK_STOPS; i++) {
            locations[i] = (CGFloat)i / (MASK_STOPS - 1);
            CGFloat distance = locations[i] * size.height;
            CGFloat alpha = 1;
            if (feather > 0 && distance < feather) {
                CGFloat t = distance / feather;
                alpha *= t * t * (3 - 2 * t);
            }
            if (halfDistance > 0) {
                alpha *= LightFalloff(distance, halfDistance, size.height);
            }
            [colors addObject:(id)[UIColor colorWithWhite:0 alpha:alpha].CGColor];
        }
        CGContextSetBlendMode(cg, kCGBlendModeDestinationIn);
        CGGradientRef gradient = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)colors, locations);
        CGContextDrawLinearGradient(cg, gradient, CGPointZero, CGPointMake(0, size.height), 0);
        CGGradientRelease(gradient);
    }];
}

// The reflection comes in quickly at slight folds and levels off as the panels close: a steep
// ease-out over the fold, from zero when flat (pi radians) to one when closed
static CGFloat ReflectionStrength(CGFloat hingeAngle) {
    CGFloat fold = MIN(MAX((M_PI - hingeAngle) / M_PI, 0), 1);
    return 1 - pow(1 - fold, 10);
}

// The reflected corners of the video, clockwise from the top left, for an eye at eyeY along and
// eyeZ above the lower panel. The top of the video reflects farthest from the hinge.
static void ReflectedCorners(CGPoint corners[4], CGFloat width, CGFloat nearDistance, CGFloat farDistance,
                             CGFloat fold, CGFloat eyeY, CGFloat eyeZ);

// Where a point on the upper panel appears in the mirror of the lower panel. The point lies on the
// upper panel at x across and distance from the hinge. Results are x across and y away from the
// hinge on the lower panel, with the eye at eyeY along and eyeZ above the lower panel.
static CGPoint ReflectedPoint(CGFloat x, CGFloat distance, CGFloat fold, CGFloat eyeY, CGFloat eyeZ) {
    CGFloat pointY = -distance * cos(fold);
    CGFloat pointZ = distance * sin(fold);
    // The reflection is where the line from the eye to the mirror image of the point meets the panel
    CGFloat t = eyeZ / (eyeZ + pointZ);
    return CGPointMake(t * x, eyeY + t * (pointY - eyeY));
}

static void ReflectedCorners(CGPoint corners[4], CGFloat width, CGFloat nearDistance, CGFloat farDistance,
                             CGFloat fold, CGFloat eyeY, CGFloat eyeZ) {
    corners[0] = ReflectedPoint(-width / 2, farDistance, fold, eyeY, eyeZ);
    corners[1] = ReflectedPoint(width / 2, farDistance, fold, eyeY, eyeZ);
    corners[2] = ReflectedPoint(width / 2, nearDistance, fold, eyeY, eyeZ);
    corners[3] = ReflectedPoint(-width / 2, nearDistance, fold, eyeY, eyeZ);
}

// Maps a layer of the given size, anchored at its origin, onto a quadrilateral given clockwise
// from the top left corner (Heckbert's square-to-quad projective mapping)
static CATransform3D QuadTransform(CGSize size, const CGPoint corners[4]) {
    CGPoint p0 = corners[0], p1 = corners[1], p2 = corners[2], p3 = corners[3];
    CGFloat dx1 = p1.x - p2.x, dx2 = p3.x - p2.x, dx3 = p0.x - p1.x + p2.x - p3.x;
    CGFloat dy1 = p1.y - p2.y, dy2 = p3.y - p2.y, dy3 = p0.y - p1.y + p2.y - p3.y;
    CGFloat denominator = dx1 * dy2 - dx2 * dy1;
    CGFloat g = (dx3 * dy2 - dx2 * dy3) / denominator;
    CGFloat h = (dx1 * dy3 - dx3 * dy1) / denominator;
    CATransform3D transform = CATransform3DIdentity;
    transform.m11 = (p1.x - p0.x + g * p1.x) / size.width;
    transform.m12 = (p1.y - p0.y + g * p1.y) / size.width;
    transform.m14 = g / size.width;
    transform.m21 = (p3.x - p0.x + h * p3.x) / size.height;
    transform.m22 = (p3.y - p0.y + h * p3.y) / size.height;
    transform.m24 = h / size.height;
    transform.m41 = p0.x;
    transform.m42 = p0.y;
    return transform;
}

- (void)updateReflection {
    // The display link eases these values, so changes apply directly
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    reflectionImage.opacity = REFLECTION_OPACITY * reflectionStrength;
    reflectionLightGradient.opacity = LIGHT_OPACITY * reflectionStrength;
    NSMutableArray* colors = [[NSMutableArray alloc] init];
    for (int i = 0; i < LIGHT_BANDS; i++) {
        [colors addObject:(id)[UIColor colorWithRed:lightColors[i][0] green:lightColors[i][1] blue:lightColors[i][2] alpha:1].CGColor];
    }
    reflectionLightGradient.colors = colors;
    [self layoutReflection];
    [CATransaction commit];
}

- (void)startReflectionLink {
    if (reflectionLink != nil) {
        return;
    }
    reflectionLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(stepReflection:)];
    reflectionLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 120);
    [reflectionLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stopReflectionLink {
    // The display link retains this view until it is invalidated
    [reflectionLink invalidate];
    reflectionLink = nil;
}

- (void)willMoveToWindow:(UIWindow*)newWindow {
    [super willMoveToWindow:newWindow];
    if (newWindow == nil) {
        [self stopReflectionLink];
    }
}

- (void)stepReflection:(CADisplayLink*)link {
    // Ease toward the latest readings so the reflection moves smoothly without lagging behind
    CFTimeInterval interval = MIN(link.targetTimestamp - link.timestamp, .1);
    hingeAngle += (targetHingeAngle - hingeAngle) * (1 - exp(-interval / HINGE_EASING));
    reflectionStrength = ReflectionStrength(hingeAngle);
    CGFloat lightStep = 1 - exp(-interval / LIGHT_EASING);
    for (int i = 0; i < LIGHT_BANDS; i++) {
        for (int c = 0; c < 3; c++) {
            lightColors[i][c] += (targetLightColors[i][c] - lightColors[i][c]) * lightStep;
        }
    }
    [self renderReflectionWithTimestamp:link.timestamp];
    [self updateReflection];
}

// The reflection is a small, blurred copy of the frame on screen, and the cast light follows the
// colors along the bottom of that frame. A backdrop blur cannot be relied on to blur video, and
// this needs no second decoder. All of the work, including reading the frame, happens on a
// background queue, because the video's frames are pulled from the main thread and stalling it
// would back up the stream.
- (void)renderReflectionWithTimestamp:(CFTimeInterval)timestamp {
    if (@available(iOS 17.4, *)) {
        // The video layer stays hidden until its first frame arrives
        CALayer* videoLayer = self.videoLayer;
        if (isRenderingReflection || reflectionImage.hidden || videoLayer.hidden ||
            ![videoLayer isKindOfClass:AVSampleBufferDisplayLayer.class]) {
            return;
        }
        BOOL sampleLight = timestamp - lastLightSample >= LIGHT_SAMPLE_INTERVAL;
        if (sampleLight) {
            lastLightSample = timestamp;
        }
        isRenderingReflection = YES;
        AVSampleBufferVideoRenderer* renderer = ((AVSampleBufferDisplayLayer*)videoLayer).sampleBufferRenderer;
        __weak StreamView* weakSelf = self;
        dispatch_async(reflectionQueue, ^{
            CVPixelBufferRef pixelBuffer = [renderer copyDisplayedPixelBuffer];
            CGImageRef reflection = NULL;
            LightSample light = {{{0}}};
            BOOL hasLight = NO;
            if (pixelBuffer != NULL) {
                if (self->reflectionContext == nil) {
                    self->reflectionContext = [CIContext contextWithOptions:@{kCIContextCacheIntermediates: @NO}];
                }
                CIImage* image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
                reflection = [StreamView createReflectionFromImage:image context:self->reflectionContext];
                if (sampleLight) {
                    light = [StreamView lightFromImage:image context:self->reflectionContext];
                    hasLight = YES;
                }
                CVPixelBufferRelease(pixelBuffer);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                StreamView* strongSelf = weakSelf;
                if (strongSelf != nil) {
                    if (reflection != NULL) {
                        [CATransaction begin];
                        [CATransaction setDisableActions:YES];
                        strongSelf->reflectionImage.contents = (__bridge id)reflection;
                        [CATransaction commit];
                    }
                    if (hasLight) {
                        memcpy(strongSelf->targetLightColors, light.colors, sizeof(light.colors));
                    }
                    strongSelf->isRenderingReflection = NO;
                }
                CGImageRelease(reflection);
            });
        });
    }
}

+ (CGImageRef)createReflectionFromImage:(CIImage*)image context:(CIContext*)context CF_RETURNS_RETAINED {
    CIImage* small = [image imageByApplyingFilter:@"CILanczosScaleTransform" withInputParameters:@{
        kCIInputScaleKey: @(REFLECTION_SAMPLE_WIDTH / image.extent.size.width),
        kCIInputAspectRatioKey: @1,
    }];
    CGRect extent = CGRectIntegral(small.extent);
    CIImage* blurred = [[[small imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:REFLECTION_BLUR_SIGMA]
                        imageByCroppingToRect:extent];
    return [context createCGImage:blurred fromRect:extent];
}

// The upper panel lights the deck like a soft area light, colored across the deck by the bottom
// of the frame, which is nearest it
+ (LightSample)lightFromImage:(CIImage*)image context:(CIContext*)context {
    // Core Image's origin is the bottom left
    CGRect band = CGRectMake(CGRectGetMinX(image.extent), CGRectGetMinY(image.extent),
                             image.extent.size.width, image.extent.size.height * .4);
    CIImage* columns = [[image imageByCroppingToRect:band] imageByApplyingFilter:@"CIColumnAverage"
                                                             withInputParameters:@{kCIInputExtentKey: [CIVector vectorWithCGRect:band]}];
    size_t width = (size_t)band.size.width;
    NSMutableData* pixels = [NSMutableData dataWithLength:width * 4];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    [context render:columns toBitmap:pixels.mutableBytes rowBytes:width * 4
             bounds:CGRectMake(band.origin.x, 0, width, 1) format:kCIFormatRGBA8 colorSpace:colorSpace];
    CGColorSpaceRelease(colorSpace);

    LightSample sample = {{{0}}};
    const uint8_t* bytes = pixels.bytes;
    for (size_t x = 0; x < width; x++) {
        int bandIndex = (int)(x * LIGHT_BANDS / width);
        for (int c = 0; c < 3; c++) {
            sample.colors[bandIndex][c] += bytes[x * 4 + c] / 255.0 / (width / (CGFloat)LIGHT_BANDS);
        }
    }
    return sample;
}

- (void)layoutReflection {
    CALayer* reflection = reflectionImage;
    CGRect videoRect = [self videoAreaRect];
    // Nothing reflects when the panels are flat or fully closed
    CGFloat fold = M_PI - hingeAngle;
    reflection.hidden = !(isReflecting || isReflectionFadingOut) || fold < .01 || fold > M_PI - .01 || CGRectIsEmpty(videoRect);
    if (reflection.hidden) {
        return;
    }

    // Distances from the hinge along the upper panel, with the eye centered on the video
    CGFloat hinge = CGRectGetMidY(self.bounds);
    CGFloat nearDistance = hinge - CGRectGetMaxY(videoRect);
    CGFloat farDistance = hinge - CGRectGetMinY(videoRect);
    CGFloat width = videoRect.size.width;

    // Slight folds use a raised eye, so a reflection shows as soon as the panels start to close
    CGFloat elevation = SLIGHT_FOLD_EYE_ELEVATION * fold;
    CGPoint slight[4];
    ReflectedCorners(slight, width, nearDistance, farDistance, fold, EYE_DISTANCE * cos(elevation), EYE_DISTANCE * sin(elevation));

    // Deeper folds use a physical eye. Its angle from the lower panel's normal moves from grazing
    // to midway between the panels' normals by a right angle, so the reflection keeps growing as
    // the panels close.
    CGFloat grazing = fold < M_PI_2 ? 1 - fold / M_PI_2 : 0;
    CGFloat eyeAngle = fold / 2 + (M_PI_2 - fold / 2) * grazing;
    CGPoint physical[4];
    ReflectedCorners(physical, width, nearDistance, farDistance, fold, EYE_DISTANCE * sin(eyeAngle), EYE_DISTANCE * cos(eyeAngle));

    // Follow whichever view reflects farther, handing over smoothly where they meet
    CGFloat handover = MIN(MAX((physical[0].y - slight[0].y) / EYE_CROSSOVER + .5, 0), 1);
    handover = handover * handover * (3 - 2 * handover);
    CGPoint corners[4];
    for (int i = 0; i < 4; i++) {
        corners[i] = CGPointMake(slight[i].x + (physical[i].x - slight[i].x) * handover,
                                 slight[i].y + (physical[i].y - slight[i].y) * handover);
    }
    CGPoint origin = CGPointMake(CGRectGetMidX(videoRect) - CGRectGetMinX(reflectionClip.frame),
                                 hinge - CGRectGetMinY(reflectionClip.frame));
    for (int i = 0; i < 4; i++) {
        corners[i] = CGPointMake(origin.x + corners[i].x, origin.y + corners[i].y);
    }
    reflection.bounds = CGRectMake(0, 0, width, videoRect.size.height);
    reflection.mask.frame = reflection.bounds;
    reflection.transform = QuadTransform(videoRect.size, corners);
}

- (void)setupControlDeck {
    // The deck sits behind the controls on the lower panel, tinted with the controller color
    // near the hinge and easing off to black. The untinted glass theme has no deck.
    OnScreenControlsTheme* theme = [OnScreenControlsTheme savedTheme];
    hasControlDeckTint = theme.bodyColor != nil;
    CGFloat saturation = 0;
    [theme.bodyColor getHue:nil saturation:&saturation brightness:nil alpha:nil];
    controlDeck = [[UIView alloc] init];
    controlDeck.userInteractionEnabled = NO;
    controlDeck.layer.mask = [CALayer layer];
    controlDeckGradient = [CAGradientLayer layer];
    // Neutral shells need less tint than colored ones to look equally dim
    controlDeckGradient.colors = EasedFadeColors(theme.bodyColor ?: UIColor.clearColor, saturation < .1 ? .09 : .16, 0);
    controlDeckGradient.locations = EasedFadeLocations();
    [controlDeck.layer addSublayer:controlDeckGradient];

    // The reflection only shows on the deck, fading in from the gap at the hinge. The image is
    // small and blurred, and scaling it up to the reflected shape softens it further.
    reflectionQueue = dispatch_queue_create("com.moonlight-stream.reflection", DISPATCH_QUEUE_SERIAL);
    reflectionClip = [CALayer layer];
    reflectionClip.mask = [CALayer layer];
    reflectionClip.opacity = 0;
    reflectionClip.hidden = YES;
    reflectionImage = [CALayer layer];
    reflectionImage.anchorPoint = CGPointZero;
    reflectionImage.position = CGPointZero;
    reflectionImage.cornerRadius = DECK_CORNER_RADIUS;
    reflectionImage.cornerCurve = kCACornerCurveContinuous;
    reflectionImage.masksToBounds = YES;
    // Falls off along the reflected video from the edge nearest the hinge
    CAGradientLayer* reflectionFalloff = [CAGradientLayer layer];
    NSMutableArray* falloffColors = [[NSMutableArray alloc] init];
    NSMutableArray* falloffLocations = [[NSMutableArray alloc] init];
    for (int i = 0; i < MASK_STOPS; i++) {
        CGFloat location = (CGFloat)i / (MASK_STOPS - 1);
        [falloffLocations addObject:@(location)];
        // The top of the video reflects farthest from the hinge
        CGFloat alpha = LightFalloff(1 - location, REFLECTION_HALF_DISTANCE, 1);
        [falloffColors addObject:(id)[UIColor colorWithWhite:0 alpha:alpha].CGColor];
    }
    reflectionFalloff.colors = falloffColors;
    reflectionFalloff.locations = falloffLocations;
    reflectionImage.mask = reflectionFalloff;
    [reflectionClip addSublayer:reflectionImage];

    reflectionLight = [CALayer layer];
    reflectionLight.mask = [CALayer layer];
    reflectionLight.opacity = 0;
    reflectionLight.hidden = YES;
    reflectionLightGradient = [CAGradientLayer layer];
    reflectionLightGradient.startPoint = CGPointMake(0, .5);
    reflectionLightGradient.endPoint = CGPointMake(1, .5);
    [reflectionLight addSublayer:reflectionLightGradient];

    [self insertSubview:controlDeck atIndex:0];
    [self.layer insertSublayer:reflectionClip above:controlDeck.layer];
    [self.layer insertSublayer:reflectionLight above:reflectionClip];
}

// Fade the reflection and its light in or out rather than letting them pop
- (void)fadeReflection {
    BOOL visible = isReflecting;
    reflectionClip.hidden = NO;
    reflectionLight.hidden = NO;
    if (visible) {
        [self startReflectionLink];
    }

    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        // The device may have folded again while this faded out
        if (!self->isReflecting) {
            self->isReflectionFadingOut = NO;
            self->reflectionClip.hidden = YES;
            self->reflectionLight.hidden = YES;
            [self stopReflectionLink];
        }
    }];
    for (CALayer* layer in @[reflectionClip, reflectionLight]) {
        CABasicAnimation* fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(((CALayer*)layer.presentationLayer ?: layer).opacity);
        fade.toValue = @(visible ? 1 : 0);
        fade.duration = REFLECTION_FADE_DURATION;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [layer addAnimation:fade forKey:@"fade"];
        layer.opacity = visible ? 1 : 0;
    }
    [CATransaction commit];
}

- (void)layoutControlDeck {
    BOOL separate = [self usesSeparateControlArea];
    BOOL reflect = separate && isHingeFolded;
    if (reflect != isReflecting) {
        isReflecting = reflect;
        isReflectionFadingOut = !reflect;
        // Animate outside of layout, which runs with implicit animations disabled
        dispatch_async(dispatch_get_main_queue(), ^{
            [self fadeReflection];
        });
    }
    controlDeck.hidden = !separate || !hasControlDeckTint;
    if (!separate) {
        return;
    }

    CGRect deckFrame = [self controlDeckRect];
    controlDeck.frame = deckFrame;
    controlDeckGradient.frame = controlDeck.bounds;
    reflectionClip.frame = deckFrame;
    reflectionLight.frame = deckFrame;
    reflectionLightGradient.frame = reflectionLight.bounds;

    if (!CGSizeEqualToSize(controlDeckMaskSize, deckFrame.size) && !CGRectIsEmpty(deckFrame)) {
        controlDeckMaskSize = deckFrame.size;
        CGRect bounds = (CGRect){CGPointZero, deckFrame.size};
        controlDeck.layer.mask.frame = bounds;
        CGFloat height = deckFrame.size.height;
        controlDeck.layer.mask.contents = (id)CardMask(deckFrame.size, DECK_FEATHER, 0).CGImage;
        // The reflection and the cast light fade with distance from the hinge, so the deck stays
        // black away from it
        reflectionClip.mask.frame = bounds;
        reflectionClip.mask.contents = (id)CardMask(deckFrame.size, REFLECTION_FEATHER, height * DECK_LIGHT_HALF_DISTANCE).CGImage;
        reflectionLight.mask.frame = bounds;
        reflectionLight.mask.contents = (id)CardMask(deckFrame.size, LIGHT_FEATHER, height * LIGHT_HALF_DISTANCE).CGImage;
    }
}
#endif

#if DEBUG && !TARGET_OS_TV
- (void)setPreviewHingeAngle:(CGFloat)angle {
    isPreviewingHinge = YES;
    hasOpenHinge = YES;
    isHingeFolded = angle < M_PI - .01;
    targetHingeAngle = angle;
    if (reflectionLink == nil) {
        hingeAngle = angle;
        reflectionStrength = ReflectionStrength(angle);
        [self updateReflection];
    }
    [self setNeedsLayout];
}

- (void)setPreviewControlsLevel:(OnScreenControlsLevel)level {
    [onScreenControls setLevel:level];
    [self setNeedsLayout];
}
#endif

- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    [self setNeedsLayout];
}

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                  config:(StreamConfiguration*)streamConfig {
    self->interactionDelegate = interactionDelegate;
    self->streamAspectRatio = (float)streamConfig.width / (float)streamConfig.height;
    
    TemporarySettings* settings = [[[DataManager alloc] init] getSettings];
    
#if !TARGET_OS_TV
    hingeAngle = M_PI;
    targetHingeAngle = M_PI;
    [self setupControlDeck];
#endif

    keysDown = [[NSMutableSet alloc] init];
    keyInputField = [[KeyboardInputField alloc] initWithFrame:CGRectZero];
    [keyInputField setKeyboardType:UIKeyboardTypeDefault];
    [keyInputField setAutocorrectionType:UITextAutocorrectionTypeNo];
    [keyInputField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [keyInputField setSpellCheckingType:UITextSpellCheckingTypeNo];
    [self addSubview:keyInputField];
    
#if TARGET_OS_TV
    // tvOS requires RelativeTouchHandler to manage Apple Remote input
    self->touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
#else
    // iOS uses RelativeTouchHandler or AbsoluteTouchHandler depending on user preference
    if (settings.absoluteTouchMode) {
        self->touchHandler = [[AbsoluteTouchHandler alloc] initWithView:self];
    }
    else {
        self->touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
    }
    
#if __has_include(<UIKit/UIHingeInteraction.h>)
    if (@available(iOS 27.1, *)) {
        __weak StreamView* weakSelf = self;
        [self addInteraction:[[UIHingeInteraction alloc] initWithUpdateHandler:^(UIHingeInteraction* interaction, UIHingeInteractionUpdate* update) {
            StreamView* strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            if (strongSelf->isPreviewingHinge) {
                return;
            }
            BOOL open = update.hinge != nil && (update.hinge.status == UIHingeStatusPartiallyOpen || update.hinge.status == UIHingeStatusFullyOpen);
            BOOL folded = update.hinge != nil && update.hinge.status == UIHingeStatusPartiallyOpen;
            if (strongSelf->hasOpenHinge != open || strongSelf->isHingeFolded != folded) {
                strongSelf->hasOpenHinge = open;
                strongSelf->isHingeFolded = folded;
                [strongSelf setNeedsLayout];
            }
            // While the reflection shows, its display link eases toward the new angle
            strongSelf->targetHingeAngle = update.hinge != nil ? update.hinge.angle : M_PI;
            if (strongSelf->reflectionLink == nil) {
                strongSelf->hingeAngle = strongSelf->targetHingeAngle;
                strongSelf->reflectionStrength = ReflectionStrength(strongSelf->hingeAngle);
                [strongSelf updateReflection];
            }
        }]];
    }
#endif

    onScreenControls = [[OnScreenControls alloc] initWithView:self controllerSup:controllerSupport streamConfig:streamConfig];
    OnScreenControlsLevel level = (OnScreenControlsLevel)[settings.onscreenControls integerValue];
    if (settings.absoluteTouchMode) {
        Log(LOG_I, @"On-screen controls disabled in absolute touch mode");
        [onScreenControls setLevel:OnScreenControlsLevelOff];
    }
    else if (level == OnScreenControlsLevelAuto) {
        [controllerSupport initAutoOnScreenControlMode:onScreenControls];
    }
    else {
        Log(LOG_I, @"Setting manual on-screen controls level: %d", (int)level);
        [onScreenControls setLevel:level];
    }
    
    // It would be nice to just use GCMouse on iOS 14+ and the older API on iOS 13
    // but unfortunately that isn't possible today. GCMouse doesn't recognize many
    // mice correctly, but UIKit does. We will register for both and ignore UIKit
    // events if a GCMouse is connected.
    if (@available(iOS 13.4, *)) {
        [self addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
        
        UIPanGestureRecognizer *discreteMouseWheelRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mouseWheelMovedDiscrete:)];
        discreteMouseWheelRecognizer.maximumNumberOfTouches = 0;
        discreteMouseWheelRecognizer.allowedScrollTypesMask = UIScrollTypeMaskDiscrete;
        discreteMouseWheelRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [self addGestureRecognizer:discreteMouseWheelRecognizer];
        
        UIPanGestureRecognizer *continuousMouseWheelRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mouseWheelMovedContinuous:)];
        continuousMouseWheelRecognizer.maximumNumberOfTouches = 0;
        continuousMouseWheelRecognizer.allowedScrollTypesMask = UIScrollTypeMaskContinuous;
        continuousMouseWheelRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [self addGestureRecognizer:continuousMouseWheelRecognizer];
    }
    
#if defined(__IPHONE_16_1) || defined(__TVOS_16_1)
    if (@available(iOS 16.1, *)) {
        UIHoverGestureRecognizer *stylusHoverRecognizer = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(sendStylusHoverEvent:)];
        stylusHoverRecognizer.allowedTouchTypes = @[@(UITouchTypePencil)];
        [self addGestureRecognizer:stylusHoverRecognizer];
    }
#endif
#endif
    
    x1mouse = [[X1Mouse alloc] init];
    x1mouse.delegate = self;
    
    if (settings.btMouseSupport) {
        [x1mouse start];
    }
    
    // This is critical to ensure keyboard events are delivered to this
    // StreamView and not our parent UIView, especially on tvOS.
    [self becomeFirstResponder];
}

- (void)startInteractionTimer {
    // Restart user interaction tracking
    hasUserInteracted = NO;
    
    BOOL timerAlreadyRunning = interactionTimer != nil;
    
    // Start/restart the timer
    [interactionTimer invalidate];
    interactionTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                        target:self
                        selector:@selector(interactionTimerExpired:)
                        userInfo:nil
                        repeats:NO];
    
    // Notify the delegate if this was a new user interaction
    if (!timerAlreadyRunning) {
        [interactionDelegate userInteractionBegan];
    }
}

- (void)interactionTimerExpired:(NSTimer *)timer {
    if (!hasUserInteracted) {
        // User has finished touching the screen
        interactionTimer = nil;
        [interactionDelegate userInteractionEnded];
    }
    else {
        // User is still touching the screen. Restart the timer.
        [self startInteractionTimer];
    }
}

- (void) showOnScreenControls {
#if !TARGET_OS_TV
    [onScreenControls show];
#endif
}

- (OnScreenControlsLevel) getCurrentOscState {
    if (onScreenControls == nil) {
        return OnScreenControlsLevelOff;
    }
    else {
        return [onScreenControls getLevel];
    }
}

- (BOOL) usesSeparateControlArea {
    return hasOpenHinge && self.bounds.size.height > self.bounds.size.width &&
           [self getCurrentOscState] != OnScreenControlsLevelOff;
}

- (CGRect) videoAreaRect {
    if (streamAspectRatio <= 0) {
        return CGRectZero;
    }
    CGRect area = self.bounds;
    if ([self usesSeparateControlArea]) {
        area = UIEdgeInsetsInsetRect(area, self.safeAreaInsets);
        area.size.height = MAX(0, CGRectGetMidY(self.bounds) - HINGE_CLEARANCE - CGRectGetMinY(area));
    }
    CGSize size;
    if (area.size.width > area.size.height * streamAspectRatio) {
        size = CGSizeMake(area.size.height * streamAspectRatio, area.size.height);
    } else {
        size = CGSizeMake(area.size.width, area.size.width / streamAspectRatio);
    }
    return CGRectMake(CGRectGetMidX(area) - size.width / 2, CGRectGetMidY(area) - size.height / 2, size.width, size.height);
}

- (CGRect) controlDeckRect {
    // The video mirrored across the hinge
    CGRect videoRect = [self videoAreaRect];
    return CGRectMake(CGRectGetMinX(videoRect), CGRectGetMidY(self.bounds) * 2 - CGRectGetMaxY(videoRect),
                      videoRect.size.width, videoRect.size.height);
}

- (CGSize) getVideoAreaSize {
    return [self videoAreaRect].size;
}

- (CGPoint) adjustCoordinatesForVideoArea:(CGPoint)point {
    // These are now relative to the StreamView, however we need to scale them
    // further to make them relative to the actual video portion.
    CGRect videoRect = [self videoAreaRect];
    float x = point.x;
    float y = point.y;
    
    // For some reason, we don't seem to always get to the bounds of the window
    // so we'll subtract 1 pixel if we're to the left/below of the origin and
    // and add 1 pixel if we're to the right/above. It should be imperceptible
    // to the user but it will allow activation of gestures that require contact
    // with the edge of the screen (like Aero Snap).
    if (x < CGRectGetMidX(videoRect)) {
        x--;
    }
    else {
        x++;
    }
    if (y < CGRectGetMidY(videoRect)) {
        y--;
    }
    else {
        y++;
    }
    
    // This logic mimics what iOS does with AVLayerVideoGravityResizeAspect
    CGSize videoSize = videoRect.size;
    CGPoint videoOrigin = videoRect.origin;
    
    // Confine the cursor to the video region. We don't just discard events outside
    // the region because we won't always get one exactly when the mouse leaves the region.
    return CGPointMake(MIN(MAX(x, videoOrigin.x), videoOrigin.x + videoSize.width) - videoOrigin.x,
                       MIN(MAX(y, videoOrigin.y), videoOrigin.y + videoSize.height) - videoOrigin.y);
}

#if !TARGET_OS_TV

- (uint16_t)getRotationFromAzimuthAngle:(float)azimuthAngle {
    // iOS reports azimuth of 0 when the stylus is pointing west, but Moonlight expects
    // rotation of 0 to mean the stylus is pointing north. Rotate the azimuth angle
    // clockwise by 90 degrees to convert from iOS to Moonlight rotation conventions.
    int32_t rotationAngle = (azimuthAngle - M_PI_2) * (180.f / M_PI);
    if (rotationAngle < 0) {
        rotationAngle += 360;
    }
    return (uint16_t)rotationAngle;
}

- (uint8_t)getTiltFromAltitudeAngle:(float)altitudeAngle {
    // iOS reports an altitude of 0 when the stylus is parallel to the touch surface,
    // while Moonlight expects a tilt of 0 when the stylus is perpendicular to the surface.
    // Subtract the tilt angle from 90 to convert from iOS to Moonlight tilt conventions.
    uint8_t altitudeDegs = abs((int16_t)(altitudeAngle * (180.f / M_PI)));
    return 90 - MIN(90, altitudeDegs);
}

- (BOOL)sendStylusEvent:(UITouch*)event {
    uint8_t type;
    
    // Don't touch stylus events if the host doesn't support them. We want to pass
    // them as normal touches for legacy hosts that don't understand pen events.
    if (!(LiGetHostFeatureFlags() & LI_FF_PEN_TOUCH_EVENTS)) {
        return NO;
    }
    
    switch (event.phase) {
        case UITouchPhaseBegan:
            type = LI_TOUCH_EVENT_DOWN;
            break;
        case UITouchPhaseMoved:
            type = LI_TOUCH_EVENT_MOVE;
            break;
        case UITouchPhaseEnded:
            type = LI_TOUCH_EVENT_UP;
            break;
        case UITouchPhaseCancelled:
            type = LI_TOUCH_EVENT_CANCEL;
            break;
        default:
            return YES;
    }

    CGPoint location = [self adjustCoordinatesForVideoArea:[event locationInView:self]];
    CGSize videoSize = [self getVideoAreaSize];
    
    return LiSendPenEvent(type, LI_TOOL_TYPE_PEN, 0, location.x / videoSize.width, location.y / videoSize.height,
                          (event.force / event.maximumPossibleForce) / sin(event.altitudeAngle),
                          0.0f, 0.0f,
                          [self getRotationFromAzimuthAngle:[event azimuthAngleInView:self]],
                          [self getTiltFromAltitudeAngle:event.altitudeAngle]) != LI_ERR_UNSUPPORTED;
}

- (void)sendStylusHoverEvent:(UIHoverGestureRecognizer*)gesture API_AVAILABLE(ios(13.0)) {
    uint8_t type;
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            type = LI_TOUCH_EVENT_HOVER;
            break;

        case UIGestureRecognizerStateEnded:
            type = LI_TOUCH_EVENT_HOVER_LEAVE;
            break;

        default:
            return;
    }

    CGPoint location = [self adjustCoordinatesForVideoArea:[gesture locationInView:self]];
    CGSize videoSize = [self getVideoAreaSize];
    
    float distance = 0.0f;
#if defined(__IPHONE_16_1) || defined(__TVOS_16_1)
    if (@available(iOS 16.1, *)) {
        distance = gesture.zOffset;
    }
#endif
    
    uint16_t rotationAngle = LI_ROT_UNKNOWN;
    uint8_t tiltAngle = LI_TILT_UNKNOWN;
#if defined(__IPHONE_16_4) || defined(__TVOS_16_4)
    if (@available(iOS 16.4, *)) {
        rotationAngle = [self getRotationFromAzimuthAngle:[gesture azimuthAngleInView:self]];
        tiltAngle = [self getTiltFromAltitudeAngle:gesture.altitudeAngle];
    }
#endif
    
    LiSendPenEvent(type, LI_TOOL_TYPE_PEN, 0, location.x / videoSize.width, location.y / videoSize.height,
                   distance, 0.0f, 0.0f, rotationAngle, tiltAngle);
}

#endif

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self handleMouseButtonEvent:BUTTON_ACTION_PRESS
                          forTouches:touches
                           withEvent:event]) {
        // If it's a mouse event, we're done
        return;
    }
    
    Log(LOG_D, @"Touch down");
    
    // Notify of user interaction and start expiration timer
    [self startInteractionTimer];
    
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
    }
#endif
    
    if (![onScreenControls handleTouchDownEvent:touches]) {
        // We still inform the touch handler even if we're going trigger the
        // keyboard activation gesture. This is important to ensure the touch
        // handler has a consistent view of touch events to correctly suppress
        // activation of one or two finger gestures when a three finger gesture
        // is triggered.
        [touchHandler touchesBegan:touches withEvent:event];
        
        if ([[event allTouches] count] == 3) {
            if (isInputingText) {
                Log(LOG_D, @"Closing the keyboard");
                [keyInputField resignFirstResponder];
                isInputingText = false;
            } else {
                Log(LOG_D, @"Opening the keyboard");
                // Prepare the textbox used to capture keyboard events.
                keyInputField.delegate = self;
                keyInputField.text = @"0";
#if !TARGET_OS_TV
                // Prepare the toolbar above the keyboard for more options
                UIToolbar *customToolbarView = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, 44)];
                
                UIBarButtonItem *doneBarButton = [self createButtonWithImageNamed:@"DoneIcon.png" backgroundColor:[UIColor clearColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0x00 isToggleable:NO];
                UIBarButtonItem *windowsBarButton = [self createButtonWithImageNamed:@"WindowsIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0x5B isToggleable:YES];
                UIBarButtonItem *tabBarButton = [self createButtonWithImageNamed:@"TabIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0x09 isToggleable:NO];
                UIBarButtonItem *shiftBarButton = [self createButtonWithImageNamed:@"ShiftIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0xA0 isToggleable:YES];
                UIBarButtonItem *escapeBarButton = [self createButtonWithImageNamed:@"EscapeIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0x1B isToggleable:NO];
                UIBarButtonItem *controlBarButton = [self createButtonWithImageNamed:@"ControlIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0xA2 isToggleable:YES];
                UIBarButtonItem *altBarButton = [self createButtonWithImageNamed:@"AltIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0xA4 isToggleable:YES];
                UIBarButtonItem *deleteBarButton = [self createButtonWithImageNamed:@"DeleteIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0x2E isToggleable:NO];
                UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
                
                [customToolbarView setItems:[NSArray arrayWithObjects:doneBarButton, windowsBarButton, escapeBarButton, tabBarButton, shiftBarButton, controlBarButton, altBarButton, deleteBarButton, flexibleSpace, nil]];
                keyInputField.inputAccessoryView = customToolbarView;
#endif
                [keyInputField becomeFirstResponder];
                [keyInputField addTarget:self action:@selector(onKeyboardPressed:) forControlEvents:UIControlEventEditingChanged];
                
                // Undo causes issues for our state management, so turn it off
                [keyInputField.undoManager disableUndoRegistration];
                
                isInputingText = true;
            }
        }
    }
}

- (UIBarButtonItem *)createButtonWithImageNamed:(NSString *)imageName backgroundColor:(UIColor *)backgroundColor target:(id)target action:(SEL)action keyCode:(NSInteger)keyCode isToggleable:(BOOL)isToggleable {
    UIImage *image = [UIImage imageNamed:imageName];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:image forState:UIControlStateNormal];
    button.frame = CGRectMake(0, 0, 30, 30);
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.imageView.backgroundColor = backgroundColor;
    button.imageView.layer.cornerRadius = 10.0;
    button.imageEdgeInsets = UIEdgeInsetsMake(6, 6, 6, 6);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, "keyCode", @(keyCode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "isToggleable", @(isToggleable), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "isOn", @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIBarButtonItem *barButton = [[UIBarButtonItem alloc] initWithCustomView:button];
    return barButton;
}

- (void)toolbarButtonClicked:(UIButton *)sender {
    BOOL isToggleable = [objc_getAssociatedObject(sender, "isToggleable") boolValue];
    BOOL isOn = [objc_getAssociatedObject(sender, "isOn") boolValue];
    if (isToggleable){
        isOn = !isOn;
        // Update the button's appearance based on its new state
        if (isOn) {
            sender.imageView.backgroundColor = [UIColor lightGrayColor];
        } else {
            sender.imageView.backgroundColor = [UIColor blackColor];
        }
    }
    // Update the new on/off state of the button
    objc_setAssociatedObject(sender, "isOn", @(isOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Get the keyCode parameter and convert to short for key press event
    short keyCode = [objc_getAssociatedObject(sender, "keyCode") shortValue];
    // Close keyboard if done button clicked
    if (!keyCode) {
        [keyInputField resignFirstResponder];
        isInputingText = false;
    }
    else {
        // Send key press event using keyCode parameter, toggle if necessary
        if (isToggleable){
            if (isOn){
                LiSendKeyboardEvent(keyCode, KEY_ACTION_DOWN, 0);
                [keysDown addObject:@(keyCode)];
            } else {
                LiSendKeyboardEvent(keyCode, KEY_ACTION_UP, 0);
                [keysDown removeObject:@(keyCode)];
            }
        }
        else {
            LiSendKeyboardEvent(keyCode, KEY_ACTION_DOWN, 0);
            usleep(50 * 1000);
            LiSendKeyboardEvent(keyCode, KEY_ACTION_UP, 0);
        }
    }
}

- (BOOL)handleMouseButtonEvent:(int)buttonAction forTouches:(NSSet *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        UITouch* touch = [touches anyObject];
        if (touch.type == UITouchTypeIndirectPointer) {
            if (@available(iOS 14.0, *)) {
                if ([GCMouse current] != nil) {
                    // We'll handle this with GCMouse. Do nothing here.
                    return YES;
                }
            }
            
            UIEventButtonMask normalizedButtonMask;
            
            // iOS 14 includes the released button in the buttonMask for the release
            // event, while iOS 13 does not. Normalize that behavior here.
            if (@available(iOS 14.0, *)) {
                if (buttonAction == BUTTON_ACTION_RELEASE) {
                    normalizedButtonMask = lastMouseButtonMask & ~event.buttonMask;
                }
                else {
                    normalizedButtonMask = event.buttonMask;
                }
            }
            else {
                normalizedButtonMask = event.buttonMask;
            }
            
            UIEventButtonMask changedButtons = lastMouseButtonMask ^ normalizedButtonMask;
                        
            for (int i = BUTTON_LEFT; i <= BUTTON_X2; i++) {
                UIEventButtonMask buttonFlag;
                
                switch (i) {
                    // Right and Middle are reversed from what iOS uses
                    case BUTTON_RIGHT:
                        buttonFlag = UIEventButtonMaskForButtonNumber(2);
                        break;
                    case BUTTON_MIDDLE:
                        buttonFlag = UIEventButtonMaskForButtonNumber(3);
                        break;
                        
                    default:
                        buttonFlag = UIEventButtonMaskForButtonNumber(i);
                        break;
                }
                
                if (changedButtons & buttonFlag) {
                    LiSendMouseButtonEvent(buttonAction, i);
                }
            }
            
            lastMouseButtonMask = normalizedButtonMask;
            return YES;
        }
    }
#endif
    
    return NO;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
        
        UITouch *touch = [touches anyObject];
        if (touch.type == UITouchTypeIndirectPointer) {
            if (@available(iOS 14.0, *)) {
                if ([GCMouse current] != nil) {
                    // We'll handle this with GCMouse. Do nothing here.
                    return;
                }
            }
            
            // We must handle this event to properly support
            // drags while the middle, X1, or X2 mouse buttons are
            // held down. For some reason, left and right buttons
            // don't require this, but we do it anyway for them too.
            // Cursor movement without a button held down is handled
            // in pointerInteraction:regionForRequest:defaultRegion.
            [self updateCursorLocation:[touch locationInView:self] isMouse:YES];
            return;
        }
    }
#endif
    
    hasUserInteracted = YES;
    
    if (![onScreenControls handleTouchMovedEvent:touches]) {
        [touchHandler touchesMoved:touches withEvent:event];
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
            // For now, we'll treated it as handled if we handle at least one of the
            // UIPress events inside the set.
            if ([KeyboardSupport sendKeyEventForPress:press down:YES]) {
                // This will prevent the legacy UITextField from receiving the event
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesBegan:presses withEvent:event];
    }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
            // For now, we'll treated it as handled if we handle at least one of the
            // UIPress events inside the set.
            if ([KeyboardSupport sendKeyEventForPress:press down:NO]) {
                // This will prevent the legacy UITextField from receiving the event
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesEnded:presses withEvent:event];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self handleMouseButtonEvent:BUTTON_ACTION_RELEASE
                          forTouches:touches
                           withEvent:event]) {
        // If it's a mouse event, we're done
        return;
    }
    
    Log(LOG_D, @"Touch up");
    
    hasUserInteracted = YES;
    
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
    }
#endif
    
    if (![onScreenControls handleTouchUpEvent:touches]) {
        [touchHandler touchesEnded:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [onScreenControls handleTouchUpEvent:touches];
    [touchHandler touchesCancelled:touches withEvent:event];
    [self handleMouseButtonEvent:BUTTON_ACTION_RELEASE
                      forTouches:touches
                       withEvent:event];
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                [self sendStylusEvent:touch];
            }
        }
    }
#endif
}

#if !TARGET_OS_TV
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse {
    CGPoint normalizedLocation = [self adjustCoordinatesForVideoArea:location];
    CGSize videoSize = [self getVideoAreaSize];
    
    // Send the mouse position relative to the video region if it has changed
    // if we're receiving coordinates from a real mouse.
    //
    // NB: It is important for functionality (not just optimization) to only
    // send it if the value has changed. We will receive one of these events
    // any time the user presses a modifier key, which can result in errant
    // mouse motion when using a Citrix X1 mouse.
    if (normalizedLocation.x != lastMouseX || normalizedLocation.y != lastMouseY || !isMouse) {
        if (lastMouseX != 0 || lastMouseY != 0 || !isMouse) {
            LiSendMousePositionEvent(normalizedLocation.x, normalizedLocation.y, videoSize.width, videoSize.height);
        }
        
        if (isMouse) {
            lastMouseX = normalizedLocation.x;
            lastMouseY = normalizedLocation.y;
        }
    }
}

- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction
                       regionForRequest:(UIPointerRegionRequest *)request
                          defaultRegion:(UIPointerRegion *)defaultRegion API_AVAILABLE(ios(13.4)) {
    if (@available(iOS 14.0, *)) {
        if ([GCMouse current] != nil) {
            // We'll handle this with GCMouse. Do nothing here.
            return nil;
        }
    }
    
    CGRect videoRect = [self videoAreaRect];
    
    // Move the cursor on the host if no buttons are pressed.
    // Motion with buttons pressed in handled in touchesMoved:
    if (lastMouseButtonMask == 0) {
        [self updateCursorLocation:request.location isMouse:YES];
    }
    
    // The pointer interaction should cover the video region only
    return [UIPointerRegion regionWithRect:videoRect identifier:nil];
}

- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region  API_AVAILABLE(ios(13.4)) {
    // Always hide the mouse cursor over our stream view
    return [UIPointerStyle hiddenPointerStyle];
}

- (void)mouseWheelMovedContinuous:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            break;
        
        case UIGestureRecognizerStateEnded:
        default:
            // Ignore recognition failure and other states
            lastScrollTranslation = CGPointMake(0, 0);
            return;
    }
    
    CGPoint currentScrollTranslation = [gesture translationInView:self];
    const short translationMultiplier = 120 * 20; // WHEEL_DELTA * 20
    
    {
        short translationDeltaY = ((currentScrollTranslation.y - lastScrollTranslation.y) / self.bounds.size.height) * translationMultiplier;
        if (translationDeltaY != 0) {
            LiSendHighResScrollEvent(translationDeltaY);
            lastScrollTranslation = currentScrollTranslation;
        }
    }

    {
        short translationDeltaX = ((currentScrollTranslation.x - lastScrollTranslation.x) / self.bounds.size.width) * translationMultiplier;
        if (translationDeltaX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHighResHScrollEvent(-translationDeltaX);
            lastScrollTranslation = currentScrollTranslation;
        }
    }
}

- (void)mouseWheelMovedDiscrete:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            break;
        
        case UIGestureRecognizerStateEnded:
        default:
            // Ignore recognition failure and other states
            lastScrollTranslation = CGPointMake(0, 0);
            return;
    }
    
    // Using velocityInView is 0 for discrete scroll events
    // when scrolling very slowly, but translationInView does work.
    CGPoint currentScrollTranslation = [gesture translationInView:self];
    
    {
        short translationDeltaY = currentScrollTranslation.y - lastScrollTranslation.y;
        if (translationDeltaY != 0) {
            LiSendScrollEvent(translationDeltaY > 0 ? 1 : -1);
        }
    }

    {
        short translationDeltaX = currentScrollTranslation.x - lastScrollTranslation.x;
        if (translationDeltaX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHScrollEvent(translationDeltaX < 0 ? 1 : -1);
        }
    }
    
    lastScrollTranslation = currentScrollTranslation;
}

#endif

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (@available(iOS 13.0, *)) {
        // Disable the 3 finger tap gestures that trigger the copy/paste/undo toolbar on iOS 13+
        return gestureRecognizer.name == nil || ![gestureRecognizer.name hasPrefix:@"kbProductivity."];
    }
    else {
        return YES;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    // This method is called when the "Return" key is pressed.
    LiSendKeyboardEvent(0x0d, KEY_ACTION_DOWN, 0);
    usleep(50 * 1000);
    LiSendKeyboardEvent(0x0d, KEY_ACTION_UP, 0);
    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    for (NSNumber* keyCode in keysDown) {
        LiSendKeyboardEvent([keyCode shortValue], KEY_ACTION_UP, 0);
    }
    [keysDown removeAllObjects];
}

- (void)onKeyboardPressed:(UITextField *)textField {
    NSString* inputText = textField.text;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // If the text became empty, we know the user pressed the backspace key.
        if ([inputText isEqual:@""]) {
            LiSendKeyboardEvent(0x08, KEY_ACTION_DOWN, 0);
            usleep(50 * 1000);
            LiSendKeyboardEvent(0x08, KEY_ACTION_UP, 0);
        } else {
            // Character 0 will be our known sentinel value
            
            // Check if any characters exist which can't be represented in a basic key event
            for (int i = 1; i < [inputText length]; i++) {
                struct KeyEvent event = [KeyboardSupport translateKeyEvent:[inputText characterAtIndex:i] withModifierFlags:0];
                if (event.keycode == 0) {
                    // We found an unknown key, so send the entire string as UTF-8
                    const char* utf8String = [inputText UTF8String];
                    
                    // Skip the first character which is our sentinel
                    LiSendUtf8TextEvent(utf8String + 1, (int)strlen(utf8String) - 1);
                    return;
                }
            }
            
            // We didn't find any unknown characters, so send them all as basic key events
            for (int i = 1; i < [inputText length]; i++) {
                struct KeyEvent event = [KeyboardSupport translateKeyEvent:[inputText characterAtIndex:i] withModifierFlags:0];
                assert(event.keycode != 0);
                [self sendLowLevelEvent:event];
            }
        }
    });
    
    // Reset text field back to known state
    textField.text = @"0";
    
    // Move the insertion point back to the end of the text box
    UITextRange *textRange = [textField textRangeFromPosition:textField.endOfDocument toPosition:textField.endOfDocument];
    [textField setSelectedTextRange:textRange];
}

- (void)specialCharPressed:(UIKeyCommand *)cmd {
    struct KeyEvent event = [KeyboardSupport translateKeyEvent:0x20 withModifierFlags:[cmd modifierFlags]];
    event.keycode = [[dictCodes valueForKey:[cmd input]] intValue];
    [self sendLowLevelEvent:event];
}

- (void)keyPressed:(UIKeyCommand *)cmd {
    struct KeyEvent event = [KeyboardSupport translateKeyEvent:[[cmd input] characterAtIndex:0] withModifierFlags:[cmd modifierFlags]];
    [self sendLowLevelEvent:event];
}

- (void)sendLowLevelEvent:(struct KeyEvent)event {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // When we want to send a modified key (like uppercase letters) we need to send the
        // modifier ("shift") seperately from the key itself.
        if (event.modifier != 0) {
            LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_DOWN, event.modifier);
        }
        // Let the host know these are not (necessarily) normalized to US English scancodes
        LiSendKeyboardEvent2(event.keycode, KEY_ACTION_DOWN, event.modifier, SS_KBE_FLAG_NON_NORMALIZED);
        usleep(50 * 1000);
        LiSendKeyboardEvent2(event.keycode, KEY_ACTION_UP, event.modifier, SS_KBE_FLAG_NON_NORMALIZED);
        if (event.modifier != 0) {
            LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_UP, event.modifier);
        }
    });
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (NSArray<UIKeyCommand *> *)keyCommands
{
    NSString *charset = @"qwertyuiopasdfghjklzxcvbnm1234567890\t§[]\\'\"/.,`<>-´ç+`¡'º;ñ= ";
    
    NSMutableArray<UIKeyCommand *> * commands = [NSMutableArray<UIKeyCommand *> array];
    dictCodes = [[NSDictionary alloc] initWithObjectsAndKeys: [NSNumber numberWithInt: 0x0d], @"\r", [NSNumber numberWithInt: 0x08], @"\b", [NSNumber numberWithInt: 0x1b], UIKeyInputEscape, [NSNumber numberWithInt: 0x28], UIKeyInputDownArrow, [NSNumber numberWithInt: 0x26], UIKeyInputUpArrow, [NSNumber numberWithInt: 0x25], UIKeyInputLeftArrow, [NSNumber numberWithInt: 0x27], UIKeyInputRightArrow, nil];
    
    [charset enumerateSubstringsInRange:NSMakeRange(0, charset.length)
                                options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:0 action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierShift action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierControl action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierAlternate action:@selector(keyPressed:)]];
                             }];
    
    for (NSString *c in [dictCodes keyEnumerator]) {
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:0
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift | UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift | UIKeyModifierControl
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierControl
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierControl | UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
    }
    
    return commands;
}

- (void)connectedStateDidChangeWithIdentifier:(NSUUID * _Nonnull)identifier isConnected:(BOOL)isConnected {
    NSLog(@"Citrix X1 mouse state change: %@ -> %s",
          identifier, isConnected ? "connected" : "disconnected");
}

- (void)mouseDidMoveWithIdentifier:(NSUUID * _Nonnull)identifier deltaX:(int16_t)deltaX deltaY:(int16_t)deltaY {
    accumulatedMouseDeltaX += deltaX / X1_MOUSE_SPEED_DIVISOR;
    accumulatedMouseDeltaY += deltaY / X1_MOUSE_SPEED_DIVISOR;
    
    short shortX = (short)accumulatedMouseDeltaX;
    short shortY = (short)accumulatedMouseDeltaY;
    
    if (shortX == 0 && shortY == 0) {
        return;
    }
    
    LiSendMouseMoveEvent(shortX, shortY);
    
    accumulatedMouseDeltaX -= shortX;
    accumulatedMouseDeltaY -= shortY;
}

- (int) buttonFromX1ButtonCode:(enum X1MouseButton)button {
    switch (button) {
        case X1MouseButtonLeft:
            return BUTTON_LEFT;
        case X1MouseButtonRight:
            return BUTTON_RIGHT;
        case X1MouseButtonMiddle:
            return BUTTON_MIDDLE;
        default:
            return -1;
    }
}

- (void)mouseDownWithIdentifier:(NSUUID * _Nonnull)identifier button:(enum X1MouseButton)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, [self buttonFromX1ButtonCode:button]);
}

- (void)mouseUpWithIdentifier:(NSUUID * _Nonnull)identifier button:(enum X1MouseButton)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, [self buttonFromX1ButtonCode:button]);
}

- (void)wheelDidScrollWithIdentifier:(NSUUID * _Nonnull)identifier deltaZ:(int8_t)deltaZ {
    LiSendScrollEvent(deltaZ);
}

#if !TARGET_OS_TV
- (BOOL)isMultipleTouchEnabled {
    return YES;
}
#endif

@end
