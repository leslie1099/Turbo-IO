#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 定时提醒 · 语音版：录一句（如"下午三点提醒我开会"）→ SenseVoice 识别 →
// 已配置模型解析出 {title,start,end} → 写入苹果日历+提醒事项（复用待办同步的日程能力），
// 系统到点提醒；打开 App 时已建日程会显示在“待办同步”页日程区。
FOUNDATION_EXPORT UIViewController *TIOReminderVoiceController(void);

NS_ASSUME_NONNULL_END
