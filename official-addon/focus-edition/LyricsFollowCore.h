// LyricsFollowCore.h
// 无感歌词跟随：监听系统级"正在播放"（MediaRemote 私有框架），
// 任何 App（QQ音乐/网易云/其他）播放时自动把当前歌词推送到眼镜。零交互。
#import <Foundation/Foundation.h>

@interface TOLyricsFollow : NSObject
@property(class,nonatomic,readonly) TOLyricsFollow *shared;
- (void)start;   // 后台启动监听（自动）
- (void)stop;    // 停止监听并关闭眼镜音乐页
@property(nonatomic,readonly) BOOL running;
@property(nonatomic,readonly) NSString *status;   // 供调试/设置页展示
@property(nonatomic,readonly) NSDictionary *info; // 当前全局播放信息
@end
