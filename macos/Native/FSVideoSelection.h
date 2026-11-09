#import <Cocoa/Cocoa.h>

@interface FSChoiceButton : NSButton
@property BOOL primary;
@end
@implementation FSChoiceButton
- (void)drawRect:(NSRect)dirty {
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:18 yRadius:18];
    NSColor *color=(self.primary ? FSThemeAccent(fsDark) : FSThemeRaised(fsDark));
    [([self isHighlighted] ? [color colorWithAlphaComponent:0.75] : color) setFill]; [shape fill];
    if(!self.primary) { [[FSThemeText(fsDark) colorWithAlphaComponent:0.5] setStroke];shape.lineWidth=1;[shape stroke]; }
    [super drawRect:dirty];
}
@end

@interface FSChoiceRow : NSTableRowView
@end
@implementation FSChoiceRow
- (void)drawSelectionInRect:(NSRect)dirty {
    [FSThemeSelected(fsDark) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0,2) xRadius:12 yRadius:12] fill];
}
@end

// A sheet owned by the already-visible player, never by the catalogue window.
@interface FSVideoSelection : NSObject <NSTableViewDataSource,NSTableViewDelegate>
@property NSPanel *panel;
@property NSTableView *table;
@property NSArray<NSDictionary *> *files;
@property(copy) void (^completion)(NSNumber *);
- (void)showForPlayer:(NSWindow *)parent files:(NSArray<NSDictionary *> *)files title:(NSString *)title completion:(void (^)(NSNumber *))completion;
- (void)finish:(NSNumber *)index;
- (void)cancel;
@end
@implementation FSVideoSelection
- (void)showForPlayer:(NSWindow *)parent files:(NSArray<NSDictionary *> *)files title:(NSString *)title completion:(void (^)(NSNumber *))completion {
    self.files=files;self.completion=completion;
    CGFloat width=MIN(620,NSWidth(parent.contentView.bounds)-32),height=MIN(440,NSHeight(parent.contentView.bounds)-32);
    self.panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,width,height) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.panel.releasedWhenClosed=NO;self.panel.title=fsEnglish ? @"Choose an episode or file" : @"Выберите серию или файл";
    NSView *root=self.panel.contentView ?: [NSView new];self.panel.contentView=root;
    self.panel.appearance=[NSAppearance appearanceNamed:fsDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    self.panel.backgroundColor=FSThemeBackground(fsDark);
    NSTextField *heading=[NSTextField labelWithString:self.panel.title];heading.font=FSFont(21);
    NSTextField *name=[NSTextField labelWithString:title ?: @""];name.font=FSFont(13);name.maximumNumberOfLines=1;name.lineBreakMode=NSLineBreakByTruncatingMiddle;name.toolTip=title;
    for(NSTextField *label in @[heading,name]) { label.textColor=FSThemeText(fsDark); [label setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal]; }
    self.table=[NSTableView new];self.table.headerView=nil;self.table.rowHeight=64;self.table.intercellSpacing=NSMakeSize(0,4);self.table.allowsEmptySelection=NO;
    self.table.backgroundColor=self.panel.backgroundColor;self.table.focusRingType=NSFocusRingTypeNone;
    NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"video"];column.resizingMask=NSTableColumnAutoresizingMask;[self.table addTableColumn:column];self.table.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;
    self.table.frame=NSMakeRect(0,0,width-48,0);column.width=width-48;self.table.autoresizingMask=NSViewWidthSizable;
    self.table.dataSource=self;self.table.delegate=self;self.table.target=self;self.table.doubleAction=@selector(play:);
    NSScrollView *scroll=[NSScrollView new];scroll.documentView=self.table;scroll.hasVerticalScroller=YES;scroll.drawsBackground=NO;
    [scroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    FSChoiceButton *cancel=[self button:fsEnglish ? @"Cancel" : @"Отмена" primary:NO action:@selector(cancel:)];cancel.keyEquivalent=@"\e";
    FSChoiceButton *play=[self button:fsEnglish ? @"Play" : @"Воспроизвести" primary:YES action:@selector(play:)];play.keyEquivalent=@"\r";
    NSView *space=[NSView new];[space setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons=[NSStackView stackViewWithViews:@[space,cancel,play]];buttons.orientation=NSUserInterfaceLayoutOrientationHorizontal;buttons.distribution=NSStackViewDistributionFill;buttons.spacing=12;
    NSStackView *stack=[NSStackView stackViewWithViews:@[heading,name,scroll,buttons]];stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.distribution=NSStackViewDistributionFill;stack.alignment=NSLayoutAttributeLeading;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],[stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],[stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:20],[stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20],[name.widthAnchor constraintEqualToAnchor:stack.widthAnchor],[scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor],[scroll.heightAnchor constraintGreaterThanOrEqualToConstant:100],[buttons.widthAnchor constraintEqualToAnchor:stack.widthAnchor]]];
    [self.table reloadData];[self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [parent makeKeyAndOrderFront:nil];
    [parent beginSheet:self.panel completionHandler:^(NSModalResponse response){ [self cancel]; }];
    [self.panel makeFirstResponder:self.table];
}
- (FSChoiceButton *)button:(NSString *)title primary:(BOOL)primary action:(SEL)action {
    FSChoiceButton *button=[[FSChoiceButton alloc] initWithFrame:NSZeroRect];button.title=title;button.target=self;button.action=action;button.primary=primary;button.bordered=NO;button.font=FSFont(14);button.focusRingType=NSFocusRingTypeNone;
    NSColor *foreground=(primary ? FSThemeOnAccent(fsDark) : FSThemeText(fsDark));
    button.attributedTitle=[[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName:FSFont(14),NSForegroundColorAttributeName:foreground}];
    button.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[[button.widthAnchor constraintEqualToConstant:primary ? 172 : 110],[button.heightAnchor constraintEqualToConstant:38]]];return button;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return self.files.count; }
