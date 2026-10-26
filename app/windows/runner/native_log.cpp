#include "native_log.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <chrono>
#include <memory>
#include <mutex>
#include <utility>

namespace {

using flutter::EncodableList;
using flutter::EncodableValue;
using Result = std::unique_ptr<flutter::MethodResult<EncodableValue>>;

constexpr UINT kSend = WM_APP + 1;
constexpr size_t kMaxWaiting = 1000;

std::mutex lock;
EncodableList waiting;   // until the app listens
EncodableList outgoing;  // for the platform thread to send
bool listening = false;
HWND window = nullptr;  // a message-only window on the platform thread
std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;

LRESULT CALLBACK Proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message != kSend) return DefWindowProc(hwnd, message, wparam, lparam);
  EncodableList ready;
  {
    std::lock_guard<std::mutex> guard(lock);
    ready.swap(outgoing);
  }
  for (auto& record : ready) channel->InvokeMethod("log", std::make_unique<EncodableValue>(std::move(record)));
  return 0;
}

}  // namespace

void RegisterNativeLog(flutter::BinaryMessenger* messenger) {
  WNDCLASS type{};
  type.lpfnWndProc = Proc;
  type.hInstance = GetModuleHandle(nullptr);
  type.lpszClassName = L"PhotolibLog";
  RegisterClass(&type);
  window = CreateWindowEx(0, type.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, type.hInstance, nullptr);
  channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "org.photolib/log", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call, Result reply) {
        if (call.method_name() != "listen") return reply->NotImplemented();
        EncodableList records;
        {
          std::lock_guard<std::mutex> guard(lock);
          listening = true;
          records.swap(waiting);
        }
        reply->Success(EncodableValue(std::move(records)));
      });
}

void NativeLog(const std::string& level, const std::string& logger, const std::string& message,
               flutter::EncodableMap fields) {
  const int64_t ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                         std::chrono::system_clock::now().time_since_epoch())
                         .count();
  EncodableValue record(EncodableList{EncodableValue(ms), EncodableValue(level), EncodableValue(logger),
                                      EncodableValue(message), EncodableValue(std::move(fields))});
  std::lock_guard<std::mutex> guard(lock);
  if (!listening) {
    if (waiting.size() < kMaxWaiting) waiting.push_back(std::move(record));
    return;
  }
  outgoing.push_back(std::move(record));
  PostMessage(window, kSend, 0, 0);
}
