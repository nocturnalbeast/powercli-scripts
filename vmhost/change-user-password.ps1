function ConvertSecureStringToPlainText {
    param([Parameter(Mandatory = $true)][System.Security.SecureString] $SecurePassword)
    $PasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    $PlainTextPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($PasswordPointer)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($PasswordPointer)
    $PlainTextPassword
}

## get esxi server details
$EsxiServer = Read-Host "Enter ESXi Server IP/DNS name:"
Write-Host "Enter root credentials:`n"
$EsxiServerCredential = Get-Credential

## get user name
$EsxiUser = Read-Host "Enter username:"
$EsxiPassword = Read-Host "Enter the new password:" -AsSecureString
$EsxiPasswordPlain = ConvertSecureStringToPlainText($EsxiPassword)

## set the password
Connect-VIServer -Protocol https -Server $EsxiServer -Credential $EsxiServerCredential
Set-VMHostAccount -UserAccount $EsxiUser -Password $EsxiPasswordPlain
Disconnect-VIServer $EsxiServer -Confirm:$false