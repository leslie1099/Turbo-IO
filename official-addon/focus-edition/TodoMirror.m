#import "TodoMirror.h"
#import "TodoMirrorLedger.h"
#import "TodoProtocol.h"
#import "AppleCalendarSync.h"
#import "ProtocolContext.h"
#import <UIKit/UIKit.h>
#import <EventKit/EventKit.h>

static TIOTodoMirrorLedger *Ledger;
static void (^Sender)(NSString *,NSData *,void (^)(BOOL));
static NSString *MirrorDevice,*LastReadStatus=@"waiting_for_glasses";
static NSArray *OfficialRows;
static BOOL Fetching,RefreshAgain,Queued;
static NSTimeInterval ReadAt;
static NSUInteger ReadCount,SendAttempts,SendSuccesses,SendFailures,AppleWrites,AppleWriteFailures,PhysicalChanges,BatchChanges,OperationReceipts,LastOperationSuccessCount,UnsupportedCount;
static NSMutableDictionary *Submitted,*RetryAt;
static NSMutableSet *InFlight;
static NSTimer *PollTimer;
static EKEventStore *ChangeStore;
static id ChangeObserver,ForegroundObserver;
static NSString *Text(id v){return [v isKindOfClass:NSString.class]?v:@"";}
static NSData *Bytes(id v){if([v isKindOfClass:NSData.class])return v;@try{id b=[v valueForKey:@"data"];return [b isKindOfClass:NSData.class]?b:nil;}@catch(NSException *e){return nil;}}
static NSDictionary *Diag(void){NSUInteger pending=0,active=0,owned=0,conflicts=0;for(NSDictionary *r in [Ledger recordsForDevice:MirrorDevice]){if([r[@"active"] boolValue]){active++;if([r[@"owned"] boolValue])owned++;if(r[@"pendingApple"]||![Submitted[r[@"source"]] isEqual:r[@"revision"]])pending++;}if(r[@"lastConflict"])conflicts++;}
    return @{@"version":@1,@"scope":@"dedicated_todo_list",@"lastReadStatus":LastReadStatus?:@"",@"reads":@(ReadCount),@"activePairs":@(active),@"localImports":@(owned),@"pending":@(pending),@"conflictsPreserved":@(conflicts),@"unsupported":@(UnsupportedCount),@"sendAttempts":@(SendAttempts),@"submitted":@(SendSuccesses),@"sendFailures":@(SendFailures),@"appleWrites":@(AppleWrites),@"appleWriteFailures":@(AppleWriteFailures),@"physicalChanges":@(PhysicalChanges),@"batchChanges":@(BatchChanges),@"operationReceipts":@(OperationReceipts),@"lastOperationSuccessCount":@(LastOperationSuccessCount),@"lastReadAt":@(ReadAt),@"at":@(NSDate.date.timeIntervalSince1970)};
}
static void SaveDiag(void){NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];NSString *p=[dir stringByAppendingPathComponent:@"todo-mirror.json"];NSData *d=[NSJSONSerialization dataWithJSONObject:Diag() options:NSJSONWritingSortedKeys error:nil];[d writeToFile:p options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:p error:nil];}
static void Schedule(void){if(Queued)return;Queued=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.6*NSEC_PER_SEC)),dispatch_get_main_queue(),^{Queued=NO;TIOTodoMirrorRefresh();});}
static void Drain(void){
    if(!Ledger||!MirrorDevice.length)return;NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(NSDictionary *r in [Ledger recordsForDevice:MirrorDevice]){
        NSString *source=r[@"source"];if(![r[@"active"] boolValue]||[InFlight containsObject:source]||[RetryAt[source] doubleValue]>now)continue;
        NSDictionary *pending=r[@"pendingApple"];
        if(![r[@"bound"] boolValue]){[InFlight addObject:source];
            TIOAppleBindTodoIdentity(source,r[@"apple"],^(NSDictionary *result){[InFlight removeObject:source];[Ledger boundSource:source result:result];if(![result[@"status"] isEqual:@"linked"])RetryAt[source]=@(NSDate.date.timeIntervalSince1970+20);SaveDiag();Schedule();});continue;}
        if(pending){[InFlight addObject:source];AppleWrites++;
            TIOAppleApplyTodoFields(source,pending[@"expected"],pending[@"fields"],^(NSDictionary *result){[InFlight removeObject:source];[Ledger finishAppleWrite:source pending:pending result:result];if(![@[@"updated",@"unchanged",@"conflict"] containsObject:result[@"status"]]){AppleWriteFailures++;RetryAt[source]=@(NSDate.date.timeIntervalSince1970+20);}SaveDiag();Schedule();});continue;}
        if(!Sender||![TIOProtocolDevice() isEqual:MirrorDevice]||now-ReadAt>30||![LastReadStatus isEqual:@"ok"]||[Submitted[source] isEqual:r[@"revision"]])continue;
        NSData *payload=TIOTodoEncodeStatusUpdate(r[@"row"],[r[@"row"][@"status"] integerValue],(NSInteger)now);if(!payload)continue;
        [InFlight addObject:source];NSString *revision=r[@"revision"];SendAttempts++;SaveDiag();
        __block BOOL finished=NO;void(^finish)(BOOL)=^(BOOL submitted){if(finished)return;finished=YES;[InFlight removeObject:source];if(submitted){Submitted[source]=revision;SendSuccesses++;}else{SendFailures++;RetryAt[source]=@(NSDate.date.timeIntervalSince1970+10);}SaveDiag();Schedule();};
        Sender(MirrorDevice,payload,finish);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{finish(NO);});
        // Serialize Bluetooth writes. A receipt for a bulk operation is not a
        // per-item display proof; diagnostics call this only "submitted".
        break;
    }
}
void TIOTodoMirrorRefresh(void){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOTodoMirrorRefresh();});return;}
    if(!Ledger||!MirrorDevice.length||!OfficialRows)return;
    if(Fetching){RefreshAgain=YES;return;}Fetching=YES;
    NSString *device=[MirrorDevice copy];
    TIOAppleReadTodoList(^(NSDictionary *result){Fetching=NO;LastReadStatus=result[@"status"]?:@"unknown";ReadCount++;
        if([device isEqual:MirrorDevice]&&[LastReadStatus isEqual:@"ok"]){
            NSMutableArray *apple=[NSMutableArray array];
            for(NSDictionary *item in result[@"items"]){NSMutableDictionary *copy=[item mutableCopy];NSMutableArray *sources=[NSMutableArray array];
                for(NSDictionary *row in OfficialRows){NSString *source=[NSString stringWithFormat:@"%@:%@",device,row[@"wireId"]];NSDictionary *link=TIOAppleTodoLinkIdentity(source);
                    BOOL exact=[link[@"identifier"] length]&&[link[@"identifier"] isEqual:item[@"identifier"]];
                    BOOL external=[link[@"externalIdentifier"] length]&&[link[@"externalIdentifier"] isEqual:item[@"externalIdentifier"]]&&[link[@"calendarIdentifier"] isEqual:item[@"calendarIdentifier"]];if(exact||external)[sources addObject:source];}
                if(sources.count==1)copy[@"sourceID"]=sources.firstObject;
                if(sources.count>1)copy[@"hasLink"]=@YES;[apple addObject:copy];
            }
            [Ledger reconcileApple:apple officialRows:OfficialRows device:device now:NSDate.date.timeIntervalSince1970];ReadAt=NSDate.date.timeIntervalSince1970;UnsupportedCount=[result[@"unsupportedCount"] unsignedIntegerValue];Drain();
        }
        SaveDiag();if(RefreshAgain){RefreshAgain=NO;Schedule();}
    });
}
void TIOTodoMirrorStart(void (^sender)(NSString *,NSData *,void (^)(BOOL))){
    if(Ledger)return;Ledger=[[TIOTodoMirrorLedger alloc]initWithDefaults:NSUserDefaults.standardUserDefaults];Sender=[sender copy];Submitted=[NSMutableDictionary dictionary];RetryAt=[NSMutableDictionary dictionary];InFlight=[NSMutableSet set];
    ChangeStore=[EKEventStore new];
    ChangeObserver=[NSNotificationCenter.defaultCenter addObserverForName:EKEventStoreChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){Schedule();}];
    ForegroundObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){[RetryAt removeAllObjects];Schedule();}];
    PollTimer=[NSTimer scheduledTimerWithTimeInterval:10 repeats:YES block:^(NSTimer *t){TIOTodoMirrorRefresh();}];SaveDiag();
}
void TIOTodoMirrorObserveOutgoing(NSDictionary *args){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOTodoMirrorObserveOutgoing(args);});return;}
    if(!Ledger||![args[@"businessId"] isEqual:@22])return;
    NSData *data=Bytes(args[@"payload"]);NSDictionary *envelope=TIOTodoEnvelope(data);NSString *device=Text(args[@"deviceId"]);if(!device.length)return;
    NSDictionary *snapshot=TIOTodoSnapshot(data);
    if(snapshot&&[snapshot[@"isLastBatch"] boolValue]&&[snapshot[@"total"] unsignedIntegerValue]==[snapshot[@"items"] count]){
        [Ledger observeOfficialRows:snapshot[@"items"] device:device];OfficialRows=snapshot[@"items"];MirrorDevice=device;
        // The official complete-list transfer may replace local imports on the
        // glasses. Reapply only this bridge's own exact mappings afterwards.
        [Submitted removeAllObjects];Schedule();
    }else if([envelope[@"type"] isEqual:@2]&&[device isEqual:MirrorDevice]){
        NSDictionary *row=TIOTodoOutgoingTask(data);if(row){[Ledger observeOfficialRows:@[row] device:device];NSString *source=[NSString stringWithFormat:@"%@:%@",device,row[@"wireId"]];[Submitted removeObjectForKey:source];Drain();Schedule();}
    }
}
static void Varint(NSMutableData *out,uint64_t v){while(v>=128){uint8_t b=(v&127)|128;[out appendBytes:&b length:1];v>>=7;}uint8_t b=v;[out appendBytes:&b length:1];}
static NSData *Packet(NSInteger type,NSDictionary *body){NSData *json=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];if(!json)return nil;NSMutableData *out=[NSMutableData dataWithBytes:"\x08\x01\x10" length:3];Varint(out,type);uint8_t tag=26;[out appendBytes:&tag length:1];Varint(out,json.length);[out appendData:json];return out;}
NSDictionary *TIOTodoMirrorProjection(NSDictionary *arguments){
    if(!NSThread.isMainThread||![arguments[@"businessId"] isEqual:@22]||![arguments[@"deviceId"] isEqual:MirrorDevice]||![LastReadStatus isEqual:@"ok"]||NSDate.date.timeIntervalSince1970-ReadAt>30)return nil;
    return TIOTodoOverlaySnapshot(Bytes(arguments[@"payload"]),[Ledger recordsForDevice:MirrorDevice],(NSInteger)NSDate.date.timeIntervalSince1970);
}
void TIOTodoMirrorProjectionSubmitted(NSDictionary *projection,BOOL success){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOTodoMirrorProjectionSubmitted(projection,success);});return;}
    for(NSDictionary *receipt in projection[@"receipts"])if(success)Submitted[receipt[@"source"]]=receipt[@"revision"];
    SaveDiag();Schedule();
}
NSDictionary *TIOTodoMirrorRouteEvent(NSDictionary *event){
    if(!Ledger||![event[@"eventType"] isEqual:@"messageReceived"])return event;
    NSDictionary *message=event[@"message"];if(![message isKindOfClass:NSDictionary.class]||![message[@"businessId"] isEqual:@22])return event;
    NSString *device=Text(message[@"deviceId"]);NSDictionary *envelope=TIOTodoEnvelope(Bytes(message[@"payload"]));if(!device.length||!envelope)return event;
    // The Flutter engine invokes this callback on its platform/main thread.
    if(!NSThread.isMainThread)return event;
    NSDictionary *physical=TIOTodoPhysicalStatus(event);
    if(physical){BOOL handled=[Ledger observeStatus:[physical[@"status"] integerValue] wire:physical[@"wireId"] device:device];if(handled){PhysicalChanges++;Drain();Schedule();SaveDiag();}
        if([Ledger ownsWire:physical[@"wireId"] device:device])return nil;return event;}
    if([envelope[@"type"] isEqual:@14]){OperationReceipts++;id count=envelope[@"json"][@"successCount"];if([count isKindOfClass:NSNumber.class])LastOperationSuccessCount=[count unsignedIntegerValue];SaveDiag();return event;}
    if([envelope[@"type"] isEqual:@10]){
        NSDictionary *body=envelope[@"json"];id raw=body[@"eventList"];if(![raw isKindOfClass:NSArray.class]||[raw count]>2000)return event;
        NSMutableArray *foreign=[NSMutableArray array];NSUInteger removed=0;
        for(id row in raw){if(![row isKindOfClass:NSDictionary.class]||![row[@"eventType"] isEqual:@1]||![row[@"eventID"] isKindOfClass:NSNumber.class]){[foreign addObject:row];continue;}
            NSString *wire=[row[@"eventID"] stringValue];if([row[@"status"] isEqual:@0]||[row[@"status"] isEqual:@1])if([Ledger observeBatchStatus:[row[@"status"] integerValue] wire:wire device:device])BatchChanges++;
            if([Ledger ownsWire:wire device:device])removed++;else[foreign addObject:row];}
        Drain();Schedule();SaveDiag();if(!removed)return event;
        NSMutableDictionary *next=[body mutableCopy];next[@"eventList"]=foreign;
        if([next[@"todoTotal"] isKindOfClass:NSNumber.class])next[@"todoTotal"]=@(MAX(0,[next[@"todoTotal"] integerValue]-(NSInteger)removed));
        NSMutableDictionary *m=[message mutableCopy];m[@"payload"]=Packet(10,next);NSMutableDictionary *e=[event mutableCopy];e[@"message"]=m;return e;
    }return event;
}
BOOL TIOTodoMirrorHandlesSource(NSString *source){return [Ledger handlesSource:source];}
BOOL TIOTodoMirrorToggleSource(NSString *source){NSDictionary *r=[Ledger recordForSource:source];if(![r[@"active"] boolValue])return NO;BOOL handled=[Ledger observeStatus:[r[@"row"][@"status"] boolValue]?0:1 wire:r[@"wireId"] device:r[@"device"]];if(handled){Drain();Schedule();}return handled;}
NSArray<NSDictionary *> *TIOTodoMirrorDisplayRows(NSString *device,NSArray<NSDictionary *> *officialRows){NSMutableDictionary *rows=[NSMutableDictionary dictionary];NSMutableArray *order=[NSMutableArray array];for(NSDictionary *r in officialRows){rows[r[@"wireId"]]=r;[order addObject:r[@"wireId"]];}for(NSDictionary *r in [Ledger displayRowsForDevice:device]){if(!rows[r[@"wireId"]])[order addObject:r[@"wireId"]];rows[r[@"wireId"]]=r;}NSMutableArray *out=[NSMutableArray array];for(NSString *key in order)[out addObject:rows[key]];return out;}
NSDictionary *TIOTodoMirrorDiagnostics(void){return Diag();}
