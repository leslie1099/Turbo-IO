#import <Foundation/Foundation.h>

@interface TIOTodoCompletionLedger : NSObject

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (BOOL)isPending:(NSString *)sourceID;
- (void)markPending:(NSString *)sourceID;
- (void)markPending:(NSString *)sourceID title:(NSString *)title;
- (NSString *)titleForSource:(NSString *)sourceID;
- (void)deferConfirmation:(NSString *)sourceID;
- (void)authorizeCompletion:(NSString *)sourceID;
- (BOOL)authorizeAutomaticCompletion:(NSString *)sourceID hasExactLink:(BOOL)hasExactLink;
- (BOOL)isCompletionAuthorized:(NSString *)sourceID;
- (void)markSynchronized:(NSString *)sourceID;
- (BOOL)shouldPresentConfirmation:(NSString *)sourceID;
- (void)markConfirmationPresented:(NSString *)sourceID;
- (void)resetConfirmationPresentation:(NSString *)sourceID;
- (void)clearPending:(NSString *)sourceID;
@property (nonatomic, readonly) NSUInteger pendingCount;
@property (nonatomic, readonly) NSArray<NSString *> *pendingSources;

@end
