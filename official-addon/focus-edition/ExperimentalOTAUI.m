#import "ExperimentalOTAUI.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAGuard.h"
#import "ExperimentalOTAFlash.h"
#import "ResearchUI.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface TIOExperimentalOTAPage:UITableViewController<UIDocumentPickerDelegate>
@property(nonatomic,copy) NSString *statusText;
@property(nonatomic) BOOL busy;
@property(nonatomic,copy) NSString *directoryStatus;
@end
static NSURL *StoreDirectory(void){return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ExperimentalOTA"] isDirectory:YES];}
static NSString *CurrentImportedKind(void){
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *dir=StoreDirectory();
    NSURL *newest=nil;NSDate *newestDate=nil;
    for(NSString *sha in @[TIOExperimentalOTASHA(),TIOStockOTASHA()]){
        NSURL *f=[dir URLByAppendingPathComponent:[sha stringByAppendingString:@".zip"]];
        if(![fm fileExistsAtPath:f.path])continue;
        NSDate *date=[[fm attributesOfItemAtPath:f.path error:nil] fileModificationDate];
        if(date&&(!newestDate||[date compare:newestDate]==NSOrderedDescending)){newest=f;newestDate=date;}
    }
    if(newest){NSError *e=nil;NSDictionary *r=TIOReadExperimentalOTA(newest,&e);if(r)return r[@"kind"];}
    return nil;
}
@implementation TIOExperimentalOTAPage
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"固件刷机 · TFP1 实验 / 原厂 1.0.4.12 恢复 · 默认锁定";self.statusText=@"未选择 ZIP。不会自动查询升级或向眼镜发送指令。";self.directoryStatus=@"尚未检查。只读取官方同版本解压目录，不清理、不覆盖。";TIOStyleResearchTable(self);
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *dir=StoreDirectory();
    NSMutableArray<NSURL *> *candidates=[NSMutableArray new];
    for(NSString *sha in @[TIOExperimentalOTASHA(),TIOStockOTASHA()]){
        NSURL *f=[dir URLByAppendingPathComponent:[sha stringByAppendingString:@".zip"]];
        if([fm fileExistsAtPath:f.path])[candidates addObject:f];
    }
    if(!candidates.count){
        self.busy=YES;self.statusText=@"正在核对内置固件候选；只保存本机，不开放更新…";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSMutableString *out=[NSMutableString new];BOOL any=NO;
            for(NSString *name in @[@"TurboWeReadCandidate",@"StockCandidate"]){
                NSURL *bundled=[NSBundle.mainBundle URLForResource:name withExtension:@"zip"];
                if(!bundled)continue;NSError *e=nil;BOOL ok=TIOImportExperimentalOTA(bundled,StoreDirectory(),&e)!=nil;
                if(ok){any=YES;[out appendFormat:@"%@：校验通过。\n",[name isEqual:@"StockCandidate"]?@"原厂 1.0.4.12":@"TFP1 实验"];}else [out appendFormat:@"%@：%@\n",name,e.localizedDescription?:@"导入失败"];
            }
            dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.statusText=any?[out stringByAppendingString:@"未开放下载，未授权刷写。"]:(out.length?out:@"无内置固件候选；可从“文件”导入 ZIP。");[self.tableView reloadData];});});return;
    }
    if(candidates.count){self.busy=YES;self.statusText=@"正在重新核对已保存的固件副本…";dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSMutableString *out=[NSMutableString new];BOOL all=YES;
        for(NSURL *f in candidates){NSError *error=nil;NSDictionary *r=TIOReadExperimentalOTA(f,&error);if(!r)all=NO;[out appendFormat:@"%@：%@\n",[f.lastPathComponent substringToIndex:8],r?@"完整 SHA-256 复核通过":(error.localizedDescription?:@"校验失败")];}
        dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.statusText=all?[out stringByAppendingString:@"未发送、未安装；不会自动启动升级。"]:out;[self.tableView reloadData];});});}
}
- (void)refresh{TIORefreshExperimentalOTAReport();[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 4;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==2&&TIOOTAFlashBuild()?5:(section==2&&TIOOTAPreparationBuild()?3:(section==0||section==3?2:1));}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @[@"本地包",@"改动与安装范围",@"官方升级流程",@"手机解压目录 · 只读复核"][section];}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path{
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(cell);
    if(path.section==0&&path.row==0){cell.textLabel.text=self.busy?@"正在校验…":@"选择固件 ZIP（TFP1 实验 / 原厂恢复）";cell.detailTextLabel.text=@"从“文件”导入 · 完整 SHA-256 比对 · 不解压、不发送";cell.imageView.image=[UIImage systemImageNamed:@"doc.badge.plus"];cell.accessibilityIdentifier=@"experimental-ota-import";}
    else if(path.section==0){cell.textLabel.text=@"本地校验状态";cell.detailTextLabel.text=self.statusText;cell.accessibilityIdentifier=@"experimental-ota-status";}
    else if(path.section==1){cell.textLabel.text=@"TFP1 实验：仅 AP 内容变化，不代表只写 AP";cell.detailTextLabel.text=@"Strix OS 1.0.4.12 · TFP1 番茄与交互修正\n仅 AP 修改，其他13个负载原样。音乐旋钮防误触、文字边距、阅读本地长按返回；新增第十二项番茄时钟。\nAP MD5：2d5c14d7c348d01c333f3561423cb47e\n原厂恢复包：原厂 AP + 原厂清单，其余 13 负载逐字节与原厂一致。\n试验固件有风险，回滚不保证恢复。";}
    else if(path.section==2){NSDictionary *feed=TIOExperimentalOTAFeedStatus(),*guard=TIOOTAGuardStatus();NSString *kind=CurrentImportedKind()?:@"";
        if(path.row==3){cell.textLabel.text=kind.length?[NSString stringWithFormat:@"允许一次 %@ 试刷",[kind isEqual:@"STOCK"]?@"原厂恢复":@"TFP1 实验"]:@"允许一次固件试刷";cell.detailTextLabel.text=kind.length?[NSString stringWithFormat:@"当前已导入：%@。重新校验并冻结实际待传文件；限定本次设备、Mode 2、匹配清单及每个分片。授权后再点官方“开始安装”。不保证启动或可救砖。",[kind isEqual:@"STOCK"]?@"原厂 1.0.4.12（恢复原厂 AP 与清单）":@"TFP1（番茄与交互修正）"]:@"请先在“本地包”导入 TFP1 或原厂 ZIP。";cell.accessibilityIdentifier=@"experimental-ota-authorize-tfp1";}
        else if(path.row==4){cell.textLabel.text=@"撤销尚未开始的试刷授权";cell.detailTextLabel.text=@"只有未开始时能撤销。开始后不要强停 App、断电或切换版本。";}
        else if(path.row==0&&TIOOTAFlashBuild()){NSDictionary *s=TIOOTAFlashStatus();cell.textLabel.text=@"DISPLAY 固件 · 默认锁定";cell.detailTextLabel.text=[NSString stringWithFormat:@"授权：%@ · 已开始：%@\n清单匹配：%@ · 已核对分片 %@\n%@",s[@"authorized"],s[@"started"],s[@"manifestMatched"],s[@"validatedSlices"],s[@"failure"]];}
        else if(path.row==1){cell.textLabel.text=@"开启 15 分钟只下载验收";cell.detailTextLabel.text=TIOOTAFlashBuild()?@"只提供已导入固件（TFP1 或原厂）的下载，不授予试刷权限；需另外明确确认。":@"只向固件查询提供已导入固件；所有发送被隔离，仅允许读取 OS 版本。官方可能提示发送失败，这是准备阶段的预期。";cell.accessibilityIdentifier=@"experimental-ota-prepare-only";}
        else if(path.row==2){cell.textLabel.text=@"撤销下载来源";cell.detailTextLabel.text=@"立即停止提供元数据和 ZIP。发送隔离保持到退出此进程，不自动恢复。";cell.accessibilityIdentifier=@"experimental-ota-cancel";}
        else if(TIOOTAPreparationBuild()){cell.textLabel.text=@"PREPARE 02 · 禁止刷写";cell.detailTextLabel.text=[NSString stringWithFormat:@"隔离钩子：%@；已阻止 %@ 次发送\n来源开放：%@ · 固件查询 %@ · App 查询 %@ · 下载 %@\n这是只下载构建，没有解除发送隔离的入口。",[guard[@"transportHookReady"] boolValue]?@"已安装":@"未安装",guard[@"blockedCalls"],[feed[@"armed"] boolValue]?@"是":@"否",feed[@"firmwareQueries"]?:@0,feed[@"appQueries"]?:@0,feed[@"downloadRequests"]?:@0];cell.accessibilityIdentifier=@"experimental-ota-preparation-status";}
        else{cell.textLabel.text=@"刷机门禁关闭 · 不能开始升级";cell.detailTextLabel.text=[feed[@"running"] boolValue]?[NSString stringWithFormat:@"本机升级来源已启动，仅返回“无更新”。已收到 %@ 次查询。\n同版本缓存及官方宿主尚待验收；编译门禁禁止提供实验包。没有发送到眼镜。",feed[@"queryCount"]]:@"本机升级来源组件已编译，当前包未启用实验路由。官方调度尚待验收。\n不覆盖官方缓存、不修改同版本升级开关、不向眼镜发送。";cell.accessibilityIdentifier=@"experimental-ota-not-connected";}}
    else if(path.row==0){cell.textLabel.text=self.busy?@"正在校验…":@"核对官方解压目录";cell.detailTextLabel.text=@"逐个比对 14 文件与清单；旧原厂包不会被当作 TFP1";cell.accessibilityIdentifier=@"experimental-ota-check-directory";}
    else{cell.textLabel.text=@"目录快照结果";cell.detailTextLabel.text=self.directoryStatus;cell.accessibilityIdentifier=@"experimental-ota-directory-status";}
    cell.selectionStyle=(((path.section==0||path.section==3)&&path.row==0)||(path.section==2&&path.row>0))&&!self.busy?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path{
    [tableView deselectRowAtIndexPath:path animated:YES];if(self.busy)return;
    if(path.section==2&&path.row==4&&TIOOTAFlashBuild()){self.statusText=TIOOTAFlashCancel()?@"未开始的授权已撤销":@"会话已开始，未中断传输；请保持供电和连接";[self refresh];return;}
    if(path.section==2&&path.row==3&&TIOOTAFlashBuild()){
        NSString *kind=CurrentImportedKind();
        if(!kind){self.statusText=@"尚未导入固件 ZIP（TFP1 或原厂），无法授权。";[self refresh];return;}
        NSString *word=[kind isEqual:@"STOCK"]?@"STOCK":@"TFP1";
        NSString *desc=[kind isEqual:@"STOCK"]?@"原厂 1.0.4.12（恢复原厂 AP 与清单，FOCUS-04 实验菜单与番茄时钟将不再提供）":@"TFP1（番茄与交互修正）";
        UIAlertController *a=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"仅授权本次 %@ 试刷",[kind isEqual:@"STOCK"]?@"原厂恢复":@"TFP1 实验"] message:[NSString stringWithFormat:@"已导入：%@。不保证只写 AP；可能无法启动，原厂 ZIP 不保证能救砖。先关闭官方自动更新。确认当前无录音、提词、导航或对话，电量充足。输入 %@ 后授权，随后在官方页面手动开始安装。",desc,word] preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=word;f.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"确认风险并授权" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
            if(![a.textFields.firstObject.text isEqual:word]){self.statusText=@"确认文字不符，未授权";[self refresh];return;}
            NSError *e=nil;BOOL ok=TIOOTAFlashAuthorize(&e);self.statusText=ok?[NSString stringWithFormat:@"本次设备的 %@ 文件已冻结，允许一次正常 Mode 2 会话。请返回官方页，手动点开始安装。",desc]:e.localizedDescription;[self refresh];
        }]];[self presentViewController:a animated:YES completion:nil];return;
    }
    if(path.section==2&&path.row==2){TIOCancelExperimentalOTAPreparation();[self refresh];return;}
    if(path.section==2&&path.row==1){UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"只下载验收，不刷眼镜" message:@"开放 15 分钟本机 TFP1 下载源，只供手机获取、校验和解压，不授予升级发送权限。正常语音和天气不因此禁用。若已单独授权，请先撤销未开始的授权。" preferredStyle:UIAlertControllerStyleAlert];[confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[confirm addAction:[UIAlertAction actionWithTitle:@"只下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){if([TIOOTAFlashStatus()[@"stage"] integerValue]!=0){self.statusText=@"已有授权或发送会话，不能作为只下载验收开启；未改变会话。";[self refresh];return;}NSError *e=nil;BOOL ok=TIOBeginExperimentalOTAPreparation(&e);self.statusText=ok?@"来源已开放。回官方升级页检查并下载；未授予眼镜升级权限。":e.localizedDescription;[self refresh];}]];[self presentViewController:confirm animated:YES completion:nil];return;}
    if(path.row!=0)return;
    if(path.section==3){self.busy=YES;self.directoryStatus=@"逐个读取并核对 SHA-256…";[self.tableView reloadData];
        NSURL *directory=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ota/Strix_OS_1.0.4.12"] isDirectory:YES];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *result=TIOCheckExperimentalOTADirectory(directory,&error);dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.directoryStatus=result?@"此刻目录中 15 个成员均与 TFP1 一致。\n仅是读取快照，尚未绑定官方传输会话；未发送、仍不能刷写。":error.localizedDescription;[self.tableView reloadData];});});return;}
    if(path.section!=0)return;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];picker.allowsMultipleSelection=NO;picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
    if(self.busy||urls.count!=1)return;self.busy=YES;self.statusText=@"正在读取并核对指定 TFP1 的完整 SHA-256…";[self.tableView reloadData];
    NSURL *source=urls.firstObject;
    NSURL *directory=StoreDirectory();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        BOOL access=[source startAccessingSecurityScopedResource];NSError *error=nil;NSDictionary *result=TIOImportExperimentalOTA(source,directory,&error);if(access)[source stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.statusText=result?@"TFP1 完整文件校验通过，已保存扩展本地副本。\n未向眼镜发送，未开始安装；返回本页不会触发升级。":(error.localizedDescription?:@"导入失败，未发送。");[self.tableView reloadData];});
    });
}
@end
UIViewController *TIOExperimentalOTAController(void){return [[TIOExperimentalOTAPage alloc]initWithStyle:UITableViewStyleInsetGrouped];}
