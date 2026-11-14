#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

namespace {

// State threaded through the window enumeration callback.
struct SameExecutableSearch {
  const wchar_t* window_class;
  const wchar_t* exe_basename;
  HWND window;
};

// Case-insensitively compares the base name of |image_path| (its length in
// UTF-16 units is |image_path_chars|) against |exe_basename|.
bool ImageBaseNameMatches(const wchar_t* image_path, DWORD image_path_chars,
                          const wchar_t* exe_basename) {
  const wchar_t* image_name = image_path + image_path_chars;
  while (image_name > image_path && image_name[-1] != L'\\' &&
         image_name[-1] != L'/') {
    --image_name;
  }
  const int image_name_length =
      static_cast<int>(image_path + image_path_chars - image_name);
  const int result = ::CompareStringW(LOCALE_INVARIANT, NORM_IGNORECASE,
                                      image_name, image_name_length,
                                      exe_basename, -1);
  return result == CSTR_EQUAL;
}

BOOL CALLBACK EnumWindowsForSameExecutable(HWND window, LPARAM lparam) {
  auto* search = reinterpret_cast<SameExecutableSearch*>(lparam);

  wchar_t class_name[128];
  if (::GetClassNameW(window, class_name,
                      static_cast<int>(sizeof(class_name) / sizeof(wchar_t))) ==
      0) {
    return TRUE;
  }
  if (::wcscmp(class_name, search->window_class) != 0) {
    return TRUE;
  }

  DWORD process_id = 0;
  ::GetWindowThreadProcessId(window, &process_id);
  if (process_id == 0) {
    return TRUE;
  }
  ::HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (!process) {
    return TRUE;
  }
  wchar_t image_path[MAX_PATH];
  DWORD image_path_chars = MAX_PATH;
  const bool matches =
      ::QueryFullProcessImageNameW(process, 0, image_path, &image_path_chars) &&
      ImageBaseNameMatches(image_path, image_path_chars, search->exe_basename);
  ::CloseHandle(process);
  if (matches) {
    search->window = window;
    return FALSE;  // A match was found; stop enumerating.
  }
  return TRUE;
}

}  // namespace

HWND FindWindowOfSameExecutable(const wchar_t* window_class) {
  wchar_t self_path[MAX_PATH];
  const DWORD self_path_chars = ::GetModuleFileNameW(nullptr, self_path, MAX_PATH);
  if (self_path_chars == 0 || self_path_chars >= MAX_PATH) {
    return nullptr;
  }
  self_path[self_path_chars] = L'\0';

  const wchar_t* self_basename = self_path + self_path_chars;
  while (self_basename > self_path && self_basename[-1] != L'\\' &&
         self_basename[-1] != L'/') {
    --self_basename;
  }

  SameExecutableSearch search{};
  search.window_class = window_class;
  search.exe_basename = self_basename;
  search.window = nullptr;
  ::EnumWindows(EnumWindowsForSameExecutable,
                reinterpret_cast<LPARAM>(&search));
  return search.window;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  // First, find the length of the string with a safe upper bound (CWE-126).
  // UNICODE_STRING_MAX_CHARS (32767) is the maximum length of a UNICODE_STRING.
  int input_length = static_cast<int>(wcsnlen(utf16_string, UNICODE_STRING_MAX_CHARS));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || static_cast<size_t>(target_length) > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
