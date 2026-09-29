// SmsTodoCore.m
// 短信转待办闭环：
//  快捷指令自动化（收到含"取件码/验证码/快递"的短信）→ POST 到 127.0.0.1:60123/sms
//  → 本模块解析关键信息 → 通过官方"建议卡片"通道(rayneonet businessId 21, envelope type 33)
//    推送到眼镜 → 用户点头确认/摇头取消（官方头控，type 34 回执 cmd 1/2）
//  → 确认则写入 Apple 提醒事项「待办」清单（复用 TIOAppleCreateReminder）。
#import "SmsTodoCore.h"
#import "AppleCalendarSync.h"
#import "ProtocolContext.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <objc/message.h>

static const uint16_t kSmsPort=60123;

// ---- 事件日志 ----
@interface TOSmsTodoCore ()
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,assign) BOOL running;
@property(nonatomic,copy) NSString *status;
@property(nonatomic,strong) dispatch_source_t listener;
@property(nonatomic,assign) int listenFd;
@end

@implementation TOSmsTodoCore

+ (instancetype)shared{static TOSmsTodoCore *one=nil;static dispatch_once_t once;dispatch_once(&once,^{one=[TOSmsTodoCore new];});return one;}
- (instancetype)init{self=[super init];if(self){_events=[NSMutableArray new];_status=@"未启动";}return self;}

- (NSArray *)log{return [_events copy];}
- (void)addEvent:(NSString *)message{
    NSString *line=[NSString stringWithFormat:@"%@ %@",[NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle],message];
    @synchronized(self){[_events insertObject:line atIndex:0];while(_events.count>50)[_events removeLastObject];}
}

// ---- protobuf-like 信封编码（与 TodoProtocol.m 解码器互逆：tag1=version, tag2=type, tag3=json） ----
static void PutVarUInt(NSMutableData *data,uint64_t value){
    do{uint8_t byte=(uint8_t)(value&0x7f);value>>=7;if(value)byte|=0x80;[data appendBytes:&byte length:1];}while(value);
}
static NSData *Envelope(uint64_t type,NSDictionary *json){
    if(!json)return nil;
    NSData *jsonData=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    if(!jsonData||!jsonData.length||jsonData.length>65536)return nil;
    NSMutableData *data=[NSMutableData data];
    PutVarUInt(data,1u<<3|0);PutVarUInt(data,1);        // tag1: version=1
    PutVarUInt(data,2u<<3|0);PutVarUInt(data,type);      // tag2: type
    PutVarUInt(data,3u<<3|2);PutVarUInt(data,jsonData.length);[data appendData:jsonData]; // tag3: json
    return data;
}
static NSData *FlutterTypedData(NSData *payload){
    if(!payload)return nil;
    NSMutableData *typed=[NSMutableData data];
    uint8_t flag=0;[typed appendBytes:&flag length:1];[typed appendData:payload];
    return typed;
}

// ---- 通过官方 rayneonet 通道发送建议卡片（businessId 21, envelope type 33） ----
static BOOL SendSuggestionCard(NSDictionary *body){
    NSString *device=TIOProtocolDevice();id plugin=TIOProtocolPlugin();
    if(!device.length||!plugin)return NO;
    NSData *envelope=Envelope(33,body);NSData *typed=FlutterTypedData(envelope);
    Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:");
    if(!typed||![cls respondsToSelector:make])return NO;
    @try{
        id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,@"rayneonet_sendMessage",@{@"deviceId":device,@"businessId":@21,@"payload":typed});
        ((void(*)(id,SEL,id,id))objc_msgSend)(plugin,NSSelectorFromString(@"handleMethodCall:result:"),call,[^(id r){} copy]);
        return YES;
    }@catch(NSException *e){return NO;}
}

// ---- 短信解析：取件码 / 验证码 / 快递类关键词 ----
static NSString *FirstMatch(NSString *text,NSString *pattern){
    NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    if(!rx)return nil;
    NSTextCheckingResult *hit=[rx firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
    if(!hit)return nil;
    NSRange r=[hit rangeAtIndex:1];if(r.location==NSNotFound)return nil;
    return [text substringWithRange:r];
}
static NSDictionary *ParseSms(NSString *text){
    NSString *trimmed=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!trimmed.length)return nil;
    NSString *code=nil,*kind=nil;
    if((code=FirstMatch(trimmed,@"取件码\\s*[:：]?\\s*([A-Z0-9\\-]{4,12})")))kind=@"取件码";
    else if((code=FirstMatch(trimmed,@"[取收][货件][码号]\\s*[:：]?\\s*([A-Z0-9\\-]{4,12})")))kind=@"取件码";
    else if((code=FirstMatch(trimmed,@"验证码\\s*[:：]?\\s*(\\d{4,8})")))kind=@"验证码";
    else if((code=FirstMatch(trimmed,@"动态码\\s*[:：]?\\s*(\\d{4,8})")))kind=@"验证码";
    if(kind&&code.length){
        NSString *title=[NSString stringWithFormat:@"%@ %@",kind,code];
        NSString *summary=trimmed.length>140?[trimmed substringToIndex:140]:trimmed;
        return @{@"title":title,@"text":summary,@"kind":kind,@"code":code};
    }
    NSArray<NSString *> *keywords=@[@"快递",@"驿站",@"丰巢",@"取件",@"包裹",@"货件",@"提醒"];
    for(NSString *kw in keywords)if([trimmed rangeOfString:kw].location!=NSNotFound){
        NSString *title=trimmed.length>40?[trimmed substringToIndex:40]:trimmed;
        return @{@"title":title,@"text":trimmed,@"kind":@"快递提醒"};
    }
    return nil;
}

