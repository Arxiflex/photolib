#!/usr/bin/env bash
# Drag and drop with the file manager on the three desktops (M1-20, ADR-0144). Nothing here compiles Swift or Windows
# C++, so the runners are checked as text against the Dart that calls them; the Linux smoke test drags both ways with
# another X11 client (tools/desktop/xdnd.c), and the smoke jobs run the macOS and Windows apps.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

DART=app/lib/features/desktop/file_drag.dart
LINUX=app/linux/runner/file_drag.cc
MACOS=app/macos/Runner/FileDrag.swift
WINDOWS=app/windows/runner/file_drag.cpp

assert_patterns assert_matches "$DART" \
  "MethodChannel\('org\.photolib/drag'\)" "the Dart side uses org.photolib/drag" \
  "invokeMethod\('drag'" "drags paths out" \
  "'dropped'" "takes the paths of a drop"
for runner in "$LINUX" "$MACOS" "$WINDOWS"; do
  assert_patterns assert_matches "$runner" \
    '"org\.photolib/drag"' "answers org.photolib/drag" \
    '"drag"' "drags paths out" \
    '"dropped"' "hands Dart the paths of a drop"
done

# --- each desktop's own drag and drop, as copies, ignoring the window's own files
assert_patterns assert_matches "$LINUX" \
  'gtk_drag_dest_add_uri_targets' "takes file URIs dropped on the window" \
  'gtk_drag_begin_with_coordinates' "drags file URIs out" \
  'GDK_ACTION_COPY' "as copies" \
  'gtk_drag_get_source_widget' "ignoring its own drags" \
  'GDK_BUTTON_RELEASE' "and tells FlView the button went up after a drag"
assert_patterns assert_matches "$MACOS" \
  'beginDraggingSession' "drags file URLs out" \
  'outsideApplication \? \.copy' "as copies, only out of the app" \
  'draggingSource == nil' "ignoring its own drags" \
  'leftMouseUp' "and tells Flutter the button went up after a drag"
assert_patterns assert_matches app/macos/Runner/MainFlutterWindow.swift \
  'registerForDraggedTypes\(\[\.fileURL\]\)' "the window takes file URLs dropped on it" \
  'files\.dropped\(' "and hands them to FileDrag" \
  'FileDrag\(\)' "makes FileDrag" \
  'files\.register\(' "and registers it"
assert_patterns assert_matches "$WINDOWS" \
  'DragAcceptFiles\(window, TRUE\)' "takes files dropped on the window" \
  'DragQueryFileW' "reads their paths" \
  'SHDoDragDrop' "drags files out through the shell" \
  'DROPEFFECT_COPY' "as copies" \
  'if \(!dragging' "ignoring its own drags" \
  'WM_LBUTTONUP' "and tells Flutter the button went up after a drag"
assert_patterns assert_matches app/windows/runner/flutter_window.cpp \
  'RegisterFileDrag\(' "the window registers its file drags" \
  'case WM_DROPFILES' "and passes on WM_DROPFILES"
assert_matches app/windows/runner/main.cpp 'OleInitialize' "OLE runs, which a drag needs"

# --- Open with Photolib: Linux and Windows start the app with the files (main.dart), macOS's Finder opens them
assert_matches app/lib/main.dart 'openedFilesProvider\.overrideWithValue' "main hands the app the files of its command line"
assert_patterns assert_matches "$MACOS" \
  'addApplicationDelegate\(self\)' "macOS hears the files Finder opens with the app" \
  'func handleOpen\(_ urls' "takes them" \
  'case \("opened"' "and keeps those that come before Dart asks"
assert_matches "$DART" "invokeListMethod<String>\('opened'\)" "the Dart side asks for them"
# Offered beside the system's viewers, never as their default (photolib-design#551): macOS ranks its types Alternate,
# and nothing makes Photolib Linux's default (a mimeapps.list's [Default Applications], xdg-mime default).
ranks=$(tr -d '\n\t' <app/macos/Runner/Info.plist | grep -oE '<key>LSHandlerRank</key><string>[A-Za-z]+</string>')
[[ $ranks == '<key>LSHandlerRank</key><string>Alternate</string>' ]] && ok "macOS offers the app, ranked Alternate" ||
  fail "macOS's document types must rank Alternate alone: $ranks"
grep -rqsE 'Default Applications|xdg-mime default' app/linux tools/package.sh &&
  fail "Linux must not make Photolib a default" || ok "Linux offers the app without making it a default"
# ADR-0154 states the desktop entry as it is and that one instance takes a later start's files (ADR-0206)
OPEN_ADR=docs/adr/0154-desktop-open-with-packages-keyring.md
exec_line=$(grep -m1 '^Exec=' app/linux/packaging/org.photolib.photolib.desktop)
assert_matches "$OPEN_ADR" "\`$exec_line\`" "gives the desktop entry's $exec_line"
assert_prose "$OPEN_ADR" 'later start[^.]*hands [^.]*running app[^.]*ADR-0206' \
  "says a later start hands its files to the running app (ADR-0206)"
