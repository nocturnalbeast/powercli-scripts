param(
    [Parameter(Mandatory=$false)]
    [int]$DaysAgo = 30
)

# Get the cutoff date
$CutoffDate = (Get-Date).AddDays(-$DaysAgo)

# Get powered off VMs and their last power off event
$PoweredOffVMs = Get-VM | Where-Object {$_.PowerState -eq "PoweredOff"}
$PowerOffEvents = Get-VIEvent -Entity $PoweredOffVMs -Finish $CutoffDate -Types Info | 
    Where-Object {$_.FullFormattedMessage -like "*powered off*"} |
    Group-Object -Property {$_.VM.Name} |
    ForEach-Object {
        $lastEvent = $_.Group | Sort-Object CreatedTime -Descending | Select-Object -First 1
        [PSCustomObject]@{
            VM = $lastEvent.VM.Name
            'Powered Off Date' = $lastEvent.CreatedTime
        }
    }

# Display results
if ($PowerOffEvents) {
    $PowerOffEvents | Format-Table -AutoSize
} else {
    Write-Host "No VMs found powered off for $DaysAgo days or more"
}