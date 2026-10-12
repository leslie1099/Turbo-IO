// TicketTrip.m —— 车票行程识别与推送
#import "TicketTrip.h"
#import "MusicBridge.h"
#import "AppleCalendarSync.h"
#import "ResearchUI.h"

static NSString *FirstMatch(NSString *text,NSString *pattern){
    if(![text isKindOfClass:NSString.class]||!text.length)return nil;
    NSError *error=nil;
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    if(!re)return nil;
    NSTextCheckingResult *m=[re firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
    if(!m||m.range.location==NSNotFound)return nil;
    NSRange r=[m rangeAtIndex:1];
    if(r.location==NSNotFound)return nil;
    return [text substringWithRange:r];
}

NSDictionary *TIOTicketTripParse(NSString *text){
    if(![text isKindOfClass:NSString.class]||text.length<8)return nil;
    NSString *train=FirstMatch(text,@"([GCDZTK]\\d{1,4})"),
             *flight=FirstMatch(text,@"([A-Z]{2}\\d{3,4})"),
             *gate=FirstMatch(text,@"(?:检票口|检票\\s*口|登机口|登机\\s*口)\\s*[:：]?\\s*([A-Z]?\\d{1,4})"),
             *seat=FirstMatch(text,@"([A-Z]\\d{2,4}号?|\\d{1,2}车\\d{1,2}[A-Z]?号?)"),
             *time=FirstMatch(text,@"((?:\\d{1,2}月\\d{1,2}日)?\\s*\\d{1,2}[:：]\\d{2})"),
             *station=FirstMatch(text,@"(?:从|自|出发地|始发|起点)\\s*[:：]?\\s*([\\u4e00-\u9fa5A-Za-z]{2,8})");
    if(!train&&!flight)return nil;
    BOOL byAir=flight!=nil;
    NSString *kind=byAir?@"机票":@"火车票";
    NSString *code=byAir?flight:train;
    NSString *from=station, *to=FirstMatch(text,@"(?:到|至|到达|终点|目的地)\\s*[:：]?\\s*([\\u4e00-\u9fa5A-Za-z]{2,8})");
    NSMutableArray *parts=[NSMutableArray new];
    if(from.length)[parts addObject:from];
    if(to.length)[parts addObject:[@"→" stringByAppendingString:to]];
    NSString *title=[NSString stringWithFormat:@"%@ %@ %@",kind,code,parts.count?[parts componentsJoinedByString:@""]:@""];
    NSMutableArray *detail=[NSMutableArray new];
    if(time.length)[detail addObject:time];
    if(gate.length)[detail addObject:[@"口 " stringByAppendingString:gate]];
    if(seat.length)[detail addObject:seat];
    return @{@"kind":kind,@"code":code,@"time":time?:@"",@"from":from?:@"",@"to":to?:@"",@"gate":gate?:@"",@"seat":seat?:@"",@"title":title,@"text":detail.count?[detail componentsJoinedByString:@" · "]:@""};
}

static void ShowTicket(NSDictionary *parsed){
    TMMusicBridge *bridge=[TMMusicBridge shared];
    if(bridge.failed)[bridge reset];
    NSMutableArray *lyrics=[NSMutableArray new];
    [lyrics addObject:@{@"ms":@0,@"text":parsed[@"title"]}];
    NSString *text=parsed[@"text"];
    if(text.length)[lyrics addObject:@{@"ms":@0,@"text":text}];
    [bridge openWithCover:nil lyrics:lyrics];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        TMMusicBridge *b=[TMMusicBridge shared];
        if(![b failed])[b close];
    });
}

@interface TIOTicketTripPanel:UITableViewController
@property(nonatomic,strong) NSMutableArray *log;
@end
@implementation TIOTicketTripPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"车票行程";TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOFeatureHeader(@"车票/航班短信 → 镜片",@"识别 12306/航旅纵横/携程等短信中的车次航班、时间、口与座位，推送眼镜 8 秒并写入提醒事项。",@"ticket");_log=[NSMutableArray new];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 3;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?2:(s==1?2:MIN(_log.count,10));}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"测试样本",@"识别结果",@"记录"][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==0?@"自动识别走快捷指令转发（同短信桥）：短信 → 快捷指令 → 本机 60123 端口。本页可先粘贴测试。":nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    if(ip.section==0){
        if(ip.row==0){c.textLabel.text=@"[12306] 您预订的2026年10月15日G1234次列车，武汉15:30开，检票口A12，7车5F号";c.detailTextLabel.text=@"点击识别并推送（示例）";}
        else{c.textLabel.text=@"[航旅纵横] 您乘坐的CA1831航班，10月15日08:15起飞，登机口B23，座位32A";c.detailTextLabel.text=@"点击识别并推送（示例）";}
    }else if(ip.section==1){
        c.textLabel.text=_log.count?_log[0]:@"尚未识别";
        c.detailTextLabel.text=_log.count>1?_log[1]:nil;
    }else{c.textLabel.text=_log[ip.row];}
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];
    if(ip.section==0){
        NSString *sample=ip.row==0?@"您预订的2026年10月15日G1234次列车，武汉15:30开，检票口A12，7车5F号":@"您乘坐的CA1831航班，10月15日08:15起飞，登机口B23，座位32A";
        NSDictionary *parsed=TIOTicketTripParse(sample);
        if(!parsed){[self toast:@"未能识别为车票/航班"];return;}
        [_log insertObject:[NSString stringWithFormat:@"识别：%@ %@",parsed[@"title"],parsed[@"text"]] atIndex:0];
        ShowTicket(parsed);
        NSString *sourceID=[@"io.turboio.ticket." stringByAppendingString:NSUUID.UUID.UUIDString];
        TIOAppleCreateReminder(parsed[@"title"],sourceID,^(NSDictionary *result){});
        [t reloadData];
    }
}
- (void)toast:(NSString *)msg{UIAlertController *a=[UIAlertController alertControllerWithTitle:msg message:nil preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
@end
UIViewController *TIOTicketTripController(void){return [[TIOTicketTripPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
