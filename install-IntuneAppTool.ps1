# Run as Administrator — downloads latest IntuneWinAppUtil.exe from Microsoft GitHub
$toolPath = "C:\IntuneApps\_Tool"
New-Item -ItemType Directory -Force -Path $toolPath | Out-Null

$zipUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/archive/refs/heads/master.zip"
$zipDest = "$toolPath\IntuneWinTool.zip"

Invoke-WebRequest -Uri $zipUrl -OutFile $zipDest
Expand-Archive -Path $zipDest -DestinationPath $toolPath -Force

# Copy just the EXE to the tool root for easy access
Copy-Item "$toolPath\Microsoft-Win32-Content-Prep-Tool-master\IntuneWinAppUtil.exe" -Destination $toolPath

Write-Host "Tool ready at: $toolPath\IntuneWinAppUtil.exe" -ForegroundColor Green
