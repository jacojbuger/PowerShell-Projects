$Tool    = "C:\IntuneApps\_Tool\IntuneWinAppUtil.exe"
$Version = "1.3.315"
$Src1 = "C:\IntuneApps\Greenshot_v$Version\Source"
$Out1 = "C:\IntuneApps\Greenshot_v$Version\Output"
New-Item -ItemType Directory -Force -Path $Out1 | Out-Null
& $Tool -c $Src1 -s "gshot.exe" -o $Out1 -q
Write-Host "VS Code package: $(Get-ChildItem $Out1 -Filter *.intunewin | Select-Object -ExpandProperty FullName)" -ForegroundColor Green
