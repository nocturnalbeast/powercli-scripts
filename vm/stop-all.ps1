Param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerIP
)


### get vsphere server
#$VSphereServer = Read-Host "Enter VSphere Server IP/DNS name"

## connect to vcenter
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -DefaultVIServerMode Multiple | Out-Null
$VSphereCredential = Get-Credential
$ConnectedServer = Connect-VIServer -Server $VSphereServer -Credential $VSphereCredential

$vms = Get-Datacenter -Name "UGW" | Get-VM | Where-Object { $_.PowerState -eq "PoweredOn" }
$vms | Format-Table -AutoSize
ForEach ($vm in $vms) {
    if ($vm.Name -like "vCenter*") { continue }
    Write-Host "Trying to shut down VM "$vm.Name
    if ($vm.PowerState -eq "PoweredOn") {
        $vm_success = Stop-VMGuest -VM $vm.Name -Confirm:$false
    if ($vm_success -eq $null) {
        $choice = Read-Host -Prompt "Could not shutdown Guest OS. Power off VM?"
        if ($choice -eq 'y') {
            Stop-VM -VM $vm.Name -Confirm:$false
        }
    }
    }
}
Disconnect-VIServer $ConnectedServer -Confirm:$false
