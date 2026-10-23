#ifndef LIZZIE_CRASHPAD_H
#define LIZZIE_CRASHPAD_H
#include <stddef.h>
#if defined(_WIN32) && defined(LIZZIE_CRASHPAD_BUILD)
#define LIZZIE_CRASHPAD_API __declspec(dllexport)
#elif defined(_WIN32)
#define LIZZIE_CRASHPAD_API __declspec(dllimport)
#else
#define LIZZIE_CRASHPAD_API
#endif
#ifdef __cplusplus
extern "C" {
#endif

typedef struct LizzieCrashpad LizzieCrashpad;
/* One registration per process, on the main thread, before creating workers.
 * At most 16 attachments. All paths are absolute UTF-8, with no embedded NUL.
 * The database directory
 * is dedicated to Crashpad. Attachments must exist before a crash; prepare
 * them during healthy execution. Paths and annotation values are copied.
 * No upload URL, uploader, periodic pruning or automatic restart is enabled.
 * Returns NULL on failure. Keep the owner alive through all worker teardown. */
LIZZIE_CRASHPAD_API LizzieCrashpad *lizzie_crashpad_start(
    const char *handler, const char *database,
    const char *const *attachments, size_t attachment_count);
/* Main-thread only; copies nonempty keys and values of at most 255 bytes.
 * Up to 64 entries, with no embedded NULs. Returns 0 for invalid input. */
LIZZIE_CRASHPAD_API int lizzie_crashpad_set(
    LizzieCrashpad *owner, const char *key, size_t key_size,
    const char *value, size_t value_size);
/* Capture on demand without terminating. Requires an active registration. */
LIZZIE_CRASHPAD_API void lizzie_crashpad_dump(void);
/* After all workers stop, detach metadata and release its owner. The DLL must
 * remain loaded through process exit. Linux's process signal registration
 * remains installed; this is not a stop/restart or restore-handler API. */
LIZZIE_CRASHPAD_API void lizzie_crashpad_free(LizzieCrashpad *owner);

#ifdef __cplusplus
}
#endif
#endif
