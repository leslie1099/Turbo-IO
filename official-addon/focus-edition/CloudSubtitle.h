#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 云端字幕 · 麦克风版（听写 / 听书外放收音 / 翻译）：
// 录音分段 → 硅基流动 SenseVoice ASR → 可选 DeepSeek 翻译 → 推眼镜（官方音乐页通道）。
// 限制（如实标注）：只能收到麦克风声音；手机外放听书时 TTS 清晰可识别，
// 戴耳机听书时收不到（iOS 侧载环境无内部音频捕获通道）。
FOUNDATION_EXPORT void TIOCloudSubtitleTranscribe(NSData *audio, void (^done)(NSString *text, NSString *error));
// 非流式 chat 调用（复用已配置的硅基流动 Key/endpoint/模型），供翻译与提醒解析等复用。
FOUNDATION_EXPORT void TIOCloudSubtitleChat(NSString *prompt, void (^done)(NSString *answer, NSString *error));
FOUNDATION_EXPORT UIViewController *TIOCloudSubtitleController(void);

NS_ASSUME_NONNULL_END
