// LyricsFollowCore.m
// 无感歌词跟随（MediaRemote 全局监听）
// 原理：iOS 的 MediaRemote 私有框架提供系统级"正在播放"信息（标题/歌手/当前句歌词），
// 由任何前台音乐 App（QQ音乐/网易云等）写入。我们 dlopen 读取，无需登录、无需蓝牙车载歌词开关。
// 数据流：MediaRemote(全局播放) -> 歌词行变化 -> TMMusicBridge 推给眼镜 -> 眼镜显示当前句。
// 行为：播放中自动跟随；暂停保持最后一句（歌词常亮）；切歌自动换；停止（无播放源）自动关闭眼镜音乐页。
#import "LyricsFollowCore.h"
#import "MusicBridge.h"
#import "MusicPlayer.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>

typedef void (^MRNowPlayingInfoBlock)(NSDictionary *info);
typedef void (^MRNotificationBlock)(void);
static void (*MRMediaRemoteGetNowPlayingInfoFunc)(dispatch_queue_t, MRNowPlayingInfoBlock);
static void (*MRMediaRemoteRegisterForNowPlayingNotificationsFunc)(dispatch_queue_t, MRNotificationBlock);

static NSString *KeyTitle(void){return @"kMRMediaRemoteNowPlayingInfoTitle";}
static NSString *KeyArtist(void){return @"kMRMediaRemoteNowPlayingInfoArtist";}
static NSString *KeyLyrics(void){return @"kMRMediaRemoteNowPlayingInfoLyrics";}
static NSString *KeyRate(void){return @"kMRMediaRemoteNowPlayingInfoPlaybackRate";}
static NSString *KeyApp(void){return @"kMRMediaRemoteNowPlayingInfoApplicationDisplayName";}

static BOOL LoadMediaRemote(void){
    static BOOL tried=NO,ok=NO;
    if(tried)return ok;tried=YES;
    void *handle=dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",RTLD_NOW);
    if(!handle)return ok;
    MRMediaRemoteGetNowPlayingInfoFunc=dlsym(handle,"MRMediaRemoteGetNowPlayingInfo");
    MRMediaRemoteRegisterForNowPlayingNotificationsFunc=dlsym(handle,"MRMediaRemoteRegisterForNowPlayingNotifications");
    ok=MRMediaRemoteGetNowPlayingInfoFunc!=NULL&&MRMediaRemoteRegisterForNowPlayingNotificationsFunc!=NULL;
    return ok;
}

@interface TOLyricsFollow()
@property(nonatomic)BOOL running;
@property(nonatomic,strong)NSDictionary *info;
@property(nonatomic,strong)NSString *status;
@property(nonatomic,strong)TMMusicBridge *bridge;
@property(nonatomic,strong)NSTimer *pollTimer;
@property(nonatomic,strong)NSString *lastTitle,*lastArtist,*lastLyric;
@property(nonatomic,assign)BOOL glassesOpen;
@property(nonatomic,assign)BOOL skipActive; // 我们自己的网易云播放器占用时跳过接管
@end

@implementation TOLyricsFollow

+ (TOLyricsFollow *)shared{
    static TOLyricsFollow *s=nil;
    static dispatch_once_t once;dispatch_once(&once,^{s=[TOLyricsFollow new];});
    return s;
}

- (instancetype)init{
    if((self=[super init])){
        _bridge=[TMMusicBridge shared];
        _status=@"歌词跟随待机";
    }
    return self;
}

- (void)start{
    if(_running)return;
    if(!LoadMediaRemote()){_status=@"歌词跟随不可用：系统媒体接口不可用";return;}
    _running=YES;_status=@"歌词跟随待机";
    // 通知订阅（播放状态/切歌/歌词变化都会触发）
    MRMediaRemoteRegisterForNowPlayingNotificationsFunc(dispatch_get_main_queue(),^{
        [self refreshNowPlaying];
    });
    [NSNotificationCenter.defaultCenter addObserverForName:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){[self refreshNowPlaying];}];
    // 兜底轮询：通知偶发漏推时保持跟随
    _pollTimer=[NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(refreshNowPlaying) userInfo:nil repeats:YES];
    [self refreshNowPlaying];
}

- (void)stop{
    _running=NO;
    [_pollTimer invalidate];_pollTimer=nil;
    if(_glassesOpen){[_bridge close];_glassesOpen=NO;}
    _lastTitle=_lastArtist=_lastLyric=nil;
    _status=@"歌词跟随已停止";
}

- (void)refreshNowPlaying{
    if(!_running)return;
    MRMediaRemoteGetNowPlayingInfoFunc(dispatch_get_main_queue(),^(NSDictionary *info){
        [self ingest:info];
    });
}

- (void)ingest:(NSDictionary *)info{
    if(![info isKindOfClass:NSDictionary.class])info=@{};
    NSString *title=info[KeyTitle()];
    NSString *artist=info[KeyArtist()];
    NSString *lyric=info[KeyLyrics()];
    NSNumber *rateNum=info[KeyRate()];
    BOOL playing=rateNum?[rateNum doubleValue]>0:NO;
    BOOL hasTitle=title.length>0;
    NSString *app=info[KeyApp()];
    self.info=info;
    // 无播放源：关闭眼镜音乐页
    if(!hasTitle){
        if(_glassesOpen){[_bridge close];_glassesOpen=NO;}
        _lastTitle=_lastArtist=_lastLyric=nil;
        _status=@"歌词跟随待机：等待播放";
        return;
    }
    // 标题变化：切歌，重置跟随并重新打开眼镜音乐页
    if(![_lastTitle isEqual:title]||![_lastArtist isEqual:artist]){
        _lastTitle=title;_lastArtist=artist;_lastLyric=nil;
        if(_glassesOpen){[_bridge close];_glassesOpen=NO;}
        _status=[NSString stringWithFormat:@"跟随：%@%@",title,artist.length?[@" - " stringByAppendingString:artist]:@""];
        // 新歌先推标题行（封面不可用时也能看到歌名）
        if(lyric.length){} // 下面统一走歌词推送
        [self pushLyric:lyric.length?lyric:title];
        return;
    }
    // 同一首歌：只推歌词变化
    if(lyric.length&&![_lastLyric isEqual:lyric]){
        [self pushLyric:lyric];
    }
    // 暂停时保持最后一句（常亮），不做任何操作
    (void)playing;
}

- (void)pushLyric:(NSString *)lyric{
    _lastLyric=lyric;
    NSString *clean=lyric;
    // 去掉常见的歌词附加信息（如 "♫"、时间戳残留）
    NSCharacterSet *trim=[NSCharacterSet whitespaceAndNewlineCharacterSet];
    clean=[clean stringByTrimmingCharactersInSet:trim];
    if(!clean.length)return;
    if(_skipActive)return;
    // 我们自己 App 的网易云播放器正在推眼镜时，不接管（避免双推冲突）
    if([TMPlayer shared].playing&&[TMPlayer shared].glasses)return;
    if(_bridge.failed)[_bridge reset];
    // 眼镜音乐页：单句歌词（ms=0 常驻显示，随更新刷新）
    if(!_glassesOpen){
        [_bridge openWithCover:nil lyrics:@[@{@"ms":@0,@"text":clean}]];
        _glassesOpen=YES;
    }else{
        [_bridge openWithCover:nil lyrics:@[@{@"ms":@0,@"text":clean}]];
    }
    _status=[NSString stringWithFormat:@"推送歌词：%@",clean];
}
@end
