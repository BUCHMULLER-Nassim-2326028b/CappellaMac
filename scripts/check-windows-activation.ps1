param([Parameter(Mandatory=$true)][string]$Executable, [Parameter(Mandatory=$true)][string]$Fixture)
$ErrorActionPreference = 'Stop'
$executablePath = (Resolve-Path -LiteralPath $Executable).Path
$marker = Join-Path $env:TEMP ('cappella-activation-' + [guid]::NewGuid().ToString() + '.json')
$env:CAPPELLA_WINDOWS_ACTIVATION_MARKER = $marker
$oldInstanceKey = $env:CAPPELLA_WINDOWS_INSTANCE_KEY
$env:CAPPELLA_WINDOWS_INSTANCE_KEY = 'Cappella.Test.' + [guid]::NewGuid().ToString()
$activationFixture = Join-Path $env:TEMP ('Cappella scène # ' + [guid]::NewGuid().ToString() + '.detx')
Copy-Item -LiteralPath (Resolve-Path -LiteralPath $Fixture).Path -Destination $activationFixture
$primary = $null; $secondary = $null
try {
    $primary = Start-Process -FilePath $executablePath -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (!(Test-Path -LiteralPath $marker)) {
        if ($primary.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Premiere instance indisponible.' }
        Start-Sleep -Milliseconds 150
    }
    $secondary = Start-Process -FilePath $executablePath -ArgumentList ('"' + $activationFixture + '"') -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $state = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($primary.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Le fichier ne rejoint pas la premiere fenetre.' }
        Start-Sleep -Milliseconds 150
    } while ($state.cues -le 0)
    if ($state.pid -ne $primary.Id -or !$state.visible) { throw 'Une nouvelle instance a charge le projet.' }
    if (!$secondary.WaitForExit(10000)) { throw 'La seconde instance ne se termine pas apres redirection.' }
    if ($secondary.ExitCode -ne 0) { throw "Echec de redirection ($($secondary.ExitCode))." }
    Write-Host "Activation OK : PID $($primary.Id), $($state.cues) repliques, seconde instance terminee."
} catch {
    Get-ChildItem -Path ($marker + '.*.log') -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_.Name; Get-Content -LiteralPath $_.FullName -Encoding UTF8 | Write-Host }
    throw
} finally {
    Remove-Item Env:CAPPELLA_WINDOWS_ACTIVATION_MARKER -ErrorAction SilentlyContinue
    if ($oldInstanceKey) { $env:CAPPELLA_WINDOWS_INSTANCE_KEY = $oldInstanceKey }
    else { Remove-Item Env:CAPPELLA_WINDOWS_INSTANCE_KEY -ErrorAction SilentlyContinue }
    foreach ($appProcess in @($secondary,$primary)) {
        if ($appProcess -and !$appProcess.HasExited) {
            [void]$appProcess.CloseMainWindow()
            if (!$appProcess.WaitForExit(2000)) { Stop-Process -Id $appProcess.Id }
        }
    }
    if (Test-Path -LiteralPath $activationFixture) { Remove-Item -LiteralPath $activationFixture }
    Get-ChildItem -Path ($marker + '.*.log') -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
}
