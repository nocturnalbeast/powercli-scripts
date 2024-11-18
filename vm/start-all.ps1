<#
.SYNOPSIS
    Power on all VMs from VCenter
.DESCRIPTION
    Powers on all VMs from VCenter-managed ESXi hosts.
.PARAMETER ExcludeCSV
    The path to the CSV file containing the list of VMs to exclude from powering on.
.EXAMPLE
    start-vms.ps1 -ExcludeCSV poweredoffvms.csv
.NOTES
    Author: nocturnalbeast
#>

Param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ExcludeCSV
)

$ExcludeList = Import-Csv $ExcludeCSV | foreach { $_.VMName }

## disconnect from all previous servers
Disconnect-VIServer -Server * -Confirm:$false

## get vsphere server
$VSphereServer = Read-Host "Enter VSphere Server IP/DNS name"

## connect to vcenter
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -DefaultVIServerMode Multiple | Out-Null
$VSphereCredential = Get-Credential
Connect-VIServer -Server $VSphereServer -Credential $VSphereCredential

$VMs = Get-VM | Where-Object { $_.PowerState -eq "PoweredOff" }
foreach ($VM in $VMs) {
    $vmname = $VM.Name
    if ($ExcludeList -contains $vmname) {
        Write-Host "$vmname is in exclude list, skipping power on!"
    }
    else {
        Write-Host "$vmname is powered off, powering on..."
        $VM | Start-VM -Confirm:$false -RunAsync
    }
}

Disconnect-VIServer -Server * -Confirm:$false
