// ClipboardRelay.m —— 字幕接力：轮询剪贴板，检测到新增文本即推眼镜
// 配合系统“实时字幕 → 拷贝字幕”实现任意 App 音频（含耳机内音）字幕上镜；
// 也是通用方案：任何 App 复制文本即推眼镜。
#import "ClipboardRelay.h"
#import "MusicBridge.h"
#import "ResearchUI.h"

static NSString *LastClipboard=nil;   // 上次读到的剪贴板全文
static NSString *LastPushed=nil;      // 上次推送的文本（去重）
static NSDate *LastPushAt=nil;        // 上次推送时间（控制关闭时机）
static NSTimer *PollTimer=nil;        // 前台轮询定时器

BOOL TIOClipboardRelayEnabled(void){return [Prefs boolForKey:@"clipboardRelayEnabled"];}
void TIOClipboardRelaySetEnabled(BOOL on){[Prefs setBool:on forKey:@"clipboardRelayEnabled"];}

static NSString *Trim(NSString *s){return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];}

static void PushText(NSString *text){
    if(!text.length)return;
    NSString *clean=Trim(text);
    if(clean.length<4)return;                    // 过短视为误触
    if(clean.length>300)clean=[clean substringToIndex:300];
    if([clean isEqualToString:LastPushed])return; // 重复不推
    LastPushed=clean;
    LastPushAt=NSDate.date;
    TMMusicBridge *bridge=[TMMusicBridge shared];
    if(bridge.failed)[bridge reset];
    [bridge openWithCover:nil lyrics:@[@{@"ms":@0,@"text":clean}]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        TMMusicBridge *b=[TMMusicBridge shared];
        // 距上次推送已满 8 秒才关闭；期间有新推送则保持显示
        if(![b failed]&&LastPushAt&&[LastPushAt timeIntervalSinceNow]<=-8)[b close];
    });
}

static void PollClipboard(void){
    NSString *now=UIPasteboard.general.string;
    if(!now.length)return;
    NSString *delta=nil;
    if(LastClipboard.length&&[now hasPrefix:LastClipboard]&&now.length>LastClipboard.length){
        delta=[now substringFromIndex:LastClipboard.length]; // 实时字幕累积全文 → 只推新增段
    }else if(![now isEqualToString:LastClipboard]){
        delta=now;                                           // 复制了全新内容 → 推整段
    }
    LastClipboard=now;
    if(delta.length)PushText(delta);
}

static void EnsureTimer(void){
    if(PollTimer)return;
    PollTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t){PollClipboard();}];
    [PollTimer fire];
}

@interface TIOClipboardRelayPanel:UITableViewController
@property(nonatomic,strong) NSString *lastPreview;
- (UISwitch *)switchView;
@end
@implementation TIOClipboardRelayPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"字幕接力";TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOFeatureHeader(@"剪贴板 → 眼镜",@"系统实时字幕拷贝后，眼镜自动显示新增字幕；任何 App 复制文本也会推送到眼镜。",@"doc.on.clipboard");}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 3;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 1;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{
    if(s==0)return @"开启后每 1 秒读取一次剪贴板（系统可能显示“粘贴自…”提示），关闭即停止。建议听书时才开。";
    if(s==1)return @"使用步骤：① 设置→辅助功能→实时字幕→打开（选 iPhone 音频）；② 播放听书/视频（耳机也可以）；③ 听一段后点实时字幕浮窗右上角“…→拷贝字幕”，眼镜立即显示新增内容。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    if(ip.section==0){
        c.textLabel.text=@"开启字幕接力";c.accessoryView=[self switchView];
    }else if(ip.section==1){
        c.textLabel.text=@"最近推送";c.detailTextLabel.text=_lastPreview?:@"暂无，拷贝字幕或复制文本后自动推送";
    }else{
        c.textLabel.text=@"说明";c.detailTextLabel.text=@"耳机内音也能转：系统实时字幕转写的是整机音频，不依赖扬声器。";
    }
    return c;
}
- (UISwitch *)switchView{
    UISwitch *s=[[UISwitch alloc]init];s.on=TIOClipboardRelayEnabled();
    [s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];return s;
}
- (void)toggle:(UISwitch *)s{
    TIOClipboardRelaySetEnabled(s.on);
    if(s.on){LastClipboard=UIPasteboard.general.string;EnsureTimer();}
    else if(PollTimer){[PollTimer invalidate];PollTimer=nil;}
    [self.tableView reloadData];
}
- (void)viewDidAppear:(BOOL)a{[super viewDidAppear:a];if(TIOClipboardRelayEnabled())EnsureTimer();[self.tableView reloadData];}
@end
UIViewController *TIOClipboardRelayController(void){return [[TIOClipboardRelayPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