// ---- 待办写入 ----
static void CreateTodo(NSString *title){
    if(!title.length)return;
    NSString *sourceID=[NSString stringWithFormat:@"sms-%@",NSUUID.UUID.UUIDString];
    [TOSmsTodoCore.shared addEvent:[NSString stringWithFormat:@"确认写入待办：%@",title]];
    TIOAppleCreateReminder(title,sourceID,^(NSDictionary *result){
        NSString *status=result[@"status"]?:@"unknown";
        [TOSmsTodoCore.shared addEvent:[NSString stringWithFormat:@"待办写入结果：%@",status]];
        TOSmsTodoCore.shared.status=[NSString stringWithFormat:@"最后写入：%@（%@）",title,status];
    });
}

// ---- 建议卡确认回执处理（由 TodoRuntime 观察器调用） ----
- (void)handleSuggestionChoice:(NSInteger)cmd payload:(NSDictionary *)body{
    NSString *title=body[@"title"];
    if(![title isKindOfClass:NSString.class]||!title.length)title=[[NSUserDefaults.standardUserDefaults stringForKey:@"TOSmsPendingTitle"] copy];
    if(!title.length){[self addEvent:@"收到头控回执但无待确认内容，已忽略"];return;}
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"TOSmsPendingTitle"];
    if(cmd==1){
        [self addEvent:[NSString stringWithFormat:@"点头确认：%@",title]];
        CreateTodo(title);
    }else{
        [self addEvent:[NSString stringWithFormat:@"摇头取消：%@",title]];
        self.status=@"已取消";
    }
}

// ---- 入口：处理一条短信文本 ----
- (BOOL)ingestText:(NSString *)text{
    NSDictionary *parsed=ParseSms(text);
    if(!parsed){[self addEvent:@"收到短信但未识别取件码/验证码/快递信息"];return NO;}
    NSString *title=parsed[@"title"];
    [[NSUserDefaults standardUserDefaults] setObject:title forKey:@"TOSmsPendingTitle"];
    NSDictionary *body=@{
        @"type":@1,
        @"requestId":[NSUUID UUID].UUIDString,
        @"title":title,
        @"text":parsed[@"text"],
        @"positive":@"点头加入待办",
        @"negative":@"摇头忽略"
    };
    [self addEvent:[NSString stringWithFormat:@"识别%@：%@ → 推送眼镜建议卡",parsed[@"kind"],parsed[@"code"]]];
    BOOL ok=SendSuggestionCard(body);
    self.status=ok?[NSString stringWithFormat:@"已推送待确认：%@（点头确认/摇头取消）",title]:@"推送失败：眼镜未连接或通道不可用";
    if(!ok)[self addEvent:@"建议卡推送失败（眼镜未连接？）"];
    return ok;
}
- (void)sendSuggestionCard:(NSString *)title text:(NSString *)text{
    [[NSUserDefaults standardUserDefaults] setObject:title forKey:@"TOSmsPendingTitle"];
    NSDictionary *body=@{@"type":@1,@"requestId":[NSUUID UUID].UUIDString,@"title":title,@"text":text,@"positive":@"点头加入待办",@"negative":@"摇头忽略"};
    BOOL ok=SendSuggestionCard(body);
    self.status=ok?[NSString stringWithFormat:@"已推送待确认：%@",title]:@"推送失败：眼镜未连接或通道不可用";
    [self addEvent:ok?[NSString stringWithFormat:@"手动推送建议卡：%@",title]:@"手动推送失败"];
}

