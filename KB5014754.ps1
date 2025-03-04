$logpath = "C:\admin\logs\IntuneDeviceSync\$(Get-Date -Format FileDateTime).log"
Start-Transcript -Path $logpath -Append -Force -Confirm:$false
$orgUnit = "OU=Intune Laptops,OU=Domain Computers,DC=DomainName,DC=com" 
$cert = gci cert:\CurrentUser\My | where Issuer -like '*ISSUINGCA*' | Select -exp thumbprint
Connect-MgGraph -TenantId 12345-6789-01234 -ClientId 12345-6789-01234 -CertificateThumbprint $cert -NoWelcome
Import-Module PSPKI -ErrorAction Stop
Get-AutopilotDevice | % {
    IF ($_.enrollmentState -ne "enrolled") {
        $devSn = $_.SerialNumber
        switch ($_.GroupTag) {
            "Issued Laptop" { $deviceName = -join ("LPT-" + $devSn) } 
            "Kiosk Laptop" { $deviceName = -join ("KIOSK-" + $devSn) } 
            "Loaner Laptop" { $deviceName = -join ("LOANER-" + $devSn) } 
        }
    }
    else {
        $deviceName = (Get-MgDevice -Filter "DeviceId eq '$($_.azureAdDeviceId)'").DisplayName
        
    }
    $SAMAccountName = if ($deviceName.Length -ge 15) { $deviceName.Substring(0, 15) + "$" } else { $deviceName + "$" }
    try {
        New-ADComputer -Name "$deviceName" -SAMAccountName $SAMAccountName -Path $orgUnit -ServicePrincipalNames "HOST/$deviceName", "HOST/$deviceName.DomaFFFinName.com"
        Write-Verbose "Computer object created. ($($deviceName))" 
    }
    catch {
        Write-Verbose "Skipping AD computer object creation (likely because it already exists in AD)" -ForegroundColor Yellow
    }
Get-CertificationAuthority | Get-IssuedRequest -Filter "CertificateTemplate -eq Azure Laptops", "CommonName -eq $deviceName" -Property * | % {
    $commonName = $_.CommonName
    $sn = $_.SerialNumber
    $byteArray = for ($i = 0; $i -lt $sn.Length; $i += 2) { [Convert]::ToByte($sn.Substring($i, 2), 16) }
    [array]::Reverse($byteArray)
    $hexString = -join ($byteArray | ForEach-Object { "{0:X2}" -f $_ })
    $ca = ($_.ConfigString).Split('\')[1]
    $altSecValue = "X509:<I>DC=com,DC=DomainName,CN=$ca<SR>$hexString"
    [Array]::Reverse($altSecValue)
    Write-Verbose "$commonName,$altSecValue"
    try {
        Set-ADComputer $commonName -Add @{altSecurityIdentities = "$altSecValue" } -Confirm:$false
    }
    catch {
        Write-Verbose ("Computer $commonName not found")
        }
    } 
}
Disconnect-MgGraph
Stop-Transcript
