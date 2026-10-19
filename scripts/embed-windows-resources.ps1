param([Parameter(Mandatory=$true)][string]$Executable, [Parameter(Mandatory=$true)][string]$Icon, [ValidateSet('x64','arm64')][string]$Architecture = 'x64')
$ErrorActionPreference = 'Stop'
# PE resources only: the application UI is implemented with WinUI controls.
$nativeSource = @'
using System;
using System.IO;
using System.Text;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class CappellaPEResources {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr BeginUpdateResourceW(string path, bool deleteExisting);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool UpdateResourceW(IntPtr update, IntPtr type, IntPtr name, ushort language, byte[] data, uint length);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool EndUpdateResourceW(IntPtr update, bool discard);
    static void Write(IntPtr handle, int type, int id, byte[] bytes) {
        if (!UpdateResourceW(handle, (IntPtr)type, (IntPtr)id, 0, bytes, (uint)bytes.Length)) throw new Win32Exception();
    }
    public static void UseWindowsSubsystem(string executable, ushort expectedMachine) {
        // Equivalent to editbin /SUBSYSTEM:WINDOWS. Keep the Swift CRT entry
        // point intact; avoid making linker flags invalidate every projection.
        using (var file = new FileStream(executable, FileMode.Open, FileAccess.ReadWrite))
        using (var reader = new BinaryReader(file, Encoding.UTF8, true))
        using (var writer = new BinaryWriter(file, Encoding.UTF8, true)) {
            if (reader.ReadUInt16()!=0x5A4D) throw new InvalidDataException("Missing DOS signature.");
            file.Position=0x3C; int pe=reader.ReadInt32();
            if (pe<0x40 || pe>file.Length-96) throw new InvalidDataException("Invalid PE offset.");
            file.Position=pe;
            if (reader.ReadUInt32()!=0x4550 || reader.ReadUInt16()!=expectedMachine) throw new InvalidDataException("Unexpected PE architecture.");
            file.Position=pe+24;
            if (reader.ReadUInt16()!=0x20B) throw new InvalidDataException("Expected PE32+ image.");
            file.Position=pe+24+64; writer.Write((uint)0); // Checksum is optional for user applications.
            file.Position=pe+24+68; writer.Write((ushort)2);
        }
    }
    public static void Embed(string executable, string icon, string manifest) {
        byte[] ico = File.ReadAllBytes(icon);
        ushort count = BitConverter.ToUInt16(ico, 4);
        if (ico.Length < 6 || BitConverter.ToUInt16(ico,2)!=1 || count==0) throw new InvalidDataException("ICO invalide.");
        IntPtr handle = BeginUpdateResourceW(executable, false);
        if (handle == IntPtr.Zero) throw new Win32Exception();
        bool committed = false;
        try {
            using (var group = new MemoryStream()) using (var writer = new BinaryWriter(group)) {
                writer.Write((ushort)0); writer.Write((ushort)1); writer.Write(count);
                for (int i=0; i<count; i++) {
                    int entry=6+i*16, length=checked((int)BitConverter.ToUInt32(ico,entry+8)), offset=checked((int)BitConverter.ToUInt32(ico,entry+12));
                    byte[] image=new byte[length]; Array.Copy(ico,offset,image,0,length);
                    Write(handle,3,i+1,image);
                    writer.Write(ico,entry,12); writer.Write((ushort)(i+1));
                }
                Write(handle,14,1,group.ToArray());
            }
            Write(handle,24,1,Encoding.UTF8.GetBytes(manifest));
            if (!EndUpdateResourceW(handle,false)) throw new Win32Exception();
            committed=true;
        } finally { if (!committed) EndUpdateResourceW(handle,true); }
    }
}

'@
# Add-Type definitions live for the entire PowerShell process. Key the type by
# its source so a script update never reuses an older, incompatible helper.
$hasher = [Security.Cryptography.SHA256]::Create()
try { $digest = $hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($nativeSource)) }
finally { $hasher.Dispose() }
$typeName = 'CappellaPEResources_' + [BitConverter]::ToString($digest).Replace('-', '')
$resourceType = $typeName -as [type]
if (!$resourceType) {
    $resourceType = Add-Type -TypeDefinition $nativeSource.Replace('CappellaPEResources', $typeName) -PassThru
}
$manifest = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity version="0.9.0.4" processorArchitecture="amd64" name="Cappella.Windows" type="win32"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="asInvoker" uiAccess="false"/></requestedPrivileges></security></trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application><supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/></application></compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings>
    <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
    <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    <activeCodePage xmlns="http://schemas.microsoft.com/SMI/2019/WindowsSettings">UTF-8</activeCodePage>
  </windowsSettings></application>
</assembly>
'@
$manifestArchitecture = if ($Architecture -eq 'arm64') { 'arm64' } else { 'amd64' }
$manifest = $manifest.Replace('processorArchitecture="amd64"', ('processorArchitecture="' + $manifestArchitecture + '"'))
$resourceType::Embed((Resolve-Path -LiteralPath $Executable).Path, (Resolve-Path -LiteralPath $Icon).Path, $manifest)

$machine = if ($Architecture -eq 'arm64') { [uint16]0xAA64 } else { [uint16]0x8664 }
$resourceType::UseWindowsSubsystem((Resolve-Path -LiteralPath $Executable).Path, $machine)