// ---- 本地 HTTP 监听（快捷指令转发入口） ----
- (BOOL)start{
    if(_listener)return YES;
    int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0){self.status=@"创建监听失败";return NO;}
    int one=1;setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
    struct sockaddr_in addr={0};addr.sin_len=sizeof(addr);addr.sin_family=AF_INET;addr.sin_port=htons(kSmsPort);addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(bind(fd,(struct sockaddr *)&addr,sizeof(addr))||listen(fd,4)||fcntl(fd,F_SETFL,O_NONBLOCK)<0){close(fd);self.status=@"端口占用或监听失败";return NO;}
    _listenFd=fd;_listener=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,fd,0,dispatch_get_global_queue(0,0));
    __weak typeof(self) weak=self;
    dispatch_source_set_event_handler(_listener,^{
        struct sockaddr_in peer={0};socklen_t count=sizeof(peer);int client=accept(fd,(struct sockaddr *)&peer,&count);
        if(client>=0)[weak handleClient:client];
    });
    dispatch_source_set_cancel_handler(_listener,^{close(fd);});
    dispatch_resume(_listener);
    _running=YES;self.status=@"监听中（127.0.0.1:60123/sms，快捷指令转发目标）";
    return YES;
}
- (void)stop{@synchronized(self){if(_listener){dispatch_source_cancel(_listener);_listener=nil;}_running=NO;self.status=@"已停止";}}
- (void)handleClient:(int)fd{
    NSMutableData *buffer=[NSMutableData data];
    uint8_t chunk[4096];
    time_t deadline=time(NULL)+8;
    NSRange headerEnd=NSMakeRange(NSNotFound,0);
    while(time(NULL)<deadline){
        ssize_t n=read(fd,chunk,sizeof(chunk));
        if(n>0){[buffer appendBytes:chunk length:(NSUInteger)n];
            NSData *hay=buffer;
            NSUInteger end=[hay rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4] options:0 range:NSMakeRange(0,hay.length)].location;
            if(end!=NSNotFound){headerEnd=NSMakeRange(end,4);break;}
        }else if(n==0)break;
        else if(errno!=EINTR&&errno!=EAGAIN)break;
        if(buffer.length>131072)break;
    }
    NSInteger status=400;NSString *response=@"bad request";
    if(headerEnd.location!=NSNotFound){
        NSString *head=[[NSString alloc]initWithData:[buffer subdataWithRange:NSMakeRange(0,headerEnd.location)] encoding:NSUTF8StringEncoding];
        NSString *requestLine=[head componentsSeparatedByString:@"\r\n"].firstObject;
        NSArray *parts=[requestLine componentsSeparatedByString:@" "];
        NSString *method=parts.count?parts.firstObject:@"";
        NSString *target=parts.count>1?parts[1]:@"";
        NSInteger contentLength=0;
        for(NSString *line in [head componentsSeparatedByString:@"\r\n"]){
            if([line.lowercaseString hasPrefix:@"content-length:"]){
                NSInteger v=[line substringFromIndex:15].integerValue;
                if(v>0&&v<=65536)contentLength=v;
            }
        }
        BOOL isSms=[target isEqual:@"/sms"]||[target hasPrefix:@"/sms?"]||[target isEqual:@"/s"]||[target hasPrefix:@"/s?"];
        if(isSms){
            NSString *text=nil;
            if([method isEqual:@"POST"]){
                NSData *bodyData=contentLength?[buffer subdataWithRange:NSMakeRange(headerEnd.location+4,MIN(contentLength,buffer.length-headerEnd.location-4))]:nil;
                text=[[NSString alloc]initWithData:bodyData encoding:NSUTF8StringEncoding];
            }else if([method isEqual:@"GET"]){
                NSRange q=[target rangeOfString:@"?"];
                if(q.location!=NSNotFound){
                    NSString *query=[target substringFromIndex:q.location+1];
                    NSString *escaped=query;
                    for(NSString *pair in [query componentsSeparatedByString:@"&"]){
                        NSArray *kv=[pair componentsSeparatedByString:@"="];
                        if(kv.count==2&&[kv[0] isEqual:@"text"]){
                            escaped=[kv[1] stringByReplacingOccurrencesOfString:@"+" withString:@" "];
                            escaped=[escaped stringByRemovingPercentEncoding]?:escaped;
                            text=escaped;
                        }
                    }
                }
            }
            if(text.length){BOOL ok=[self ingestText:text];status=ok?200:202;response=ok?@"{\"ok\":true}":@"{\"ok\":false,\"reason\":\"unrecognized\"}";}
            else{status=400;response=@"{\"ok\":false,\"reason\":\"empty\"}";}
        }else if([target isEqual:@"/health"]){status=200;response=@"{\"ok\":true,\"service\":\"sms-todo\"}";}
        else{status=404;response=@"not found";}
    }
    NSData *resp=[response dataUsingEncoding:NSUTF8StringEncoding];
    NSString *headOut=[NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\nContent-Type: text/plain\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",(long)status,status==200?@"OK":@"",(unsigned long)resp.length];
    NSMutableData *out=[NSMutableData data];[out appendData:[headOut dataUsingEncoding:NSUTF8StringEncoding]];[out appendData:resp];
    size_t sent=0;while(sent<out.length){ssize_t w=write(fd,out.bytes+sent,out.length-sent);if(w>0)sent+=(size_t)w;else break;}
    close(fd);
}
@end
