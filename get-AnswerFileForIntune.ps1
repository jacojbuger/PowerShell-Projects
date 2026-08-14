# Run as Administrator on your Windows 11 laptop
# This opens the normal Git installer wizard — go through it with your preferred options
# When it finishes, it writes every answer to the INF file

Start-Process -FilePath "C:\IntuneApps\Git 253\Source\Git-2.53.0-64-bit.exe" `
              -ArgumentList "/SAVEINF=`"C:\IntuneApps\Git 253\Source\git-vscode.inf`"" `
              -Wait
