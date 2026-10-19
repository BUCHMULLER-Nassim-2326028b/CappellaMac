param([ValidateSet('debug','release')][string]$Configuration = 'release', [switch]$SkipPrepare)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot/lib/WindowsBuild.ps1"
Push-Location $repo
try {
    # Skip preparation only when the generated bindings match the configuration.
    # An unstamped cache is regenerated once.
    $configurationHash = (Get-FileHash -LiteralPath "$repo/windows/projections.json" -Algorithm SHA256).Hash
    $projectionStamp = Join-Path $repo '.windows/projections.config.sha256'
    $bindingsCurrent = (Test-Path -LiteralPath '.windows/Projections/Package.swift') -and
        (Test-Path -LiteralPath $projectionStamp) -and
        ([IO.File]::ReadAllText($projectionStamp).Trim() -eq $configurationHash)
    if (!$SkipPrepare -or !$bindingsCurrent) { & "$PSScriptRoot/prepare-windows.ps1" }
    if (!(Test-Path '.windows/Projections/Package.swift')) { throw 'Exécuter scripts/prepare-windows.ps1 avant de compiler.' }
    # Refresh handwritten runtime support even when generated bindings are cached.
    Sync-WindowsRuntimeSupport -RepositoryRoot $repo -ProjectionRoot "$repo/.windows/Projections"
    # Windows PowerShell 5.1 turns redirected native stderr (including compiler
    # warnings) into error records. Judge the compiler by its exit code.
    $buildLog = Join-Path $repo ".build/windows-build-$Configuration.log"
    $ErrorActionPreference = 'Continue'
    try {
        # Merge inside cmd so PowerShell 5 does not turn each Swift diagnostic
        # line into a RemoteException. Configuration is restricted by ValidateSet.
        $buildCommand = "swift build -c $Configuration --product CappellaWindows -j 4 2>&1"
        & $env:ComSpec /d /c $buildCommand | Tee-Object -FilePath $buildLog | ForEach-Object { Write-Host $_ }
        $compileExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = 'Stop' }
    if ($compileExitCode -ne 0) {
        Select-String -LiteralPath $buildLog -Pattern "error:" | Select-Object -First 12 | ForEach-Object { Write-Host $_.Line }
        throw "Compilation Windows échouée ($compileExitCode). Journal : $buildLog"
    }
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
