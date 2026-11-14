#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Name of the MethodChannel used by the Dart side to control window
// behavior. Must match the channel name used in lib/.
constexpr char kWindowChannelName[] = "com.kepler16f.tuxuejieda/window";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Channel that lets Dart toggle close-to-tray and other window behaviors.
  // The native default is close-to-tray enabled; Dart syncs the user's real
  // preference once it has loaded it.
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HandleWindowChannelCall(call, std::move(result));
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Tear the channel down before the engine: it references the engine's
  // messenger.
  window_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleWindowChannelCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name().compare("setCloseToTray") == 0) {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!arguments) {
      result->Error("badarg", "setCloseToTray expects a map argument");
      return;
    }
    const auto enabled_it =
        arguments->find(flutter::EncodableValue("enabled"));
    if (enabled_it == arguments->end()) {
      result->Error("badarg", "setCloseToTray expects an \"enabled\" key");
      return;
    }
    const bool* enabled = std::get_if<bool>(&enabled_it->second);
    if (!enabled) {
      result->Error("badarg", "\"enabled\" must be a bool");
      return;
    }
    SetCloseToTray(*enabled);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  result->NotImplemented();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Handle session shutdown before forwarding to the engine: the engine also
  // listens to WM_ENDSESSION for app-lifecycle reporting and may consume it,
  // which would skip the runner's tray cleanup and real-quit path in
  // Win32Window::MessageHandler. The engine does not need to observe it here
  // because the app is terminating.
  if (message == WM_ENDSESSION && wparam) {
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
