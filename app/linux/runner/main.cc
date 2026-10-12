#include "my_application.h"

int main(int argc, char** argv) {
  // Prefer X11/XWayland: some GTK/GNOME combinations abort on Wayland when
  // reading removed font keys from the legacy xsettings schema. This choice
  // is local to this process, with native Wayland available as a fallback.
  // Configure GDK before GtkApplication initializes its display connection.
  gdk_set_allowed_backends("x11,wayland,*");
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
