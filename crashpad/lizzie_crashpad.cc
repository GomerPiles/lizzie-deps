// Own all C++ state on this side of the C ABI, including Windows CRT allocations.
#define LIZZIE_CRASHPAD_BUILD
#include "lizzie_crashpad.h"
#include <cstring>
#include <memory>
#include <new>
#include <string_view>
#include <vector>
#include "base/files/file_path.h"
#include "client/crash_report_database.h"
#include "client/crashpad_client.h"
#include "client/crashpad_info.h"
#include "client/settings.h"
#include "client/simple_string_dictionary.h"
#include "util/misc/capture_context.h"
#if defined(__APPLE__)
#include "client/simulate_crash.h"
#endif

struct LizzieCrashpad {
    crashpad::CrashpadClient client;
    crashpad::SimpleStringDictionary annotations;
};

static bool pathFromUtf8(const char *text, base::FilePath *path) {
    if (!text) return false;
#if defined(_WIN32)
    const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         text, -1, nullptr, 0);
    if (count <= 1) return false;
    std::wstring wide(static_cast<size_t>(count), L'\0');
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                            text, -1, wide.data(), count)) return false;
    wide.resize(static_cast<size_t>(count - 1));
    *path = base::FilePath(wide);
    return wide.size() >= 3 &&
           ((wide[1] == L':' && (wide[2] == L'\\' || wide[2] == L'/')) ||
            (wide[0] == L'\\' && wide[1] == L'\\'));
#else
    *path = base::FilePath(text);
    return text[0] == '/';
#endif
}

extern "C" LizzieCrashpad *lizzie_crashpad_start(
    const char *handler_text, const char *database_text,
    const char *const *attachment_text, size_t attachment_count) {
    if (attachment_count > 16 || (attachment_count && !attachment_text)) return nullptr;
    auto *info = crashpad::CrashpadInfo::GetCrashpadInfo();
    if (info->simple_annotations()) return nullptr;
    base::FilePath handler, database_path;
    if (!pathFromUtf8(handler_text, &handler) ||
        !pathFromUtf8(database_text, &database_path)) return nullptr;
    std::vector<base::FilePath> attachments;
    for (size_t i = 0; i < attachment_count; ++i) {
        base::FilePath path;
        if (!pathFromUtf8(attachment_text[i], &path)) return nullptr;
        attachments.push_back(path);
    }
    auto database = crashpad::CrashReportDatabase::Initialize(database_path);
    if (!database || !database->GetSettings()->SetUploadsEnabled(false)) return nullptr;
    auto owner = std::unique_ptr<LizzieCrashpad>(new (std::nothrow) LizzieCrashpad);
    if (!owner || !owner->client.StartHandler(
            handler, database_path, base::FilePath(), "", {},
            {"--no-periodic-tasks"}, false, false, attachments)) return nullptr;
    info->set_simple_annotations(&owner->annotations);
    return owner.release();
}

extern "C" int lizzie_crashpad_set(LizzieCrashpad *owner, const char *key,
    size_t key_size, const char *value, size_t value_size) {
    if (!owner || !key || !value || key_size == 0 || key_size >= 256 ||
        value_size >= 256 || std::memchr(key, 0, key_size) ||
        std::memchr(value, 0, value_size)) return 0;
    owner->annotations.SetKeyValue(std::string_view(key, key_size),
                                   std::string_view(value, value_size));
    return 1;
}

extern "C" void lizzie_crashpad_dump(void) {
    crashpad::NativeCPUContext context;
    crashpad::CaptureContext(&context);
#if defined(__APPLE__)
    crashpad::SimulateCrash(context);
#elif defined(_WIN32)
    crashpad::CrashpadClient::DumpWithoutCrash(context);
#else
    crashpad::CrashpadClient::DumpWithoutCrash(&context);
#endif
}

extern "C" void lizzie_crashpad_free(LizzieCrashpad *owner) {
    if (!owner) return;
    crashpad::CrashpadInfo::GetCrashpadInfo()->set_simple_annotations(nullptr);
    delete owner;
}
