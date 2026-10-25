//
//  OnScreenControls.m
//  Moonlight
//
//  Created by Diego Waxemberg on 12/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "OnScreenControls.h"
#import "StreamView.h"
#import "ControllerSupport.h"
#import "Controller.h"
#include "Limelight.h"

#define UPDATE_BUTTON(x, y) (buttonFlags = \
(y) ? (buttonFlags | (x)) : (buttonFlags & ~(x)))

static UIColor* ColorFromHex(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.f
                           green:((hex >> 8) & 0xFF) / 255.f
                            blue:(hex & 0xFF) / 255.f
                           alpha:1.f];
}

static NSString* const OnScreenControlsThemeKey = @"onscreenControlsTheme";
static NSString* const OnScreenControlsLayoutKey = @"onscreenControlsLayout";
static NSString* const OnScreenControlsStickCompensationKey = @"onscreenControlsStickCompensation";
static NSString* const OnScreenControlsRightStickPedalsKey = @"onscreenControlsRightStickPedals";

@implementation OnScreenControlsTheme

- (instancetype)initWithIdentifier:(NSString*)identifier name:(NSString*)name
                              body:(UIColor*)body bodyGlyph:(UIColor*)bodyGlyph
                               cap:(UIColor*)cap legends:(NSArray<UIColor*>*)legends
                             stick:(UIColor*)stick
                             guide:(UIColor*)guide guideGlyph:(UIColor*)guideGlyph {
    self = [super init];
    _identifier = identifier;
    _name = name;
    _bodyColor = body;
    _bodyGlyphColor = bodyGlyph;
    _capColor = cap;
    _legendColors = legends;
    _stickColor = stick;
    _guideColor = guide;
    _guideGlyphColor = guideGlyph;
    return self;
}

+ (NSArray<OnScreenControlsTheme*>*) themes {
    static NSArray<OnScreenControlsTheme*>* themes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Colors are sampled from Xbox Wireless Controller product photos. Every
        // colorway pairs its shell with glossy black face buttons and D-pad.
        UIColor* cap = ColorFromHex(0x141414);
        UIColor* white = ColorFromHex(0xF5F7FC);
        UIColor* dark = ColorFromHex(0x1E1E1E);
        NSArray* xboxLegends = @[ColorFromHex(0x68C44A), ColorFromHex(0xE0282B), ColorFromHex(0x07B0F6), ColorFromHex(0xF5E10A)];
        // Colored shells use tonal legends, lightened here to stay legible on black caps.
        NSArray* (^tonal)(uint32_t) = ^(uint32_t hex) {
            UIColor* color = ColorFromHex(hex);
            return @[color, color, color, color];
        };
        themes = @[
            [[self alloc] initWithIdentifier:@"glass" name:@"Glass"
                                        body:nil bodyGlyph:UIColor.whiteColor
                                         cap:nil legends:@[UIColor.whiteColor, UIColor.whiteColor, UIColor.whiteColor, UIColor.whiteColor]
                                       stick:[UIColor colorWithWhite:1 alpha:.9]
                                       guide:nil guideGlyph:UIColor.whiteColor],
            [[self alloc] initWithIdentifier:@"graphite" name:@"Graphite"
                                        body:ColorFromHex(0x434343) bodyGlyph:ColorFromHex(0xC8C8C8)
                                         cap:cap legends:xboxLegends
                                       stick:ColorFromHex(0x2A2A2A)
                                       guide:white guideGlyph:ColorFromHex(0x434343)],
            [[self alloc] initWithIdentifier:@"arctic" name:@"Arctic"
                                        body:white bodyGlyph:ColorFromHex(0x6E7179)
                                         cap:cap legends:xboxLegends
                                       stick:dark
                                       guide:ColorFromHex(0x1A1B23) guideGlyph:UIColor.whiteColor],
            [[self alloc] initWithIdentifier:@"cobalt" name:@"Cobalt"
                                        body:ColorFromHex(0x2A5299) bodyGlyph:UIColor.whiteColor
                                         cap:cap legends:tonal(0x5A8FE6)
                                       stick:ColorFromHex(0x2A55A0)
                                       guide:white guideGlyph:ColorFromHex(0x2A5299)],
            [[self alloc] initWithIdentifier:@"crimson" name:@"Crimson"
                                        body:ColorFromHex(0xD11A14) bodyGlyph:UIColor.whiteColor
                                         cap:cap legends:tonal(0xF6454D)
                                       stick:ColorFromHex(0xD02A2B)
                                       guide:white guideGlyph:ColorFromHex(0xD11A14)],
            [[self alloc] initWithIdentifier:@"neonLime" name:@"Neon Lime"
                                        body:ColorFromHex(0xC5E20A) bodyGlyph:dark
                                         cap:cap legends:tonal(0xD6F04F)
                                       stick:ColorFromHex(0xC4E000)
                                       guide:white guideGlyph:ColorFromHex(0x7E9400)],
            [[self alloc] initWithIdentifier:@"fuchsia" name:@"Fuchsia"
                                        body:ColorFromHex(0xD84C7B) bodyGlyph:UIColor.whiteColor
                                         cap:cap legends:tonal(0xF06A98)
                                       stick:ColorFromHex(0xD74A78)
                                       guide:white guideGlyph:ColorFromHex(0xD84C7B)],
            [[self alloc] initWithIdentifier:@"emerald" name:@"Emerald"
                                        body:ColorFromHex(0x4FC858) bodyGlyph:dark
                                         cap:cap legends:tonal(0x3FD86A)
                                       stick:ColorFromHex(0x51CB58)
                                       guide:white guideGlyph:ColorFromHex(0x2E9A38)],
            [[self alloc] initWithIdentifier:@"amethyst" name:@"Amethyst"
                                        body:ColorFromHex(0x563E6A) bodyGlyph:UIColor.whiteColor
                                         cap:cap legends:tonal(0x9B7BC0)
                                       stick:ColorFromHex(0x563F6A)
                                       guide:white guideGlyph:ColorFromHex(0x563E6A)],
        ];
    });
    return themes;
}

+ (OnScreenControlsTheme*) savedTheme {
    NSString* identifier = [[NSUserDefaults standardUserDefaults] stringForKey:OnScreenControlsThemeKey];
    for (OnScreenControlsTheme* theme in [self themes]) {
        if ([theme.identifier isEqualToString:identifier]) {
            return theme;
        }
    }
    return [self themes].firstObject;
}

+ (void) saveTheme:(OnScreenControlsTheme*)theme {
    [[NSUserDefaults standardUserDefaults] setObject:theme.identifier forKey:OnScreenControlsThemeKey];
}

@end

@interface GamepadButton : UIButton
@property(nonatomic, weak) UIView* streamInputView;
@property(nonatomic, copy) NSString* legendTitle;
@property(nonatomic, copy) NSString* legendSymbol;
@property(nonatomic) UIColor* legendTint;
@property(nonatomic) UIColor* legendColor;
@property(nonatomic) BOOL isTrigger;
@property(nonatomic) CGSize styledSize;
@end

@implementation GamepadButton
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [super touchesBegan:touches withEvent:event];
    [self.streamInputView touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [super touchesMoved:touches withEvent:event];
    [self.streamInputView touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [super touchesEnded:touches withEvent:event];
    [self.streamInputView touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [super touchesCancelled:touches withEvent:event];
    [self.streamInputView touchesCancelled:touches withEvent:event];
}
@end

@interface GamepadDirectionGroup : UIVisualEffectView
@end

@implementation GamepadDirectionGroup
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    for (UIView* ancestor = hit; ancestor != nil && ancestor != self; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:GamepadButton.class]) {
            return hit;
        }
    }
    return nil;
}
@end

static const NSInteger StickWellTag = 1;
static const NSInteger StickCapTag = 2;

