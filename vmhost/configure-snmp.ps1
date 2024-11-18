# script to configure snmp on all esxi hosts

function ConvertSecureStringToPlainText {
    param([Parameter(Mandatory = $true)][System.Security.SecureString] $SecurePassword)
    $PasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    $PlainTextPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($PasswordPointer)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($PasswordPointer)
    $PlainTextPassword
}

## get vsphere server
$VSphereServer = Read-Host "Enter VSphere Server IP/DNS name:"

## connect to vcenter
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -DefaultVIServerMode Multiple | Out-Null
$VSphereCredential = Get-Credential
Connect-VIServer -Server $VSphereServer -Credential $VSphereCredential

## get snmp settings
$EsxiRootUserPassword = Read-Host "Enter ESXi root user password:" -AsSecureString
$EsxiRootUserPasswordPlain = ConvertSecureStringToPlainText($EsxiRootUserPassword)
$myHosts = Get-VMHost | Out-GridView -OutputMode Multiple
Connect-ViServer $myHosts -User root -Password $EsxiRootUserPasswordPlain
$hostSNMP = Get-VMHostSnmp -Server $myHosts.Name
Write-Host "`nThe current settings for your ESXi hosts are as follows:" -ForegroundColor Blue
$hostSNMP | Select-Object VMHost, Enabled, Port, ReadOnlyCommunities | Format-Table -AutoSize

## set snmp settings
$communityString = Read-Host "Enter SNMP string:"
Write-Host "SNMP community string entered is: $communityString `n" -ForegroundColor Blue
Write-Host "Updated settings for your ESXi hosts are as follows: `n" -ForegroundColor Green
$hostSNMP = Set-VMHostSNMP $hostSNMP -Enabled:$true -ReadOnlyCommunity $communityString
$hostSNMP | Select-Object VMHost, Enabled, Port, ReadOnlyCommunities | Format-Table -AutoSize
$snmpStatus = $myHosts | Get-VMHostService | Where-Object { $_.Key -eq "snmpd" }

ForEach ($i in $snmpStatus) {
    if ($snmpStatus.running -eq $true) {
        $i | Restart-VMHostService -Confirm:$false | Out-Null
    }
    else {
        $i | Start-VMHostService -Confirm:$false | Out-Null
    }
    $i | Set-VMHostService -Policy "On"
}

Write-Host "SNMP service has been started on the ESXi host(s)." -ForegroundColor Blue
$myHosts | Get-VMHostService | Where-Object { $_.Key -eq "snmpd" } | Select-Object VMHost, Key, Running | Format-Table -AutoSize

# cleanup
Disconnect-VIServer -Server * -Confirm:$false