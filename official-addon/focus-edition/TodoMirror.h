#import <Foundation/Foundation.h>
void TIOTodoMirrorStart(void (^sender)(NSString *device,NSData *payload,void (^completion)(BOOL submitted)));
void TIOTodoMirrorRefresh(void);
void TIOTodoMirrorObserveOutgoing(NSDictionary *arguments);
NSDictionary *TIOTodoMirrorProjection(NSDictionary *arguments);
void TIOTodoMirrorProjectionSubmitted(NSDictionary *projection,BOOL success);
// Receives normalized NSData payloads. Returns nil only for locally owned
// messages; mixed reconnect batches retain every foreign row and schedule.
NSDictionary *TIOTodoMirrorRouteEvent(NSDictionary *event);
BOOL TIOTodoMirrorHandlesSource(NSString *source);
BOOL TIOTodoMirrorToggleSource(NSString *source);
NSArray<NSDictionary *> *TIOTodoMirrorDisplayRows(NSString *device,NSArray<NSDictionary *> *officialRows);
NSDictionary *TIOTodoMirrorDiagnostics(void);
