// ClipboardRelay.m —— 字幕接力：轮询剪贴板，检测到新增文本即推眼镜
// v2：状态全透明——显示眼镜连接状态、推送结果/失败原因；定时器加入 CommonModes（锁屏听书仍轮询）
#import "ClipboardRelay.h"
#import "MusicBridge.h"
#import "ResearchUI.h"
#import "ProtocolContext.h"

static NSString *LastClipboard=nil;   // 上次读到的剪贴板全文
static NSString *LastPushed=nil;      // 上次推送的文本（去重）
static NSDate *LastPushAt=nil;        // 上次推送时间（控制关闭时机）
static NSTimer *PollTimer=nil;        // 轮询定时器
static NSString *RelayState=@"未开启"; // 状态行：监听中/已推送/失败原因/眼镜未连接
static NSString *RelayPreview=nil;    // 最近一次推送的文本

BOOL TIOClipboardRelayEnabled(void){return [[NSUserDefaults standardUserDefaults] boolForKey:@"clipboardRelayEnabled"];}
void TIOClipboardRelaySetEnabled(BOOL on){[[NSUserDefaults standardUserDefaults] setBool:on forKey:@"clipboardRelayEnabled"];}

static NSString *Trim(NSString *s){return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];}

static void Notify(void){dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:@"TIOClipboardRelayChanged" object:nil];});}

static void PushText(NSString *text){
    if(!text.length)return;
    NSString *clean=Trim(text);
    if(clean.length<4)return;                    // 过短视为误触
    if(clean.length>300)clean=[clean substringToIndex:300];
    if([clean isEqualToString:LastPushed])return; // 重复不推
    LastPushed=clean;
    LastPushAt=NSDate.date;
    RelayPreview=clean;
    NSString *device=TIOProtocolDevice();
    if(!device.length){RelayState=@"眼镜未连接：先连接眼镜再复制字幕";Notify();return;}
    TMMusicBridge *bridge=[TMMusicBridge shared];
    if(bridge.failed)[bridge reset];
    [bridge openWithCover:nil lyrics:@[@{@"ms":@0,@"text":clean}]];
    if(bridge.failed)RelayState=[NSString stringWithFormat:@"推镜失败：%@",bridge.note];
    else RelayState=bridge.note?:@"已推送，等待眼镜确认…";
    Notify();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        TMMusicBridge *b=[TMMusicBridge shared];
        if(![b failed]&&LastPushAt&&[LastPushAt timeIntervalSinceNow]<=-8)[b close];
    });
}

static void PollClipboard(void){
    NSString *now=[UIPasteboard generalPasteboard].string;
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
    PollTimer=[NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t){PollClipboard();}];
    [[NSRunLoop mainRunLoop] addTimer:PollTimer forMode:NSRunLoopCommonModes];
    [PollTimer fire];
}

@interface TIOClipboardRelayPanel:UITableViewController
@end
@implementation TIOClipboardRelayPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"字幕接力";TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOFeatureHeader(@"剪贴板 → 眼镜",@"系统实时字幕拷贝后，眼镜自动显示新增字幕；任何 App 复制文本也会推送到眼镜。",@"doc.on.clipboard");
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:) name:@"TIOClipboardRelayChanged" object:nil];
    if(TIOClipboardRelayEnabled())EnsureTimer();
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh:(NSNotification *)n{[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 3;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{
    if(s==0)return 1;
    if(s==1)return 3; // 眼镜连接 / 推送状态 / 最近推送
    return 1;
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{
    if(s==0)return @"开启后每 1 秒读取一次剪贴板（系统可能显示“粘贴自…”提示），关闭即停止。建议听书时才开。";
    if(s==1)return @"若显示“推镜失败：眼镜未回执”，请确认眼镜已连接并刷入含音乐页的固件（FOCUS-04 含音乐）。";
    return @"使用步骤：① 设置→辅助功能→实时字幕→打开（选 iPhone 音频）；② 播放听书/视频（耳机也可以）；③ 听一段后点实时字幕浮窗右上角“…→拷贝字幕”，眼镜立即显示新增内容。";
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    if(ip.section==0){
        c.textLabel.text=@"开启字幕接力";
        UISwitch *s=[[UISwitch alloc]init];s.on=TIOClipboardRelayEnabled();
        [s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;
    }else if(ip.section==1){
        if(ip.row==0){
            NSString *device=TIOProtocolDevice();
            c.textLabel.text=@"眼镜连接";
            c.detailTextLabel.text=device.length?@"已连接（正在同步）":@"未连接——推镜不会生效";
            c.imageView.image=[UIImage systemImageNamed:device.length?@"checkmark.circle.fill":@"exclamationmark.triangle.fill"];
            c.imageView.tintColor=device.length?UIColor.systemGreenColor:UIColor.systemRedColor;
        }else if(ip.row==1){
            c.textLabel.text=@"推送状态";
            c.detailTextLabel.text=RelayState?:@"未开启";
        }else{
            c.textLabel.text=@"最近推送";
            c.detailTextLabel.text=RelayPreview?:@"暂无，拷贝字幕或复制文本后自动推送";
        }
    }else{
        c.textLabel.text=@"说明";
        c.detailTextLabel.text=@"耳机内音也能转：系统实时字幕转写的是整机音频，不依赖扬声器。";
    }
    return c;
}
- (void)toggle:(UISwitch *)s{
    TIOClipboardRelaySetEnabled(s.on);
    if(s.on){LastClipboard=[UIPasteboard generalPasteboard].string;RelayState=@"监听中…（每 1 秒读剪贴板）";EnsureTimer();}
    else if(PollTimer){[PollTimer invalidate];PollTimer=nil;RelayState=@"已关闭";}
    [self.tableView reloadData];
}
- (void)viewDidAppear:(BOOL)a{[super viewDidAppear:a];if(TIOClipboardRelayEnabled())EnsureTimer();[self.tableView reloadData];}
- (void)viewWillDisappear:(BOOL)a{[super viewWillDisappear:a];}
@end
UIViewController *TIOClipboardRelayController(void){return [[TIOClipboardRelayPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
