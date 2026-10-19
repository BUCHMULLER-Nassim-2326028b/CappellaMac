param([ValidateSet('debug','release')][string]$Configuration = 'release', [switch]$SkipPrepare)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Push-Location $repo
try {
    if (!$SkipPrepare) { & "$PSScriptRoot/prepare-windows.ps1" }
    if (!(Test-Path '.windows/Projections/Package.swift')) { throw 'Exécuter scripts/prepare-windows.ps1 avant de compiler.' }
    # Windows PowerShell 5.1 turns redirected native stderr (including compiler
    # warnings) into error records. Judge the compiler by its exit code.
    $ErrorActionPreference = 'Continue'
    try {
        & swift build -c $Configuration --product CappellaWindows -j 4 2>&1 | ForEach-Object { Write-Host $_.ToString() }
        $compileExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = 'Stop' }
    if ($compileExitCode -ne 0) { throw "Compilation Windows échouée ($compileExitCode)." }
    $bin = (& swift build -c $Configuration --show-bin-path | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Répertoire Swift introuvable.' }
    $app = Join-Path $repo 'dist/Cappella-Windows-x64'
    New-Item -ItemType Directory -Force -Path "$app/Resources", "$app/Licenses" | Out-Null
    Copy-Item -LiteralPath (Join-Path $bin 'CappellaWindows.exe') -Destination "$app/Cappella.exe"
    Copy-Item -Path "$repo/packaging/Resources/*" -Destination "$app/Resources"
    Copy-Item -LiteralPath "$repo/.windows/microsoft.windowsappsdk.1.7.250909003/runtimes/win-x64/native/Microsoft.WindowsAppRuntime.Bootstrap.dll" -Destination $app
    # Swift DLLs must travel with the app; do not rely on the developer's PATH.
    $swiftExe = (Get-Command swift).Source
    $swiftRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path $swiftExe -Parent) '../../../..'))
    $runtime = Get-ChildItem -LiteralPath (Join-Path $swiftRoot 'Runtimes') -Recurse -Filter 'swiftCore.dll' | Sort-Object FullName -Descending | Select-Object -First 1
    if (!$runtime) { throw "Runtime Swift introuvable sous $swiftRoot/Runtimes." }
    Copy-Item -Path (Join-Path $runtime.DirectoryName '*.dll') -Destination $app
    Copy-Item -Path "$repo/windows/*LICENSE*", "$repo/windows/THIRD-PARTY-NOTICES.md" -Destination "$app/Licenses"
    foreach ($package in @('microsoft.windowsappsdk.1.7.250909003','microsoft.windows.sdk.contracts.10.0.22621.3233','microsoft.web.webview2.1.0.2903.40')) {
        Get-ChildItem -LiteralPath "$repo/.windows/$package" -File | Where-Object Name -Match 'license|notice' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination "$app/Licenses/$package-$($_.Name)" }
    }
    & "$PSScriptRoot/build-windows-icons.ps1" -OutputDirectory "$app/Resources"
    & "$PSScriptRoot/embed-windows-resources.ps1" -Executable "$app/Cappella.exe" -Icon "$app/Resources/AppIcon.ico"
    Copy-Item -LiteralPath "$repo/windows/Installer-runtime.ps1" -Destination $app
    Copy-Item -LiteralPath "$repo/docs/WINDOWS.md" -Destination "$app/LIRE-MOI.md"
    Compress-Archive -LiteralPath $app -DestinationPath "$repo/dist/Cappella-Windows-x64.zip" -Force
    Write-Host "Application : $app/Cappella.exe"
    Write-Host "Archive : $repo/dist/Cappella-Windows-x64.zip"
} finally { Pop-Location }
