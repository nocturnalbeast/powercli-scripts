$clusterName = "UGW"
$vsH = @{}
Get-View -ViewType HostSystem -SearchRoot (Get-Datacenter -Name $clusterName | Get-View).MoRef | %{
$esx = $_
# Get vswitches
$esx.Config.Network.Vswitch | %{
if($vsH.ContainsKey($_.Key)){$pgH = $vsH[$_.Key][1]}
else{$pgH = @{}}
$_.Portgroup | %{
if(!$pgH.ContainsKey($_)){
$pgH[$_] = "", @(), 0, @{}
}
}
$vsH[$_.Key] = $_.Name, $pgH
}
# Get portgroups
$esx.Config.Network.Portgroup | %{
$pgHash = $vsH[$_.Vswitch][1]
$esxTab = $pgHash[$_.Key][1]
$esxTab += $esx.Name
$puH = @{}
if($_.Port){
$_.Port | %{
$puH[$_.Key] = "poweredon", $_.Type, $_.Mac
}
$pgHash[$_.Key] = $_.Spec.Name, $esxTab, $_.Port.Count, $puH
}
else{
$pgHash[$_.Key] = $_.Spec.Name, $esxTab, 0, @{}
}
$vsH[$_.Vswitch][1] = $pgHash
}
# Get poweredoff VMs on host, find their NICs and increment counter
$esx.Vm | %{Get-View -Id $_} | where {$_.Runtime.PowerState -eq ([VMware.Vim.VirtualMachinePowerState]"poweredOff")} | %{
$vm = $_
$vm.Config.Hardware.Device | where {$_.DeviceInfo.Label -like "Network*"} | %{
$nic = $_
$esx.Config.Network.Portgroup | where {$_.Spec.Name -eq $nic.Backing.DeviceName} | %{
$vSw = $vsH[$_.Vswitch]
$pg = $vSw[1][$_.Key]
$pg[2] += 1
$pg[3][$vm.Name + "/" + $nic.Key] = "poweredOff", "virtualMachine", $nic.MacAddress
$vSw[1][$_.Key] = $pg
$vsH[$_.Vswitch] = $vSw
}
}
}
}
# Display results on console
$vsH.GetEnumerator() | %{
Write-Host $_.Value[0]
$_.Value[1].GetEnumerator() | %{
Write-Host "`t" $_.Value[0] -NoNewline
if($_.Value[2]){
$foCol = "green"
}
else{
$foCol = "red"
}
Write-Host -ForegroundColor $foCol " Ports:" $_.Value[2]
Write-Host "`tUsed on:"
$_.Value[1] | %{
Write-Host "`t " $_
}
Write-Host "`tPorts"
$_.Value[3].GetEnumerator() | %{
Write-Host "`t" $_.Value
}
Write-Host
}
}