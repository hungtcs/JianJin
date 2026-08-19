#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;

  // 与 Dart 侧通信的方法通道。菜单项被点击时把动作名发过去执行，
  // Dart 侧的可用状态变化时回推过来更新菜单项的启用/禁用。
  FlMethodChannel* menu_channel;
  GtkWindow* window;

  // 标题栏里是否真的挂上了原生菜单。传统标题栏（非 GNOME 的 X11 会话）
  // 放不下 popover 按钮，此时要让 Dart 侧退回窗口内菜单，
  // 否则那些桌面上会完全没有菜单入口。
  gboolean has_native_menu;

  // 「关于」对话框要显示的信息，由 Dart 侧推送（版本号来自 bundle，
  // ffmpeg 版本是启动时探测的结果）
  gchar* about_version;
  gchar* about_ffmpeg;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// 菜单动作。与 Dart 侧 AppMenuActions 的字段一一对应，
// 名字即通道上传递的标识。「关于」不在此列——它由 GtkAboutDialog 就地处理。
static const char* kMenuActions[] = {"open", "close",    "export",
                                     "undo", "clearAll", nullptr};

// 菜单项被激活：把动作名发给 Dart 执行。
static void menu_action_cb(GSimpleAction* action, GVariant* parameter,
                           gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->menu_channel == nullptr) {
    return;
  }
  g_autoptr(FlValue) args =
      fl_value_new_string(g_action_get_name(G_ACTION(action)));
  fl_method_channel_invoke_method(self->menu_channel, "activate", args, nullptr,
                                  nullptr, nullptr);
}

// 关于对话框用 GTK 原生实现，而不是在 Flutter 里画一层浮层——
// 它是独立窗口，可移动、有自己的关闭按钮，符合桌面预期。
static void about_action_cb(GSimpleAction* action, GVariant* parameter,
                            gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);

  GtkAboutDialog* dialog = GTK_ABOUT_DIALOG(gtk_about_dialog_new());
  gtk_window_set_transient_for(GTK_WINDOW(dialog), self->window);
  gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);

  gtk_about_dialog_set_program_name(dialog, "剪金 JianJin");
  if (self->about_version != nullptr) {
    gtk_about_dialog_set_version(dialog, self->about_version);
  }
  gtk_about_dialog_set_comments(
      dialog, "快速挑选视频中有用的片段并无损导出");
  gtk_about_dialog_set_website(dialog, "https://github.com/hungtcs/JianJin");
  gtk_about_dialog_set_website_label(dialog, "GitHub");
  gtk_about_dialog_set_license_type(dialog, GTK_LICENSE_MIT_X11);

  // ffmpeg 找不到是本应用最常见的故障，放在这里方便排查
  if (self->about_ffmpeg != nullptr) {
    const gchar* authors[] = {self->about_ffmpeg, nullptr};
    gtk_about_dialog_set_authors(dialog, authors);
  }

  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* icon_path =
        g_build_filename(exe_dir, "data", "icons", "app_icon.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      g_autoptr(GError) error = nullptr;
      GdkPixbuf* logo = gdk_pixbuf_new_from_file_at_size(icon_path, 96, 96,
                                                         &error);
      if (logo != nullptr) {
        gtk_about_dialog_set_logo(dialog, logo);
        g_object_unref(logo);
      }
    }
  }

  g_signal_connect(dialog, "response", G_CALLBACK(gtk_widget_destroy), nullptr);
  gtk_widget_show_all(GTK_WIDGET(dialog));
}

// Dart 侧推送过来的状态：菜单项可用性、关于对话框的信息。
static void menu_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (g_strcmp0(method, "setEnabled") == 0 && args != nullptr &&
      fl_value_get_type(args) == FL_VALUE_TYPE_MAP &&
      self->window != nullptr) {
    for (int i = 0; kMenuActions[i] != nullptr; i++) {
      FlValue* value = fl_value_lookup_string(args, kMenuActions[i]);
      if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
        continue;
      }
      GAction* action =
          g_action_map_lookup_action(G_ACTION_MAP(self->window),
                                     kMenuActions[i]);
      if (action != nullptr) {
        g_simple_action_set_enabled(G_SIMPLE_ACTION(action),
                                    fl_value_get_bool(value));
      }
    }
  } else if (g_strcmp0(method, "setAbout") == 0 && args != nullptr &&
             fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* version = fl_value_lookup_string(args, "version");
    if (version != nullptr &&
        fl_value_get_type(version) == FL_VALUE_TYPE_STRING) {
      g_free(self->about_version);
      self->about_version = g_strdup(fl_value_get_string(version));
    }
    FlValue* ffmpeg = fl_value_lookup_string(args, "ffmpeg");
    if (ffmpeg != nullptr &&
        fl_value_get_type(ffmpeg) == FL_VALUE_TYPE_STRING) {
      g_free(self->about_ffmpeg);
      self->about_ffmpeg = g_strdup(fl_value_get_string(ffmpeg));
    }
  }

  g_autoptr(FlValue) result = fl_value_new_null();
  fl_method_call_respond_success(method_call, result, nullptr);
}

