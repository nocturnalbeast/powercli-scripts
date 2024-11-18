function Optimize-VIPermission{
    <#
    .SYNOPSIS
    Find and remove redundant permissions on vSphere objects
    .DESCRIPTION
    The function will recursively scan the permissions on the
    inventory objects passed via the Entity parameter.
    Redundant permissions will be removed.
    .NOTES
    Author:  Luc Dekens
    .PARAMETER Entity
    One or more vSphere inventory objects from where the scan
    shall start
    .EXAMPLE
    PS> Optimize-Permission -Entity Folder1 -WhatIf
    .EXAMPLE
    PS> Optimize-Permission -Entity Folder?
    .EXAMPLE
    PS> Get-Folder -Name Folder* | Optimize-Permission
    #>
    [cmdletbinding(SupportsShouldProcess=$true)]
    param(
    [parameter(ValueFromPipeline)]
    [PSObject[]]$Entity
    )
    Begin{
        function Optimize-iVIPermission{
            [cmdletbinding(SupportsShouldProcess=$true)]
            param(
            [parameter(ValueFromPipeline)]
            [VMware.Vim.ManagedObjectReference]$Entity,
            [VMware.Vim.Permission[]]$Permission = $null
            )
            Process{
                $entityObj = Get-View -Id $Entity
                $removePermission = @()
                $newParentPermission = @()
                if($Permission){
                    foreach($currentPermission in $entityObj.Permission){
                        foreach($parentPermission in $Permission){
                            if($parentPermission.Principal -eq $currentPermission.Principal -and
                            $parentPermission.RoleId -eq $currentPermission.RoleId){
                                $removePermission += $currentPermission
                                break
                            }
                            else{
                                $newParentPermission += $currentPermission
                            }
                        }
                    }
                }
                else{
                    $newParentPermission += $entityObj.Permission
                }
                if($removePermission){
                    if($pscmdlet.ShouldProcess("$($entityObj.Name)", "Cleaning up permissions")){
                        $removePermission | %{
                            $authMgr.RemoveEntityPermission($Entity,$_.Principal,$_.Group)
                        }
                    }
                }
                $Permission += $newParentPermission
                if($entityObj.ChildEntity){
                    $entityObj.ChildEntity | Optimize-iVIPermission -Permission $Permission
                }
            }
        }
    }
    Process{
        foreach($entry in $Entity){
            if($entry -is [System.String]){
                $entry = Get-Inventory -Name $entry
            }
            Optimize-iVIPermission -Entity $entry.ExtensionData.MoRef
        }
    }
}