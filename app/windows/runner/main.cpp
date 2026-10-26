#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "file_drag.h"
#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // One Photolib over the store (ADR-0206): a later start hands the running
  // one its files and ends. The flutter tool's runs, tests and drives each
  // start their own, beside it and one another.
  if (::GetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", nullptr, 0) == 0) {
    ::CreateMutexW(nullptr, FALSE, L"Local\\org.photolib.photolib");
    if (::GetLastError() == ERROR_ALREADY_EXISTS) {
      return HandFilesOver() ? EXIT_SUCCESS : EXIT_FAILURE;
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins, and OLE, which drags files out of the window (file_drag.cpp).
  ::OleInitialize(nullptr);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::OleUninitialize();
  return EXIT_SUCCESS;
}
