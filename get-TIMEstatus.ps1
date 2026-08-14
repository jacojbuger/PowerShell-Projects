$NtpServer = "time.windows.com"
Resolve-DnsName $NtpServer
Test-Connection -Count 5 -ComputerName $NtpServer
w32tm /stripchart /computer:$NtpServer /dataonly /samples:5
