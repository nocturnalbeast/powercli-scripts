# script to configure the vmuser user and associated role

function ConvertSecureStringToPlainText {
    param([Parameter(Mandatory = $true)][System.Security.SecureString] $SecurePassword)
    $PasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    $PlainTextPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($PasswordPointer)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($PasswordPointer)
    $PlainTextPassword
}

## get vcenter server
$VCenterServer = Read-Host "Enter VCenter Server IP/DNS name:"

## connect to vcenter
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -DefaultVIServerMode Multiple | Out-Null
$VCenterCredential = Get-Credential
Connect-VIServer -Server $VCenterServer -Credential $VCenterCredential

## get root creds
$EsxiRootUserPassword = Read-Host "Enter ESXi root user password:" -AsSecureString
$EsxiRootUserPasswordPlain = ConvertSecureStringToPlainText($EsxiRootUserPassword)
$myHosts = Get-VMHost | Out-GridView -OutputMode Multiple

## get new user to create
$EsxiServerNewUsername = Read-Host "Enter new user name:"
$EsxiServerNewPassword = Read-Host "Enter new user password:" -AsSecureString
$EsxiServerNewPasswordPlain = ConvertSecureStringToPlainText($EsxiServerNewPassword)

foreach($EsxiServer in ($myHosts)) {
    Connect-VIServer -Server $EsxiServer.Name -User root -Password $EsxiRootUserPasswordPlain
    # create the user / update the user
    try {
        $user = Get-VMHostAccount -Server $EsxiServer.Name -User $EsxiServerNewUsername -ErrorAction Stop
    }
    catch {
        Write-Host "User not found, creating new user!"
        $user = New-VMHostAccount -Server $EsxiServer.Name -User $EsxiServerNewUsername -Password $EsxiServerNewPasswordPlain
    }
    finally {
        Set-VMHostAccount -UserAccount $EsxiServerNewUsername -Password $EsxiServerNewPasswordPlain
    }
    # set permissions
    $perm = Get-VIPermission -Principal $EsxiServerNewUsername -Server $EsxiServer.Name
    if(!$perm){
        $readOnlyPrivileges = Get-VIPrivilege -Role Readonly
        $role = New-VIRole -Privilege $readOnlyPrivileges -Name "VMUser role" -Server $EsxiServer.Name
        $powerOnPrivileges = Get-VIPrivilege -Name "Power On" -Server $EsxiServer.Name
        $role = Set-VIRole –Role $role –AddPrivilege $powerOnPrivileges -Server $EsxiServer.Name
        $powerOffPrivileges = Get-VIPrivilege -Name "Power Off" -Server $EsxiServer.Name
        $role = Set-VIRole –Role $role –AddPrivilege $powerOffPrivileges -Server $EsxiServer.Name
        $consoleInteractionPrivileges = Get-VIPrivilege -Name "Console interaction" -Server $EsxiServer.Name
        $role = Set-VIRole –Role $role –AddPrivilege $consoleInteractionPrivileges -Server $EsxiServer.Name
        $answerQuestionPrivileges = Get-VIPrivilege -Name "Answer question" -Server $EsxiServer.Name
        $role = Set-VIRole –Role $role –AddPrivilege $answerQuestionPrivileges -Server $EsxiServer.Name
        $resetPrivileges = Get-VIPrivilege -Name "Reset" -Server $EsxiServer.Name
        $role = Set-VIRole –Role $role –AddPrivilege $resetPrivileges -Server $EsxiServer.Name
        $suspendPrivileges = Get-VIPrivilege -Name "Suspend" -Server $EsxiServer.Name
        $role = Set-VIRole –Role $role –AddPrivilege $suspendPrivileges -Server $EsxiServer.Name
        $root = Get-Folder -Name ha-folder-root -Server $EsxiServer.Name
        $permission = New-VIPermission -Entity $root -Principal $EsxiServerNewUsername -Role $role -Server $EsxiServer.Name
        $permission = Set-VIPermission -Permission $permission -Role $role -Server $EsxiServer.Name
    }
    # disconnect from the server
    Disconnect-VIServer -Server $EsxiServer.Name -Confirm:$false
}
Disconnect-VIServer -Server $VCenterServer -Confirm:$false