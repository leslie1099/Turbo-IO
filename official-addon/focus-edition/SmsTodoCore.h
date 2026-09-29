// SmsTodoCore.h
// 短信转待办：本地 HTTP 监听快捷指令转发的短信 → 解析关键信息（取件码/验证码/快递）→
// 经官方"建议卡片"通道推送到眼镜 → 用户点头/摇头（官方头控）确认 → 写入 Apple 提醒事项「待办」清单。
#import <Foundation/Foundation.h>

@interface TOSmsTodoCore : NSObject
+ (instancetype)shared;
- (void)start;   // 启动本地监听（127.0.0.1:60123）
- (void)stop;
- (BOOL)ingestText:(NSString *)text;            // 处理一条短信文本（快捷指令转发或手动测试）
- (void)sendSuggestionCard:(NSString *)title text:(NSString *)text; // 主动推送一张建议卡到眼镜
@property(nonatomic,readonly) BOOL running;
@property(nonatomic,readonly) NSString *status;
@property(nonatomic,readonly) NSArray *log;           // 最近事件日志
@end