// 构建「主菜单」：标题栏左侧的汉堡按钮 + popover。
//
// 快捷键只写进标签文本，**不注册为 GTK 加速键**：注册后按键会被 GTK 抢先
// 消费，Flutter 侧的同名处理就收不到，容易出现按一次执行两遍或完全失效。
// 键盘输入统一由 Flutter 处理，菜单只负责展示与鼠标操作。
static GtkWidget* build_primary_menu_button(MyApplication* self) {
  g_autoptr(GMenu) menu = g_menu_new();

  // GNOME 的主菜单惯例是短的：只放界面上没有其它入口、或属于应用级的操作。
  // 播放控制与打点都已有屏幕按钮并标注了单键快捷键，放进来只是噪音。
  g_autoptr(GMenu) file_section = g_menu_new();
  g_menu_append(file_section, "打开…   Ctrl+O", "win.open");
  g_menu_append(file_section, "关闭文件   Ctrl+W", "win.close");
  g_menu_append_section(menu, nullptr, G_MENU_MODEL(file_section));

  g_autoptr(GMenu) export_section = g_menu_new();
  g_menu_append(export_section, "导出片段…   Ctrl+E", "win.export");
  g_menu_append_section(menu, nullptr, G_MENU_MODEL(export_section));

  g_autoptr(GMenu) edit_section = g_menu_new();
  g_menu_append(edit_section, "撤销   Ctrl+Z", "win.undo");
  g_menu_append(edit_section, "清空全部片段", "win.clearAll");
  g_menu_append_section(menu, nullptr, G_MENU_MODEL(edit_section));

  g_autoptr(GMenu) app_section = g_menu_new();
  g_menu_append(app_section, "关于剪金", "win.about");
  g_menu_append_section(menu, nullptr, G_MENU_MODEL(app_section));

  GtkWidget* button = gtk_menu_button_new();
  gtk_menu_button_set_direction(GTK_MENU_BUTTON(button), GTK_ARROW_NONE);
  // 去掉按钮边框，与 GNOME 各应用标题栏上的图标按钮保持一致；
  // 有框的按钮在标题栏里会显得突兀
  gtk_style_context_add_class(gtk_widget_get_style_context(button), "flat");
  gtk_menu_button_set_use_popover(GTK_MENU_BUTTON(button), TRUE);
  gtk_menu_button_set_menu_model(GTK_MENU_BUTTON(button), G_MENU_MODEL(menu));
  gtk_widget_set_tooltip_text(button, "主菜单");

  GtkWidget* icon =
      gtk_image_new_from_icon_name("open-menu-symbolic", GTK_ICON_SIZE_BUTTON);
  gtk_container_add(GTK_CONTAINER(button), icon);
  gtk_widget_show_all(button);
  return button;
}

// 把动作注册到窗口上（GtkApplicationWindow 本身就是 GActionMap）。
static void install_menu_actions(MyApplication* self, GtkWindow* window) {
  for (int i = 0; kMenuActions[i] != nullptr; i++) {
    GSimpleAction* action = g_simple_action_new(kMenuActions[i], nullptr);
    // 默认全部禁用：Dart 侧就绪后会立刻推送真实状态。
    // 反过来（默认可用）会在启动瞬间露出一批点了没反应的菜单项。
    g_simple_action_set_enabled(action, FALSE);
    g_signal_connect(action, "activate", G_CALLBACK(menu_action_cb), self);
    g_action_map_add_action(G_ACTION_MAP(window), G_ACTION(action));
    g_object_unref(action);
  }

  GSimpleAction* about = g_simple_action_new("about", nullptr);
  g_signal_connect(about, "activate", G_CALLBACK(about_action_cb), self);
  g_action_map_add_action(G_ACTION_MAP(window), G_ACTION(about));
  g_object_unref(about);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
// 从可执行文件旁边的 data/icons/ 载入窗口图标。
// 不用 gtk_window_set_default_icon_name：那要求图标已装进系统 hicolor 主题，
// 便携 bundle（直接解压就跑）里找不到。
static void set_window_icon(GtkWindow* window) {
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path == nullptr) {
    return;
  }
  g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
  g_autofree gchar* icon_path =
      g_build_filename(exe_dir, "data", "icons", "app_icon.png", nullptr);
  if (!g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
    return;
  }
  g_autoptr(GError) error = nullptr;
  if (!gtk_window_set_icon_from_file(window, icon_path, &error)) {
    g_warning("载入窗口图标失败: %s", error->message);
  }
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // 应用界面是固定深色的。GTK 的标题栏、窗口边框与阴影由系统主题绘制，
  // 若跟随系统的浅色偏好，就会出现「浅色边框裹着深色内容」的撕裂感。
  // 这里请求深色主题变体，让窗口装饰与内容一致。
  // 注意：必须在创建窗口之前设置，之后再改不会影响已构造的装饰。
  g_object_set(gtk_settings_get_default(), "gtk-application-prefer-dark-theme",
               TRUE, nullptr);

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  install_menu_actions(self, window);

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
    gtk_header_bar_set_title(header_bar, "剪金");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    // 汉堡按钮放标题栏左端
    gtk_header_bar_pack_start(header_bar, build_primary_menu_button(self));
    self->has_native_menu = TRUE;
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    // 传统标题栏放不下 popover 按钮，退而在窗口顶部加一条菜单栏，
    // 保证非 GNOME 桌面也有菜单入口
    gtk_window_set_title(window, "剪金");
  }

  gtk_window_set_default_size(window, 1280, 720);
  set_window_icon(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

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

  // 通道必须在 FlView 之后建立：binary messenger 由引擎提供。
  // 菜单动作在此之前不会被触发，所以不存在竞态。
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->menu_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "jianjin/menu", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->menu_channel,
                                            menu_method_call_cb, self, nullptr);

  // 告知 Dart 侧原生菜单是否可用，决定要不要显示窗口内的汉堡按钮
  g_autoptr(FlValue) has_menu = fl_value_new_bool(self->has_native_menu);
  fl_method_channel_invoke_method(self->menu_channel, "nativeMenu", has_menu,
                                  nullptr, nullptr, nullptr);

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
  g_clear_object(&self->menu_channel);
  g_clear_pointer(&self->about_version, g_free);
  g_clear_pointer(&self->about_ffmpeg, g_free);
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
