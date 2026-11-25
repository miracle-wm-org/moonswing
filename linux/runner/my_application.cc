#include "my_application.h"

#include <dlfcn.h>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// The engine's render context is the raster thread's, and this keeps the GTK
// thread from walking off with it.
//
// A view's renderer, as it is realized, asks the driver whether it can blit,
// and to ask it makes the engine's *render* context current on the thread it
// is realized on — this one (`fl_compositor_opengl_new`). Nothing gives it
// back. EGL lets a context be current on one thread at a time, so that call
// fails harmlessly for as long as the raster thread holds the context, which
// used to be always. Since the Wayland subsurface renderer it is not: the
// raster thread presents each frame with the subsurface's own context current
// and returns to the render context afterwards. A window realized inside one
// of those presents — any second bar, background or popup, while any view is
// drawing — takes the context, the raster thread's `eglMakeCurrent` is
// refused from then on, and every view stops: `Could not make the context
// current to acquire the frame`, once per frame, behind `Timed out waiting for
// subsurface frame` for each window still waiting on its first.
//
// The embedder already hands the context back for the first view, before it
// starts the engine (`realize_cb` in fl_view.cc). This does the same for every
// view: an emission hook on GtkWidget::realize, which GLib runs straight after
// the renderer's own class handler, so the context is on the wrong thread for
// a few instructions rather than for the rest of the session. Leaving this
// thread with no context is the state it is in after the first view anyway,
// and everything the embedder draws from it makes its own current first.
//
// A stopgap, and an unproven one. The account above is read off the embedder's
// source: the failure has not been reproduced, so nothing yet shows this is
// what stops it. The fix belongs upstream, in `fl_compositor_opengl_new`
// (probe with the platform context, not the render one); remove this when
// that lands.
//
// Here rather than in Dart because it has to be in place before the first
// view exists and outlive a hot restart. EGL is looked up in the process, as
// the embedder's own copy (libepoxy dlopens it): the runner links none, and
// if it is not loaded there is nothing current to release. Only the subsurface
// renderer is touched — the X11 one draws through a GdkGLContext, which keeps
// its own idea of what is current.
static void release_gl_context() {
  using EglGetCurrentDisplay = void* (*)();
  using EglMakeCurrent = unsigned int (*)(void*, void*, void*, void*);
  static EglGetCurrentDisplay get_current_display = nullptr;
  static EglMakeCurrent make_current = nullptr;

  if (make_current == nullptr) {
    void* egl = dlopen("libEGL.so.1", RTLD_LAZY | RTLD_NOLOAD);
    if (egl == nullptr) return;
    get_current_display = reinterpret_cast<EglGetCurrentDisplay>(
        dlsym(egl, "eglGetCurrentDisplay"));
    make_current =
        reinterpret_cast<EglMakeCurrent>(dlsym(egl, "eglMakeCurrent"));
    if (get_current_display == nullptr || make_current == nullptr) {
      make_current = nullptr;
      return;
    }
  }

  // EGL_NO_DISPLAY: nothing is current on this thread.
  void* display = get_current_display();
  if (display == nullptr) return;
  // EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT.
  make_current(display, nullptr, nullptr, nullptr);
}

// GSignalEmissionHook for GtkWidget::realize.
static gboolean widget_realized_hook(GSignalInvocationHint* hint,
                                     guint n_param_values,
                                     const GValue* param_values,
                                     gpointer data) {
  if (n_param_values > 0) {
    gpointer widget = g_value_peek_pointer(&param_values[0]);
    if (widget != nullptr &&
        g_strcmp0(G_OBJECT_TYPE_NAME(widget), "FlViewRendererSubsurface") ==
            0) {
      release_gl_context();
    }
  }
  return TRUE;  // Stay connected.
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "multiple_windows");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "multiple_windows");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  // Skia, not Impeller, and this is the single highest-impact line in the
  // shell.
  //
  // Impeller's GLES backend is the engine's default on Linux, and on this
  // shell it is catastrophic. It encodes every draw as an individual GL
  // operation through its reactor — profiled on a live miracle session, an
  // *idle* shell with nothing on screen but the bar and its ticking clock
  // issued ~574 `ReactorGLES::Operation`s per frame (38,486 across 67 frames)
  // and spent 55.9 ms per frame on the raster thread. With the pointer moving
  // it fell to 6.5 fps. The UI thread was at 1.8 ms throughout: none of this
  // is Dart-side work, and no amount of repaint containment reaches it.
  //
  // The same build with Impeller off rasters the same idle frame in 17.1 ms
  // (p90 23.3 against 67.6) and scrolls the settings pane at 22.8 fps, and
  // `ReactorGLES` disappears from the timeline entirely.
  //
  // Why a compiled-in default rather than a flag anyone has to remember: this
  // is what makes the *shipped* artifact fast. `flutter run`'s own
  // `--enable-impeller` arrives as a `FLUTTER_ENGINE_SWITCH_*` environment
  // variable, so the snap and a `make install` build would both have kept the
  // slow default however carefully a developer invoked the tool.
  //
  // MOONSWING_IMPELLER=1 turns it back on, which is how the comparison
  // above is reproduced and how this decision gets revisited: Impeller's GLES
  // backend is under active development, and the machine this was measured on
  // has both an Intel iGPU and a discrete Radeon, so the fault may be in which
  // context it lands on rather than in Impeller everywhere.
  const gchar* impeller = g_getenv("MOONSWING_IMPELLER");
  gboolean enable_impeller =
      impeller != nullptr && g_strcmp0(impeller, "") != 0 &&
      g_strcmp0(impeller, "0") != 0;
  fl_dart_project_set_enable_impeller(project, enable_impeller);

  // Before the first view is realized; GtkWidget's signals exist by now, the
  // window above being one.
  guint realize_signal = g_signal_lookup("realize", GTK_TYPE_WIDGET);
  if (realize_signal != 0) {
    g_signal_add_emission_hook(realize_signal, 0, widget_realized_hook, nullptr,
                               nullptr);
  }

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
