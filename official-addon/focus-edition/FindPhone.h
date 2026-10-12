#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 找手机：点击后手机播放提示音并震动，同时眼镜显示"手机在这"。
FOUNDATION_EXPORT BOOL TIOFindPhoneRing(void);
FOUNDATION_EXPORT UIViewController *TIOFindPhoneController(void);

NS_ASSUME_NONNULL_END
