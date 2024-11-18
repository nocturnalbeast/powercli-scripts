## get vsphere server
$VSphereServer = Read-Host "Enter VSphere Server IP/DNS name:"

## connect to vcenter
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -DefaultVIServerMode Multiple | Out-Null
$VSphereCredential = Get-Credential
Connect-VIServer -Server $VSphereServer -Credential $VSphereCredential

## sync definitions before starting
Sync-Patch

## scan all hosts
$Report = @()
$VMHosts = Get-VMHost
foreach ($VMHost in $VMHosts) {
    test-compliance -entity $VMHost
    $results = get-compliance -entity $VMHost
    foreach ($result in $results) {
        $row = "" | Select-Object Hostname, Baseline, Status
        $row.Hostname = $result.Entity
        $row.Baseline = $result.Baseline.Name
        $row.Status = $result.Status
        $report += $row
    }
}

## print result
$Report | Sort-Object Hostname, Baseline, Status | Format-Table -AutoSize

# cleanup
Disconnect-VIServer -Server * -Confirm:$false

# these lines are for remediation - use wisely
# $VMHost | Set-VMHost -State Maintenance
# Get-Baseline | where {$_.TargetType -eq 'Host'} | Update-Entity -Entity $VMHost -RunAsync -Confirm $false