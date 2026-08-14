# ===================================================================
# 1. Choose a stable regional pool (ZA region works more reliably)
# ===================================================================
$NtpServer = "za.pool.ntp.org"

# ===================================================================
# 2. Clean and reset the Windows Time service
# ===================================================================
Stop-Service w32time -Force -ErrorAction SilentlyContinue

w32tm /unregister
w32tm /register

Start-Service w32time

# ===================================================================
# 3. Apply configuration
# ===================================================================
w32tm /config /manualpeerlist:$NtpServer /syncfromflags:manual /update

# ===================================================================
# 4. Force sync
# ===================================================================
w32tm /resync /force
