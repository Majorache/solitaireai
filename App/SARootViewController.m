#import "SARootViewController.h"
#import "SAShared.h"
#import <ReplayKit/ReplayKit.h>

static NSString *const SABroadcastExtensionBundleID =
    @"com.solitaireai.app.SolitaireAICapture";

@interface SARootViewController ()
@property (nonatomic, strong) UITextField *serverField;
@property (nonatomic, strong) UITextField *intervalField;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISwitch *dryRunSwitch;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) RPSystemBroadcastPickerView *picker;
@property (nonatomic, strong) NSDictionary *session;
@property (nonatomic, assign) BOOL editingFields;
@end

@implementation SARootViewController

#pragma mark - Settings

- (void)saveConfig {
  NSString *server = [self.serverField.text
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSDictionary *config = @{
    @"server": server ?: @"",
    @"interval": @(MAX(0.5, self.intervalField.text.doubleValue)),
    @"enabled": @(self.enabledSwitch.isOn),
    @"dryRun": @(self.dryRunSwitch.isOn),
  };
  self.statusLabel.text = @"Saving…";
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSDictionary *session = SASyncPost(@{@"config": config});
    dispatch_async(dispatch_get_main_queue(), ^{
      if (session) {
        self.session = session;
        SALog(@"settings saved");
      }
      [self render];
      if (!session) {
        self.statusLabel.text = @"Could not reach the server — check your "
                                @"internet connection and try again.";
        self.statusLabel.textColor = UIColor.systemRedColor;
      }
    });
  });
}

#pragma mark - UI

- (UIStackView *)row:(NSString *)title control:(UIView *)control {
  UILabel *label = [UILabel new];
  label.text = title;
  label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
  UIStackView *row =
      [[UIStackView alloc] initWithArrangedSubviews:@[ label, control ]];
  row.axis = UILayoutConstraintAxisHorizontal;
  row.alignment = UIStackViewAlignmentCenter;
  row.spacing = 12;
  [control setContentHuggingPriority:UILayoutPriorityDefaultLow
                             forAxis:UILayoutConstraintAxisHorizontal];
  return row;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Solitaire AI";
  self.view.backgroundColor = UIColor.systemBackgroundColor;

  self.statusLabel = [UILabel new];
  self.statusLabel.numberOfLines = 0;
  self.statusLabel.font = [UIFont systemFontOfSize:14];
  self.statusLabel.text = @"Loading…";

  self.serverField = [UITextField new];
  self.serverField.placeholder = @"Leave empty to use the built-in server";
  self.serverField.borderStyle = UITextBorderStyleRoundedRect;
  self.serverField.autocapitalizationType = UITextAutocapitalizationTypeNone;
  self.serverField.autocorrectionType = UITextAutocorrectionTypeNo;
  self.serverField.keyboardType = UIKeyboardTypeURL;
  self.serverField.delegate = (id<UITextFieldDelegate>)self;

  self.intervalField = [UITextField new];
  self.intervalField.borderStyle = UITextBorderStyleRoundedRect;
  self.intervalField.keyboardType = UIKeyboardTypeDecimalPad;
  self.intervalField.delegate = (id<UITextFieldDelegate>)self;
  [self.intervalField.widthAnchor constraintEqualToConstant:80].active = YES;

  self.enabledSwitch = [UISwitch new];
  self.dryRunSwitch = [UISwitch new];

  UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
  [save setTitle:@"Save settings" forState:UIControlStateNormal];
  [save addTarget:self
                action:@selector(saveConfig)
      forControlEvents:UIControlEventTouchUpInside];

  UIButton *capture = [UIButton buttonWithType:UIButtonTypeSystem];
  [capture setTitle:@"Start / stop screen capture" forState:UIControlStateNormal];
  [capture addTarget:self
                action:@selector(captureTapped)
      forControlEvents:UIControlEventTouchUpInside];

  UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
  [reset setTitle:@"Clear activity" forState:UIControlStateNormal];
  [reset addTarget:self
                action:@selector(resetTapped)
      forControlEvents:UIControlEventTouchUpInside];

  self.logView = [UITextView new];
  self.logView.editable = NO;
  self.logView.font = [UIFont monospacedSystemFontOfSize:11
                                                  weight:UIFontWeightRegular];
  self.logView.backgroundColor = UIColor.secondarySystemBackgroundColor;
  self.logView.layer.cornerRadius = 8;

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
    self.statusLabel,
    [self row:@"Server" control:self.serverField],
    [self row:@"Interval (s)" control:self.intervalField],
    [self row:@"Bot enabled" control:self.enabledSwitch],
    [self row:@"Dry run (no taps)" control:self.dryRunSwitch],
    save, capture, reset, self.logView
  ]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.spacing = 12;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:stack];

  UILayoutGuide *g = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [stack.topAnchor constraintEqualToAnchor:g.topAnchor constant:16],
    [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
    [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
    [stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-16],
  ]];

  UITapGestureRecognizer *tap =
      [[UITapGestureRecognizer alloc] initWithTarget:self.view
                                              action:@selector(endEditing:)];
  tap.cancelsTouchesInView = NO;
  [self.view addGestureRecognizer:tap];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
  self.editingFields = YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
  self.editingFields = NO;
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                               repeats:YES
                                                 block:^(NSTimer *t) {
                                                   [self reload];
                                                 }];
  [self reload];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  [self.timer invalidate];
  self.timer = nil;
}

