function Sync-WindowsRuntimeSupport {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ProjectionRoot
    )
    foreach ($module in @('WinUI', 'WinAppSDK')) {
        $moduleRoot = Join-Path $ProjectionRoot "Sources/$module"
        $supportRoot = Join-Path $moduleRoot 'Support'
        New-Item -ItemType Directory -Force -Path $supportRoot | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot "windows/Support/$module") -Filter '*.swift' -File | ForEach-Object {
            $target = Join-Path $supportRoot $_.Name
            $legacyTarget = Join-Path $moduleRoot $_.Name
            if (!(Test-Path -LiteralPath $target) -and (Test-Path -LiteralPath $legacyTarget)) { $target = $legacyTarget }
            if (!(Test-Path -LiteralPath $target) -or [IO.File]::ReadAllText($_.FullName) -ne [IO.File]::ReadAllText($target)) {
                Copy-Item -LiteralPath $_.FullName -Destination $target
            }
        }
    }
}