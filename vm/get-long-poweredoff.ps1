Write-Host "Connected" -Foregroundcolor "Green"

$PoweredOffAge = (Get-Date).AddDays(-30)
$Output = @{}
$PoweredOffvms = Get-VM | where {$_.PowerState -eq "PoweredOff"}
$EventsLog = Get-VIEvent -Entity $PoweredOffvms -Finish $PoweredOffAge  -MaxSamples ([int]::MaxValue) | where{$_.FullFormattedMessage -like "*is powered off"}
If($EventsLog)
{
    $EventsLog | %{ if($Output[$_.Vm.Name] -lt $_.CreatedTime)
        {
            $Output[$_.Vm.Name] = $_.CreatedTime
        }
    }
}
$Result = $Output.getEnumerator() | select @{N="VM";E={$_.Key}},@{N="Powered Off Date";E={$_.Value}}

If($Result)
{
    $Result | Format-Table -AutoSize
}
Else
{
    "NO VM's Powered off last 30 Days"
}