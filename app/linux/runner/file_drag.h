#ifndef RUNNER_FILE_DRAG_H_
#define RUNNER_FILE_DRAG_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Files dragged between the file manager and [window] (ADR-0144), for app/lib/features/desktop/file_drag.dart.
void file_drag_register(GtkWindow* window, FlView* view);

// Hands Dart the files a later start of Photolib opens with it (ADR-0206), and its `photolib:` links, as a drop, or as
// `opened` until it asks.
void file_drag_open(GFile** files, gint n_files);

#endif  // RUNNER_FILE_DRAG_H_
