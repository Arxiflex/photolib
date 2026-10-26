#ifndef RUNNER_FILE_DRAG_H_
#define RUNNER_FILE_DRAG_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// Files dragged between Explorer and [window], whose Flutter view is [view] (ADR-0144), for
// app/lib/features/desktop/file_drag.dart.
void RegisterFileDrag(flutter::BinaryMessenger* messenger, HWND window, HWND view);

// Hands Dart the files of a WM_DROPFILES.
void FilesDropped(HDROP drop);

// The main window's title, by which a later start finds it (HandFilesOver).
constexpr wchar_t kWindowTitle[] = L"Photolib";

// One Photolib over the store (ADR-0206): a later start hands the running app's window its command line's files,
// absolute, and its photolib: links, as WM_COPYDATA; false without such a window.
bool HandFilesOver();

// Hands Dart the files of a later start's WM_COPYDATA as a drop, or as `opened` until it asks; false when [data] is
// not one.
bool FilesOpened(const COPYDATASTRUCT* data);

#endif  // RUNNER_FILE_DRAG_H_
