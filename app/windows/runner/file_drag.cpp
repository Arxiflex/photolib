// Files dropped on the window go to Dart as their paths (`dropped`, from WM_DROPFILES), and Dart's `drag` drags paths
// out of it as copies through the shell's data object for them (SHDoDragDrop), while the mouse button is down. Files a
// later start opens with the app go as a drop, and those that come before Dart asks for them (`opened`) wait.
#include "file_drag.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <algorithm>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
HWND top = nullptr;
HWND flutter_view = nullptr;
// While the window's own drag runs, which ends on it as a drop of its own files.
bool dragging = false;
// Opened before Dart asked; empty once it did.
std::optional<EncodableList> opened = EncodableList{};
// What a later start's WM_COPYDATA carries: its files' paths and its links, each ended by a NUL.
constexpr ULONG_PTR kOpenFiles = 0x50686F74;

std::wstring Wide(const std::string& utf8) {
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  std::wstring wide(n > 0 ? n - 1 : 0, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, wide.data(), n);
  return wide;
}

std::string Utf8(const std::wstring& wide) {
  const int n = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string utf8(n > 0 ? n - 1 : 0, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, utf8.data(), n, nullptr, nullptr);
  return utf8;
}

void Drag(const EncodableList& paths) {
  std::vector<PIDLIST_ABSOLUTE> items;
  for (const auto& path : paths) {
    const auto* utf8 = std::get_if<std::string>(&path);
    if (PIDLIST_ABSOLUTE item = utf8 ? ILCreateFromPathW(Wide(*utf8).c_str()) : nullptr) items.push_back(item);
  }
  std::vector<PCIDLIST_ABSOLUTE> ids(items.begin(), items.end());
  ComPtr<IShellItemArray> array;
  ComPtr<IDataObject> data;
  if (!ids.empty() && SUCCEEDED(SHCreateShellItemArrayFromIDLists(static_cast<UINT>(ids.size()), ids.data(), &array)) &&
      SUCCEEDED(array->BindToHandler(nullptr, BHID_DataObject, IID_PPV_ARGS(&data)))) {
    DWORD effect = DROPEFFECT_NONE;
    dragging = true;
    SHDoDragDrop(top, data.Get(), nullptr, DROPEFFECT_COPY, &effect);
    dragging = false;
    // The drag kept the mouse, so Flutter never heard the button go up: tell it, or its next click is lost.
    POINT at;
    GetCursorPos(&at);
    ScreenToClient(flutter_view, &at);
    PostMessage(flutter_view, WM_LBUTTONUP, 0, MAKELPARAM(at.x, at.y));
  }
  for (PIDLIST_ABSOLUTE item : items) ILFree(item);
}

}  // namespace

void RegisterFileDrag(flutter::BinaryMessenger* messenger, HWND window, HWND view) {
  top = window;
  flutter_view = view;
  DragAcceptFiles(window, TRUE);
  channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "org.photolib/drag", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "opened") {
      result->Success(EncodableValue(opened.value_or(EncodableList{})));
      opened.reset();
      return;
    }
    const auto* paths = std::get_if<EncodableList>(call.arguments());
    if (call.method_name() != "drag" || paths == nullptr) return result->NotImplemented();
    result->Success();
    Drag(*paths);
  });
}

void FilesDropped(HDROP drop) {
  EncodableList paths;
  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < count; i++) {
    std::wstring path(DragQueryFileW(drop, i, nullptr, 0), L'\0');
    DragQueryFileW(drop, i, path.data(), static_cast<UINT>(path.size() + 1));
    paths.emplace_back(Utf8(path));
  }
  DragFinish(drop);
  if (!dragging && channel) channel->InvokeMethod("dropped", std::make_unique<EncodableValue>(paths));
}

bool HandFilesOver() {
  std::wstring paths;
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  for (int i = 1; argv != nullptr && i < argc; i++) {
    // A password setup link (ADR-0243) as it is, a file absolute.
    std::wstring path = argv[i];
    if (_wcsnicmp(argv[i], L"photolib:", 9) != 0) {
      path.assign(GetFullPathNameW(argv[i], 0, nullptr, nullptr), L'\0');
      path.resize(GetFullPathNameW(argv[i], static_cast<DWORD>(path.size()), path.data(), nullptr));
    }
    paths += path;
    paths.push_back(L'\0');
  }
  LocalFree(argv);
  // The running app's window, which may still be on its way.
  HWND window = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
  for (int i = 0; i < 100 && window == nullptr; i++) {
    Sleep(100);
    window = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
  }
  if (window == nullptr) return false;
  DWORD process = 0;
  GetWindowThreadProcessId(window, &process);
  AllowSetForegroundWindow(process);
  COPYDATASTRUCT data{kOpenFiles, static_cast<DWORD>(paths.size() * sizeof(wchar_t)), paths.data()};
  SendMessageW(window, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data));
  return true;
}

bool FilesOpened(const COPYDATASTRUCT* data) {
  if (data == nullptr || data->dwData != kOpenFiles) return false;
  const auto* text = static_cast<const wchar_t*>(data->lpData);
  const size_t length = data->cbData / sizeof(wchar_t);
  EncodableList paths;
  for (size_t start = 0; start < length;) {
    const auto end = static_cast<size_t>(std::find(text + start, text + length, L'\0') - text);
    if (end > start) paths.emplace_back(Utf8(std::wstring(text + start, end - start)));
    start = end + 1;
  }
  if (opened) {
    opened->insert(opened->end(), paths.begin(), paths.end());
  } else if (channel && !paths.empty()) {
    channel->InvokeMethod("dropped", std::make_unique<EncodableValue>(paths));
  }
  return true;
}
