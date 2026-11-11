/*
* Copyright © 2023 Alain M. (https://github.com/alainm23/planify)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 3 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Alain M. <alainmh23@gmail.com>
*/

#if WINDOWS
[CCode (cname = "GetModuleFileNameA", cheader_filename = "windows.h")]
private static extern uint32 ExternalGetModuleFileNameA (void* h_module, [CCode (array_length = false, array_null_terminated = true)] char[] lp_filename, uint32 n_size);
#endif

/*
*   Path Utils
*
*   Resolves runtime install paths. On Unix these come from the meson prefix
*   they were compiled with; on win64 the portable build is unpacked anywhere,
*   so paths are derived from the running executable's location instead.
*/
public class PathUtils : GLib.Object {
    private static string? prefix_dir = null;
    private static string? locale_dir = null;

    /*
    *  Install prefix root: the directory containing bin/ and share/.
    */

    public static string get_prefix_dir () {
        if (prefix_dir == null) {
            prefix_dir = compute_prefix_dir ();
        }

        return prefix_dir;
    }

    /*
    *  Directory of the gettext locale catalogs (share/locale).
    */

    public static string get_locale_dir () {
        if (locale_dir == null) {
            locale_dir = GLib.Path.build_filename (get_prefix_dir (), "share", "locale");
        }

        return locale_dir;
    }

    private static string compute_prefix_dir () {
#if WINDOWS
        // MAX_PATH = 260; + 1 for the terminator.
        char[] exe_path = new char[261];
        ExternalGetModuleFileNameA (null, exe_path, 261);

        string exe_dir = GLib.Path.get_dirname (((string) exe_path).dup ());
        // <prefix>\bin\planify.exe -> <prefix>
        return GLib.Path.get_dirname (exe_dir);
#else
        return Build.INSTALL_PREFIX;
#endif
    }

#if WINDOWS
    private static bool environment_ready = false;

    /*
    *  Runtime environment for the portable win64 build. Must run before any
    *  GSettings, pango or fontconfig use (i.e. before Gtk is initialized):
    *
    *  - GSettings: no dconf backend ships with the portable build, so the
    *    in-memory backend would silently discard every preference at exit.
    *    libgio's built-in keyfile backend persists to %LOCALAPPDATA% instead.
    *  - Fontconfig has no relocation support on Windows: it looks for
    *    fonts.conf in the sysconfdir it was compiled with (e.g. the MSYS2
    *    prefix), which does not exist on user machines. A config file is
    *    generated pointing at the portable bundle plus the Windows font
    *    directories.
    *  - Pango: use the fontconfig/FreeType backend so generic families
    *    ("Sans", "emoji") and the bundled fonts (Cantarell) resolve; the
    *    default GDI backend fails generic-family lookups ("All font
    *    fallbacks failed") and never sees the bundled fonts.
    */
    public static void setup_environment () {
        if (environment_ready) {
            return;
        }
        environment_ready = true;

        GLib.Environment.set_variable ("GSETTINGS_BACKEND", "keyfile", true);
        setup_fontconfig ();
        GLib.Environment.set_variable ("PANGOCAIRO_BACKEND", "fc", true);
    }

    private static void setup_fontconfig () {
        // GLib maps the cache dir to %LOCALAPPDATA%\...\INetCache on Windows,
        // which is unsuitable; the app's own data dir is used instead.
        string conf_dir = GLib.Path.build_filename (
            GLib.Environment.get_user_data_dir (), "io.github.alainm23.planify", "fontconfig"
        );

        if (GLib.DirUtils.create_with_parents (conf_dir, 0755) != 0) {
            warning ("Could not create fontconfig config dir %s", conf_dir);
            return;
        }

        string conf_path = GLib.Path.build_filename (conf_dir, "fonts.conf");
        string prefix = get_prefix_dir ().replace ("\\", "/");
        string cache_dir = GLib.Path.build_filename (conf_dir, "cache");

        string content = """<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
	<!-- Fonts shipped inside the portable bundle (Cantarell, Source Code Pro) -->
	<dir>%s/share/fonts</dir>
	<!-- System and per-user fonts installed in Windows -->
	<dir>WINDOWSFONTDIR</dir>
	<dir>WINDOWSUSERFONTDIR</dir>
	<dir prefix="xdg">fonts</dir>
	<!-- Default rendering rules shipped with fontconfig -->
	<include ignore_missing="yes">%s/etc/fonts/conf.d</include>
	<!-- Writable font cache -->
	<cachedir>%s/cache</cachedir>
</fontconfig>
""".printf (prefix, prefix, cache_dir);

        try {
            GLib.FileUtils.set_contents (conf_path, content);
        } catch (GLib.FileError e) {
            warning ("Could not write %s: %s", conf_path, e.message);
            return;
        }

        GLib.Environment.set_variable ("FONTCONFIG_FILE", conf_path, true);
    }
#endif
}
