//
//  OnScreenControls.h
//  Moonlight
//
//  Created by Diego Waxemberg on 12/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import <UIKit/UIKit.h>

@class ControllerSupport;
@class StreamConfiguration;

// Colors for the on-screen controls, modeled on Xbox Wireless Controller colorways
@interface OnScreenControlsTheme : NSObject

@property (nonatomic, readonly) NSString* identifier;
@property (nonatomic, readonly) NSString* name;
// Tint for the controller shell, or nil for untinted glass
@property (nonatomic, readonly) UIColor* bodyColor;
@property (nonatomic, readonly) UIColor* bodyGlyphColor;
// Tint for the face buttons and D-pad, or nil for untinted glass
@property (nonatomic, readonly) UIColor* capColor;
// Legend colors in A, B, X, Y order
@property (nonatomic, readonly) NSArray<UIColor*>* legendColors;
@property (nonatomic, readonly) UIColor* stickColor;
// Tint for the guide button, or nil for untinted glass
@property (nonatomic, readonly) UIColor* guideColor;
@property (nonatomic, readonly) UIColor* guideGlyphColor;

+ (NSArray<OnScreenControlsTheme*>*) themes;
+ (OnScreenControlsTheme*) savedTheme;
+ (void) saveTheme:(OnScreenControlsTheme*)theme;

@end

@interface OnScreenControls : NSObject

typedef NS_ENUM(NSInteger, OnScreenControlsLevel) {
    OnScreenControlsLevelOff,
    OnScreenControlsLevelAuto,
    OnScreenControlsLevelSimple,
    OnScreenControlsLevelFull,
    
    // Internal levels selected by ControllerSupport
    OnScreenControlsLevelAutoGCGamepad,
    OnScreenControlsLevelAutoGCExtendedGamepad,
    OnScreenControlsLevelAutoGCExtendedGamepadWithStickButtons
};

typedef NS_ENUM(NSInteger, OnScreenControlsLayout) {
    OnScreenControlsLayoutXbox,
    OnScreenControlsLayoutPlayStation
};

+ (OnScreenControlsLayout) savedLayout;
+ (void) saveLayout:(OnScreenControlsLayout)layout;

- (id) initWithView:(UIView*)view controllerSup:(ControllerSupport*)controllerSupport streamConfig:(StreamConfiguration*)streamConfig;
- (BOOL) handleTouchDownEvent:(NSSet*)touches;
- (BOOL) handleTouchUpEvent:(NSSet*)touches;
- (BOOL) handleTouchMovedEvent:(NSSet*)touches;
- (void) setLevel:(OnScreenControlsLevel)level;
- (OnScreenControlsLevel) getLevel;
- (void) show;
- (void) layoutControls;

@end
