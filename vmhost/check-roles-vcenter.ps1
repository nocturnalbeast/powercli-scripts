$SelectedVCenterServer = 'vcenter.example.com'
$si = Get-View ServiceInstance -Server $SelectedVCenterServer
$authMgr = Get-View -Id $si.Content.AuthorizationManager-Server $SelectedVCenterServer
$authMgr.RetrieveAllPermissions() |
Select @{N='Entity';E={Get-View -Id $_.Entity -Property Name -Server $SelectedVCenterServer | select -ExpandProperty Name}},
    @{N='Entity Type';E={$_.Entity.Type}},
    Principal,
    Propagate,
    @{N='Role';E={$perm = $_; ($authMgr.RoleList | where{$_.RoleId -eq $perm.RoleId}).Info.Label}} |
    Format-Table -AutoSize