@implementation OnScreenControls {
    OnScreenControlsTheme* _theme;
    OnScreenControlsLayout _layout;
    NSMapTable<CALayer*, UIView*>* _controlViews;
    GamepadDirectionGroup* _directionGroup;
    UIView* _dpadVerticalBar;
    UIView* _dpadHorizontalBar;
    CALayer* _aButton;
    CALayer* _bButton;
    CALayer* _xButton;
    CALayer* _yButton;
    CALayer* _upButton;
    CALayer* _downButton;
    CALayer* _leftButton;
    CALayer* _rightButton;
    CALayer* _leftStickBackground;
    CALayer* _leftStick;
    CALayer* _rightStickBackground;
    CALayer* _rightStick;
    CALayer* _startButton;
    CALayer* _selectButton;
    CALayer* _guideButton;
    CALayer* _r1Button;
    CALayer* _r2Button;
    CALayer* _r3Button;
    CALayer* _l1Button;
    CALayer* _l2Button;
    CALayer* _l3Button;

    UITouch* _aTouch;
    UITouch* _bTouch;
    UITouch* _xTouch;
    UITouch* _yTouch;
    UITouch* _dpadTouch;
    int _dpadFlags;
    UITouch* _lsTouch;
    UITouch* _rsTouch;
    CGPoint _lsOrigin;
    CGPoint _rsOrigin;
    CGFloat _stickCompensation;
    BOOL _rightStickPedals;
    UITouch* _startTouch;
    UITouch* _selectTouch;
    UITouch* _guideTouch;
    UITouch* _r1Touch;
    UITouch* _r2Touch;
    UITouch* _r3Touch;
    UITouch* _l1Touch;
    UITouch* _l2Touch;
    UITouch* _l3Touch;

    NSDate* l3TouchStart;
    NSDate* r3TouchStart;

    BOOL l3Set;
    BOOL r3Set;

    CGRect _separateControlArea;
    CGRect _controlArea;
    UIView* _view;
    OnScreenControlsLevel _level;
    BOOL _visible;
    CADisplayLink* _touchRateLink;

    ControllerSupport *_controllerSupport;
    Controller *_controller;
    NSMutableArray* _deadTouches;
    BOOL _swapABXY;
}

typedef struct {
    float faceButton;
    // From the center of the face buttons to the inner edge of each button
    float buttonDist;
    float dpadArmWidth;
    float dpadReach;
    CGSize bumper;
    CGSize trigger;
    float systemButton;
    float guideButton;
    float stickButton;
    float stickInner;
    float stickOuter;
    // Extra room around controls for touches that land just outside them, and for fingers
    // sliding between face buttons or around the D-pad
    float touchSlack;
    float slideSlack;
} ControlSizes;

// Sizes for a control area of LAYOUT_REFERENCE_SIZE, scaled down to fit smaller areas
static const ControlSizes CONTROL_SIZES = {58, 25, 54, 80, {92, 40}, {92, 50}, 42, 50, 60, 62, 124, 12, 32};
static const CGSize LAYOUT_REFERENCE_SIZE = {669, 430};
static ControlSizes gSizes = CONTROL_SIZES;

#define FACE_BUTTON_SIZE gSizes.faceButton
#define BUTTON_DIST gSizes.buttonDist
#define D_PAD_ARM_WIDTH gSizes.dpadArmWidth
#define D_PAD_REACH gSizes.dpadReach
#define BUMPER_SIZE gSizes.bumper
#define TRIGGER_SIZE gSizes.trigger
#define SYSTEM_BUTTON_SIZE gSizes.systemButton
#define GUIDE_BUTTON_SIZE gSizes.guideButton
#define STICK_BUTTON_SIZE gSizes.stickButton
#define STICK_INNER_SIZE gSizes.stickInner
#define STICK_OUTER_SIZE gSizes.stickOuter
#define TOUCH_SLACK gSizes.touchSlack
#define SLIDE_SLACK gSizes.slideSlack

static float BUTTON_CENTER_X;
static float BUTTON_CENTER_Y;

static float D_PAD_CENTER_X;
static float D_PAD_CENTER_Y;


static const float DEAD_ZONE_PADDING = 15;

static const double STICK_CLICK_RATE = 100;
// A thumb on glass can't make the fine corrections a sprung stick allows over its short throw, so
// travel is longer than a real stick's and the output rises slowly near the centre
static const CGFloat STICK_TRAVEL = 72;
static const CGFloat STICK_BUFFER = 3;
static const CGFloat STICK_RESPONSE = 1.5;
static const NSInteger DEFAULT_STICK_COMPENSATION = 10;
static const CGFloat PEDAL_THROTTLE_TRAVEL = 64;
static const CGFloat PEDAL_BRAKE_TRAVEL = 48;
static const CGFloat PEDAL_BUFFER = 4;
static float LS_CENTER_X;
static float LS_CENTER_Y;
static float RS_CENTER_X;
static float RS_CENTER_Y;

static float START_X;
static float START_Y;

static float SELECT_X;
static float SELECT_Y;

static float R1_X;
static float R1_Y;
static float R2_X;
static float R2_Y;
static float R3_X;
static float R3_Y;
static float L1_X;
static float L1_Y;
static float L2_X;
static float L2_Y;
static float L3_X;
static float L3_Y;

- (id) initWithView:(UIView*)view controllerSup:(ControllerSupport*)controllerSupport streamConfig:(StreamConfiguration*)streamConfig {
    self = [self init];
    _view = view;
    _controllerSupport = controllerSupport;
    _controller = [controllerSupport getOscController];
    _deadTouches = [[NSMutableArray alloc] init];
    _swapABXY = streamConfig.swapABXYButtons;
    _theme = [OnScreenControlsTheme savedTheme];
    _layout = [OnScreenControls savedLayout];
    _stickCompensation = [OnScreenControls savedStickCompensation] / 100.0;
    _rightStickPedals = [OnScreenControls savedRightStickPedals];
    BOOL playStation = _layout == OnScreenControlsLayoutPlayStation;

    _controlViews = [NSMapTable strongToStrongObjectsMapTable];
    if (@available(iOS 26.0, tvOS 26.0, *)) {
        UIGlassContainerEffect* effect = [[UIGlassContainerEffect alloc] init];
        effect.spacing = 16;
        _directionGroup = [[GamepadDirectionGroup alloc] initWithEffect:effect];
    }
    // Two overlapping bars merge into a single cross behind the D-pad arms
    _dpadVerticalBar = [self glassViewWithTint:_theme.capColor cornerRadius:8];
    _dpadHorizontalBar = [self glassViewWithTint:_theme.capColor cornerRadius:8];

    NSArray<UIColor*>* legends = _theme.legendColors;
    CGSize faceSize = CGSizeMake(FACE_BUTTON_SIZE, FACE_BUTTON_SIZE);
    if (playStation) {
        // Plain shapes, without the multicolored legends of either controller
        if (![legends[0] isEqual:legends[1]]) {
            UIColor* neutral = [UIColor colorWithWhite:.85 alpha:1];
            legends = @[neutral, neutral, neutral, neutral];
        }
        _aButton = [self buttonWithTitle:nil symbol:@"xmark" label:@"Cross" size:faceSize tint:_theme.capColor glyph:legends[0]];
        _bButton = [self buttonWithTitle:nil symbol:@"circle" label:@"Circle" size:faceSize tint:_theme.capColor glyph:legends[1]];
        _xButton = [self buttonWithTitle:nil symbol:@"square" label:@"Square" size:faceSize tint:_theme.capColor glyph:legends[2]];
        _yButton = [self buttonWithTitle:nil symbol:@"triangle" label:@"Triangle" size:faceSize tint:_theme.capColor glyph:legends[3]];
    }
    else {
        _aButton = [self buttonWithTitle:@"A" symbol:nil label:nil size:faceSize tint:_theme.capColor glyph:legends[0]];
        _bButton = [self buttonWithTitle:@"B" symbol:nil label:nil size:faceSize tint:_theme.capColor glyph:legends[1]];
        _xButton = [self buttonWithTitle:@"X" symbol:nil label:nil size:faceSize tint:_theme.capColor glyph:legends[2]];
        _yButton = [self buttonWithTitle:@"Y" symbol:nil label:nil size:faceSize tint:_theme.capColor glyph:legends[3]];
    }

    // The D-pad arms share the face button tint, as on the controller
    UIColor* dpadGlyph = _theme.capColor != nil ? [UIColor colorWithWhite:1 alpha:.55] : [UIColor colorWithWhite:1 alpha:.7];
    CGSize armSize = CGSizeMake(D_PAD_ARM_WIDTH, D_PAD_ARM_WIDTH);
    _upButton = [self buttonWithTitle:nil symbol:@"arrowtriangle.up.fill" label:@"Up" size:armSize tint:_theme.capColor glyph:dpadGlyph];
    _downButton = [self buttonWithTitle:nil symbol:@"arrowtriangle.down.fill" label:@"Down" size:armSize tint:_theme.capColor glyph:dpadGlyph];
    _leftButton = [self buttonWithTitle:nil symbol:@"arrowtriangle.left.fill" label:@"Left" size:armSize tint:_theme.capColor glyph:dpadGlyph];
    _rightButton = [self buttonWithTitle:nil symbol:@"arrowtriangle.right.fill" label:@"Right" size:armSize tint:_theme.capColor glyph:dpadGlyph];

    UIColor* body = _theme.bodyColor;
    UIColor* bodyGlyph = _theme.bodyGlyphColor;
    CGSize stickButtonSize = CGSizeMake(STICK_BUTTON_SIZE, STICK_BUTTON_SIZE);
    CGSize systemSize = CGSizeMake(SYSTEM_BUTTON_SIZE, SYSTEM_BUTTON_SIZE);
    CGSize guideSize = CGSizeMake(GUIDE_BUTTON_SIZE, GUIDE_BUTTON_SIZE);
    _l1Button = [self buttonWithTitle:playStation ? @"L1" : @"LB" symbol:nil label:nil size:BUMPER_SIZE tint:body glyph:bodyGlyph];
    _r1Button = [self buttonWithTitle:playStation ? @"R1" : @"RB" symbol:nil label:nil size:BUMPER_SIZE tint:body glyph:bodyGlyph];
    _l2Button = [self buttonWithTitle:playStation ? @"L2" : @"LT" symbol:nil label:nil size:TRIGGER_SIZE tint:body glyph:bodyGlyph];
    _r2Button = [self buttonWithTitle:playStation ? @"R2" : @"RT" symbol:nil label:nil size:TRIGGER_SIZE tint:body glyph:bodyGlyph];
    _l3Button = [self buttonWithTitle:playStation ? @"L3" : @"LS" symbol:nil label:nil size:stickButtonSize tint:body glyph:bodyGlyph];
    _r3Button = [self buttonWithTitle:playStation ? @"R3" : @"RS" symbol:nil label:nil size:stickButtonSize tint:body glyph:bodyGlyph];
    _l3Button.borderColor = _r3Button.borderColor = legends[0].CGColor;
    if (playStation) {
        _startButton = [self buttonWithTitle:nil symbol:@"line.3.horizontal" label:@"Options" size:systemSize tint:body glyph:bodyGlyph];
        _selectButton = [self buttonWithTitle:nil symbol:@"square.and.arrow.up" label:@"Create" size:systemSize tint:body glyph:bodyGlyph];
        _guideButton = [self buttonWithTitle:nil symbol:@"playstation.logo" label:@"PlayStation" size:guideSize tint:_theme.guideColor glyph:_theme.guideGlyphColor];
    }
    else {
        _startButton = [self buttonWithTitle:nil symbol:@"line.3.horizontal" label:@"Menu" size:systemSize tint:body glyph:bodyGlyph];
        _selectButton = [self buttonWithTitle:nil symbol:@"square.on.square" label:@"View" size:systemSize tint:body glyph:bodyGlyph];
        _guideButton = [self buttonWithTitle:nil symbol:@"xbox.logo" label:@"Xbox" size:guideSize tint:_theme.guideColor glyph:_theme.guideGlyphColor];
    }

    _leftStickBackground = [self stickWell];
    _rightStickBackground = [self stickWell];
    _leftStick = [self stickCap];
    _rightStick = [self stickCap];

    return self;
}

