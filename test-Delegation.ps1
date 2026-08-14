
Set-ADAccountControl gMSA-SQL$ -TrustedForDelegation $false -TrustedToAuthForDelegation $false

Set-ADServiceAccount gMSA-SQL$ `
  -Add @{'msDS-AllowedToDelegateTo'=@(
    'MSSQLSvc/KDC-SQL01',
    'MSSQLSvc/KDC-SQL01.domainname.lab',
    'MSSQLSvc/KDC-SQL01:1433',
    'MSSQLSvc/KDC-SQL01.domainname.lab:1433'
  )}