- (NSTableRowView *)tableView:(NSTableView *)table rowViewForRow:(NSInteger)row { return [FSChoiceRow new]; }
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary *file=self.files[row];NSTableCellView *cell=[NSTableCellView new];
    NSImageView *radio=[NSImageView new];radio.translatesAutoresizingMaskIntoConstraints=NO;cell.imageView=radio;[cell addSubview:radio];
    radio.image=[NSImage imageWithSystemSymbolName:row==table.selectedRow ? @"largecircle.fill.circle" : @"circle" accessibilityDescription:nil];radio.contentTintColor=FSThemeText(fsDark);
    NSString *path=file[@"name"] ?: @"";
    NSTextField *name=[NSTextField labelWithString:path];name.font=FSFont(14);name.maximumNumberOfLines=1;name.lineBreakMode=NSLineBreakByTruncatingMiddle;name.toolTip=path;name.translatesAutoresizingMaskIntoConstraints=NO;cell.textField=name;[cell addSubview:name];
    NSTextField *size=[NSTextField labelWithString:[NSByteCountFormatter stringFromByteCount:[file[@"size"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile]];size.font=FSFont(11);size.translatesAutoresizingMaskIntoConstraints=NO;[cell addSubview:size];
    for(NSTextField *label in @[name,size])label.textColor=FSThemeText(fsDark);
    [name setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [NSLayoutConstraint activateConstraints:@[[radio.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],[radio.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],[radio.widthAnchor constraintEqualToConstant:22],[radio.heightAnchor constraintEqualToConstant:22],[name.leadingAnchor constraintEqualToAnchor:radio.trailingAnchor constant:12],[name.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],[name.topAnchor constraintEqualToAnchor:cell.topAnchor constant:10],[size.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],[size.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:5]]];
    return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    for(NSInteger row=0;row<self.files.count;row++) {
        NSTableCellView *cell=[self.table viewAtColumn:0 row:row makeIfNecessary:NO];
        cell.imageView.image=[NSImage imageWithSystemSymbolName:row==self.table.selectedRow ? @"largecircle.fill.circle" : @"circle" accessibilityDescription:nil];
    }
}
- (void)play:(id)sender { NSInteger row=self.table.selectedRow;if(row>=0 && row<self.files.count)[self finish:self.files[row][@"index"]]; }
- (void)cancel:(id)sender { [self cancel]; }
- (void)cancel { [self finish:nil]; }
- (void)finish:(NSNumber *)index {
    void (^completion)(NSNumber *)=self.completion;if(!completion)return;self.completion=nil;
    if(self.panel.sheetParent)[self.panel.sheetParent endSheet:self.panel returnCode:index ? NSModalResponseOK : NSModalResponseCancel];
    [self.panel orderOut:nil];completion(index);
}
@end