- (CALayer*)buttonWithTitle:(NSString*)title symbol:(NSString*)symbol label:(NSString*)label size:(CGSize)size tint:(UIColor*)tint glyph:(UIColor*)glyph {
    GamepadButton* button = [[GamepadButton alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    button.legendTitle = title;
    button.legendSymbol = symbol;
    button.legendTint = tint;
    button.legendColor = glyph;
    button.isTrigger = CGSizeEqualToSize(size, TRIGGER_SIZE);
    button.streamInputView = _view;
    button.accessibilityLabel = label ?: title;
    if ([symbol hasPrefix:@"arrowtriangle"]) {
        button.configurationUpdateHandler = ^(UIButton* button) {
            UIButtonConfiguration* configuration = button.configuration;
            configuration.background.backgroundColor = button.highlighted ? [UIColor colorWithWhite:1 alpha:.2] : UIColor.clearColor;
            button.configuration = configuration;
        };
    }
#if !TARGET_OS_TV
    button.multipleTouchEnabled = YES;
    button.exclusiveTouch = NO;
#endif
    [self styleButton:button size:size];
    [_controlViews setObject:button forKey:button.layer];
    return button.layer;
}

- (void)styleButton:(GamepadButton*)button size:(CGSize)size {
    NSString* title = button.legendTitle;
    NSString* symbol = button.legendSymbol;
    UIColor* tint = button.legendTint;
    UIColor* glyph = button.legendColor;
    BOOL isDirection = [symbol hasPrefix:@"arrowtriangle"];
    UIButtonConfiguration* configuration;
    if (isDirection) {
        // The D-pad cross provides the background
        configuration = [UIButtonConfiguration plainButtonConfiguration];
    }
    else if (@available(iOS 26.0, tvOS 26.0, *)) {
        configuration = tint != nil ? [UIButtonConfiguration prominentGlassButtonConfiguration] : [UIButtonConfiguration clearGlassButtonConfiguration];
    }
    else {
        configuration = [UIButtonConfiguration filledButtonConfiguration];
        tint = tint ?: [UIColor colorWithWhite:0 alpha:.35];
    }
    configuration.baseBackgroundColor = tint;
    configuration.baseForegroundColor = glyph;
    configuration.contentInsets = NSDirectionalEdgeInsetsZero;
    
    // Prominent glass restyles titles and template images for contrast, which washes out
    // dark legends on light tints, so every legend is drawn as an image in its own color.
    CGFloat shortSide = MIN(size.width, size.height);
    if (title != nil) {
        UIFontDescriptor* descriptor = [[UIFont systemFontOfSize:shortSide * .42 weight:UIFontWeightBold].fontDescriptor
                                        fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        NSDictionary* attributes = @{
            NSFontAttributeName: [UIFont fontWithDescriptor:descriptor size:0],
            NSForegroundColorAttributeName: glyph
        };
        CGSize titleSize = [title sizeWithAttributes:attributes];
        UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(ceil(titleSize.width), ceil(titleSize.height))];
        configuration.image = [[renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [title drawAtPoint:CGPointZero withAttributes:attributes];
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    else {
        UIImage* image = [UIImage systemImageNamed:symbol];
        if (image == nil && [symbol hasSuffix:@".logo"]) {
            // Earlier releases name brand logos the other way around
            image = [UIImage systemImageNamed:[@"logo." stringByAppendingString:[symbol stringByDeletingPathExtension]]];
        }
        CGFloat pointSize = isDirection ? shortSide * .27 : shortSide * .4;
        image = [image imageByApplyingSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold]];
        configuration.image = [image imageWithTintColor:glyph renderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    
    // Triggers and D-pad arms keep their corners, everything else is round
    if (button.isTrigger) {
        configuration.cornerStyle = UIButtonConfigurationCornerStyleFixed;
        configuration.background.cornerRadius = shortSide * .36;
    }
    else if (isDirection) {
        configuration.cornerStyle = UIButtonConfigurationCornerStyleFixed;
        configuration.background.cornerRadius = shortSide * .2;
    }
    else {
        configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    }
    button.configuration = configuration;
    button.layer.cornerRadius = shortSide / 2;
    button.styledSize = size;
}

- (UIView*)glassViewWithTint:(UIColor*)tint cornerRadius:(CGFloat)cornerRadius {
    UIVisualEffectView* view;
    if (@available(iOS 26.0, tvOS 26.0, *)) {
        // Tinted glass matches the prominent glass buttons, untinted glass stays clear
        UIGlassEffect* effect = [UIGlassEffect effectWithStyle:tint != nil ? UIGlassEffectStyleRegular : UIGlassEffectStyleClear];
        effect.tintColor = tint;
        view = [[UIVisualEffectView alloc] initWithEffect:effect];
        view.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:cornerRadius]];
    }
    else {
        view = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        view.contentView.backgroundColor = tint;
        view.layer.cornerRadius = cornerRadius;
        view.clipsToBounds = YES;
    }
    // Touches pass through to the stream view, which tracks them for the controls
    view.userInteractionEnabled = NO;
    return view;
}

- (CALayer*)stickWell {
    UIView* well = [self glassViewWithTint:_theme.bodyColor cornerRadius:STICK_OUTER_SIZE / 2];
    well.tag = StickWellTag;
    [_controlViews setObject:well forKey:well.layer];
    return well.layer;
}

- (CALayer*)stickCap {
    UIView* cap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, STICK_INNER_SIZE, STICK_INNER_SIZE)];
    cap.tag = StickCapTag;
    cap.userInteractionEnabled = NO;
    cap.backgroundColor = _theme.stickColor;
    cap.layer.cornerRadius = STICK_INNER_SIZE / 2;
    cap.layer.shadowColor = UIColor.blackColor.CGColor;
    cap.layer.shadowOpacity = .35;
    cap.layer.shadowRadius = 6;
    cap.layer.shadowOffset = CGSizeMake(0, 2);
    cap.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:cap.bounds].CGPath;

    // Ring around the concave thumb rest
    CGFloat brightness = 0;
    [_theme.stickColor getHue:nil saturation:nil brightness:&brightness alpha:nil];
    CALayer* rest = [CALayer layer];
    rest.frame = CGRectInset(cap.bounds, 8, 8);
    rest.cornerRadius = rest.bounds.size.width / 2;
    rest.borderWidth = 1.5;
    rest.borderColor = (brightness > .8 ? [UIColor colorWithWhite:0 alpha:.14] : [UIColor colorWithWhite:1 alpha:.2]).CGColor;
    [cap.layer addSublayer:rest];

    [_controlViews setObject:cap forKey:cap.layer];
    return cap.layer;
}

- (void)showButton:(CALayer*)layer frame:(CGRect)frame {
    UIView* view = [_controlViews objectForKey:layer];
    view.frame = frame;
    [self resizeControl:view];
    BOOL isDirection = layer == _upButton || layer == _downButton || layer == _leftButton || layer == _rightButton;
    if (isDirection && _directionGroup != nil) {
        // Preserve the stream coordinate space for the existing input handling.
        _directionGroup.frame = _view.bounds;
        [_view addSubview:_directionGroup];
        [_directionGroup.contentView addSubview:view];
    }
    else {
        [_view addSubview:view];
    }
}

- (void)resizeControl:(UIView*)view {
    CGSize size = view.bounds.size;
    if ([view isKindOfClass:GamepadButton.class]) {
        GamepadButton* button = (GamepadButton*)view;
        if (!CGSizeEqualToSize(button.styledSize, size)) {
            [self styleButton:button size:size];
        }
    }
    else if (view.tag == StickWellTag) {
        if (@available(iOS 26.0, tvOS 26.0, *)) {
            view.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:size.width / 2]];
        }
        else {
            view.layer.cornerRadius = size.width / 2;
        }
    }
    else if (view.tag == StickCapTag && view.layer.cornerRadius != size.width / 2) {
        view.layer.cornerRadius = size.width / 2;
        view.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:view.bounds].CGPath;
        CALayer* rest = view.layer.sublayers.firstObject;
        rest.frame = CGRectInset(view.bounds, size.width / 6, size.width / 6);
        rest.cornerRadius = rest.bounds.size.width / 2;
    }
}

