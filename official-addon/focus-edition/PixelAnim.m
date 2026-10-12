// PixelAnim.m —— 15×4 像素动画推眼镜
// 动画在手机端生成帧文本（15 字符宽 × 4 行），定时推送到眼镜音乐页通道。
#import "PixelAnim.h"
#import "MusicBridge.h"
#import "ResearchUI.h"

typedef NSArray<NSString *> *(^FrameGenerator)(NSUInteger frame);

static NSArray<NSString *> *BounceFrame(NSUInteger f){
    // 弹珠：15×4 网格内反弹
    NSUInteger x=(f*2)%26;if(x>=15)x=30-x-1; // 0..14 往返
    NSUInteger row=(f/2)%4;
    NSMutableArray *out=[NSMutableArray new];
    for(NSUInteger r=0;r<4;r++){NSMutableString *line=[NSMutableString stringWithCapacity:15];for(NSUInteger c=0;c<15;c++)[line appendString:(r==row&&c==x)?@"●":@"·"];[out addObject:line];}
    return out;
}
static NSArray<NSString *> *HeartFrame(NSUInteger f){
    // 爱心脉冲：大小交替
    NSArray *small=@[@"·●·······●··",@"●···●···●···●",@"······●······",@"·············"];
    NSArray *big=@[@"·●···●···●···●",@"●··●·●··●·●··●",@"●···········●",@"··●·········●··"];
    NSMutableArray *out=[NSMutableArray new];
    for(NSString *row in (f%2?big:small)){
        NSString *padded=[row stringByPaddingToLength:15 withString:@"·" startingAtIndex:0];
        [out addObject:padded];
    }
    return out;
}
static NSArray<NSString *> *BreathFrame(NSUInteger f){
    // 呼吸条：宽度随帧变化
    NSUInteger width=(f%8)+3; // 3..10
    NSMutableArray *out=[NSMutableArray new];
    for(NSUInteger r=0;r<4;r++){NSMutableString *line=[NSMutableString stringWithCapacity:15];for(NSUInteger c=0;c<15;c++)[line appendString:c<width?@"█":@"·"];[out addObject:line];}
    return out;
}
static NSArray<NSString *> *MarqueeFrame(NSUInteger f){
    // 跑马灯：圆点从右向左
    NSMutableArray *out=[NSMutableArray new];
    for(NSUInteger r=0;r<4;r++){NSMutableString *line=[NSMutableString stringWithCapacity:15];for(NSUInteger c=0;c<15;c++)[line appendString:((c+f)%15<3)?@"●":@"·"];[out addObject:line];}
    return out;
}

@interface TIOPixelAnimPanel:UITableViewController
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,assign) NSUInteger frame;
@property(nonatomic,copy) NSString *animation;
@end
@implementation TIOPixelAnimPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"像素动画";TIOStyleResearchTable(self);_animation=@"弹珠";self.tableView.tableHeaderView=TIOFeatureHeader(@"15×4 像素动画 → 镜片",@"弹珠/爱心/呼吸条/跑马灯。播放约 15 秒自动停止，可随时重播。",@"square.grid.3x3");}
- (NSArray<NSString *> *)animations{return @[@"弹珠",@"爱心",@"呼吸条",@"跑马灯"];}
- (FrameGenerator)generator{return [_animation isEqual:@"爱心"]?HeartFrame:([_animation isEqual:@"呼吸条"]?BreathFrame:([_animation isEqual:@"跑马灯"]?MarqueeFrame:BounceFrame));}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?self.animations.count:1;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return s==0?@"选择动画":@"播放控制";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==1?@"播放期间占用音乐页显示；停止后自动关闭。":nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if(ip.section==0){c.textLabel.text=self.animations[ip.row];c.accessoryType=[self.animations[ip.row] isEqual:_animation]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;}
    else{c.textLabel.text=_timer?@"■ 停止播放":@"▶ 播放动画（15 秒）";c.textLabel.textColor=_timer?UIColor.systemRedColor:UIColor.systemBlueColor;}
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];
    if(ip.section==0){_animation=self.animations[ip.row];[t reloadData];return;}
    if(_timer){[_timer invalidate];_timer=nil;TMMusicBridge *b=[TMMusicBridge shared];if(![b failed])[b close];[t reloadData];return;}
    _frame=0;FrameGenerator gen=self.generator;
    __weak typeof(self) weak=self;
    _timer=[NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *timer){
        TIOPixelAnimPanel *s=weak;if(!s)return;
        NSArray<NSString *> *rows=gen(s.frame++);
        TMMusicBridge *bridge=[TMMusicBridge shared];if(bridge.failed)[bridge reset];
        NSMutableArray *lyrics=[NSMutableArray new];
        for(NSString *row in rows)if(row.length)[lyrics addObject:@{@"ms":@0,@"text":row}];
        [bridge openWithCover:nil lyrics:lyrics];
        if(s.frame>=40){[timer invalidate];s.timer=nil;TMMusicBridge *b=[TMMusicBridge shared];if(![b failed])[b close];}
        [s.tableView reloadData];
    }];
    [_timer fire];
    [t reloadData];
}
@end
UIViewController *TIOPixelAnimController(void){return [[TIOPixelAnimPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
