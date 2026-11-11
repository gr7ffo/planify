#
# win64-deploy.ps1 — assemble a self-contained portable Planify zip for win64.
#
# Takes a meson install prefix (a real install tree) and combines it with the
# runtime pieces from the MSYS2 toolchain environment into a relocatable tree:
#
#     bin/       planify.exe, libplanify-0.dll + every needed runtime DLL
#     lib/       gio TLS modules, gdk-pixbuf loaders (+ loaders.cache)
#     share/     glib-2.0/schemas (compiled), icons, locale, fonts
#     etc/fonts  fontconfig configuration (system fonts are picked up too)
#
# Usage (from a MSYS2 or plain PowerShell environment):
#     ./scripts/win64-deploy.ps1 -Prefix <meson install prefix> [-MsysRoot C:\msys64] [-ToolchainDir ucrt64]
#

param (
    [string]$MsysRoot = 'C:\msys64',
    [Parameter(Mandatory = $true)][string]$Prefix,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Stage = '',
    [string]$OutFile = '',
    # MSYS2 environment the build was made with ('mingw64' or 'ucrt64').
    # CI builds against UCRT64 (MINGW64 is retired upstream); local builds
    # may still use the legacy mingw64 environment.
    [string]$ToolchainDir = 'ucrt64'
)

$ErrorActionPreference = 'Stop'

$mingwRoot = Join-Path $MsysRoot $ToolchainDir
$mingwBin = Join-Path $mingwRoot 'bin'

$objdump = $null
foreach ($od in @((Join-Path $mingwBin 'objdump.exe'), (Get-Command objdump -ErrorAction SilentlyContinue).Source)) {
    if ($od -and (Test-Path $od)) { $objdump = $od; break }
}
if (-not $objdump) { throw "objdump.exe not found in $mingwBin (install the toolchain package for the $ToolchainDir environment)." }

$exeName = if (Test-Path (Join-Path $Prefix 'bin\io.github.alainm23.planify.exe')) {
    'io.github.alainm23.planify.exe'
} elseif (Test-Path (Join-Path $Prefix 'bin\planify.exe')) {
    'planify.exe'
} else {
    throw "io.github.alainm23.planify.exe not found under $Prefix\bin — run 'meson install' first."
}

# ---- read the version for the zip name -------------------------------------

$mesonBuild = Get-Content (Join-Path $ProjectRoot 'meson.build') -Raw
if ($mesonBuild -match "version:\s*'([^']+)'") { $version = $Matches[1] } else { $version = 'dev' }

if (-not $Stage) { $Stage = Join-Path $ProjectRoot 'build\win64-stage' }
if (-not $OutFile) { $OutFile = Join-Path $ProjectRoot "build\dist\planify-$version-win64.zip" }

Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
$null = New-Item -ItemType Directory -Path (Join-Path $Stage 'bin') -Force

# ---- dependency closure -----------------------------------------------------

$systemDirs = @((Join-Path $env:SystemRoot 'System32'), $env:SystemRoot)

function Test-SystemDll ($name) {
    # api-set forwarders (api-ms-win-*) are virtual system DLLs without a
    # physical file in System32.
    if ($name -match '^(api-ms-|ext-ms-)') { return $true }
    foreach ($d in $systemDirs) { if (Test-Path (Join-Path $d $name)) { return $true } }
    return $false
}

$installed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Copy-Closure ([string[]]$startFiles) {
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($f in $startFiles) { $queue.Enqueue($f) }

    while ($queue.Count -gt 0) {
        $file = $queue.Dequeue()
        if (-not (Test-Path $file)) { continue }

        $deps = & $objdump -p $file |
            Select-String -Pattern '^\s*DLL Name:\s*(\S+)' |
            ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }

        foreach ($name in ($deps | Select-Object -Unique)) {
            $candidate = Join-Path $mingwBin $name
            if (Test-Path $candidate) {
                if ($installed.Add($name)) {
                    Copy-Item $candidate (Join-Path (Join-Path $Stage 'bin') $name)
                    $queue.Enqueue($candidate)
                }
            } elseif ((Test-Path (Join-Path (Join-Path $Stage 'bin') $name)) -or (Test-SystemDll $name)) {
                # already staged (app-owned DLLs from the prefix) or a system DLL
            } else {
                Write-Warning "DLL '$name' (needed by $(Split-Path -Leaf $file)) is not in $mingwBin and not a system DLL — the zip may be incomplete."
            }
        }
    }
}

Write-Host "== copying the application ($exeName) =="
Copy-Item (Join-Path $Prefix 'bin\*') (Join-Path $Stage 'bin')
Copy-Closure @((Get-ChildItem (Join-Path $Stage 'bin') -Filter '*.exe').FullName) |
    Out-Null
Copy-Closure @((Get-ChildItem (Join-Path $Stage 'bin') -Filter '*.dll').FullName) |
    Out-Null

# GLib helper process used by g_spawn on win64.
foreach ($helper in @('gspawn-win64-helper.exe', 'gspawn-win64-helper-console.exe')) {
    $src = Join-Path $mingwBin $helper
    if (Test-Path $src) { Copy-Item $src (Join-Path (Join-Path $Stage 'bin') $helper) }
}

# ---- gio TLS modules (libsoup needs them for CalDAV/Todoist HTTPS) ----------