- (BOOL)button:(CALayer*)layer containsPoint:(CGPoint)point {
    UIView* button = [_controlViews objectForKey:layer];
    CGPoint localPoint = [button convertPoint:point fromView:_view];
    return button.superview != nil && [button pointInside:localPoint withEvent:nil];
}

- (void)hideButton:(CALayer*)layer {
    [[_controlViews objectForKey:layer] removeFromSuperview];
}

// The face button nearest the point, or -1 when the point is farther than slack outside the cluster.
// Indexes follow A, B, X, Y.
- (int)faceButtonAt:(CGPoint)point slack:(CGFloat)slack {
    if (_aButton.superlayer == nil) {
        return -1;
    }
    CGFloat faceOffset = BUTTON_DIST + FACE_BUTTON_SIZE / 2;
    if (hypot(point.x - BUTTON_CENTER_X, point.y - BUTTON_CENTER_Y) > faceOffset + FACE_BUTTON_SIZE / 2 + slack) {
        return -1;
    }
    NSArray<CALayer*>* buttons = @[_aButton, _bButton, _xButton, _yButton];
    int nearest = -1;
    CGFloat nearestDistance = CGFLOAT_MAX;
    for (int i = 0; i < 4; i++) {
        CGRect frame = [_controlViews objectForKey:buttons[i]].frame;
        CGFloat distance = hypot(point.x - CGRectGetMidX(frame), point.y - CGRectGetMidY(frame));
        if (distance < nearestDistance) {
            nearest = i;
            nearestDistance = distance;
        }
    }
    return nearest;
}

- (UITouch* __strong *)faceTouchAtIndex:(int)index {
    switch (index) {
        case 0: return &_aTouch;
        case 1: return &_bTouch;
        case 2: return &_xTouch;
        default: return &_yTouch;
    }
}

static const int FACE_FLAGS[] = {A_FLAG, B_FLAG, X_FLAG, Y_FLAG};

- (void)highlightFaceButtons {
    NSArray<CALayer*>* buttons = @[_aButton, _bButton, _xButton, _yButton];
    for (int i = 0; i < 4; i++) {
        ((UIButton*)[_controlViews objectForKey:buttons[i]]).highlighted = *[self faceTouchAtIndex:i] != nil;
    }
}

// The D-pad directions for a point, including diagonals between neighboring arms. Returns -1
// when the point is farther than slack outside the D-pad, and no directions near its center.
- (int)dpadFlagsAt:(CGPoint)point slack:(CGFloat)slack {
    if (_upButton.superlayer == nil) {
        return -1;
    }
    CGFloat dx = point.x - D_PAD_CENTER_X;
    CGFloat dy = point.y - D_PAD_CENTER_Y;
    CGFloat distance = hypot(dx, dy);
    if (distance > D_PAD_REACH + slack) {
        return -1;
    }
    if (distance < D_PAD_ARM_WIDTH / 4) {
        return 0;
    }
    // Each arm owns 60 degrees around its axis, and the 30 degrees between arms press both
    CGFloat degrees = atan2(-dy, dx) * 180 / M_PI;
    int flags = 0;
    if (fabs(degrees) < 60) flags |= RIGHT_FLAG;
    if (fabs(degrees) > 120) flags |= LEFT_FLAG;
    if (degrees > 30 && degrees < 150) flags |= UP_FLAG;
    if (degrees < -30 && degrees > -150) flags |= DOWN_FLAG;
    return flags;
}

- (void)highlightDirections:(int)flags {
    ((UIButton*)[_controlViews objectForKey:_upButton]).highlighted = (flags & UP_FLAG) != 0;
    ((UIButton*)[_controlViews objectForKey:_downButton]).highlighted = (flags & DOWN_FLAG) != 0;
    ((UIButton*)[_controlViews objectForKey:_leftButton]).highlighted = (flags & LEFT_FLAG) != 0;
    ((UIButton*)[_controlViews objectForKey:_rightButton]).highlighted = (flags & RIGHT_FLAG) != 0;
}

// The stick under a point, including the whole well and a margin around it
- (BOOL)stickAtCenter:(CGPoint)center containsPoint:(CGPoint)point layer:(CALayer*)layer {
    return layer.superlayer != nil && hypot(point.x - center.x, point.y - center.y) <= STICK_OUTER_SIZE / 2 + TOUCH_SLACK;
}

- (void)dealloc {
    [_directionGroup removeFromSuperview];
    [_dpadVerticalBar removeFromSuperview];
    [_dpadHorizontalBar removeFromSuperview];
    for (UIView* view in _controlViews.objectEnumerator) {
        [view removeFromSuperview];
    }
}

static CGFloat LayoutScale(CGSize area) {
    return MAX(.5, MIN(1, MIN(area.width / LAYOUT_REFERENCE_SIZE.width, area.height / LAYOUT_REFERENCE_SIZE.height)));
}

static ControlSizes ScaledSizes(ControlSizes sizes, CGFloat scale) {
    return (ControlSizes){
        sizes.faceButton * scale, sizes.buttonDist * scale, sizes.dpadArmWidth * scale, sizes.dpadReach * scale,
        CGSizeMake(sizes.bumper.width * scale, sizes.bumper.height * scale),
        CGSizeMake(sizes.trigger.width * scale, sizes.trigger.height * scale),
        sizes.systemButton * scale, sizes.guideButton * scale, sizes.stickButton * scale,
        sizes.stickInner * scale, sizes.stickOuter * scale,
        sizes.touchSlack * scale, sizes.slideSlack * scale,
    };
}

+ (OnScreenControlsLayout) savedLayout {
    return [[NSUserDefaults standardUserDefaults] integerForKey:OnScreenControlsLayoutKey] == OnScreenControlsLayoutPlayStation ?
        OnScreenControlsLayoutPlayStation : OnScreenControlsLayoutXbox;
}

+ (void) saveLayout:(OnScreenControlsLayout)layout {
    [[NSUserDefaults standardUserDefaults] setInteger:layout forKey:OnScreenControlsLayoutKey];
}

+ (NSInteger) savedStickCompensation {
    NSNumber* percent = [[NSUserDefaults standardUserDefaults] objectForKey:OnScreenControlsStickCompensationKey];
    return percent != nil ? MAX(0, MIN(25, percent.integerValue)) : DEFAULT_STICK_COMPENSATION;
}