! grep -qi 'second window' "$OPEN_ADR" && ok "$OPEN_ADR: no second window" ||
  fail "$OPEN_ADR: still says a second start opens a second window"

# --- one Photolib over the store (ADR-0206): a later start of the Linux or Windows app hands the running one its files,
# taken as a drop, and ends; the flutter tool's runs, tests and drives each start their own
assert_patterns assert_matches app/linux/runner/my_application.cc \
  'G_APPLICATION_HANDLES_OPEN' "the Linux app is a unique GApplication that opens files" \
  'g_application_get_is_remote' "a later start finds the running one" \
  'g_application_open\(' "and hands it its files" \
  '->open = my_application_open' "which the running one takes" \
  'gtk_window_present' "bringing its window to the front" \
  'FLUTTER_ENGINE_SWITCHES' "unless the flutter tool started it"
! grep -q 'G_APPLICATION_NON_UNIQUE,' app/linux/runner/my_application.cc && ok "the Linux app is not always non-unique" ||
  fail "the Linux app is always non-unique"
assert_matches "$LINUX" 'void file_drag_open\(' "the Linux drag channel takes the files of a later start"
assert_matches "$LINUX" 'g_file_has_uri_scheme\(files\[i\], "photolib"\)' "and its photolib: links, as they are"
assert_patterns assert_matches app/windows/runner/main.cpp \
  'CreateMutexW\(.*org\.photolib\.photolib' "the Windows app holds a mutex of the session" \
  'ERROR_ALREADY_EXISTS' "a later start finds the running one" \
  'HandFilesOver\(\)' "and hands it its files" \
  'FLUTTER_ENGINE_SWITCHES' "unless the flutter tool started it"
assert_patterns assert_matches "$WINDOWS" \
  '_wcsnicmp\(argv\[i\], L"photolib:", 9\)' "photolib: links as they are" \
  'GetFullPathNameW' "files absolute" \
  'WM_COPYDATA' "as WM_COPYDATA to the running window" \
  'AllowSetForegroundWindow' "which may come to the front"
assert_patterns assert_matches app/windows/runner/flutter_window.cpp \
  'case WM_COPYDATA' "the window takes them" \
  'SetForegroundWindow' "and comes to the front"
for runner in "$LINUX" "$WINDOWS"; do
  assert_matches "$runner" '"opened"' "keeps the files that come before Dart asks"
done
ADR=docs/adr/0206-desktop-single-instance.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-21\. The owner kept [^*]*photolib-design#596' \
  "ADR-0206 is Accepted, as the owner kept it (#596)"
assert_matches docs/adr/README.md '\(0206-desktop-single-instance\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0206 as Accepted"

# --- compiled into each app
assert_matches app/linux/runner/my_application.cc 'file_drag_register\(' "the Linux app registers its file drags"
for build in app/linux/runner/CMakeLists.txt:file_drag.cc app/windows/runner/CMakeLists.txt:file_drag.cpp; do
  assert_matches "${build%%:*}" "\"${build#*:}\"" "builds ${build#*:}"
done
sources=$(sed -n '/Begin PBXSourcesBuildPhase/,/End PBXSourcesBuildPhase/p' app/macos/Runner.xcodeproj/project.pbxproj)
[[ $sources == *"/* FileDrag.swift in Sources */"* ]] && ok "the macOS app compiles FileDrag.swift" ||
  fail "FileDrag.swift is in no Sources phase"

# --- the Linux smoke test drags both ways with another X11 client
assert_prose app/integration_test/app_test.dart "XDND.*'drop'.*'catch'.*TargetPlatform\.linux" \
  "the Linux smoke test drops a folder in and catches a cell's file"
assert_patterns assert_matches tools/desktop/xdnd.c \
  'XdndDrop' "the other client speaks XDND" \
  'XTestFakeButtonEvent' "and moves the pointer as a person would"

# --- the decision, as the owner answered it (photolib-design#505)
ADR=docs/adr/0144-desktop-drag-and-drop.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-20\. The owner confirmed [^*]*photolib-design#505' \
  "is Accepted, recording the owner's confirmation (#505)"
assert_prose "$ADR" '\* \*\*Status\*\*: [^*]*mouse drag in the viewer[^*]*photolib-design#553' \
  "records that the owner kept the viewer's mouse drag out (#553)"
assert_matches docs/adr/README.md '\(0144-desktop-drag-and-drop\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0144 as Accepted"
assert_prose "$ADR" 'already lies in a library folder[^.]*opens? (that|the) item in its library context[^.]*M10-04' \
  "keeps the owner's note for file associations (M10-04)"

finish
