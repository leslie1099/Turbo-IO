// KeepAliveAudio.m
// 无声音频后台保活实现。
// 原理：AVAudioSession ambient + AVAudioPlayer 循环播放 1 秒静音 WAV，
// iOS 后台运行规则中"正在播放音频"的 App 不会被挂起。
// ambient 类别不抢占其他音频（QQ音乐/网易云外放不被打断），无声音频不产生可闻输出。
// 兼容性：与 TMMusicBridge 音乐页显示通道无冲突（那是显示通道，不是音频播放）。
#import "KeepAliveAudio.h"
#import "KeepAliveAudio_data.h"
#import <AVFoundation/AVFoundation.h>

@implementation TOKeepAliveAudio {
    AVAudioPlayer *_player;
}
+ (instancetype)shared{static TOKeepAliveAudio *one=nil;static dispatch_once_t once;dispatch_once(&once,^{one=[TOKeepAliveAudio new];});return one;}

- (BOOL)start{
    if(_player&&_player.playing)return YES;
    @try{
        AVAudioSession *session=[AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryAmbient withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
        [session setActive:YES error:nil];
        NSData *wav=[NSData dataWithBytes:kSilentWav length:sizeof(kSilentWav)];
        if(!wav.length)return NO;
        _player=[[AVAudioPlayer alloc] initWithData:wav error:nil];
        if(!_player)return NO;
        _player.numberOfLoops=-1;           // 无限循环
        _player.volume=0.0;                 // 双重保险：静音数据 + 零音量
        [_player prepareToPlay];
        [_player play];
        return _player.playing;
    }@catch(NSException *e){return NO;}
}
- (void)stop{
    @try{if(_player&&_player.playing)[_player stop];}@catch(NSException *e){}
    _player=nil;
}
- (BOOL)playing{return _player&&_player.playing;}
@end