+ (void) saveStickCompensation:(NSInteger)percent {
    [[NSUserDefaults standardUserDefaults] setInteger:percent forKey:OnScreenControlsStickCompensationKey];
}

+ (BOOL) savedRightStickPedals {
    return [[NSUserDefaults standardUserDefaults] boolForKey:OnScreenControlsRightStickPedalsKey];
}

+ (void) saveRightStickPedals:(BOOL)pedals {
    [[NSUserDefaults standardUserDefaults] setBool:pedals forKey:OnScreenControlsRightStickPedalsKey];
}

- (void) layoutControls {
    // Use equal side insets so controls stay evenly spaced and clear of a cutout on either side
    UIEdgeInsets insets = _view.safeAreaInsets;
    insets.left = insets.right = MAX(insets.left, insets.right);
    CGRect controlArea = UIEdgeInsetsInsetRect(_view.bounds, insets);
    _separateControlArea = CGRectZero;
    if ([(StreamView*)_view usesSeparateControlArea]) {
        // Touches anywhere below the hinge belong to the controls, which sit on the deck that
        // mirrors the video
        CGFloat top = MAX(CGRectGetMinY(controlArea), CGRectGetMidY(_view.bounds) + 16);
        _separateControlArea = CGRectMake(controlArea.origin.x, top, controlArea.size.width, MAX(0, CGRectGetMaxY(controlArea) - top));
        // The deck may extend under the home indicator, but the controls stay clear of it
        controlArea = CGRectIntersection([(StreamView*)_view controlDeckRect], _separateControlArea);
        if (CGRectIsNull(controlArea)) {
            controlArea = _separateControlArea;
        }
    }
    if (CGRectEqualToRect(controlArea, _controlArea)) {
        return;
    }
    gSizes = ScaledSizes(CONTROL_SIZES, LayoutScale(controlArea.size));

    // Release held controls before moving their hit targets underneath active touches.
    NSMutableSet* touches = [self heldTouches];
    [self handleTouchUpEvent:touches];
    // Consume the rest of these touches rather than turning them into mouse input.
    [_deadTouches addObjectsFromArray:touches.allObjects];
    _controlArea = controlArea;
    if (_visible) {
        [self updateControls];
    }
}

- (NSMutableSet*) heldTouches {
    NSMutableSet* touches = [NSMutableSet setWithArray:_deadTouches];
    UITouch* heldTouches[] = {_aTouch, _bTouch, _xTouch, _yTouch, _dpadTouch, _lsTouch, _rsTouch,
                             _startTouch, _selectTouch, _guideTouch, _r1Touch, _r2Touch, _r3Touch,
                             _l1Touch, _l2Touch, _l3Touch};
    for (int i = 0; i < sizeof(heldTouches) / sizeof(*heldTouches); i++) {
        if (heldTouches[i] != nil) {
            [touches addObject:heldTouches[i]];
        }
    }
    return touches;
}

