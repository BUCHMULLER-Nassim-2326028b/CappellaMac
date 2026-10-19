$ErrorActionPreference = 'Stop'
# Appx requires Windows PowerShell 5.1 rather than PowerShell 7.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $windowsPowerShell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    & $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}
# Per-user packages, no forced upgrade or shutdown of other applications.
$required = Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.1.7' | Where-Object Architecture -EQ 'X64'
if ($required) { Write-Host 'Windows App Runtime 1.7 x64 est déjà installé.'; exit 0 }
$download = Join-Path $env:TEMP ('Cappella-runtime-' + [guid]::NewGuid().ToString() + '.exe')
Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/windowsappsdk/1.7/1.7.250909003/windowsappruntimeinstall-x64.exe' -OutFile $download
$signature = Get-AuthenticodeSignature -LiteralPath $download
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'Signature Microsoft du runtime invalide.' }
$installer = Start-Process -FilePath $download -ArgumentList '--quiet' -WindowStyle Hidden -Wait -PassThru
if ($installer.ExitCode -ne 0) { throw "Installation échouée ($($installer.ExitCode))." }
Remove-Item -LiteralPath $download
Write-Host 'Runtime WinUI installé. Lancer Cappella.exe.'
