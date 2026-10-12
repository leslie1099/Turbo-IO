#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 车票行程：解析 12306 / 航旅纵横 / 携程 / 去哪儿 / 同程 等短信中的车次/航班、
// 时间、检票口/登机口、座位，推送到眼镜（音乐页通道 8 秒），并写入苹果提醒事项。
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTicketTripParse(NSString *text);
FOUNDATION_EXPORT UIViewController *TIOTicketTripController(void);

NS_ASSUME_NONNULL_END