// Touches arrive once per display refresh, and the display otherwise follows the stream's frame
// rate, so run it at full speed while the controls are held
- (void) updateTouchRate {
    if ([self heldTouches].count == 0) {
        [_touchRateLink invalidate];
        _touchRateLink = nil;
    }
    else if (_touchRateLink == nil) {
        _touchRateLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(touchRateTick:)];
        _touchRateLink.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
        [_touchRateLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void) touchRateTick:(CADisplayLink*)link {
}

- (void) show {
    [self layoutControls];
    _visible = YES;
        
    [self updateControls];
}

- (void) setLevel:(OnScreenControlsLevel)level {
    _level = level;
    [_view setNeedsLayout];
    
    // Only update controls if we're showing, otherwise
    // show will do it for us.
    if (_visible) {
        [self updateControls];
    }
}

- (OnScreenControlsLevel) getLevel {
    return _level;
}

- (void) updateControls {
    switch (_level) {
        case OnScreenControlsLevelOff:
            [self hideButtons];
            [self hideBumpers];
            [self hideTriggers];
            [self hideStartSelect];
            [self hideSticks];
            [self hideL3R3];
            break;
        case OnScreenControlsLevelAutoGCGamepad:
            // GCGamepad is missing triggers, both analog sticks,
            // and the select button
            [self setupControls];
            
            [self hideButtons];
            [self hideBumpers];
            [self hideL3R3];
            [self drawTriggers];
            [self drawStartSelect];
            [self drawSticks];
            break;
        case OnScreenControlsLevelAutoGCExtendedGamepad:
            // GCExtendedGamepad is missing R3, L3, and select
            [self setupControls];
            
            [self hideButtons];
            [self hideBumpers];
            [self hideTriggers];
            [self drawStartSelect];
            [self hideSticks];
            [self drawL3R3];
            break;
        case OnScreenControlsLevelAutoGCExtendedGamepadWithStickButtons:
            // This variant of GCExtendedGamepad has L3 and R3 but
            // is still missing Select
            [self setupControls];
            
            [self hideButtons];
            [self hideBumpers];
            [self hideTriggers];
            [self hideL3R3];
            [self drawStartSelect];
            [self hideSticks];
            break;
        case OnScreenControlsLevelSimple:
            [self setupControls];
            
            [self hideTriggers];
            [self hideL3R3];
            [self hideBumpers];
            [self hideSticks];
            [self drawStartSelect];
            [self drawButtons];
            break;
        case OnScreenControlsLevelFull:
            [self setupControls];
            
            [self drawButtons];
            [self drawStartSelect];
            [self drawBumpers];
            [self drawTriggers];
            [self drawSticks];
            [self hideL3R3]; // Full controls don't need these they have the sticks
            break;
        default:
            Log(LOG_W, @"Unknown on-screen controls level: %d", (int)_level);
            break;
    }
}

// The controls follow the controller: the left stick and face buttons where the thumbs rest, with
// the D-pad and right stick lower and further in, and the shoulder buttons above them. The
// PlayStation layout swaps the left stick and D-pad. Each side is placed from its own edge of the
// control area, so wider areas leave room in the middle.
- (void) setupControls
{
    CGFloat scale = LayoutScale(_controlArea.size);
    CGFloat left = CGRectGetMinX(_controlArea);
    CGFloat right = CGRectGetMaxX(_controlArea);
    CGFloat top = CGRectGetMaxY(_controlArea) - LAYOUT_REFERENCE_SIZE.height * scale;
#define LEFT_X(x) (left + (x) * scale)
#define RIGHT_X(x) (right - (x) * scale)
#define LAYOUT_Y(y) (top + (y) * scale)
    BOOL playStation = _layout == OnScreenControlsLayoutPlayStation;
    LS_CENTER_X = LEFT_X(playStation ? 240 : 112);
    LS_CENTER_Y = LAYOUT_Y(playStation ? 345 : 232);
    D_PAD_CENTER_X = LEFT_X(playStation ? 112 : 240);
    D_PAD_CENTER_Y = LAYOUT_Y(playStation ? 232 : 345);
    BUTTON_CENTER_X = RIGHT_X(112);
    BUTTON_CENTER_Y = LAYOUT_Y(232);
    RS_CENTER_X = RIGHT_X(240);
    RS_CENTER_Y = LAYOUT_Y(345);

    L2_X = LEFT_X(96);
    L2_Y = LAYOUT_Y(48);
    L1_X = LEFT_X(96);
    L1_Y = LAYOUT_Y(108);
    R2_X = RIGHT_X(96);
    R2_Y = LAYOUT_Y(48);
    R1_X = RIGHT_X(96);
    R1_Y = LAYOUT_Y(108);

    // The system buttons sit along the bottom between the lower controls when they fit,
    // otherwise between the shoulder buttons
    BOOL bottomRow = right - left - 640 * scale >= 203 * scale;
    SELECT_X = CGRectGetMidX(_controlArea) - 64.5 * scale;
    START_X = CGRectGetMidX(_controlArea) + 64.5 * scale;
    SELECT_Y = START_Y = LAYOUT_Y(bottomRow ? 395 : 60);

    // Stick clicks replace the sticks when a controller provides them
    L3_X = LS_CENTER_X;
    L3_Y = LS_CENTER_Y;
    R3_X = RS_CENTER_X;
    R3_Y = RS_CENTER_Y;
#undef LEFT_X
#undef RIGHT_X
#undef LAYOUT_Y
}

static CGRect CenteredRect(CGFloat x, CGFloat y, CGSize size) {
    return CGRectMake(x - size.width / 2, y - size.height / 2, size.width, size.height);
}

- (void) drawButtons {
    CGSize faceSize = CGSizeMake(FACE_BUTTON_SIZE, FACE_BUTTON_SIZE);
    CGFloat faceOffset = BUTTON_DIST + FACE_BUTTON_SIZE / 2;
    CGRect aButtonFrame = CenteredRect(BUTTON_CENTER_X, BUTTON_CENTER_Y + faceOffset, faceSize);
    CGRect bButtonFrame = CenteredRect(BUTTON_CENTER_X + faceOffset, BUTTON_CENTER_Y, faceSize);
    CGRect xButtonFrame = CenteredRect(BUTTON_CENTER_X - faceOffset, BUTTON_CENTER_Y, faceSize);
    CGRect yButtonFrame = CenteredRect(BUTTON_CENTER_X, BUTTON_CENTER_Y - faceOffset, faceSize);

    // create A button
    [self showButton:_aButton frame:_swapABXY ? bButtonFrame : aButtonFrame];

    // create B button
    [self showButton:_bButton frame:_swapABXY ? aButtonFrame : bButtonFrame];

    // create X Button
    [self showButton:_xButton frame:_swapABXY ? yButtonFrame : xButtonFrame];

    // create Y Button
    [self showButton:_yButton frame:_swapABXY ? xButtonFrame : yButtonFrame];

    // The arms leave the center of the D-pad neutral
    CGFloat half = D_PAD_ARM_WIDTH / 2;
    CGFloat armLength = D_PAD_REACH - half;
    UIView* dpadContainer = _view;
    if (_directionGroup != nil) {
        _directionGroup.frame = _view.bounds;
        [_view addSubview:_directionGroup];
        dpadContainer = _directionGroup.contentView;
    }
    _dpadVerticalBar.frame = CGRectMake(D_PAD_CENTER_X - half, D_PAD_CENTER_Y - D_PAD_REACH, D_PAD_ARM_WIDTH, D_PAD_REACH * 2);
    _dpadHorizontalBar.frame = CGRectMake(D_PAD_CENTER_X - D_PAD_REACH, D_PAD_CENTER_Y - half, D_PAD_REACH * 2, D_PAD_ARM_WIDTH);
    [dpadContainer addSubview:_dpadVerticalBar];
    [dpadContainer addSubview:_dpadHorizontalBar];
    [self showButton:_upButton frame:CGRectMake(D_PAD_CENTER_X - half, D_PAD_CENTER_Y - D_PAD_REACH, D_PAD_ARM_WIDTH, armLength)];
    [self showButton:_downButton frame:CGRectMake(D_PAD_CENTER_X - half, D_PAD_CENTER_Y + half, D_PAD_ARM_WIDTH, armLength)];
    [self showButton:_leftButton frame:CGRectMake(D_PAD_CENTER_X - D_PAD_REACH, D_PAD_CENTER_Y - half, armLength, D_PAD_ARM_WIDTH)];
    [self showButton:_rightButton frame:CGRectMake(D_PAD_CENTER_X + half, D_PAD_CENTER_Y - half, armLength, D_PAD_ARM_WIDTH)];
}

- (void) drawStartSelect {
    CGSize systemSize = CGSizeMake(SYSTEM_BUTTON_SIZE, SYSTEM_BUTTON_SIZE);
    [self showButton:_startButton frame:CenteredRect(START_X, START_Y, systemSize)];
    [self showButton:_selectButton frame:CenteredRect(SELECT_X, SELECT_Y, systemSize)];

    // The guide button sits centered between View and Menu, as on the controller
    [self showButton:_guideButton frame:CenteredRect(CGRectGetMidX(_controlArea), (START_Y + SELECT_Y) / 2,
                                                      CGSizeMake(GUIDE_BUTTON_SIZE, GUIDE_BUTTON_SIZE))];
}

- (void) drawBumpers {
    [self showButton:_l1Button frame:CenteredRect(L1_X, L1_Y, BUMPER_SIZE)];
    [self showButton:_r1Button frame:CenteredRect(R1_X, R1_Y, BUMPER_SIZE)];
}

- (void) drawTriggers {
    [self showButton:_l2Button frame:CenteredRect(L2_X, L2_Y, TRIGGER_SIZE)];
    [self showButton:_r2Button frame:CenteredRect(R2_X, R2_Y, TRIGGER_SIZE)];
}

- (void) drawSticks {
    CGSize outerSize = CGSizeMake(STICK_OUTER_SIZE, STICK_OUTER_SIZE);
    CGSize innerSize = CGSizeMake(STICK_INNER_SIZE, STICK_INNER_SIZE);
    [self showButton:_leftStickBackground frame:CenteredRect(LS_CENTER_X, LS_CENTER_Y, outerSize)];
    [self showButton:_leftStick frame:CenteredRect(LS_CENTER_X, LS_CENTER_Y, innerSize)];
    [self showButton:_rightStickBackground frame:CenteredRect(RS_CENTER_X, RS_CENTER_Y, outerSize)];
    [self showButton:_rightStick frame:CenteredRect(RS_CENTER_X, RS_CENTER_Y, innerSize)];
}

- (void) drawL3R3 {
    CGSize stickButtonSize = CGSizeMake(STICK_BUTTON_SIZE, STICK_BUTTON_SIZE);
    [self showButton:_l3Button frame:CenteredRect(L3_X, L3_Y, stickButtonSize)];
    [self showButton:_r3Button frame:CenteredRect(R3_X, R3_Y, stickButtonSize)];
}

- (void) hideButtons {
    [_directionGroup removeFromSuperview];
    [_dpadVerticalBar removeFromSuperview];
    [_dpadHorizontalBar removeFromSuperview];
    [self hideButton:_aButton];
    [self hideButton:_bButton];
    [self hideButton:_xButton];
    [self hideButton:_yButton];
    [self hideButton:_upButton];
    [self hideButton:_downButton];
    [self hideButton:_leftButton];
    [self hideButton:_rightButton];
}

- (void) hideStartSelect {
    [self hideButton:_startButton];
    [self hideButton:_selectButton];
    [self hideButton:_guideButton];
}

- (void) hideBumpers {
    [self hideButton:_l1Button];
    [self hideButton:_r1Button];
}

- (void) hideTriggers {
    [self hideButton:_l2Button];
    [self hideButton:_r2Button];
}

- (void) hideSticks {
    [self hideButton:_leftStickBackground];
    [self hideButton:_rightStickBackground];
    [self hideButton:_leftStick];
    [self hideButton:_rightStick];
}

- (void) hideL3R3 {
    [self hideButton:_l3Button];
    [self hideButton:_r3Button];
}

// Deflection is measured from where the touch started so grabbing the stick never jumps it.
// Past a small buffer the output starts at the compensation level, so the first movement already
// clears the dead zone the game applies, then curves up to full deflection.
- (CGPoint) moveStick:(CALayer*)stick center:(CGPoint)center origin:(CGPoint)origin location:(CGPoint)location
{
    CGFloat scale = LayoutScale(_controlArea.size);
    CGFloat travel = STICK_TRAVEL * scale;
    CGFloat buffer = STICK_BUFFER * scale;
    CGFloat dx = location.x - origin.x;
    CGFloat dy = location.y - origin.y;
    CGFloat distance = hypot(dx, dy);
    if (distance > travel) {
        dx *= travel / distance;
        dy *= travel / distance;
        distance = travel;
    }
    CGFloat capScale = MIN(1, STICK_OUTER_SIZE / 2 / travel);
    stick.frame = CGRectMake(center.x + dx * capScale - STICK_INNER_SIZE / 2, center.y + dy * capScale - STICK_INNER_SIZE / 2, STICK_INNER_SIZE, STICK_INNER_SIZE);
    if (distance <= buffer) {
        return CGPointZero;
    }
    CGFloat output = _stickCompensation + (1 - _stickCompensation) * pow((distance - buffer) / (travel - buffer), STICK_RESPONSE);
    return CGPointMake(dx / distance * output, dy / distance * output);
}

// Sliding up from where the touch started presses the throttle (RT) and sliding down the brake (LT),
// so the right thumb can brake while the left one steers
- (void) movePedals:(CGPoint)location
{
    CGFloat scale = LayoutScale(_controlArea.size);
    CGFloat throttleTravel = PEDAL_THROTTLE_TRAVEL * scale;
    CGFloat brakeTravel = PEDAL_BRAKE_TRAVEL * scale;
    CGFloat buffer = PEDAL_BUFFER * scale;
    CGFloat dy = MAX(-throttleTravel, MIN(brakeTravel, location.y - _rsOrigin.y));
    CGFloat capOffset = (dy < 0 ? dy / throttleTravel : dy / brakeTravel) * STICK_OUTER_SIZE / 2;
    _rightStick.frame = CGRectMake(RS_CENTER_X - STICK_INNER_SIZE / 2, RS_CENTER_Y + capOffset - STICK_INNER_SIZE / 2, STICK_INNER_SIZE, STICK_INNER_SIZE);
    if (_r2Touch == nil) {
        [_controllerSupport updateRightTrigger:_controller right:0xFF * MAX(0, (-dy - buffer) / (throttleTravel - buffer))];
    }
    if (_l2Touch == nil) {
        [_controllerSupport updateLeftTrigger:_controller left:0xFF * MAX(0, (dy - buffer) / (brakeTravel - buffer))];
    }
}

- (BOOL) handleTouchMovedEvent:touches {
    BOOL updated = false;
    BOOL buttonTouch = false;
    
    for (UITouch* touch in touches) {
        CGPoint touchLocation = [touch locationInView:_view];
        if (touch == _lsTouch) {
            CGPoint value = [self moveStick:_leftStick center:CGPointMake(LS_CENTER_X, LS_CENTER_Y) origin:_lsOrigin location:touchLocation];
            [_controllerSupport updateLeftStick:_controller x:0x7FFE * value.x y:0x7FFE * -value.y];
            
            updated = true;
        } else if (touch == _rsTouch) {
            if (_rightStickPedals) {
                [self movePedals:touchLocation];
            }
            else {
                CGPoint value = [self moveStick:_rightStick center:CGPointMake(RS_CENTER_X, RS_CENTER_Y) origin:_rsOrigin location:touchLocation];
                [_controllerSupport updateRightStick:_controller x:0x7FFE * value.x y:0x7FFE * -value.y];
            }
            
            updated = true;
        } else if (touch == _dpadTouch) {
            // Follow the finger around the D-pad, including onto the diagonals. Directions keep
            // following it past the edge so a slide never drops the input.
            int flags = [self dpadFlagsAt:touchLocation slack:CGFLOAT_MAX];
            if (flags != _dpadFlags) {
                [_controllerSupport clearButtonFlag:_controller flags:_dpadFlags & ~flags];
                [_controllerSupport setButtonFlag:_controller flags:flags & ~_dpadFlags];
                _dpadFlags = flags;
                [self highlightDirections:flags];
                updated = true;
            }
            buttonTouch = true;
        } else if (touch == _aTouch || touch == _bTouch || touch == _xTouch || touch == _yTouch) {
            // Let the finger roll from one face button onto another
            int current = touch == _aTouch ? 0 : touch == _bTouch ? 1 : touch == _xTouch ? 2 : 3;
            int next = [self faceButtonAt:touchLocation slack:SLIDE_SLACK];
            if (next >= 0 && next != current && *[self faceTouchAtIndex:next] == nil) {
                [_controllerSupport clearButtonFlag:_controller flags:FACE_FLAGS[current]];
                *[self faceTouchAtIndex:current] = nil;
                *[self faceTouchAtIndex:next] = touch;
                [_controllerSupport setButtonFlag:_controller flags:FACE_FLAGS[next]];
                [self highlightFaceButtons];
                updated = true;
            }
            buttonTouch = true;
        } else if (touch == _startTouch) {
            buttonTouch = true;
        } else if (touch == _selectTouch) {
            buttonTouch = true;
        } else if (touch == _guideTouch) {
            buttonTouch = true;
        } else if (touch == _l1Touch) {
            buttonTouch = true;
        } else if (touch == _r1Touch) {
            buttonTouch = true;
        } else if (touch == _l2Touch) {
            buttonTouch = true;
        } else if (touch == _r2Touch) {
            buttonTouch = true;
        } else if (touch == _l3Touch) {
            buttonTouch = true;
        } else if (touch == _r3Touch) {
            buttonTouch = true;
        }
        if ([_deadTouches containsObject:touch]) {
            updated = true;
        }
    }
    if (updated) {
        [_controllerSupport updateFinished:_controller];
    }
    return updated || buttonTouch;
}

- (BOOL)handleTouchDownEvent:touches {
    BOOL updated = false;
    BOOL stickTouch = false;
    for (UITouch* touch in touches) {
        CGPoint touchLocation = [touch locationInView:_view];
        if (!CGRectIsEmpty(_separateControlArea) && !CGRectContainsPoint(_separateControlArea, touchLocation)) {
            continue;
        }
        
        BOOL leftStickHit = [self stickAtCenter:CGPointMake(LS_CENTER_X, LS_CENTER_Y) containsPoint:touchLocation layer:_leftStickBackground];
        BOOL rightStickHit = [self stickAtCenter:CGPointMake(RS_CENTER_X, RS_CENTER_Y) containsPoint:touchLocation layer:_rightStickBackground];
        int faceButton = leftStickHit || rightStickHit ? -1 : [self faceButtonAt:touchLocation slack:TOUCH_SLACK];
        int dpadFlags = _dpadTouch == nil && !leftStickHit && !rightStickHit ? [self dpadFlagsAt:touchLocation slack:TOUCH_SLACK] : -1;
        if (faceButton >= 0) {
            if (*[self faceTouchAtIndex:faceButton] == nil) {
                [_controllerSupport setButtonFlag:_controller flags:FACE_FLAGS[faceButton]];
                *[self faceTouchAtIndex:faceButton] = touch;
                [self highlightFaceButtons];
            }
            else {
                [_deadTouches addObject:touch];
            }
            updated = true;
        } else if (dpadFlags >= 0) {
            [_controllerSupport setButtonFlag:_controller flags:dpadFlags];
            _dpadTouch = touch;
            _dpadFlags = dpadFlags;
            [self highlightDirections:dpadFlags];
            updated = true;
        } else if (_startButton.superlayer != nil && [self button:_startButton containsPoint:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:PLAY_FLAG];
            _startTouch = touch;
            updated = true;
        } else if (_selectButton.superlayer != nil && [self button:_selectButton containsPoint:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:BACK_FLAG];
            _selectTouch = touch;
            updated = true;
        } else if (_guideButton.superlayer != nil && [self button:_guideButton containsPoint:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:SPECIAL_FLAG];
            _guideTouch = touch;
            updated = true;
        } else if (_l1Button.superlayer != nil && [self button:_l1Button containsPoint:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:LB_FLAG];
            _l1Touch = touch;
            updated = true;
        } else if (_r1Button.superlayer != nil && [self button:_r1Button containsPoint:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:RB_FLAG];
            _r1Touch = touch;
            updated = true;
        } else if (_l2Button.superlayer != nil && [self button:_l2Button containsPoint:touchLocation]) {
            [_controllerSupport updateLeftTrigger:_controller left:0xFF];
            _l2Touch = touch;
            updated = true;
        } else if (_r2Button.superlayer != nil && [self button:_r2Button containsPoint:touchLocation]) {
            [_controllerSupport updateRightTrigger:_controller right:0xFF];
            _r2Touch = touch;
            updated = true;
        } else if (_l3Button.superlayer != nil && [self button:_l3Button containsPoint:touchLocation]) {
            if (l3Set) {
                [_controllerSupport clearButtonFlag:_controller flags:LS_CLK_FLAG];
                _l3Button.borderWidth = 0.0f;
            } else {
                [_controllerSupport setButtonFlag:_controller flags:LS_CLK_FLAG];
                _l3Button.borderWidth = 2.0f;
            }
            l3Set = !l3Set;
            _l3Touch = touch;
            updated = true;
        } else if (_r3Button.superlayer != nil && [self button:_r3Button containsPoint:touchLocation]) {
            if (r3Set) {
                [_controllerSupport clearButtonFlag:_controller flags:RS_CLK_FLAG];
                _r3Button.borderWidth = 0.0f;
            } else {
                [_controllerSupport setButtonFlag:_controller flags:RS_CLK_FLAG];
                _r3Button.borderWidth = 2.0f;
            }
            r3Set = !r3Set;
            _r3Touch = touch;
            updated = true;
        } else if (_lsTouch == nil && leftStickHit) {
            if (l3TouchStart != nil) {
                // Find elapsed time and convert to milliseconds
                // Use (-) modifier to conversion since receiver is earlier than now
                double l3TouchTime = [l3TouchStart timeIntervalSinceNow] * -1000.0;
                if (l3TouchTime < STICK_CLICK_RATE) {
                    [_controllerSupport setButtonFlag:_controller flags:LS_CLK_FLAG];
                    updated = true;
                }
            }
            _lsTouch = touch;
            _lsOrigin = touchLocation;
            stickTouch = true;
        } else if (_rsTouch == nil && rightStickHit) {
            if (r3TouchStart != nil && !_rightStickPedals) {
                // Find elapsed time and convert to milliseconds
                // Use (-) modifier to conversion since receiver is earlier than now
                double r3TouchTime = [r3TouchStart timeIntervalSinceNow] * -1000.0;
                if (r3TouchTime < STICK_CLICK_RATE) {
                    [_controllerSupport setButtonFlag:_controller flags:RS_CLK_FLAG];
                    updated = true;
                }
            }
            _rsTouch = touch;
            _rsOrigin = touchLocation;
            stickTouch = true;
        } else if (leftStickHit || rightStickHit) {
            [_deadTouches addObject:touch];
            updated = true;
        }
        if (!updated && !stickTouch && [self isInDeadZone:touch]) {
            [_deadTouches addObject:touch];
            updated = true;
        }
    }
    if (updated) {
        [_controllerSupport updateFinished:_controller];
    }
    [self updateTouchRate];
    return updated || stickTouch;
}

- (BOOL)handleTouchUpEvent:touches {
    BOOL updated = false;
    BOOL touched = false;
    BOOL releasedTrigger = false;
    for (UITouch* touch in touches) {
        if (touch == _aTouch || touch == _bTouch || touch == _xTouch || touch == _yTouch) {
            for (int i = 0; i < 4; i++) {
                if (*[self faceTouchAtIndex:i] == touch) {
                    [_controllerSupport clearButtonFlag:_controller flags:FACE_FLAGS[i]];
                    *[self faceTouchAtIndex:i] = nil;
                }
            }
            [self highlightFaceButtons];
            updated = true;
        } else if (touch == _dpadTouch) {
            [_controllerSupport clearButtonFlag:_controller
                                          flags:UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG];
            _dpadTouch = nil;
            _dpadFlags = 0;
            [self highlightDirections:0];
            updated = true;
        } else if (touch == _startTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:PLAY_FLAG];
            _startTouch = nil;
            updated = true;
        } else if (touch == _selectTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:BACK_FLAG];
            _selectTouch = nil;
            updated = true;
        } else if (touch == _guideTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:SPECIAL_FLAG];
            _guideTouch = nil;
            updated = true;
        } else if (touch == _l1Touch) {
            [_controllerSupport clearButtonFlag:_controller flags:LB_FLAG];
            _l1Touch = nil;
            updated = true;
        } else if (touch == _r1Touch) {
            [_controllerSupport clearButtonFlag:_controller flags:RB_FLAG];
            _r1Touch = nil;
            updated = true;
        } else if (touch == _l2Touch) {
            [_controllerSupport updateLeftTrigger:_controller left:0];
            _l2Touch = nil;
            releasedTrigger = true;
            updated = true;
        } else if (touch == _r2Touch) {
            [_controllerSupport updateRightTrigger:_controller right:0];
            _r2Touch = nil;
            releasedTrigger = true;
            updated = true;
        } else if (touch == _lsTouch) {
            _leftStick.frame = CGRectMake(LS_CENTER_X - STICK_INNER_SIZE / 2, LS_CENTER_Y - STICK_INNER_SIZE / 2, STICK_INNER_SIZE, STICK_INNER_SIZE);
            [_controllerSupport updateLeftStick:_controller x:0 y:0];
            [_controllerSupport clearButtonFlag:_controller flags:LS_CLK_FLAG];
            l3TouchStart = [NSDate date];
            _lsTouch = nil;
            updated = true;
        } else if (touch == _rsTouch) {
            _rightStick.frame = CGRectMake(RS_CENTER_X - STICK_INNER_SIZE / 2, RS_CENTER_Y - STICK_INNER_SIZE / 2, STICK_INNER_SIZE, STICK_INNER_SIZE);
            [_controllerSupport updateRightStick:_controller x:0 y:0];
            [_controllerSupport clearButtonFlag:_controller flags:RS_CLK_FLAG];
            if (_rightStickPedals) {
                if (_r2Touch == nil) {
                    [_controllerSupport updateRightTrigger:_controller right:0];
                }
                if (_l2Touch == nil) {
                    [_controllerSupport updateLeftTrigger:_controller left:0];
                }
            }
            r3TouchStart = [NSDate date];
            _rsTouch = nil;
            updated = true;
        }
        else if (touch == _l3Touch) {
            _l3Touch = nil;
            touched = true;
        }
        else if (touch == _r3Touch) {
            _r3Touch = nil;
            touched = true;
        }
        if ([_deadTouches containsObject:touch]) {
            [_deadTouches removeObject:touch];
            updated = true;
        }
    }
    if (releasedTrigger && _rightStickPedals && _rsTouch != nil) {
        [self movePedals:[_rsTouch locationInView:_view]];
    }
    if (updated) {
        [_controllerSupport updateFinished:_controller];
    }
    
    [self updateTouchRate];
    return updated || touched;
}

