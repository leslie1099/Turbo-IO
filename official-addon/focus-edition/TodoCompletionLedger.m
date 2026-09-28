#import "TodoCompletionLedger.h"

static NSString *const PendingCompletionKey=@"io.turboio.todo.pendingAppleCompletions.v1";
static NSString *const PresentedConfirmationKey=@"io.turboio.todo.presentedAppleCompletionConfirmations.v1";
static NSString *const CompletionDetailsKey=@"io.turboio.todo.appleCompletionDetails.v2";

@implementation TIOTodoCompletionLedger {
    NSUserDefaults *_defaults;
    NSMutableSet<NSString *> *_pending;
    NSMutableSet<NSString *> *_presented;
    NSMutableSet<NSString *> *_deferred,*_authorized,*_synchronized;
    NSMutableDictionary<NSString *,NSString *> *_titles;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self=[super init];
    if(!self)return nil;
    _defaults=defaults?:NSUserDefaults.standardUserDefaults;
    _pending=[NSMutableSet set];
    _presented=[NSMutableSet set];
    _deferred=[NSMutableSet set];_authorized=[NSMutableSet set];_synchronized=[NSMutableSet set];_titles=[NSMutableDictionary dictionary];
    id stored=[_defaults objectForKey:PendingCompletionKey];
    if([stored isKindOfClass:NSArray.class])for(id value in (NSArray *)stored){
        if([value isKindOfClass:NSString.class]&&[value length]>0&&[value length]<=300)[_pending addObject:value];
    }
    // A displayed alert is not a user decision. Never restore that transient
    // state after process death; v1 could permanently hide unfinished work.
    id details=[_defaults objectForKey:CompletionDetailsKey];
    if([details isKindOfClass:NSDictionary.class])for(id source in details){
        if(![source isKindOfClass:NSString.class]||![source length]||[source length]>300)continue;
        id row=details[source];if(![row isKindOfClass:NSDictionary.class])continue;
        if([row[@"synchronized"] isEqual:@YES]){[_synchronized addObject:source];[_pending removeObject:source];continue;}
        if(![_pending containsObject:source])continue;
        id title=row[@"title"];if([title isKindOfClass:NSString.class]&&[title length]&&[title length]<=240)_titles[source]=title;
        if([row[@"authorized"] isEqual:@YES])[_authorized addObject:source];
        else if([row[@"deferred"] isEqual:@YES])[_deferred addObject:source];
    }
    return self;
}

- (NSUInteger)pendingCount { return _pending.count; }
- (NSArray<NSString *> *)pendingSources { return [_pending.allObjects sortedArrayUsingSelector:@selector(compare:)]; }
- (NSString *)titleForSource:(NSString *)sourceID { return _titles[sourceID]; }

- (BOOL)isPending:(NSString *)sourceID {
    return [sourceID isKindOfClass:NSString.class]&&[_pending containsObject:sourceID];
}

- (void)persist {
    if(_pending.count)[_defaults setObject:[_pending.allObjects sortedArrayUsingSelector:@selector(compare:)] forKey:PendingCompletionKey];
    else [_defaults removeObjectForKey:PendingCompletionKey];
    NSMutableDictionary *details=[NSMutableDictionary dictionary];
    for(NSString *source in _pending){NSMutableDictionary *row=[NSMutableDictionary dictionary];if(_titles[source])row[@"title"]=_titles[source];if([_authorized containsObject:source])row[@"authorized"]=@YES;else if([_deferred containsObject:source])row[@"deferred"]=@YES;details[source]=row;}
    for(NSString *source in _synchronized)details[source]=@{@"synchronized":@YES};
    [_defaults setObject:details forKey:CompletionDetailsKey];
    [_defaults removeObjectForKey:PresentedConfirmationKey];
    [_defaults synchronize];
}

- (BOOL)shouldPresentConfirmation:(NSString *)sourceID {
    return [self isPending:sourceID]&&![_presented containsObject:sourceID]&&![_deferred containsObject:sourceID]&&![_authorized containsObject:sourceID];
}

- (void)markConfirmationPresented:(NSString *)sourceID {
    if([self shouldPresentConfirmation:sourceID])[_presented addObject:sourceID];
}

- (void)resetConfirmationPresentation:(NSString *)sourceID {
    if(![self isPending:sourceID])return;
    [_presented removeObject:sourceID];
    [_deferred removeObject:sourceID];
    [self persist];
}

- (void)markPending:(NSString *)sourceID {
    [self markPending:sourceID title:nil];
}
- (void)markPending:(NSString *)sourceID title:(NSString *)title {
    if(![sourceID isKindOfClass:NSString.class]||!sourceID.length||sourceID.length>300||[_synchronized containsObject:sourceID])return;
    // Keep the title that accompanied the completion decision. A later rename
    // must not silently broaden a previously confirmed write.
    if(!_titles[sourceID]&&[title isKindOfClass:NSString.class]&&title.length&&title.length<=240)_titles[sourceID]=title;
    [_pending addObject:sourceID];
    [self persist];
}
- (void)deferConfirmation:(NSString *)sourceID {
    if(![self isPending:sourceID])return;
    [_presented removeObject:sourceID];[_authorized removeObject:sourceID];[_deferred addObject:sourceID];[self persist];
}
- (void)authorizeCompletion:(NSString *)sourceID {
    if(![self isPending:sourceID])return;
    [_presented removeObject:sourceID];[_deferred removeObject:sourceID];[_authorized addObject:sourceID];[self persist];
}
- (BOOL)authorizeAutomaticCompletion:(NSString *)sourceID hasExactLink:(BOOL)hasExactLink {
    // The user's automatic-sync policy covers an observed completion with an
    // exact saved Apple link. An old explicit deferral remains retryable.
    if(!hasExactLink||![self isPending:sourceID]||!_titles[sourceID].length||[_deferred containsObject:sourceID])return NO;
    if(![_authorized containsObject:sourceID])[self authorizeCompletion:sourceID];
    return YES;
}
- (BOOL)isCompletionAuthorized:(NSString *)sourceID { return [self isPending:sourceID]&&[_authorized containsObject:sourceID]; }
- (void)markSynchronized:(NSString *)sourceID {
    if(![sourceID isKindOfClass:NSString.class]||!sourceID.length||sourceID.length>300)return;
    [_pending removeObject:sourceID];[_presented removeObject:sourceID];[_titles removeObjectForKey:sourceID];[_deferred removeObject:sourceID];[_authorized removeObject:sourceID];[_synchronized addObject:sourceID];[self persist];
}

- (void)clearPending:(NSString *)sourceID {
    if(![sourceID isKindOfClass:NSString.class])return;
    [_pending removeObject:sourceID];
    [_presented removeObject:sourceID];
    [_titles removeObjectForKey:sourceID];[_deferred removeObject:sourceID];[_authorized removeObject:sourceID];[_synchronized removeObject:sourceID];
    [self persist];
}

@end
