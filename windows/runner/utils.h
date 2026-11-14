#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <windows.h>

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Finds the handle of an existing top-level window of |window_class| that
// belongs to a process running the same executable image as this process.
// Returns nullptr when no such window exists. Used by the single-instance
// logic: the Flutter runner window class name is shared by many Flutter apps,
// so the process image must be matched as well to find the right window.
HWND FindWindowOfSameExecutable(const wchar_t* window_class);

#endif  // RUNNER_UTILS_H_