- (BOOL) isInDeadZone:(UITouch*) touch {
    // Dynamically evaluate deadzones based on the controls
    // on screen at the time
    if (_leftButton.superlayer != nil && [self isDpadDeadZone:touch]) {
        return true;
    }
    else if (_aButton.superlayer != nil && [self isAbxyDeadZone:touch]) {
        return true;
    }
    else if (_l2Button.superlayer != nil && [self isTriggerDeadZone:touch]) {
        return true;
    }
    else if (_l1Button.superlayer != nil && [self isBumperDeadZone:touch]) {
        return true;
    }
    else if (_startButton.superlayer != nil && [self isStartSelectDeadZone:touch]) {
        return true;
    }
    else if (_guideButton.superlayer != nil && [self isGuideDeadZone:touch]) {
        return true;
    }
    else if (_l3Button.superlayer != nil && [self isL3R3DeadZone:touch]) {
        return true;
    }
    else if (_leftStickBackground.superlayer != nil && [self isStickDeadZone:touch]) {
        return true;
    }
    
    return false;
}

- (BOOL) isDpadDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_upButton.frame.origin.y
                       endX:_rightButton.frame.origin.x + _rightButton.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isAbxyDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_xButton.frame.origin.x
                     startY:_yButton.frame.origin.y
                       endX:_view.frame.origin.x + _view.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isBumperDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_l2Button.frame.origin.y + _l2Button.frame.size.height
                       endX:_l1Button.frame.origin.x + _l1Button.frame.size.width
                       endY:_upButton.frame.origin.y]
    || [self isDeadZone:touch
                 startX:_r2Button.frame.origin.x
                 startY:_r2Button.frame.origin.y + _r2Button.frame.size.height
                   endX:_view.frame.origin.x + _view.frame.size.width
                   endY:_yButton.frame.origin.y];
}

