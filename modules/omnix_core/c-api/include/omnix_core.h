#ifndef OMNIX_CORE_H
#define OMNIX_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OmnixModel OmnixModel;
typedef struct OmnixConversation OmnixConversation;
typedef struct OmnixCancellation OmnixCancellation;

typedef struct {
    uint32_t kind;
    const uint8_t *data;
    size_t size;
} OmnixPart;

enum { OMNIX_TEXT = 0, OMNIX_IMAGE = 1, OMNIX_AUDIO = 2 };
enum { OMNIX_COMPLETED = 0, OMNIX_CANCELLED = 1, OMNIX_ERROR = -1 };

/* Preview C ABI. Strings are UTF-8. On error, release *error with omnix_string_free.
 * Model and conversation operations require exclusive access. Conversations can outlive
 * their model handle. The blocking send owns no caller memory after returning.
 * The callback runs on a runtime thread. Its bytes are borrowed for the call.
 * Return false to cancel. Only cancellation may be called concurrently with send.
 */
typedef bool (*OmnixTextCallback)(void *user, const uint8_t *text, size_t size);

OmnixModel *omnix_model_open(const char *path, const char *cache_dir, uint32_t context_tokens,
                            bool images, bool audio, char **error);
void omnix_model_close(OmnixModel *model);
OmnixConversation *omnix_conversation_open(OmnixModel *model, const char *system_prompt,
                                           uint32_t output_tokens, char **error);
void omnix_conversation_close(OmnixConversation *conversation);
OmnixCancellation *omnix_cancellation_new(void);
void omnix_cancel(const OmnixCancellation *cancel);
void omnix_cancellation_free(OmnixCancellation *cancel);
int32_t omnix_conversation_send(OmnixConversation *conversation, const OmnixPart *parts,
                                size_t count, const OmnixCancellation *cancel,
                                OmnixTextCallback callback, void *user, char **error);
void omnix_string_free(char *string);

#ifdef __cplusplus
}
#endif
#endif
