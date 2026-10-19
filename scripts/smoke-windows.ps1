param([Parameter(Mandatory=$true)][string]$Executable, [string]$Fixture = '', [int]$ExpectedCues = 0)
$ErrorActionPreference = 'Stop'
$executablePath = (Resolve-Path -LiteralPath $Executable).Path
$marker = Join-Path $env:TEMP ('cappella-smoke-' + [guid]::NewGuid().ToString() + '.json')
$env:CAPPELLA_WINDOWS_SMOKE_MARKER = $marker
$oldInstanceKey = $env:CAPPELLA_WINDOWS_INSTANCE_KEY
$env:CAPPELLA_WINDOWS_INSTANCE_KEY = 'Cappella.Smoke.' + [guid]::NewGuid().ToString()
$appProcess = $null
try {
    $parameters = @{FilePath=$executablePath; WorkingDirectory=(Split-Path $executablePath -Parent); WindowStyle='Hidden'; PassThru=$true}
    if ($Fixture) { $parameters.ArgumentList = '"' + (Resolve-Path -LiteralPath $Fixture).Path + '"' }
    $appProcess = Start-Process @parameters
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (!(Test-Path -LiteralPath $marker)) {
        if ($appProcess.HasExited) { throw "Cappella a quitté pendant le lancement ($($appProcess.ExitCode))." }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Le lancement WinUI ne répond pas dans le délai prévu.' }
        Start-Sleep -Milliseconds 150
    }
    $state = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
    if (!$state.visible -or $state.pid -ne $appProcess.Id) { throw "La fenêtre attendue n’est pas visible dans le processus lancé." }
    if ($state.layoutWidth -le 0 -or $state.bandElements -le 0 -or !$state.editingWorks) { throw "L’interface ou la saisie sur la bande n’est pas opérationnelle." }
    if ($Fixture -and $state.cues -le 0) { throw "Le DetX de test n’a pas été chargé." }
    if ($state.scriptRows -ne $state.cues) { throw 'Le script ne contient pas toutes les repliques.' }
    if ($ExpectedCues -gt 0 -and $state.cues -ne $ExpectedCues) { throw 'Nombre de repliques inattendu.' }
    Start-Sleep -Milliseconds 600
    if ($appProcess.HasExited) { throw 'Cappella a quitté après le lancement.' }
    Write-Host "WinUI OK : $($state.title), $($state.cues) répliques, PID $($state.pid)."
} finally {
    if ($oldInstanceKey) { $env:CAPPELLA_WINDOWS_INSTANCE_KEY = $oldInstanceKey }
    else { Remove-Item Env:CAPPELLA_WINDOWS_INSTANCE_KEY -ErrorAction SilentlyContinue }
    Remove-Item Env:CAPPELLA_WINDOWS_SMOKE_MARKER -ErrorAction SilentlyContinue
    if ($appProcess -and !$appProcess.HasExited) {
        [void]$appProcess.CloseMainWindow()
        if (!$appProcess.WaitForExit(3000)) { Stop-Process -Id $appProcess.Id }
    }
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
}
