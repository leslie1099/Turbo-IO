// KeepAliveAudio.h
// 无声音频后台保活：iOS 判定 App 正在播放音频 → 不挂起 → 蓝牙连接与本地 60123 服务保持活跃。
// 副作用：控制中心出现"正在播放"图标；静音音频耗电极小。
#import <Foundation/Foundation.h>

@interface TOKeepAliveAudio : NSObject
+ (instancetype)shared;
- (void)start;   // 启动静音循环（App 启动时调用一次）
- (void)stop;
@property(nonatomic,readonly) BOOL playing;
@end
