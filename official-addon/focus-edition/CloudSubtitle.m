// CloudSubtitle.m —— 云端字幕 · 麦克风版
// 链路：AVAudioRecorder 分段录音(4s/wav 16k mono) → 音量门控 → 硅基流动
// /v1/audio/transcriptions(SenseVoiceSmall) → 可选 DeepSeek 翻译 → 推眼镜。
// 说明：内部音频(ReplayKit 广播扩展)在侧载免费签名环境不可行，本模块只收麦克风；
// 手机外放听书/会议/口译场景可用，耳机场景不可用。
#import "CloudSubtitle.h"
#import "Core.h"
#import "MusicBridge.h"
#import "ResearchUI.h"
#import <AVFoundation/AVFoundation.h>
#import <Security/Security.h>

static NSString *const Domain=@"io.turboio.official-private-addon";
static NSString *const ASRModel=@"FunAudioLLM/SenseVoiceSmall";
static NSString *const kCloudSubtitleRunning=@"io.turboio.subtitle.running";
static NSString *const kCloudSubtitleTranslate=@"io.turboio.subtitle.translate";
static NSString *const kCloudSubtitleTarget=@"io.turboio.subtitle.target";

// ---- 钥匙串读取（与模型接口配置同一 service/account：endpoint URL）----
static NSString *SubtitleKey(void){
    NSString *endpoint=[[NSUserDefaults standardUserDefaults] stringForKey:@"endpoint"]?:@"";
    if(!endpoint.length)return @"";
    NSDictionary *q=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:Domain,(__bridge id)kSecAttrAccount:endpoint,(__bridge id)kSecReturnData:@YES};
    CFTypeRef out=NULL;if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&out)!=errSecSuccess)return @"";
    return [[NSString alloc]initWithData:CFBridgingRelease(out) encoding:NSUTF8StringEncoding]?:@"";
}

static NSDictionary *SubtitleStatus(void){return @{@"running":@([[NSUserDefaults standardUserDefaults] boolForKey:kCloudSubtitleRunning]),@"translate":@([[NSUserDefaults standardUserDefaults] boolForKey:kCloudSubtitleTranslate]),@"target":[[NSUserDefaults standardUserDefaults] stringForKey:kCloudSubtitleTarget]?:@"简体中文"};}
static NSString *SubtitleState=@"未开始";
static NSMutableArray *SubtitleLog;

// ---- 由用户已配 endpoint 推导硅基流动 host；Key 从钥匙串按 endpoint 读取 ----
static NSString *ASRURL(void){
    NSString *endpoint=[[NSUserDefaults standardUserDefaults] stringForKey:@"endpoint"]?:@"";
    NSURL *url=[NSURL URLWithString:endpoint];
    if(!url.scheme.length||!url.host.length)return @"";
    return [NSString stringWithFormat:@"%@://%@/v1/audio/transcriptions",url.scheme,url.host];
}
static NSString *ChatURL(void){
    NSString *endpoint=[[NSUserDefaults standardUserDefaults] stringForKey:@"endpoint"]?:@"";
    NSURL *url=[NSURL URLWithString:endpoint];
    return url.scheme.length?endpoint:@"";
}
static NSString *SubtitleModel(void){return [[NSUserDefaults standardUserDefaults] stringForKey:@"model"]?:@"deepseek-ai/DeepSeek-V3.2";}

static void SubtitleLogAdd(NSString *line){
    static dispatch_once_t once;dispatch_once(&once,^{SubtitleLog=[NSMutableArray new];});
    @synchronized(SubtitleLog){[SubtitleLog insertObject:line atIndex:0];while(SubtitleLog.count>50)[SubtitleLog removeLastObject];}
}

// ---- 推一行到眼镜（音乐页通道，持续显示；调用方负责停） ----
static void ShowLineOnGlasses(NSString *text){
    if(!text.length)return;
    TMMusicBridge *bridge=[TMMusicBridge shared];
    if(bridge.failed)[bridge reset];
    [bridge openWithCover:nil lyrics:@[@{@"ms":@0,@"text":text}]];
    SubtitleLogAdd([NSString stringWithFormat:@"推镜：%@",text]);
}

// ---- ASR：multipart 上传音频到硅基流动 ----
void TIOCloudSubtitleTranscribe(NSData *audio, void (^done)(NSString *text, NSString *error)){
    if(![audio isKindOfClass:NSData.class]||!audio.length||!done)return;
    NSString *url=ASRURL(),*key=SubtitleKey();
    if(!url.length||!key.length){done(nil,@"未配置模型接口密钥：请在“模型与接口”配置硅基流动 Key 与 endpoint。");return;}
    NSString *boundary=@"----TIOCloudSubtitleBoundary";
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod=@"POST";
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [req setTimeoutInterval:30];
    NSMutableData *body=[NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:audio];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n%@\r\n--%@--\r\n",boundary,ASRModel,boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:body];
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary] forHTTPHeaderField:@"Content-Type"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *resp,NSError *err){
        if(err){done(nil,err.localizedDescription.length?err.localizedDescription:@"网络错误");return;}
        NSDictionary *json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        if(![json isKindOfClass:NSDictionary.class]){done(nil,@"ASR 返回异常（非 JSON）；请检查 Key 余额或模型名");return;}
        NSString *text=[json[@"text"] isKindOfClass:NSString.class]?json[@"text"]:@"";
        if(!text.length&&[json[@"error"] isKindOfClass:NSString.class]){done(nil,json[@"error"]);return;}
        done(text,nil);
    }] resume];
}

