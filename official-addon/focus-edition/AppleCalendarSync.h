#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The phone is the only writer. Source ID includes glasses device and official task ID.
FOUNDATION_EXPORT void TIOAppleCreateReminder(NSString *title, NSString *sourceID,
    void (^completion)(NSDictionary *result));
FOUNDATION_EXPORT void TIOAppleCompleteLinkedReminder(NSString *sourceID, NSString *expectedTitle,
    void (^completion)(NSDictionary *result));
// Two voice turns: select one exact, incomplete Apple reminder, then confirm it.
FOUNDATION_EXPORT void TIOApplePrepareReminderCompletion(NSString *title,
    void (^completion)(NSDictionary *result));
FOUNDATION_EXPORT void TIOAppleConfirmReminderCompletion(void (^completion)(NSDictionary *result));
FOUNDATION_EXPORT BOOL TIOAppleHasPendingReminderCompletion(void);
FOUNDATION_EXPORT NSString * _Nullable TIOAppleCompletionTitleFromUtterance(NSString *utterance);
FOUNDATION_EXPORT BOOL TIOAppleIsCompletionConfirmation(NSString *utterance);
FOUNDATION_EXPORT BOOL TIOAppleHasLinkedReminder(NSString *sourceID);
// Read the exact saved Apple item when the glasses no longer include its row.
// This never changes the reminder's completion state or matches by title.
FOUNDATION_EXPORT void TIOAppleReadLinkedReminder(NSString *sourceID,void (^completion)(NSDictionary *result));
// Local two-way bridge, scoped to the selected ordinary 待办 list. Identity
// matching is by saved identifiers only; these APIs never search by title.
FOUNDATION_EXPORT NSDictionary *TIOAppleTodoLinkIdentity(NSString *sourceID);
FOUNDATION_EXPORT void TIOAppleReadTodoList(void (^completion)(NSDictionary *result));
FOUNDATION_EXPORT void TIOAppleBindTodoIdentity(NSString *sourceID,NSDictionary *identity,void (^completion)(NSDictionary *result));
FOUNDATION_EXPORT void TIOAppleApplyTodoFields(NSString *sourceID,NSDictionary *expected,NSDictionary *fields,void (^completion)(NSDictionary *result));
// Exact-title candidate picker for a user-confirmed link to an observed glasses task.
FOUNDATION_EXPORT void TIOAppleFindPendingReminders(NSString *title,void (^completion)(NSDictionary *result));
FOUNDATION_EXPORT void TIOAppleLinkReminder(NSString *sourceID,NSString *identifier,NSString *expectedTitle,void (^completion)(NSDictionary *result));
FOUNDATION_EXPORT void TIOAppleCreateSchedule(NSDictionary *schedule,
    void (^completion)(NSDictionary *result));
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOAppleScheduleRows(void);
FOUNDATION_EXPORT void TIOAppleCompleteScheduleReminder(NSString *scheduleID,
    void (^completion)(NSDictionary *result));
FOUNDATION_EXPORT NSDictionary * _Nullable TIOScheduleArguments(NSString *raw);

NS_ASSUME_NONNULL_END
