#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "win32_window.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins. Initialized before the single-instance check so the early-exit
  // path can balance it.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Single-instance guard: when another instance of this app is already
  // running, ask it to show itself and exit without starting an engine.
  ::HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    const UINT activate_message =
        ::RegisterWindowMessageW(kActivateMessageName);
    if (activate_message != 0) {
      // The running instance may be hidden in the tray; grant it permission
      // to take the foreground from this (briefly foreground) process before
      // asking it to activate.
      ::AllowSetForegroundWindow(ASFW_ANY);
      const HWND existing_window =
          FindWindowOfSameExecutable(Win32Window::kWindowClassName);
      if (existing_window != nullptr) {
        ::PostMessageW(existing_window, activate_message, 0, 0);
      }
    }
    ::CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // Impeller has been the default renderer on Windows since Flutter 3.47 and
  // can flicker / corrupt frames on some GPU driver combinations (reported on
  // Windows ARM64). Disable it so the engine falls back to Skia, per the
  // officially documented opt-out for deployed Windows apps.
  // https://docs.flutter.dev/perf/impeller
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1360, 840);
  if (!window.Create(L"图学基础教程习题解答", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Release the single-instance mutex before exiting.
  if (single_instance_mutex) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