// ---- 翻译：非流式 chat（DeepSeek）----
void TIOCloudSubtitleChat(NSString *prompt,void (^done)(NSString *answer,NSString *error)){
    if(!prompt.length){done(nil,nil);return;}
    NSString *url=ChatURL(),*key=SubtitleKey(),*model=SubtitleModel();
    if(!url.length||!key.length){done(nil,@"未配置模型接口密钥：请在“模型与接口”配置硅基流动 Key 与 endpoint。");return;}
    NSDictionary *payload=TIOChatRequestWithHistory(model,prompt,@[]);
    if(!payload){done(nil,@"请求参数错误");return;}
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod=@"POST";
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setTimeoutInterval:30];
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *resp,NSError *err){
        if(err){done(nil,err.localizedDescription.length?err.localizedDescription:@"网络错误");return;}
        NSDictionary *json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        NSArray *choices=[json[@"choices"] isKindOfClass:NSArray.class]?json[@"choices"]:nil;
        NSString *content=choices.count?choices[0][@"message"][@"content"]:nil;
        if(![content isKindOfClass:NSString.class]){done(nil,@"返回异常；请检查 Key 余额");return;}
        done(content,nil);
    }] resume];
}
static void TranslateText(NSString *text,NSString *target,void (^done)(NSString *translation,NSString *error)){
    if(!text.length){done(nil,nil);return;}
    NSString *prompt=[NSString stringWithFormat:@"把下面内容翻译成%@，只输出译文，不要解释：\n%@",target,text];
    TIOCloudSubtitleChat(prompt,^(NSString *answer,NSString *err){done(answer,err);});
}

// ---- 录音引擎：分段循环 ----
@interface TIOCloudSubtitleEngine:NSObject<AVAudioRecorderDelegate>
@property(nonatomic,strong) AVAudioRecorder *recorder;
@property(nonatomic,copy) NSString *recordingPath;
@property(nonatomic,strong) NSTimer *meterTimer;
@property(nonatomic,assign) float peak;
@property(nonatomic,assign) BOOL stopping,processing;
@property(nonatomic,strong) NSDate *lastShownAt;
- (void)begin;
- (void)stop;
@end
@implementation TIOCloudSubtitleEngine
+ (instancetype)shared{static TIOCloudSubtitleEngine *one=nil;static dispatch_once_t once;dispatch_once(&once,^{one=[TIOCloudSubtitleEngine new];});return one;}
- (void)begin{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kCloudSubtitleRunning];
    SubtitleState=@"正在准备录音…";
    NSError *sessionError=nil;
    AVAudioSession *session=[AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryRecord withOptions:AVAudioSessionCategoryOptionDuckOthers error:&sessionError];
    [session setActive:YES error:&sessionError];
    _stopping=NO;_processing=NO;_peak=0;
    [self recordNextChunk];
}
- (void)recordNextChunk{
    if(_stopping)return;
    NSString *dir=NSTemporaryDirectory();
    _recordingPath=[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"subtitle_%d.wav",(int)NSDate.date.timeIntervalSince1970]];
    NSDictionary *settings=@{AVFormatIDKey:@(kAudioFormatLinearPCM),AVSampleRateKey:@16000,AVNumberOfChannelsKey:@1,AVLinearPCMBitDepthKey:@16,AVLinearPCMIsBigEndianKey:@NO,AVLinearPCMIsFloatKey:@NO,AVEncoderAudioQualityKey:@(AVAudioQualityMax)};
    NSError *error=nil;
    AVAudioRecorder *r=[[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:_recordingPath] settings:settings error:&error];
    if(!r||error){SubtitleState=@"录音初始化失败（麦克风权限？）";[self stop];return;}
    _recorder=r;
    r.delegate=self;[r setMeteringEnabled:YES];
    if(![r recordForDuration:4]){SubtitleState=@"录音启动失败";[self stop];return;}
    SubtitleState=@"录音中…";
    _peak=0;
    __weak typeof(self) weak=self;
    _meterTimer=[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){TIOCloudSubtitleEngine *s=weak;if(!s||!s.recorder)return;[s.recorder updateMeters];float p=[s.recorder averagePowerForChannel:0];if(p>s.peak)s.peak=p;}];
}
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag{
    [_meterTimer invalidate];_meterTimer=nil;
    if(_stopping){_recorder=nil;return;}
    _recorder=nil;
    NSData *audio=[NSData dataWithContentsOfFile:_recordingPath];
    if(!audio.length||_peak<-48){SubtitleState=@"未检测到声音，跳过本段";[self recordNextChunk];return;}
    _processing=YES;SubtitleState=@"识别中…";
    __weak typeof(self) weak=self;
    TIOCloudSubtitleTranscribe(audio,^(NSString *text,NSString *error){
        TIOCloudSubtitleEngine *s=weak;if(!s)return;
        s.processing=NO;
        if(error){SubtitleState=[NSString stringWithFormat:@"识别失败：%@",error];[s recordNextChunk];return;}
        NSString *clean=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(!clean.length){SubtitleState=@"未识别到文字，跳过本段";[s recordNextChunk];return;}
        ShowLineOnGlasses(clean);
        s.lastShownAt=NSDate.date;
        if([SubtitleStatus()[@"translate"] boolValue]){
            SubtitleState=[NSString stringWithFormat:@"识别：%@\n翻译中…",clean];
            TranslateText(clean,SubtitleStatus()[@"target"],^(NSString *translation,NSString *tError){
                if(s.stopping)return;
                if(translation.length){ShowLineOnGlasses(translation);SubtitleState=[NSString stringWithFormat:@"%@\n译：%@",clean,translation];}
                else SubtitleState=tError.length?[NSString stringWithFormat:@"识别：%@\n翻译失败：%@",clean,tError]:[NSString stringWithFormat:@"识别：%@",clean];
                [s recordNextChunk];
            });
        }else{SubtitleState=clean;[s recordNextChunk];}
    });
}
- (void)stop{
    _stopping=YES;
    [_meterTimer invalidate];_meterTimer=nil;
    if(_recorder&&_recorder.isRecording)[_recorder stop];
    _recorder=nil;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kCloudSubtitleRunning];
    SubtitleState=@"已停止";
    TMMusicBridge *bridge=[TMMusicBridge shared];
    if(bridge.active&&![bridge failed])[bridge close];
}
@end

