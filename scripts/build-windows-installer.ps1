param(
    [string]$Version,
    [string]$Compiler
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$app = Join-Path $repo 'dist/Cappella-Windows-x64'
if (!(Test-Path -LiteralPath "$app/Cappella.exe" -PathType Leaf)) {
    throw 'Compiler le programme avec scripts/build-windows.ps1 avant de créer le Setup.'
}
if (!$Version) {
    if ($env:GITHUB_REF_TYPE -eq 'tag' -and $env:GITHUB_REF_NAME -match '^v(.+)$') {
        $Version = $Matches[1]
    } else {
        [xml]$info = [IO.File]::ReadAllText((Join-Path $repo 'packaging/Info.plist'))
        $versionKey = $info.SelectSingleNode("//key[text()='CFBundleShortVersionString']")
        $Version = $versionKey.NextSibling.InnerText
    }
}
# Also safe as an ISPP value and as part of the output file name.
if ($Version -notmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$') {
    throw 'Version invalide : utiliser par exemple 0.9.0 ou 0.9.0-beta.1.'
}
if (!$Compiler) {
    $command = Get-Command ISCC.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { $Compiler = $command.Source }
    else {
        foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
            if ($base) {
                $candidate = Join-Path $base 'Inno Setup 6/ISCC.exe'
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $Compiler = $candidate; break }
            }
        }
    }
}
if (!$Compiler -or !(Test-Path -LiteralPath $Compiler -PathType Leaf)) {
    throw 'Installer Inno Setup 6 (https://jrsoftware.org/isinfo.php), ou préciser -Compiler avec le chemin de ISCC.exe.'
}
$cache = Join-Path $repo '.windows/installer'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$runtime = Join-Path $cache 'WindowsAppRuntimeInstall-x64.exe'
if (!(Test-Path -LiteralPath $runtime -PathType Leaf)) {
    $partial = $runtime + '.download.exe'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/windowsappsdk/1.7/1.7.250909003/windowsappruntimeinstall-x64.exe' -OutFile $partial
        $signature = Get-AuthenticodeSignature -LiteralPath $partial
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw 'Signature Microsoft du runtime invalide.'
        }
        Move-Item -LiteralPath $partial -Destination $runtime
    } finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial }
    }
}
$signature = Get-AuthenticodeSignature -LiteralPath $runtime
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    throw "Runtime en cache invalide : supprimer $runtime puis relancer."
}
& $Compiler "/DAppVersion=$Version" "/DRepositoryRoot=$repo" (Join-Path $repo 'windows/Cappella.iss')
if ($LASTEXITCODE -ne 0) { throw "Création du Setup échouée ($LASTEXITCODE)." }
$setup = Join-Path $repo "dist/Cappella-$Version-Windows-x64-Setup.exe"
if (!(Test-Path -LiteralPath $setup -PathType Leaf)) { throw "Setup introuvable : $setup" }
Write-Host "Installateur : $setup"
