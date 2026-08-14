<#
.SYNOPSIS
    Prints a chronological timeline of authentication failures on this server:
    when, why, which auth type (Kerberos/NTLM), and against what target.
    Run locally on each server. Console output only.
#>

[CmdletBinding()]
param(
    [datetime]$StartTime = (Get-Date).AddHours(-24),
    [switch]$IncludeLowRisk   # show LOW-risk/noise codes instead of skipping them
)

# Codes that are normal Kerberos negotiation or otherwise not actionable on their own -
# skipped by default, shown only with -IncludeLowRisk
$LowRiskCodes = @('0x18')

$CodeMeanings = @{
    '0x6'        = 'Client account not found'
    '0x7'        = 'Target SPN not found / not registered on any account'
    '0x9'        = 'Client name malformed'
    '0xA'        = 'Server/SPN name malformed'
    '0x12'       = 'Account revoked (disabled, locked, or expired)'
    '0x17'       = 'Pre-authentication failed (bad password)'
    '0x18'       = 'Additional pre-authentication required - normal Kerberos negotiation step, only a problem if not immediately followed by a successful 4768'
    '0x1F'       = 'Ticket integrity check failed - often a duplicate SPN or mismatched key'
    '0x20'       = 'Clock skew too great'
    '0x21'       = 'Ticket not yet valid (clock skew)'
    '0x25'       = 'Clock skew too great'
    '0xC0000064' = 'Username does not exist'
    '0xC000006A' = 'Bad password'
    '0xC000006D' = 'Generic logon failure - check SubStatus for the real reason (this is the outer Status code on a 4625)'
    '0xC0000234' = 'Account locked out'
    '0xC0000072' = 'Account disabled'
    '0xC0000193' = 'Account expired'
    '0xC0000071' = 'Password expired'
    '0xC000018C' = 'Trusted domain failure - trust relationship problem'
    '0xC000018D' = 'Trust relationship failure between this workstation/server and the domain'
    '0xC0000133' = 'Clock skew between client and server'
    '0xC00002EE' = 'STATUS_UNFINISHED_CONTEXT_DELETED - auth exchange aborted before completion (client/service closed connection, firewall interference, or target process restarted mid-handshake) - not a credential/trust code, check SourceIp and correlate with target server stability'
    '0xE'        = 'KDC_ERR_ETYPE_NOSUPP - client offered an encryption type the KDC will not accept for this account/policy (often a legacy DES/RC4-only client against an AES-only Kerberos encryption policy) - check SourceIp, especially on privileged accounts'
}

function Get-EventDataHash {
    param($Event)
    $xml = [xml]$Event.ToXml()
    $h = @{}
    foreach ($d in $xml.Event.EventData.Data) {
        if ($d.Name) { $h[$d.Name] = $d.'#text' }
    }
    return $h
}

function Get-Reason {
    param([string]$Code)
    if (-not $Code) { return 'Unknown - no result code on this event' }
    $Code = $Code.Trim()
    if ($CodeMeanings.ContainsKey($Code)) { return $CodeMeanings[$Code] }
    return "Unmapped code $Code - check manually"
}

Write-Host "`n=== Auth failure timeline for $env:COMPUTERNAME - since $StartTime ===" -ForegroundColor Cyan

try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4768, 4769, 4771, 4776, 4625
        StartTime = $StartTime
    } -ErrorAction Stop
}
catch {
    Write-Host "No matching events, or access denied: $($_.Exception.Message)" -ForegroundColor Yellow
    return
}

$rows = foreach ($evt in $events) {
    $data = Get-EventDataHash -Event $evt

    $authType = switch ($evt.Id) {
        4768 { 'Kerberos (TGT)' }
        4769 { 'Kerberos (TGS)' }
        4771 { 'Kerberos (PreAuth)' }
        4776 { 'NTLM' }
        4625 { if ($data['AuthenticationPackageName']) { $data['AuthenticationPackageName'] } else { 'Unspecified' } }
    }

    $status    = $data['Status']
    $substatus = $data['SubStatus']
    # For 4625, SubStatus carries the actual reason - Status is often just the generic
    # 0xC000006D wrapper. Show SubStatus as the primary code when present.
    $code = if ($evt.Id -eq 4625 -and $substatus -and $substatus -ne '0x0') { $substatus } else { $status }
    if (-not $code) { $code = $data['ResultCode'] }
    if ($code -eq '0x0') { continue }   # skip clean successes
    if (-not $IncludeLowRisk -and $LowRiskCodes -contains $code.Trim()) { continue }   # skip noise by default

    $target = $data['ServiceName']
    if (-not $target) { $target = $data['TargetServerName'] }
    if (-not $target) { $target = $data['Workstation'] }

    [PSCustomObject]@{
        TimeLocal = $evt.TimeCreated
        EventId   = $evt.Id
        AuthType  = $authType
        Account   = $data['TargetUserName']
        Target    = $target
        SourceIp  = $data['IpAddress']
        Code      = $code
        Risk      = if ($LowRiskCodes -contains $code.Trim()) { 'LOW' } else { 'REVIEW' }
        Why       = Get-Reason -Code $code
    }
}

if (-not $rows) {
    Write-Host "No authentication failures in this window." -ForegroundColor Green
    if (-not $IncludeLowRisk) { Write-Host "(LOW-risk/noise codes are hidden - rerun with -IncludeLowRisk to see everything)" -ForegroundColor DarkGray }
}
else {
    $rows | Sort-Object TimeLocal |
        Format-Table TimeLocal, AuthType, Account, Target, SourceIp, Code, Risk, Why -AutoSize -Wrap

    Write-Host "`nTotal failures shown: $(@($rows).Count)" -ForegroundColor White
    if (-not $IncludeLowRisk) { Write-Host "(LOW-risk/noise codes hidden - rerun with -IncludeLowRisk to see everything)" -ForegroundColor DarkGray }
    Write-Host "By auth type:" -ForegroundColor White
    $rows | Group-Object AuthType | Sort-Object Count -Descending |
        Format-Table Name, Count -AutoSize
}
