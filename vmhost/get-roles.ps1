## get vcenter server
$VCenterServer = Read-Host "Enter VCenter Server IP/DNS name:"

## connect to vcenter
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -DefaultVIServerMode Multiple | Out-Null
$VCenterCredential = Get-Credential
Connect-VIServer -Server $VCenterServer -Credential $VCenterCredential

$report =@()
$authMgr = Get-View AuthorizationManager
foreach($role in $authMgr.RoleList){
$row = "" | Select RoleName, Label, RoleId
$row.RoleName = $role.Name
$row.Label = $role.Info.Label
$row.RoleId = $role.RoleId
$report += $row
}

Write-Host $report

Disconnect-VIServer -Server $VCenterServer -Confirm:$false