// ---- UI ----
@interface TIOCloudSubtitlePanel:UITableViewController
@end
@implementation TIOCloudSubtitlePanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"云端字幕 · 麦克风";TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOFeatureHeader(@"听写 / 听书外放字幕 / 翻译",@"对着手机说话，或让手机外放听书，识别文字实时显示到眼镜。耳机听书收不到（iOS 无内部音频捕获）。",@"captions.bubble");}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 3;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?4:(s==1?1:MIN(SubtitleLog.count,10));}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"控制",@"当前状态",@"最近记录"][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==0?@"识别走硅基流动 SenseVoice；翻译走已配置模型。每 4 秒一段，静音自动跳过。字幕持续显示，停止时关闭音乐页。":nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    if(ip.section==0){
        NSDictionary *s=SubtitleStatus();
        if(ip.row==0){c.textLabel.text=[s[@"running"] boolValue]?@"■ 停止字幕":@"▶ 开始字幕";c.detailTextLabel.text=@"录音→识别→推眼镜，循环进行";}
        else if(ip.row==1){c.textLabel.text=@"翻译到镜片";UISwitch *sw=[UISwitch new];sw.on=[s[@"translate"] boolValue];[sw addTarget:self action:@selector(toggleTranslate:) forControlEvents:UIControlEventValueChanged];c.accessoryView=sw;}
        else if(ip.row==2){c.textLabel.text=[NSString stringWithFormat:@"目标语言 · %@",s[@"target"]];c.detailTextLabel.text=@"点击修改（如 英语/日语/粤语）";}
        else {c.textLabel.text=@"查看最近字幕";c.detailTextLabel.text=@"本机保留最近 50 条";}
    }else if(ip.section==1){c.textLabel.text=SubtitleState;c.detailTextLabel.text=[NSString stringWithFormat:@"模式：%@ · %@",[SubtitleStatus()[@"translate"] boolValue]?@"识别+翻译":@"仅识别",[SubtitleStatus()[@"running"] boolValue]?@"运行中":@"空闲"];}
    else{c.textLabel.text=SubtitleLog[ip.row];}
    return c;
}
- (void)toggleTranslate:(UISwitch *)sw{[[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kCloudSubtitleTranslate];[self.tableView reloadData];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];
    if(ip.section==0&&ip.row==0){if([SubtitleStatus()[@"running"] boolValue])[[TIOCloudSubtitleEngine shared] stop];else [[TIOCloudSubtitleEngine shared] begin];[t reloadData];}
    else if(ip.section==0&&ip.row==2){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"目标语言" message:@"翻译输出语言（中文以外建议，中文可留空直接识别）" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=SubtitleStatus()[@"target"];f.placeholder=@"如 英语 / 日语 / 粤语";}];[a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *v=[a.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(v.length)[[NSUserDefaults standardUserDefaults] setObject:v forKey:kCloudSubtitleTarget];else [[NSUserDefaults standardUserDefaults] setObject:@"简体中文" forKey:kCloudSubtitleTarget];[t reloadData];}]];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.tableView reloadData];}
@end
UIViewController *TIOCloudSubtitleController(void){return [[TIOCloudSubtitlePanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
