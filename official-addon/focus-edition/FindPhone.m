// FindPhone.m —— 找手机：响铃 + 震动 + 镜片提示
#import "FindPhone.h"
#import "MusicBridge.h"
#import "ResearchUI.h"
#import <AudioToolbox/AudioToolbox.h>

static NSInteger RingCount=0;
BOOL TIOFindPhoneRing(void){
    // 连续播放 4 次系统提示音并震动（每次间隔 0.8s）
    RingCount=0;
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(NSTimer *t){
        RingCount++;
        AudioServicesPlaySystemSound(1005);
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        if(RingCount>=4)[t invalidate];
    }];
    [timer fire];
    TMMusicBridge *bridge=[TMMusicBridge shared];
    if(bridge.failed)[bridge reset];
    [bridge openWithCover:nil lyrics:@[@{@"ms":@0,@"text":@"📱 手机在这（已响铃）"}]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        TMMusicBridge *b=[TMMusicBridge shared];
        if(![b failed])[b close];
    });
    return YES;
}
@interface TIOFindPhonePanel:UITableViewController
@property(nonatomic,strong) NSDate *lastAt;
@end
@implementation TIOFindPhonePanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"找手机";TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOFeatureHeader(@"手机响铃 + 镜片提示",@"在眼镜上看不见手机时，点这里让手机发声震动，眼镜同步显示提示。",@"iphone.radiowaves.left.and.right");}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 1;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==0?@"声音走系统提示音（静音模式下仍会震动；如完全静音可能不发声）。":nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    if(ip.section==0){c.textLabel.text=@"🔔 响铃找手机";c.detailTextLabel.text=_lastAt?[NSString stringWithFormat:@"上次触发：%@",[NSDateFormatter localizedStringFromDate:_lastAt dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle]]:@"点击后手机响 4 声并震动";}
    else{c.textLabel.text=@"说明";c.detailTextLabel.text=@"需要手机离身不远且能听到声音；眼镜需已连接蓝牙。";}
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];if(ip.section==0){_lastAt=NSDate.date;TIOFindPhoneRing();[t reloadData];}}
@end
UIViewController *TIOFindPhoneController(void){return [[TIOFindPhonePanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
