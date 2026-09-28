# Compiler bootstrap and its relocation test. No application sources or caches.
param(
    [Parameter(Mandatory = $true)] [ValidateSet('package', 'verify')] [string] $Mode,
    [string] $Archive
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path $PSScriptRoot -Parent
$version = $null
$checksum = $null
$url = $null
foreach ($line in Get-Content (Join-Path $repo 'zig/TOOLCHAIN')) {
    $fields = $line.Trim() -split '\s+'
    if ($fields[0] -eq 'version') { $version = $fields[1] }
    if ($fields[0] -eq 'x86_64-windows') { $checksum = $fields[1]; $url = $fields[2] }
}
if (-not $version -or $checksum -cnotmatch '^[0-9a-f]{64}$' -or -not $url.StartsWith('https://')) {
    throw 'Invalid Windows toolchain pin'
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('zig-seed-' + [Guid]::NewGuid().ToString('N'))
[void] [IO.Directory]::CreateDirectory($work)
$tar = Join-Path $env:SystemRoot 'System32/tar.exe'
$rootName = "zig-x86_64-windows-$version"
$install = Join-Path $work $rootName
$savedCache = $env:ZIG_GLOBAL_CACHE_DIR

function Invoke-Warmup {
    $zig = Join-Path $install 'zig.exe'
    $observed = & $zig version
    if ($LASTEXITCODE -ne 0 -or $observed -cne $version) { throw 'Wrong compiler version' }
    $local = Join-Path $work 'local-cache'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    & $zig translate-c (Join-Path $PSScriptRoot 'warmup.h') -target x86_64-windows-msvc --cache-dir $local > $null
    if ($LASTEXITCODE -ne 0) { throw 'Header translation failed' }
    Write-Output "MEASURE mode=$Mode translator_ms=$($clock.ElapsedMilliseconds)"
    $clock.Restart()
    $output = Join-Path $work 'warmup.exe'
    & $zig build-exe (Join-Path $PSScriptRoot 'warmup.zig') -target x86_64-windows-msvc --win32-manifest (Join-Path $PSScriptRoot 'warmup.manifest') --cache-dir $local "-femit-bin=$output"
    if ($LASTEXITCODE -ne 0) { throw 'Manifest build failed' }
    Write-Output "MEASURE mode=$Mode manifest_build_ms=$($clock.ElapsedMilliseconds)"
    & $output
    if ($LASTEXITCODE -ne 0) { throw 'Warmup executable failed' }
}

function Get-Helpers {
    $helpers = @(Get-ChildItem (Join-Path $env:ZIG_GLOBAL_CACHE_DIR 'o') -Recurse -File |
        Where-Object { $_.Name -eq 'translate-c.exe' -or $_.Name -eq 'resinator.exe' } |
        Sort-Object FullName)
    if ($helpers.Count -ne 2) { throw "Expected exactly two compiler helpers; found $($helpers.Count)" }
    return @($helpers | ForEach-Object {
        # Both changed paths (new cache keys) and rewrites in place fail verification.
        '{0}|{1}|{2}' -f $_.FullName, $_.LastWriteTimeUtc.Ticks, (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    })
}

try {
    if ($Mode -eq 'package') {
        $download = Join-Path $work 'upstream.zip'
        & curl.exe --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --retry 2 --output $download $url
        if ($LASTEXITCODE -ne 0) { throw 'Download failed' }
        if ((Get-FileHash $download -Algorithm SHA256).Hash.ToLowerInvariant() -cne $checksum) { throw 'Upstream checksum mismatch' }
        & $tar -xf $download -C $work
        if ($LASTEXITCODE -ne 0) { throw 'Upstream extraction failed' }
        $env:ZIG_GLOBAL_CACHE_DIR = Join-Path $install 'global-cache'
        if (Test-Path $env:ZIG_GLOBAL_CACHE_DIR) { throw 'Seed cache must start empty' }
        Invoke-Warmup
        $null = Get-Helpers
        $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
        $metadata = [ordered]@{
            zig_version = $version
            upstream_sha256 = $checksum
            recipe_commit = $env:GITHUB_SHA
            runner_class = 'avrea-windows-2025-4-vcpu'
            processor = $cpu
            inputs = @('warmup.h', 'warmup.zig', 'warmup.manifest')
        } | ConvertTo-Json
        [IO.File]::WriteAllText((Join-Path $install 'CACHE-SEED.json'), $metadata + "`n")
        $outputDir = Join-Path $repo 'o'
        [void] [IO.Directory]::CreateDirectory($outputDir)
        $name = "$rootName-ci.zip"
        $Archive = Join-Path $outputDir $name
        & $tar -a -cf $Archive -C $work $rootName
        if ($LASTEXITCODE -ne 0) { throw 'Packaging failed' }
        $sha = (Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText("$Archive.sha256", "$sha  $name`n")
        $seedFiles = Get-ChildItem $env:ZIG_GLOBAL_CACHE_DIR -Recurse -File
        Write-Output "MEASURE archive_bytes=$((Get-Item $Archive).Length) seed_files=$($seedFiles.Count) seed_bytes=$(($seedFiles | Measure-Object -Property Length -Sum).Sum)"
        Write-Output $metadata
        if ($env:GITHUB_OUTPUT) {
            "name=$name`nsha256=$sha`nversion=$version" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
        }
    } else {
        if (-not $Archive) { throw 'Verification needs -Archive' }
        $Archive = [IO.Path]::GetFullPath($Archive)
        $expected = (Get-Content "$Archive.sha256").Split(' ')[0]
        if ((Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) { throw 'Bundle checksum mismatch' }
        & $tar -xf $Archive -C $work
        if ($LASTEXITCODE -ne 0) { throw 'Bundle extraction failed' }
        $env:ZIG_GLOBAL_CACHE_DIR = Join-Path $install 'global-cache'
        $before = Get-Helpers
        Invoke-Warmup
        $after = Get-Helpers
        if (@(Compare-Object $before $after).Count -ne 0) { throw 'Compiler helpers were rebuilt instead of reused' }
        Write-Output 'PASS: both compiler helpers reused after relocation on a fresh runner'
    }
} finally {
    $env:ZIG_GLOBAL_CACHE_DIR = $savedCache
    # Only this invocation's unique scratch directory is removed.
    Remove-Item -LiteralPath $work -Recurse -Force
}