- (BOOL) isTriggerDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_l2Button.frame.origin.y
                       endX:_l2Button.frame.origin.x + _l2Button.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_r2Button.frame.origin.x
                 startY:_r2Button.frame.origin.y
                   endX:_view.frame.origin.x + _view.frame.size.width
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isL3R3DeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_l3Button.frame.origin.y
                       endX:_view.frame.origin.x
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_r3Button.frame.origin.x
                 startY:_r3Button.frame.origin.y
                   endX:_view.frame.origin.x + _view.frame.size.width
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isStartSelectDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_startButton.frame.origin.x
                     startY:_startButton.frame.origin.y
                       endX:_view.frame.origin.x + _view.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_view.frame.origin.x
                 startY:_selectButton.frame.origin.y
                   endX:_selectButton.frame.origin.x + _selectButton.frame.size.width
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isGuideDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_guideButton.frame.origin.x
                     startY:_guideButton.frame.origin.y
                       endX:_guideButton.frame.origin.x + _guideButton.frame.size.width
                       endY:_guideButton.frame.origin.y + _guideButton.frame.size.height];
}

- (BOOL) isStickDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_leftStickBackground.frame.origin.x - 15
                     startY:_leftStickBackground.frame.origin.y - 15
                       endX:_leftStickBackground.frame.origin.x + _leftStickBackground.frame.size.width + 15
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_rightStickBackground.frame.origin.x - 15
                 startY:_rightStickBackground.frame.origin.y - 15
                   endX:_rightStickBackground.frame.origin.x + _rightStickBackground.frame.size.width + 15
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isDeadZone:(UITouch*) touch startX:(float)deadZoneStartX startY:(float)deadZoneStartY endX:(float)deadZoneEndX endY:(float)deadZoneEndY {
    deadZoneStartX -= DEAD_ZONE_PADDING;
    deadZoneStartY -= DEAD_ZONE_PADDING;
    deadZoneEndX += DEAD_ZONE_PADDING;
    deadZoneEndY += DEAD_ZONE_PADDING;
    
    CGPoint touchLocation = [touch locationInView:_view];
    return (touchLocation.x > deadZoneStartX && touchLocation.x < deadZoneEndX
            && touchLocation.y > deadZoneStartY && touchLocation.y < deadZoneEndY);
    
}

@end
