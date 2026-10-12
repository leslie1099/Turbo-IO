// ReminderVoice.m —— 定时提醒 · 语音版
// 录音(5s) → 硅基流动 SenseVoice 识别 → 已配置模型解析 JSON {title,start,end}
// → TIOAppleCreateSchedule（苹果日历+提醒事项双写，与待办同步页日程区同一能力）。
#import "ReminderVoice.h"
#import "CloudSubtitle.h"
#import "AppleCalendarSync.h"
#import "ResearchUI.h"
#import <AVFoundation/AVFoundation.h>

static NSString *VoiceState=@"未开始";
static NSMutableArray *VoiceLog;

static void VoiceLogAdd(NSString *line){
    static dispatch_once_t once;dispatch_once(&once,^{VoiceLog=[NSMutableArray new];});
    @synchronized(VoiceLog){[VoiceLog insertObject:line atIndex:0];while(VoiceLog.count>30)[VoiceLog removeLastObject];}
}

@interface TIOReminderVoiceEngine:NSObject<AVAudioRecorderDelegate>
@property(nonatomic,strong) AVAudioRecorder *recorder;
@property(nonatomic,copy) NSString *path;
@property(nonatomic,assign) BOOL busy;
@end
@implementation TIOReminderVoiceEngine
+ (instancetype)shared{static TIOReminderVoiceEngine *one=nil;static dispatch_once_t once;dispatch_once(&once,^{one=[TIOReminderVoiceEngine new];});return one;}
- (void)record{
    if(_busy)return;_busy=YES;
    VoiceState=@"正在录音（5 秒）…";
    AVAudioSession *session=[AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryRecord withOptions:AVAudioSessionCategoryOptionDuckOthers error:nil];
    [session setActive:YES error:nil];
    _path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"reminder_%d.wav",(int)NSDate.date.timeIntervalSince1970]];
    NSDictionary *settings=@{AVFormatIDKey:@(kAudioFormatLinearPCM),AVSampleRateKey:@16000,AVNumberOfChannelsKey:@1,AVLinearPCMBitDepthKey:@16,AVLinearPCMIsBigEndianKey:@NO,AVLinearPCMIsFloatKey:@NO};
    NSError *error=nil;
    AVAudioRecorder *r=[[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:_path] settings:settings error:&error];
    if(!r||error){VoiceState=@"录音初始化失败（麦克风权限？）";_busy=NO;return;}
    _recorder=r;r.delegate=self;
    if(![r recordForDuration:5]){VoiceState=@"录音启动失败";_busy=NO;return;}
}
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag{
    _recorder=nil;
    NSData *audio=[NSData dataWithContentsOfFile:_path];
    if(!audio.length){VoiceState=@"未录到声音，请重试";_busy=NO;return;}
    VoiceState=@"识别中…";
    __weak typeof(self) weak=self;
    TIOCloudSubtitleTranscribe(audio,^(NSString *text,NSString *error){
        TIOReminderVoiceEngine *s=weak;if(!s)return;
        if(error){VoiceState=[NSString stringWithFormat:@"识别失败：%@",error];s.busy=NO;return;}
        NSString *clean=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(!clean.length){VoiceState=@"未识别到内容，请重试";s.busy=NO;return;}
        VoiceLogAdd([NSString stringWithFormat:@"语音：%@",clean]);
        [s parseAndCreate:clean];
    });
}
- (void)parseAndCreate:(NSString *)utterance{
    VoiceState=@"解析时间与事项…";
    NSString *prompt=[NSString stringWithFormat:
        @"从这句话中提取日程提醒：\"%@\"\n"
        @"返回严格 JSON（不要其他文字）：{\"title\":\"事项\",\"start\":\"ISO8601 开始时间\",\"end\":\"ISO8601 结束时间\"}\n"
        @"规则：相对时间按当前时间推算（如\"下午3点\"=今天15:00，\"明天9点\"=明天09:00，\"半小时后\"=当前+30分钟）；\n"
        @"end 缺省 = start 后 1 小时；无法确定时间时 start 用当前时间+10分钟。当前时间是 %@。",
        utterance,[NSISO8601DateFormatter new]?[[NSISO8601DateFormatter new] stringFromDate:NSDate.date]:@""];
    __weak typeof(self) weak=self;
    TIOCloudSubtitleChat(prompt,^(NSString *answer,NSString *error){
        TIOReminderVoiceEngine *s=weak;if(!s)return;
        if(error){VoiceState=[NSString stringWithFormat:@"解析失败：%@",error];s.busy=NO;return;}
        [s createFromJSON:answer utterance:utterance];
    });
}
- (void)createFromJSON:(NSString *)answer utterance:(NSString *)utterance{
    // 提取首个 {...} JSON
    NSRange range=[answer rangeOfString:@"{"];
    NSRange end=[answer rangeOfString:@"}" options:NSBackwardsSearch];
    NSDictionary *parsed=nil;
    if(range.location!=NSNotFound&&end.location!=NSNotFound&&end.location>range.location){
        NSString *json=[answer substringWithRange:NSMakeRange(range.location,end.location-range.location+1)];
        parsed=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    }
    NSDictionary *candidate=@{
        @"title":[parsed isKindOfClass:NSDictionary.class]&&[parsed[@"title"] isKindOfClass:NSString.class]&&[parsed[@"title"] length]?parsed[@"title"]:utterance,
        @"start":[parsed isKindOfClass:NSDictionary.class]&&[parsed[@"start"] isKindOfClass:NSString.class]?parsed[@"start"]:@"",
        @"end":[parsed isKindOfClass:NSDictionary.class]&&[parsed[@"end"] isKindOfClass:NSString.class]?parsed[@"end"]:@""};
    NSData *jsonData=[NSJSONSerialization dataWithJSONObject:candidate options:0 error:nil];
    NSDictionary *valid=jsonData?TIOScheduleArguments([[NSString alloc]initWithData:jsonData encoding:NSUTF8StringEncoding]):nil;
    if(!valid){VoiceState=@"未能解析出有效时间，请说得更具体（如：下午三点提醒我开会）";_busy=NO;return;}
    __weak typeof(self) weak=self;
    TIOAppleCreateSchedule(valid,^(NSDictionary *result){
        TIOReminderVoiceEngine *s=weak;if(!s)return;
        NSString *status=result[@"status"]?:@"unknown";
        if([status isEqual:@"created"]||[status isEqual:@"partial"]){
            VoiceState=[NSString stringWithFormat:@"已创建：%@ · %@",valid[@"title"],valid[@"start"]];
            VoiceLogAdd([NSString stringWithFormat:@"已建日程：%@ %@",valid[@"title"],valid[@"start"]]);
        }else{
            VoiceState=[NSString stringWithFormat:@"创建失败：%@",status];
        }
        s.busy=NO;
    });
}
@end

@interface TIOReminderVoicePanel:UITableViewController
@end
@implementation TIOReminderVoicePanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"定时提醒 · 语音";TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOFeatureHeader(@"说出提醒，自动建日程",@"例：下午三点提醒我开会 / 明天九点去拿快递。识别+解析后写入苹果日历与提醒事项，系统到点提醒。",@"alarm");}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 3;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?1:(s==1?1:MIN(VoiceLog.count,10));}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"录制",@"状态",@"记录"][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==0?@"需要麦克风权限与提醒事项权限；已建日程显示在“待办同步”页日程区。":nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    if(ip.section==0){c.textLabel.text=@"● 录一句提醒";c.detailTextLabel.text=@"点击后录音 5 秒，自动识别并创建";}
    else if(ip.section==1){c.textLabel.text=VoiceState;}
    else{c.textLabel.text=VoiceLog[ip.row];}
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];if(ip.section==0){(TIOReminderVoiceEngine *)[TIOReminderVoiceEngine shared] record;}[t reloadData];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.tableView reloadData];}
@end
UIViewController *TIOReminderVoiceController(void){return [[TIOReminderVoicePanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
