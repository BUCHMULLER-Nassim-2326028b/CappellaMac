param([Parameter(Mandatory=$true)][string]$Executable, [Parameter(Mandatory=$true)][string]$Fixture)
$ErrorActionPreference = 'Stop'
$executablePath = (Resolve-Path -LiteralPath $Executable).Path
$firstMarker = Join-Path $env:TEMP ('cappella-first-' + [guid]::NewGuid().ToString() + '.json')
$secondMarker = Join-Path $env:TEMP ('cappella-second-' + [guid]::NewGuid().ToString() + '.json')
$oldMarker = $env:CAPPELLA_WINDOWS_ACTIVATION_MARKER
$activationFixture = Join-Path $env:TEMP ('Cappella scène # ' + [guid]::NewGuid().ToString() + '.detx')
Copy-Item -LiteralPath (Resolve-Path -LiteralPath $Fixture).Path -Destination $activationFixture
$primary = $null; $secondary = $null
function Read-AppState($AppProcess, $MarkerPath, $RequireCues) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $AppProcess.Refresh()
        if ($AppProcess.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Instance indisponible.' }
        if (Test-Path -LiteralPath $MarkerPath) {
            $state = Get-Content -LiteralPath $MarkerPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($state.visible -and (!$RequireCues -or $state.cues -gt 0)) { return $state }
        }
        Start-Sleep -Milliseconds 150
    } while ($true)
}
try {
    $env:CAPPELLA_WINDOWS_ACTIVATION_MARKER = $firstMarker
    $primary = Start-Process -FilePath $executablePath -WindowStyle Hidden -PassThru
    $first = Read-AppState $primary $firstMarker $false
    $env:CAPPELLA_WINDOWS_ACTIVATION_MARKER = $secondMarker
    $secondary = Start-Process -FilePath $executablePath -ArgumentList ('"' + $activationFixture + '"') -WindowStyle Hidden -PassThru
    $second = Read-AppState $secondary $secondMarker $true
    if ($first.pid -ne $primary.Id -or $second.pid -ne $secondary.Id -or $first.pid -eq $second.pid) { throw 'Les instances ne sont pas independantes.' }
    $firstAgain = Get-Content -LiteralPath $firstMarker -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($firstAgain.cues -ne 0) { throw 'Le nouveau projet a remplace celui de la premiere instance.' }
    foreach ($appProcess in @($secondary, $primary)) {
        [void]$appProcess.CloseMainWindow()
        if (!$appProcess.WaitForExit(10000)) { throw 'Une instance reste en arriere-plan apres fermeture.' }
        if ($appProcess.ExitCode -ne 0) { throw 'Fermeture anormale.' }
    }
    Write-Host 'Instances independantes et fermeture complete : OK.'
} finally {
    if ($oldMarker) { $env:CAPPELLA_WINDOWS_ACTIVATION_MARKER = $oldMarker }
    else { Remove-Item Env:CAPPELLA_WINDOWS_ACTIVATION_MARKER -ErrorAction SilentlyContinue }
    foreach ($appProcess in @($secondary,$primary)) {
        if ($appProcess -and !$appProcess.HasExited) { Stop-Process -Id $appProcess.Id }
    }
    if (Test-Path -LiteralPath $activationFixture) { Remove-Item -LiteralPath $activationFixture }
    foreach ($markerPath in @($firstMarker,$secondMarker)) {
        Get-ChildItem -Path ($markerPath + '.*.log') -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
        if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath }
    }
}