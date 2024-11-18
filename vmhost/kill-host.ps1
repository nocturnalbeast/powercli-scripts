Param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerIP
)

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -DefaultVIServerMode Multiple | Out-Null
$ConnectedServer = Connect-VIServer -Server $ServerIP -User "root" -Password "hunter2"
Get-VMHost -Name $ConnectedServer.Name | Stop-VMHost -Confirm:$false -Force:$true
Disconnect-VIServer -Server $ConnectedServer -Confirm:$false