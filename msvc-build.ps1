[CmdletBinding()]
Param(
    [Parameter(Position=0, mandatory=$true)]
    [ValidateSet("Init", "Build", "Rebuild", "Clean")]
    [string]$Task
)

###############################################################################
# CONFIG 
# set these vars to override project defaults
###############################################################################
# - values: "" (p), "v140" (MSVC 2015), "v141" (MSVC 2017), "v141_xp" (XP support), "v142" (MSVC 2019), etc
$toolset = ""
# - values: "" (default), "7.0" (Win7 SDK), "8.1" (Win8 SDK), "10.0" (Win10 SDK), etc
$sdk = ""
# - values: "" (default), "Win32"
$platform = ""
###############################################################################

$solution = "vgmstream_full.sln"
$dependencies = "dependencies"
$vswhere = "$dependencies/vswhere.exe"
$config = "/p:Configuration=Release"
# not used ATM
$enable_aac = 0

if ($platform) { $platform = "/p:Platform=" + $platform }
if ($toolset) { $toolset = "/p:PlatformToolset=" + $toolset }
if ($sdk) { $sdk = "/p:WindowsTargetPlatformVersion=" + $sdk }

# https://stackoverflow.com/a/41618979/9919772
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# helper
function Unzip
{
    param([string]$zipfile, [string]$outpath)
    Write-Output "Extracting $zipfile"
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

# helper
function Download
{
    param([string]$uri, [string]$outfile)
    Write-Output "Downloading $uri"
    $wc = New-Object net.webclient
    $wc.Downloadfile($uri, $outfile)
}

# download and unzip dependencies
function Init
{
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    Remove-Item -Path "$dependencies" -Recurse -ErrorAction Ignore
    New-Item "$dependencies" -Type directory -Force | out-null

    # vswhere: MSBuild locator
    # may already be in %ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
    # so could test that and skip this step
    Download "https://github.com/Microsoft/vswhere/releases/download/2.6.7/vswhere.exe" "$dependencies\vswhere.exe"

    # foobar: wtl
    Download "https://www.nuget.org/api/v2/package/wtl/9.1.1" "$dependencies\wtl.zip"
    Unzip "$dependencies\wtl.zip" "$dependencies\wtl_tmp"
    Move-Item "$dependencies\wtl_tmp\lib\native" "$dependencies\wtl"
    Remove-Item -Path "$dependencies\wtl_tmp" -Recurse

    # foobar: sdk anti-hotlink (random link) defeater
    #Download "https://www.foobar2000.org/SDK" "$dependencies\SDK"
    #$key = (Select-String -Path $dependencies\SDK -Pattern "\/([a-f0-9]+)\/SDK-2018-01-11\.zip").matches.groups[1]
    #Remove-Item -Path "$dependencies\SDK"
    #Download "https://www.foobar2000.org/files/$key/SDK-2018-01-11.zip" "$dependencies\foobar.zip"

    # foobar: sdk direct link, but 2019< sdks gone ATM
    #Download "https://www.foobar2000.org/files/SDK-2018-01-11.zip" "$dependencies\foobar.zip"

    # foobar: sdk static mirror
    Download "https://github.com/vgmstream/vgmstream-deps/raw/master/foobar2000/SDK-2018-02-05.zip" "$dependencies\foobar.zip"
    Unzip "$dependencies\foobar.zip" "$dependencies\foobar"

    # foobar: aac (not used ATM)
    if ($enable_aac)
    {
        Download "https://github.com/kode54/fdk-aac/archive/master.zip" "$dependencies\fdk-aac.zip"
        Download "https://github.com/kode54/qaac/archive/master.zip" "$dependencies\qaac.zip"
        Unzip "$dependencies\fdk-aac.zip" "$dependencies\fdk-aac_tmp"
        Unzip "$dependencies\qaac.zip" "$dependencies\qaac_tmp"
        Move-Item "$dependencies\fdk-aac_tmp\fdk-aac-master" "$dependencies\fdk-aac"
        Move-Item "$dependencies\qaac_tmp\qaac-master" "$dependencies\qaac"
        Remove-Item -Path "$dependencies\fdk-aac_tmp" -Recurse
        Remove-Item -Path "$dependencies\qaac_tmp" -Recurse
    }

    # open foobar sdk project and modify WTL path
    # (maybe should just pass include to CL envvar: set CL=/I"(path)\WTL\Include")
    [xml]$proj = Get-Content $dependencies\foobar\foobar2000\ATLHelpers\foobar2000_ATL_helpers.vcxproj
    $proj.project.ItemDefinitionGroup | ForEach-Object {
        $includes = $proj.CreateElement("AdditionalIncludeDirectories", $proj.project.NamespaceURI)
        $includes.InnerText = "../../../wtl/include"
        $_.ClCompile.AppendChild($includes)
    }
    $proj.Save("$dependencies\foobar\foobar2000\ATLHelpers\foobar2000_ATL_helpers.vcxproj")
}

# main build
function CallMsbuild
{
    param([string]$target)
    if ($target) { $target = "/t:" + $target }

    # download dependencies if needed
    if(!(Test-Path $vswhere)) { Init }


    # autolocate MSBuild path
    $msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe

    if(!($msbuild -and $(Test-Path $msbuild))) {
        Write-Error "Unable to find MSBuild. Is Visual Studio installed?"
    }

    # main build (pass config separate and not as a single string)
    & $msbuild $solution $config $platform $toolset $sdk $target /m
}

function Build
{
    CallMsbuild "Build"
}

function Rebuild
{
    CallMsbuild "Rebuild"
}
function Clean
{
    CallMsbuild "Clean"
    # todo fix the above, for now:
    #Remove-Item -Path "$dependencies" -Recurse -ErrorAction Ignore
    Remove-Item -Path "cli/Debug" -Recurse -ErrorAction Ignore
    Remove-Item -Path "cli/Release" -Recurse -ErrorAction Ignore
    Remove-Item -Path "ext_libs/Debug" -Recurse -ErrorAction Ignore
    Remove-Item -Path "ext_libs/Release" -Recurse -ErrorAction Ignore
    Remove-Item -Path "ext_libs/Getopt/Release" -Recurse -ErrorAction Ignore
    Remove-Item -Path "ext_libs/Getopt/Release" -Recurse -ErrorAction Ignore
    Remove-Item -Path "fb2k/Debug" -Recurse -ErrorAction Ignore
    Remove-Item -Path "fb2k/Release" -Recurse -ErrorAction Ignore
    Remove-Item -Path "src/Debug" -Recurse -ErrorAction Ignore
    Remove-Item -Path "src/Release" -Recurse -ErrorAction Ignore
    Remove-Item -Path "winamp/Debug" -Recurse -ErrorAction Ignore
    Remove-Item -Path "winamp/Release" -Recurse -ErrorAction Ignore
    Remove-Item -Path "xmplay/Debug" -Recurse -ErrorAction Ignore
    Remove-Item -Path "xmplay/Release" -Recurse -ErrorAction Ignore
    Remove-Item -Path "Debug" -Recurse -ErrorAction Ignore
    Remove-Item -Path "Release" -Recurse -ErrorAction Ignore
}

switch ($Task)
{
    "Init" { Init }
    "Build" { Build }
    "Rebuild" { Rebuild }
    "Clean" { Clean }
}
