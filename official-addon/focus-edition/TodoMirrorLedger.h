#import <Foundation/Foundation.h>

// Durable local identities and field-level reconciliation. No device or Apple
// writes occur here. Wire numbers are local transport IDs, never cloud IDs.
@interface TIOTodoMirrorLedger:NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (void)reconcileApple:(NSArray<NSDictionary *> *)items officialRows:(NSArray<NSDictionary *> *)rows device:(NSString *)device now:(NSTimeInterval)now;
- (void)observeOfficialRows:(NSArray<NSDictionary *> *)rows device:(NSString *)device;
- (BOOL)observeStatus:(NSInteger)status wire:(NSString *)wire device:(NSString *)device;
- (BOOL)observeBatchStatus:(NSInteger)status wire:(NSString *)wire device:(NSString *)device;
- (NSArray<NSDictionary *> *)recordsForDevice:(NSString *)device;
- (NSDictionary *)recordForSource:(NSString *)source;
- (void)boundSource:(NSString *)source result:(NSDictionary *)result;
- (void)finishAppleWrite:(NSString *)source pending:(NSDictionary *)pending result:(NSDictionary *)result;
- (BOOL)ownsWire:(NSString *)wire device:(NSString *)device;
- (BOOL)handlesSource:(NSString *)source;
- (NSArray<NSDictionary *> *)displayRowsForDevice:(NSString *)device;
@end
