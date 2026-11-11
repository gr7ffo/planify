project(
  'io.github.alainm23.planify',
  'vala', 'c',
  version: '4.20.0'
)

###########
# Profile #
###########

host_windows = host_machine.system() == 'windows'
if host_windows
  # Win64 portable build: helper binaries (quick-add, cli) and GNOME-only
  # integration (search-provider) are dropped, and notifications are a silent
  # no-op (GLib has no Windows notification backend).
  add_project_arguments(['--define=WINDOWS'], language: 'vala')
endif

profile = get_option('profile')
if profile == 'development'
  find_program('git')
  rev_txt = run_command('git','rev-parse','--short','HEAD').stdout().strip()
  rev = '-@0@'.format(rev_txt)
  application_id = 'io.github.alainm23.planify.Devel'
  application_path = '/io/github/alainm23/planify/Devel'
  add_project_arguments(['--define=DEVELOPMENT'], language: 'vala')
else
  rev = ''
  application_id = 'io.github.alainm23.planify'
  application_path = '/io/github/alainm23/planify'
endif

################
# Dependencies #
################


cc = meson.get_compiler('c')

gnome = import('gnome')
i18n = import('i18n')
pkgconfig = import('pkgconfig')

add_global_arguments('-DGETTEXT_PACKAGE="@0@"'.format (application_id), language:'c')
add_project_arguments('-DLIBICAL_GLIB_UNSTABLE_API=1', language: 'c')

gio_dep = dependency('gio-2.0')
glib_dep = dependency('glib-2.0')
gee_dep = dependency('gee-0.8')
gtk_dep = dependency('gtk4')
pangocairo_dep = dependency('pangocairo')
libsoup_dep = dependency('libsoup-3.0')
sqlite3_dep = dependency('sqlite3')
libadwaita_dep = dependency('libadwaita-1', version: '>= 1.7.0')
json_dep = dependency('json-glib-1.0')
libical_dep = dependency('libical-glib')
if host_windows
  # Unused dependency of the original Linux build (no code references the
  # secret service, and Windows has no keyring) — always skip on win64.
  libsecret_dep = dependency('libsecret-1', required: false)
else
  libsecret_dep = dependency('libsecret-1', required: get_option('libsecret'))
endif
libspelling = dependency('libspelling-1', required: get_option('spelling'))
gtksourceview_dep = dependency('gtksourceview-5')
m_dep = meson.get_compiler('c').find_library('m', required : false)
icu_uc_dep = dependency('icu-uc')

# is libical version 4 or higher?
is_libical4 = libical_dep.version().version_compare('>= 4.0.0')
if is_libical4
  add_project_arguments('-D', 'IS_LIBICAL4', language: 'vala')
endif

# Datetime.vala reads the locale's short date format via Posix.nl_langinfo, so
# the posix vapi must be linked for every build variant (it is otherwise only
# pulled in transitively by the evolution-only CalendarEvents.vala).
add_project_arguments(['--pkg=posix'], language: 'vala')

# Project-local vapi overrides: icu-uc has an in-tree fallback used on every
# platform. libical-glib is a win64-only fallback (the MSYS2 libical package
# ships no vapi at all) and lives in a separate directory so it cannot shadow
# the newer system vapi on Unix builds (libical 4.x API differs).
add_project_arguments(['--vapidir=' + meson.project_source_root() / 'vapi'], language: 'vala')
if host_windows
  add_project_arguments(['--vapidir=' + meson.project_source_root() / 'vapi' / 'win64'], language: 'vala')
endif

if libspelling.found ()
  add_project_arguments(['--define=WITH_LIBSPELLING'], language: 'vala')
endif

if get_option('portal')
    libportal_dep = dependency('libportal', required: true)
    libportal_gtk4_dep = dependency('libportal-gtk4', required: true)
    add_project_arguments('-D', 'WITH_LIBPORTAL', language: 'vala')
    if not libportal_dep.found()
        error('libportal requested but not found')
    endif
    if not libportal_gtk4_dep.found()
        error('libportal-gtk4 requested but not found')
    endif
endif

if get_option('evolution')
    libecal_dep = dependency('libecal-2.0', version: '>= 3.45.1')
    libedataserver_dep = dependency('libedataserver-1.2', version: '>= 3.45.1')
    add_project_arguments('-D', 'WITH_EVOLUTION', language: 'vala')
    if not libecal_dep.found()
        error('libecal-2.0 requested but not found')
    endif
    if not libedataserver_dep.found()
        error('libedataserver-1.2 requested but not found')
    endif
endif

if get_option('goa')
    goa_dep = dependency('goa-1.0', required: true)
    add_project_arguments('-D', 'WITH_GOA', language: 'vala')
    add_project_arguments('-DGOA_API_IS_SUBJECT_TO_CHANGE', language: 'c')
    if not goa_dep.found()
        error('goa-1.0 requested but not found')
    endif
endif

############
# Resources #
############

asresources = gnome.compile_resources (
    'as-resources', 'data/io.github.alainm23.planify.gresource.xml',
    source_dir: 'data',
    c_name: 'as'
)

############
# Config #
############
prefix = get_option('prefix')
bindir = prefix / get_option('bindir')
datadir = prefix / get_option('datadir')
localedir = prefix / get_option ('localedir')
libexecdir = prefix / get_option('libexecdir')

# Only used for a translation-coverage statistic in the About dialog; skip
# rather than require the Unix grep tool for the win64 build.
total_strings = 0
if not host_windows
  grep = find_program('grep')
  total_strings_res = run_command(grep, '-c', 'msgid', meson.project_source_root() + '/po/io.github.alainm23.planify.pot', check : true)
  total_strings = total_strings_res.stdout().strip().to_int() - 1
endif

# _NL_TIME_FIRST_WEEKDAY is a glibc-ism
nl_time_first_weekday_src = '''
  #include <langinfo.h>
  int main() {
    nl_langinfo(_NL_TIME_FIRST_WEEKDAY);
  };
'''
if cc.compiles(nl_time_first_weekday_src)
    add_project_arguments('-D', 'HAVE__NL_TIME_FIRST_WEEKDAY', language: 'vala')
endif

conf_data = configuration_data()
conf_data.set('TOTAL_STRINGS', total_strings)
conf_data.set_quoted('APPLICATION_ID', application_id)
conf_data.set_quoted('GETTEXT_PACKAGE', application_id)
conf_data.set_quoted('GNOMELOCALEDIR', localedir)
conf_data.set_quoted('VERSION', meson.project_version())
conf_data.set_quoted('LOCALEDIR', localedir)
conf_data.set_quoted('PACKAGE_VERSION', meson.project_version())
conf_data.set_quoted('PREFIX', prefix)
conf_data.set_quoted('DATADIR', datadir)
conf_data.set_quoted('PROFILE', profile)

config_file = configure_file(
    configuration : conf_data,
    input : 'config.vala.in',
    output : 'config.vala'
)

subdir('core')
subdir('src')
if not host_windows
  subdir('quick-add')
  subdir('cli')
  subdir('search-provider')
endif
subdir('data')
subdir('po')

# Testing (needs the Unix-style scratch data dir; skipped for win64)
if not host_windows
  subdir('test')
endif

summary({
  'Tracing': get_option('tracing'),
  'Profile': get_option('profile'),
}, section: 'Development')

if host_windows
  gnome.post_install(
    glib_compile_schemas: true,
  )
else
  gnome.post_install(
    glib_compile_schemas: true,
    gtk_update_icon_cache: true,
    update_desktop_database: true,
  )
endif
