#import "TodoMirrorLedger.h"
#import "TodoProtocol.h"

static NSString *const MirrorKey=@"io.turboio.todo.twoWayLedger.v1";
static NSString *S(id v){return [v isKindOfClass:NSString.class]?v:@"";}
static NSDictionary *Fields(NSDictionary *r){return @{@"title":S(r[@"title"]),@"status":r[@"status"]?:@0};}
static BOOL SameIdentity(NSDictionary *a,NSDictionary *b){
    return ([S(a[@"identifier"]) length]&&[a[@"identifier"] isEqual:b[@"identifier"]])||
    (S(a[@"externalIdentifier"]).length&&[a[@"externalIdentifier"] isEqual:b[@"externalIdentifier"]]&&[a[@"calendarIdentifier"] isEqual:b[@"calendarIdentifier"]]);
}
static BOOL ValidApple(NSDictionary *r){return [r isKindOfClass:NSDictionary.class]&&S(r[@"identifier"]).length&&S(r[@"title"]).length&&S(r[@"title"]).length<=240&&([r[@"status"] isEqual:@0]||[r[@"status"] isEqual:@1]);}
@interface TIOTodoMirrorLedger()
@property(nonatomic,strong) NSUserDefaults *defaults;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSMutableDictionary *> *records;
@end
@implementation TIOTodoMirrorLedger
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults{
    if((self=[super init])){_defaults=defaults;_records=[NSMutableDictionary dictionary];id raw=[defaults objectForKey:MirrorKey];
        if([raw isKindOfClass:NSDictionary.class]&&[raw count]<=2000)for(NSString *source in raw){id r=raw[source];
            if(![r isKindOfClass:NSDictionary.class]||!ValidApple(r[@"apple"])||!S(r[@"device"]).length||!S(r[@"wireId"]).length)continue;
            if(![source isEqual:[NSString stringWithFormat:@"%@:%@",r[@"device"],r[@"wireId"]]])continue;
            if(!TIOTodoEncodeStatusUpdate(r[@"row"],[r[@"row"][@"status"] integerValue],1))continue;
            _records[source]=[r mutableCopy];}
    }return self;
}
- (void)save{[self.defaults setObject:self.records forKey:MirrorKey];[self.defaults synchronize];}
- (NSArray<NSDictionary *> *)recordsForDevice:(NSString *)device{
    NSMutableArray *out=[NSMutableArray array];for(NSString *source in [self.records.allKeys sortedArrayUsingSelector:@selector(compare:)])if([self.records[source][@"device"] isEqual:device])[out addObject:[self.records[source] copy]];return out;
}
- (NSDictionary *)recordForSource:(NSString *)source{return [self.records[source] copy];}
- (BOOL)ownsWire:(NSString *)wire device:(NSString *)device{NSDictionary *r=self.records[[NSString stringWithFormat:@"%@:%@",device,wire]];return [r[@"owned"] boolValue]&&![r[@"problem"] isEqual:@"wire_collision"];}
- (BOOL)handlesSource:(NSString *)source{return [self.records[source][@"active"] boolValue];}
- (void)applyApple:(NSDictionary *)apple record:(NSMutableDictionary *)r now:(NSTimeInterval)now{
    if(![r[@"apple"][@"identifier"] isEqual:apple[@"identifier"]])r[@"bound"]=@NO;
    NSDictionary *before=Fields(r[@"row"]);NSMutableDictionary *row=[r[@"row"] mutableCopy];[row addEntriesFromDictionary:Fields(apple)];
    if(![before isEqual:Fields(apple)]){row[@"lastModifiedTime"]=[NSString stringWithFormat:@"%.0f",MAX(1,now)];r[@"revision"]=NSUUID.UUID.UUIDString;}
    r[@"row"]=row;r[@"apple"]=apple;r[@"active"]=@YES;
}
- (void)reconcileApple:(NSArray<NSDictionary *> *)items officialRows:(NSArray<NSDictionary *> *)rows device:(NSString *)device now:(NSTimeInterval)now{
    if(!device.length||device.length>200||items.count>2000)return;
    NSMutableSet *taken=[NSMutableSet set],*matched=[NSMutableSet set];NSMutableDictionary *official=[NSMutableDictionary dictionary];
    for(NSDictionary *row in rows)if(S(row[@"wireId"]).length){[taken addObject:row[@"wireId"]];official[row[@"wireId"]]=row;}
    for(NSDictionary *r in self.records.allValues)[taken addObject:r[@"wireId"]];
    for(NSMutableDictionary *r in self.records.allValues)if([r[@"device"] isEqual:device])r[@"active"]=@NO;
    for(NSDictionary *apple in items){if(!ValidApple(apple))continue;
        NSMutableArray *matches=[NSMutableArray array];
        for(NSMutableDictionary *r in self.records.allValues)if([r[@"device"] isEqual:device]&&SameIdentity(r[@"apple"],apple))[matches addObject:r];
        if(matches.count>1)continue;
        NSMutableDictionary *r=matches.firstObject;
        if(r){
            if([matched containsObject:r[@"source"]]){r[@"active"]=@NO;r[@"problem"]=@"ambiguous_identity";continue;}
            // A future official ID collision must never overwrite that item.
            if([r[@"owned"] boolValue]&&official[r[@"wireId"]]){r[@"problem"]=@"wire_collision";continue;}
            [self applyApple:apple record:r now:now];[matched addObject:r[@"source"]];continue;
        }
        NSString *source=S(apple[@"sourceID"]);NSDictionary *original=nil;NSString *wire=nil;
        if(source.length){for(NSDictionary *row in rows){NSString *key=[NSString stringWithFormat:@"%@:%@",device,row[@"wireId"]];if([source isEqual:key]){original=row;wire=row[@"wireId"];break;}}
            if(!original||self.records[source]||!TIOTodoEncodeStatusUpdate(original,[original[@"status"] integerValue],1))continue;
        }else{
            // Do not duplicate an older official link whose row is unavailable.
            // New imports include pending reminders; completed history stays put.
            if([apple[@"hasLink"] boolValue]||[apple[@"status"] boolValue]||self.records.count>=1000)continue;
            uint64_t number=0;do{arc4random_buf(&number,sizeof(number));number=1000000000000ULL+number%8000000000000ULL;wire=[@(number) stringValue];}while([taken containsObject:wire]);
            source=[NSString stringWithFormat:@"%@:%@",device,wire];[taken addObject:wire];
            NSTimeInterval created=[apple[@"createdAt"] doubleValue];if(created<=0)created=now;
            original=@{@"wireId":wire,@"title":apple[@"title"],@"status":apple[@"status"],@"createTime":[NSString stringWithFormat:@"%.0f",MAX(1,created)],@"lastModifiedTime":[NSString stringWithFormat:@"%.0f",MAX(1,now)],@"isImportant":@NO};
        }
        r=[@{@"source":source,@"device":device,@"wireId":wire,@"owned":@(S(apple[@"sourceID"]).length==0),@"row":original,@"apple":apple,@"official":Fields(original),@"bound":@NO,@"active":@YES,@"revision":NSUUID.UUID.UUIDString} mutableCopy];
        [self applyApple:apple record:r now:now];self.records[source]=r;[matched addObject:source];
    }[self save];
}
- (void)queueFields:(NSDictionary *)fields record:(NSMutableDictionary *)r{
    NSMutableDictionary *desired=[NSMutableDictionary dictionary],*expected=[NSMutableDictionary dictionary];NSDictionary *prior=r[@"pendingApple"];
    if([prior isKindOfClass:NSDictionary.class]){[desired addEntriesFromDictionary:prior[@"fields"]?:@{}];[expected addEntriesFromDictionary:prior[@"expected"]?:@{}];}
    for(NSString *key in fields){if([fields[key] isEqual:r[@"apple"][key]]){[desired removeObjectForKey:key];[expected removeObjectForKey:key];}
        else{desired[key]=fields[key];expected[key]=r[@"apple"][key];}}
    if(desired.count)r[@"pendingApple"]=@{@"fields":desired,@"expected":expected,@"token":NSUUID.UUID.UUIDString};else[r removeObjectForKey:@"pendingApple"];
}
- (void)observeOfficialRows:(NSArray<NSDictionary *> *)rows device:(NSString *)device{
    for(NSDictionary *row in rows){NSString *source=[NSString stringWithFormat:@"%@:%@",device,row[@"wireId"]];NSMutableDictionary *r=self.records[source];
        if(!r||![r[@"active"] boolValue]||[r[@"owned"] boolValue])continue;
        NSDictionary *before=r[@"official"];NSMutableDictionary *changes=[NSMutableDictionary dictionary];
        for(NSString *key in @[@"title",@"status"])if(row[key]&&before[key]&&![row[key] isEqual:before[key]])changes[key]=row[key];
        if(changes.count)[self queueFields:changes record:r];r[@"official"]=Fields(row);
    }[self save];
}
- (BOOL)observeStatus:(NSInteger)status wire:(NSString *)wire device:(NSString *)device{
    if(status!=0&&status!=1)return NO;NSMutableDictionary *r=self.records[[NSString stringWithFormat:@"%@:%@",device,wire]];if(!r||![r[@"active"] boolValue])return NO;
    [self queueFields:@{@"status":@(status)} record:r];r[@"glassBaseline"]=@(status);
    NSMutableDictionary *observed=[r[@"official"] mutableCopy];observed[@"status"]=@(status);r[@"official"]=observed;
    [self save];return YES;
}
- (BOOL)observeBatchStatus:(NSInteger)status wire:(NSString *)wire device:(NSString *)device{
    NSMutableDictionary *r=self.records[[NSString stringWithFormat:@"%@:%@",device,wire]];if(!r||![r[@"active"] boolValue]||(status!=0&&status!=1))return NO;
    NSNumber *baseline=r[@"glassBaseline"]?:r[@"official"][@"status"];
    if(![baseline isEqual:@(status)])[self observeStatus:status wire:wire device:device];
    r[@"glassBaseline"]=@(status);[self save];return YES;
}
- (void)boundSource:(NSString *)source result:(NSDictionary *)result{
    NSMutableDictionary *r=self.records[source];if(!r)return;
    if([result[@"status"] isEqual:@"linked"]){r[@"bound"]=@YES;if(ValidApple(result[@"item"]))[self applyApple:result[@"item"] record:r now:NSDate.date.timeIntervalSince1970];}
    else r[@"lastError"]=result[@"status"]?:@"unknown";[self save];
}
- (void)finishAppleWrite:(NSString *)source pending:(NSDictionary *)pending result:(NSDictionary *)result{
    NSMutableDictionary *r=self.records[source];if(!r)return;
    if(![r[@"pendingApple"][@"token"] isEqual:pending[@"token"]])return;
    NSString *status=result[@"status"];
    if([@[@"updated",@"unchanged",@"conflict"] containsObject:status]){
        [r removeObjectForKey:@"pendingApple"];if(ValidApple(result[@"item"]))[self applyApple:result[@"item"] record:r now:NSDate.date.timeIntervalSince1970];
        // A concurrent Apple edit wins this field; preserve the rejected local
        // proposal so it is diagnosable instead of repeatedly overwriting it.
        if([status isEqual:@"conflict"])r[@"lastConflict"]=pending;
    }else r[@"lastError"]=status?:@"unknown";[self save];
}
- (NSArray<NSDictionary *> *)displayRowsForDevice:(NSString *)device{
    NSMutableArray *rows=[NSMutableArray array];for(NSDictionary *r in [self recordsForDevice:device])if([r[@"active"] boolValue])[rows addObject:r[@"row"]];return rows;
}
@end
