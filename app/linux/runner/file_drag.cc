#include "file_drag.h"

#include <cstring>

// Files dropped on the window go to Dart as their paths (`dropped`), and Dart's `drag` drags paths out of it as
// copies, while the mouse button that moved them is down. Files a later start opens with the app go as a drop, and
// those that come before Dart asks for them (`opened`) wait.
namespace {

struct FileDrag {
  FlMethodChannel* channel;
  GtkWidget* window;
  // What FlView hears the mouse through.
  GtkWidget* events;
  // The drag under way.
  gchar** uris;
  // Opened before Dart asked; null once it did.
  FlValue* opened;
};

FileDrag* file_drag = nullptr;

void dropped(GtkWidget* /*window*/, GdkDragContext* context, gint /*x*/, gint /*y*/, GtkSelectionData* data,
             guint /*info*/, guint /*time*/, gpointer user_data) {
  // A drag of the window's own files that ends on it moves nothing.
  if (gtk_drag_get_source_widget(context) != nullptr) return;
  auto* self = static_cast<FileDrag*>(user_data);
  g_auto(GStrv) uris = gtk_selection_data_get_uris(data);
  g_autoptr(FlValue) paths = fl_value_new_list();
  for (gchar** uri = uris; uri != nullptr && *uri != nullptr; uri++) {
    gchar* path = g_filename_from_uri(*uri, nullptr, nullptr);
    if (path != nullptr) fl_value_append_take(paths, fl_value_new_string(path));
    g_free(path);
  }
  fl_method_channel_invoke_method(self->channel, "dropped", paths, nullptr, nullptr, nullptr);
}

void data_get(GtkWidget* /*window*/, GdkDragContext* /*context*/, GtkSelectionData* data, guint /*info*/,
              guint /*time*/, gpointer user_data) {
  gtk_selection_data_set_uris(data, static_cast<FileDrag*>(user_data)->uris);
}

// GTK's drag takes the pointer, so FlView never hears the button go up and would drop the next click: tell it.
void drag_end(GtkWidget* /*window*/, GdkDragContext* /*context*/, gpointer user_data) {
  auto* self = static_cast<FileDrag*>(user_data);
  GdkWindow* window = self->events != nullptr ? gtk_widget_get_window(self->events) : nullptr;
  if (window == nullptr) return;
  GdkDevice* pointer = gdk_seat_get_pointer(gdk_display_get_default_seat(gdk_window_get_display(window)));
  GdkEvent* release = gdk_event_new(GDK_BUTTON_RELEASE);
  release->button.window = GDK_WINDOW(g_object_ref(window));
  release->button.send_event = TRUE;
  release->button.time = GDK_CURRENT_TIME;
  release->button.button = 1;
  gdk_window_get_device_position_double(window, pointer, &release->button.x, &release->button.y, nullptr);
  gtk_widget_event(self->events, release);
  gdk_event_free(release);
}

void method_call(FlMethodChannel* /*channel*/, FlMethodCall* call, gpointer user_data) {
  auto* self = static_cast<FileDrag*>(user_data);
  FlValue* paths = fl_method_call_get_args(call);
  if (strcmp(fl_method_call_get_name(call), "opened") == 0) {
    g_autoptr(FlValue) opened = self->opened != nullptr ? self->opened : fl_value_new_list();
    self->opened = nullptr;
    fl_method_call_respond_success(call, opened, nullptr);
    return;
  }
  if (strcmp(fl_method_call_get_name(call), "drag") != 0 || fl_value_get_type(paths) != FL_VALUE_TYPE_LIST) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  g_strfreev(self->uris);
  const size_t count = fl_value_get_length(paths);
  self->uris = g_new0(gchar*, count + 1);
  size_t n = 0;
  for (size_t i = 0; i < count; i++) {
    gchar* uri = g_filename_to_uri(fl_value_get_string(fl_value_get_list_value(paths, i)), nullptr, nullptr);
    if (uri != nullptr) self->uris[n++] = uri;
  }
  GtkTargetList* targets = gtk_target_list_new(nullptr, 0);
  gtk_target_list_add_uri_targets(targets, 0);
  gtk_drag_begin_with_coordinates(self->window, targets, GDK_ACTION_COPY, 1, nullptr, -1, -1);
  gtk_target_list_unref(targets);
  fl_method_call_respond_success(call, nullptr, nullptr);
}

}  // namespace

void file_drag_register(GtkWindow* window, FlView* view) {
  auto* self = g_new0(FileDrag, 1);
  file_drag = self;
  self->opened = fl_value_new_list();
  self->window = GTK_WIDGET(window);
  GList* children = gtk_container_get_children(GTK_CONTAINER(view));
  for (GList* child = children; child != nullptr; child = child->next) {
    if (GTK_IS_EVENT_BOX(child->data)) self->events = GTK_WIDGET(child->data);
  }
  g_list_free(children);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)),
                                        "org.photolib/drag", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call, self, nullptr);
  gtk_drag_dest_set(self->window, GTK_DEST_DEFAULT_ALL, nullptr, 0, GDK_ACTION_COPY);
  gtk_drag_dest_add_uri_targets(self->window);
  g_signal_connect(self->window, "drag-data-received", G_CALLBACK(dropped), self);
  g_signal_connect(self->window, "drag-data-get", G_CALLBACK(data_get), self);
  g_signal_connect(self->window, "drag-end", G_CALLBACK(drag_end), self);
}

void file_drag_open(GFile** files, gint n_files) {
  if (file_drag == nullptr) return;
  g_autoptr(FlValue) paths = fl_value_new_list();
  for (gint i = 0; i < n_files; i++) {
    // A password setup link (ADR-0243) as it is, which has no path.
    g_autofree gchar* path =
        g_file_has_uri_scheme(files[i], "photolib") ? g_file_get_uri(files[i]) : g_file_get_path(files[i]);
    if (path == nullptr) continue;
    fl_value_append_take(paths, fl_value_new_string(path));
    if (file_drag->opened != nullptr) fl_value_append_take(file_drag->opened, fl_value_new_string(path));
  }
  if (file_drag->opened == nullptr) {
    fl_method_channel_invoke_method(file_drag->channel, "dropped", paths, nullptr, nullptr, nullptr);
  }
}