/// Opens the system screen-recording sheet so the recorder can be started.
- (void)captureTapped {
  if (!self.picker) {
    RPSystemBroadcastPickerView *picker = [[RPSystemBroadcastPickerView alloc]
        initWithFrame:CGRectMake(0, 0, 1, 1)];
    picker.preferredExtension = SABroadcastExtensionBundleID;
    picker.showsMicrophoneButton = NO;
    picker.hidden = YES;
    [self.view addSubview:picker];
    self.picker = picker;
  }
  for (UIView *sub in self.picker.subviews) {
    if ([sub isKindOfClass:UIButton.class]) {
      [(UIButton *)sub sendActionsForControlEvents:UIControlEventTouchUpInside];
      return;
    }
  }
}

- (void)resetTapped {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSDictionary *session = SASyncPost(@{@"clear": @YES});
    dispatch_async(dispatch_get_main_queue(), ^{
      if (session) self.session = session;
      [self render];
    });
  });
}

#pragma mark - Status

- (void)reload {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSDictionary *session = SASyncFetch();
    dispatch_async(dispatch_get_main_queue(), ^{
      if (session) self.session = session;
      [self render];
    });
  });
}

- (void)render {
  NSDictionary *config = self.session[@"config"];
  if ([config isKindOfClass:NSDictionary.class] && !self.editingFields) {
    self.serverField.text = [config[@"server"] isKindOfClass:NSString.class]
                                ? config[@"server"]
                                : @"";
    self.intervalField.text =
        [NSString stringWithFormat:@"%.1f", [config[@"interval"] doubleValue]];
    self.enabledSwitch.on = [config[@"enabled"] boolValue];
    self.dryRunSwitch.on = [config[@"dryRun"] boolValue];
  }

  NSArray *log = [self.session[@"log"] isKindOfClass:NSArray.class]
                     ? self.session[@"log"]
                     : @[];
  NSString *tail = [log componentsJoinedByString:@"\n"];
  self.logView.text = tail.length ? tail : @"No activity yet.";
  if (tail.length) {
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length, 0)];
  }

  NSDictionary *status = [self.session[@"status"] isKindOfClass:NSDictionary.class]
                             ? self.session[@"status"]
                             : @{};
  NSTimeInterval age =
      NSDate.date.timeIntervalSince1970 - [status[@"updated"] doubleValue];
  BOOL live = [status[@"broadcasting"] boolValue] && age < 15;

  NSString *state;
  UIColor *color = UIColor.labelColor;
  if (!self.session) {
    state = @"Cannot reach the server. Check your internet connection.";
    color = UIColor.systemRedColor;
  } else if (live) {
    state = self.dryRunSwitch.isOn
                ? @"Watching your screen (dry run — moves are only listed)"
                : @"Watching your screen and playing moves";
    color = UIColor.systemGreenColor;
  } else if (!self.enabledSwitch.isOn) {
    state = @"Bot is off. Turn on “Bot enabled”, then Save settings.";
  } else if ([tail containsString:@"error:"]) {
    state = @"Connected, but the server reported a problem — see below.";
    color = UIColor.systemOrangeColor;
  } else {
    state = @"Tap “Start / stop screen capture”, choose “Solitaire AI Capture”, "
            @"start it, then open your game.";
  }
  self.statusLabel.text = state;
  self.statusLabel.textColor = color;
}

@end
