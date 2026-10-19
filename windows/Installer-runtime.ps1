param([string]$RuntimeInstaller)
$ErrorActionPreference = 'Stop'
# Appx requires Windows PowerShell 5.1 rather than PowerShell 7.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $windowsPowerShell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($RuntimeInstaller) { $arguments += @('-RuntimeInstaller', $RuntimeInstaller) }
    & $windowsPowerShell @arguments
    exit $LASTEXITCODE
}
# Require the SDK's runtime revision, not just any earlier 1.7 installation.
function Get-RequiredRuntime {
    Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.1.7' | Where-Object {
        $_.Architecture -eq 'X64' -and [version]$_.Version -ge [version]'7000.617.2103.0'
    }
}
if (Get-RequiredRuntime) { Write-Host 'Windows App Runtime 1.7 x64 est déjà installé.'; exit 0 }
$download = $null
try {
    if (!$RuntimeInstaller) {
        $download = Join-Path $env:TEMP ('Cappella-runtime-' + [guid]::NewGuid().ToString() + '.exe')
        Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/windowsappsdk/1.7/1.7.250909003/windowsappruntimeinstall-x64.exe' -OutFile $download
        $RuntimeInstaller = $download
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $RuntimeInstaller
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw 'Signature Microsoft du runtime invalide.'
    }
    $installer = Start-Process -FilePath $RuntimeInstaller -ArgumentList '--quiet' -WindowStyle Hidden -Wait -PassThru
    if ($installer.ExitCode -ne 0) { throw "Installation échouée ($($installer.ExitCode))." }
    if (!(Get-RequiredRuntime)) { throw 'Windows App Runtime 1.7 x64 reste introuvable après installation.' }
    Write-Host 'Runtime WinUI installé.'
} finally {
    if ($download -and (Test-Path -LiteralPath $download)) { Remove-Item -LiteralPath $download }
}