Write-Host "== gio modules =="
$gioModulesSrc = Join-Path $mingwRoot 'lib\gio\modules'
if (Test-Path $gioModulesSrc) {
    $dest = Join-Path $Stage 'lib\gio\modules'
    $null = New-Item -ItemType Directory -Path $dest -Force
    Copy-Item (Join-Path $gioModulesSrc '*.dll') $dest
    Copy-Closure @((Get-ChildItem $dest -Filter '*.dll').FullName) | Out-Null
}

# ---- gdk-pixbuf loaders ------------------------------------------------------

Write-Host "== gdk-pixbuf loaders =="
$pixbufRootSrc = Join-Path $mingwRoot 'lib\gdk-pixbuf-2.0'
if (Test-Path $pixbufRootSrc) {
    $pixbufVersion = (Get-ChildItem $pixbufRootSrc -Directory | Select-Object -First 1).Name
    $loadersSrc = Join-Path $pixbufRootSrc "$pixbufVersion\loaders"
    $loadersRel = "lib\gdk-pixbuf-2.0\$pixbufVersion\loaders"
    $loadersDest = Join-Path $Stage $loadersRel
    $null = New-Item -ItemType Directory -Path $loadersDest -Force
    Copy-Item (Join-Path $loadersSrc '*.dll') $loadersDest
    Copy-Closure @((Get-ChildItem $loadersDest -Filter '*.dll').FullName) | Out-Null

    # Generate a relocatable loaders.cache: relative module paths are written
    # when the tool is given relative file paths from the stage root.
    $query = Get-ChildItem $mingwBin -Filter 'gdk-pixbuf-query-loaders.exe' | Select-Object -First 1
    if ($query) {
        $cache = Join-Path (Join-Path (Join-Path $Stage 'lib\gdk-pixbuf-2.0') $pixbufVersion) 'loaders.cache'
        $loaderFiles = Get-ChildItem $loadersDest -Filter '*.dll' | ForEach-Object {
            Join-Path $loadersRel $_.Name
        }
        Push-Location $Stage
        try {
            # no BOM (the pixbuf cache parser chokes on one)
            $content = & $query.FullName $loaderFiles
            [System.IO.File]::WriteAllLines($cache, $content, [System.Text.UTF8Encoding]::new($false))
        } finally { Pop-Location }
        # rewrite the absolute stage prefix out of the cache so the zip stays
        # relocatable (entries become relative to the zip root)
        $stagePrefix = ((Join-Path $Stage '') -replace '\\', '/').TrimEnd('/')
        $raw = [System.IO.File]::ReadAllText($cache)
        [System.IO.File]::WriteAllText($cache, $raw.Replace("$stagePrefix/", ''))
        Write-Host "   loaders.cache written (relocatable paths)"
    }
}

# ---- GSettings schemas --------------------------------------------------------

Write-Host "== schemas =="
$schemasDest = Join-Path $Stage 'share\glib-2.0\schemas'
$null = New-Item -ItemType Directory -Path $schemasDest -Force
Copy-Item (Join-Path $Prefix 'share\glib-2.0\schemas\*') $schemasDest
# glib/gsettings-desktop-schemas are queried at runtime (e.g. proxy settings)
# and must ship compiled alongside the app's own schemas
if (Test-Path (Join-Path $mingwRoot 'share\glib-2.0\schemas')) {
    Copy-Item (Join-Path $mingwRoot 'share\glib-2.0\schemas\*') $schemasDest -Force
}
& (Join-Path $mingwBin 'glib-compile-schemas.exe') $schemasDest

# ---- icons, fonts, fontconfig -------------------------------------------------

Write-Host "== icons and fonts =="
$iconsDest = Join-Path $Stage 'share\icons'
$null = New-Item -ItemType Directory -Path $iconsDest -Force
foreach ($iconsSrc in @((Join-Path $mingwRoot 'share\icons'), (Join-Path $Prefix 'share\icons'))) {
    if (Test-Path $iconsSrc) {
        Copy-Item (Join-Path $iconsSrc '*') $iconsDest -Recurse -Force
    }
}

if (Test-Path (Join-Path $mingwRoot 'share\fonts')) {
    $null = New-Item -ItemType Directory -Path (Join-Path $Stage 'share\fonts') -Force
    Copy-Item (Join-Path $mingwRoot 'share\fonts\*') (Join-Path $Stage 'share\fonts') -Recurse -Force
}
if (Test-Path (Join-Path $mingwRoot 'etc\fonts')) {
    # fontconfig's config uses WINDOWSFONTDIR aliases provided by the MSYS2
    # build, so the Windows system fonts resolve as well.
    Copy-Item (Join-Path $mingwRoot 'etc\fonts') (Join-Path $Stage 'etc\fonts') -Recurse -Force
}

# ---- locales ------------------------------------------------------------------

Write-Host "== locales =="
if (Test-Path (Join-Path $Prefix 'share\locale')) {
    $null = New-Item -ItemType Directory -Path (Join-Path $Stage 'share\locale') -Force
    Copy-Item (Join-Path $Prefix 'share\locale\*') (Join-Path $Stage 'share\locale') -Recurse -Force
}

# ---- zip ----------------------------------------------------------------------

Write-Host "== packing =="
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $OutFile) -Force
Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $OutFile -CompressionLevel Optimal

$size = '{0:N1} MB' -f ((Get-Item $OutFile).Length / 1MB)
Write-Host "Portable zip ready: $OutFile ($size)"
Write-Host "Staging tree kept at: $Stage"
