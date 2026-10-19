param([string]$CacheRoot = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$CacheRoot) { $CacheRoot = Join-Path $repo '.windows' }
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
$packages = @(
    @('TheBrowserCompany.SwiftWinRT', '0.6.0', '7262333B4A1DCF5D6AD0F4ED14736EAA860BAB99DAF8ED9E35DDCE63B21B679F'),
    @('Microsoft.WindowsAppSDK', '1.7.250909003', 'BAE24BDC5E3B43B484C52C1F092E14119D0F24E95C0529E1C3187AF87F0B72FD'),
    @('Microsoft.Windows.SDK.Contracts', '10.0.22621.3233', 'B9B930DBAB7C6653BCC75703F0EA018E12AF0032B2CB43175ED4BF4A4BA76004'),
    @('Microsoft.Web.WebView2', '1.0.2903.40', 'EF128016DD1E51C59178C827ED5B8AA3322C57AFA8675D930F8109505542AD74')
)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$folders = @{}
foreach ($package in $packages) {
    $id, $version, $sha = $package
    $key = $id.ToLowerInvariant() + '.' + $version
    $archive = Join-Path $CacheRoot ($key + '.nupkg')
    if (!(Test-Path -LiteralPath $archive)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://api.nuget.org/v3-flatcontainer/$($id.ToLowerInvariant())/$version/$key.nupkg" -OutFile $archive
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $sha) { throw "Archive invalide : $key (SHA-256)." }
    $folder = Join-Path $CacheRoot $key
    if (!(Test-Path -LiteralPath $folder)) { [IO.Compression.ZipFile]::ExtractToDirectory($archive, $folder) }
    $folders[$id] = $folder
}
$output = Join-Path $CacheRoot 'Projections'
$config = Get-Content -LiteralPath (Join-Path $repo 'windows/projections.json') -Raw | ConvertFrom-Json
$sdk = $folders['Microsoft.WindowsAppSDK']
$metadata = @()
foreach ($directory in @('lib/uap10.0', 'lib/uap10.0.18362')) {
    $metadata += Get-ChildItem -LiteralPath (Join-Path $sdk $directory) -Filter '*.winmd'
}
$metadata += Get-ChildItem -LiteralPath (Join-Path $folders['Microsoft.Windows.SDK.Contracts'] 'ref') -Recurse -Filter '*.winmd'
$metadata += Get-Item -LiteralPath (Join-Path $folders['Microsoft.Web.WebView2'] 'lib/Microsoft.Web.WebView2.Core.winmd')
$lines = @('-output "' + $output + '"', '-support WindowsFoundation')
$lines += $metadata | ForEach-Object { '-input "' + $_.FullName + '"' }
$lines += $config.include | ForEach-Object { '-include ' + $_ }
$lines += $config.exclude | ForEach-Object { '-exclude ' + $_ }
$response = Join-Path $CacheRoot 'projections.rsp'
[IO.File]::WriteAllLines($response, $lines, [Text.UTF8Encoding]::new($false))
& (Join-Path $folders['TheBrowserCompany.SwiftWinRT'] 'bin/swiftwinrt.exe') "@$response"
if ($LASTEXITCODE -ne 0) { throw 'La génération Swift-WinRT a échoué.' }
Copy-Item -LiteralPath (Join-Path $repo 'windows/Projections.Package.swift') -Destination (Join-Path $output 'Package.swift')
foreach ($module in @('WinUI', 'WinAppSDK')) {
    $destination = Join-Path $output "Sources/$module/Support"
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -Path (Join-Path $repo "windows/Support/$module/*.swift") -Destination $destination
}
$headers = Join-Path $output 'Sources/CWinAppSDK/include'
New-Item -ItemType Directory -Force -Path $headers | Out-Null
foreach ($name in @('MddBootstrap.h', 'WindowsAppSDK-VersionInfo.h')) {
    $header = Get-ChildItem -LiteralPath $sdk -Recurse -Filter $name | Select-Object -First 1
    if (!$header) { throw "En-tête absent : $name" }
    Copy-Item -LiteralPath $header.FullName -Destination (Join-Path $headers $name)
}
[IO.File]::WriteAllText((Join-Path $headers 'bootstrap.h'), @'
#include <windows.h>
#include <roapi.h>
#include "MddBootstrap.h"
#include "WindowsAppSDK-VersionInfo.h"
static PCWSTR WINDOWSAPPSDK_RELEASE_VERSION_TAG_SWIFT = WINDOWSAPPSDK_RELEASE_VERSION_TAG_W;
'@)
[IO.File]::WriteAllText((Join-Path $headers 'module.modulemap'), 'module CWinAppSDK { header "bootstrap.h" export * }')
[IO.File]::WriteAllText((Join-Path $output 'Sources/CWinAppSDK/bootstrap.c'), '#include "include/bootstrap.h"')
Write-Host "Projections Swift-WinRT prêtes : $output"
