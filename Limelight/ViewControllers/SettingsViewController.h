//
//  SettingsViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/27/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

@interface SettingsViewController : UIViewController
@property (strong, nonatomic) UILabel *bitrateLabel;
@property (strong, nonatomic) UISlider *bitrateSlider;
@property (strong, nonatomic) UISegmentedControl *framerateSelector;
@property (strong, nonatomic) UISegmentedControl *resolutionSelector;
@property (strong, nonatomic) UIView *resolutionDisplayView;
@property (strong, nonatomic) UISegmentedControl *touchModeSelector;
@property (strong, nonatomic) UISegmentedControl *onscreenControlSelector;
@property (strong, nonatomic) UISegmentedControl *optimizeSettingsSelector;
@property (strong, nonatomic) UISegmentedControl *multiControllerSelector;
@property (strong, nonatomic) UISegmentedControl *swapABXYButtonsSelector;
@property (strong, nonatomic) UISegmentedControl *audioOnPCSelector;
@property (strong, nonatomic) UISegmentedControl *codecSelector;
@property (strong, nonatomic) UISegmentedControl *hdrSelector;
@property (strong, nonatomic) UISegmentedControl *framePacingSelector;
@property (strong, nonatomic) UISegmentedControl *btMouseSelector;
@property (strong, nonatomic) UISegmentedControl *statsOverlaySelector;
@property (strong, nonatomic) UIScrollView *scrollView;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"

// This is okay because it's just an enum and access uses @available checks
@property(nonatomic) UIUserInterfaceStyle overrideUserInterfaceStyle;

#pragma clang diagnostic pop

- (instancetype)initWithWindow:(UIWindow*)window;
- (void) saveSettings;

@end
