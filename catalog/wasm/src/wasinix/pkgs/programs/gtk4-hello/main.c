/*
 * gtk4-hello: GTK4 Wayland "Hello, Wayland World!" for WASIX + Wawona Relay.
 * Links libraries.gtk4 (toolkit). Package name is gtk4-hello, not "gtk4".
 *
 * GSK_RENDERER=cairo. Set GTK4_HELLO_SMOKE=1 to quit shortly after map
 * (CI / Relay one-frame path). Otherwise the window stays open.
 */
#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static gboolean
quit_soon(gpointer data)
{
  GtkApplication *app = GTK_APPLICATION (data);
  fprintf (stderr, "gtk4-hello: PASS mapped; quitting (smoke)\n");
  g_application_quit (G_APPLICATION (app));
  return G_SOURCE_REMOVE;
}

static void
on_map(GtkWidget *widget, gpointer data)
{
  const char *smoke;

  (void)widget;
  smoke = getenv ("GTK4_HELLO_SMOKE");
  if (smoke != NULL && smoke[0] != '\0' && strcmp (smoke, "0") != 0)
    g_timeout_add (250, quit_soon, data);
}

static void
activate(GtkApplication *app, gpointer user_data)
{
  GtkWidget *win;
  GtkWidget *box;
  GtkWidget *title;
  GtkWidget *subtitle;

  (void)user_data;

  win = gtk_application_window_new (app);
  gtk_window_set_title (GTK_WINDOW (win), "Hello, Wayland World!");
  gtk_window_set_default_size (GTK_WINDOW (win), 480, 280);
  g_signal_connect (win, "map", G_CALLBACK (on_map), app);

  box = gtk_box_new (GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_set_valign (box, GTK_ALIGN_CENTER);
  gtk_widget_set_halign (box, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_top (box, 24);
  gtk_widget_set_margin_bottom (box, 24);
  gtk_widget_set_margin_start (box, 24);
  gtk_widget_set_margin_end (box, 24);

  title = gtk_label_new (NULL);
  gtk_label_set_markup (
      GTK_LABEL (title),
      "<span size='xx-large' weight='bold'>Hello, Wayland World!</span>");
  gtk_label_set_wrap (GTK_LABEL (title), TRUE);
  gtk_label_set_justify (GTK_LABEL (title), GTK_JUSTIFY_CENTER);

  subtitle = gtk_label_new (
      "GTK4 on WASIX via Wawona Relay (wl_shm + xdg_wm_base)");
  gtk_label_set_wrap (GTK_LABEL (subtitle), TRUE);
  gtk_label_set_justify (GTK_LABEL (subtitle), GTK_JUSTIFY_CENTER);
  gtk_widget_add_css_class (subtitle, "dim-label");

  gtk_box_append (GTK_BOX (box), title);
  gtk_box_append (GTK_BOX (box), subtitle);
  gtk_window_set_child (GTK_WINDOW (win), box);
  gtk_window_present (GTK_WINDOW (win));
  fprintf (stderr, "gtk4-hello: Hello, Wayland World! presented\n");
}

int
main(int argc, char **argv)
{
  GtkApplication *app;
  int status;

  setenv ("GSK_RENDERER", "cairo", 0);

  app = gtk_application_new ("io.wawona.gtk4-hello", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect (app, "activate", G_CALLBACK (activate), NULL);
  status = g_application_run (G_APPLICATION (app), argc, argv);
  g_object_unref (app);
  return status;
}
