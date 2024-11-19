param(
    [Parameter(Mandatory=$false)]
    [int]$DaysAgo = 30,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("PoweredOn", "PoweredOff")]
    [string]$State = "PoweredOff",

    [Parameter(Mandatory=$false)]
    [int]$MaxParallelJobs = 10,

    [Parameter(Mandatory=$false)]
    [int]$BatchSize = 50
)

# Get vCenter connection details for jobs
$DefaultVIServer = $global:DefaultVIServer
if (-not $DefaultVIServer) {
    Write-Error "Not connected to vCenter Server"
    return
}
$VIConnection = @{
    Server = $DefaultVIServer.Name
    User = $DefaultVIServer.User
    Password = $DefaultVIServer.Password
}

# Get the cutoff date
$CutoffDate = (Get-Date).AddDays(-$DaysAgo)

# Get VMs based on power state and store their names
$FilteredVMs = @(Get-VM | Where-Object {$_.PowerState -eq $State} | Select-Object -ExpandProperty Name)

if (-not $FilteredVMs) {
    Write-Host "No VMs found in $State state"
    return
}

# Set the message pattern based on state
$MessagePattern = if ($State -eq "PoweredOff") { "*powered off*" } else { "*powered on*" }

# Create balanced VM batches
$TotalVMs = $FilteredVMs.Count
$VMsPerJob = [Math]::Ceiling($TotalVMs / $MaxParallelJobs)
$VMBatches = @()

for ($i = 0; $i -lt $TotalVMs; $i += $VMsPerJob) {
    $VMBatches += ,@($FilteredVMs[$i..([Math]::Min($i + $VMsPerJob - 1, $TotalVMs - 1))])
}

# Create a script block for the job that processes batches
$JobScriptBlock = {
    param($VMBatch, $CutoffDate, $MessagePattern, $State, $BatchSize, $VIConnection)
    
    # Import VMware PowerCLI module and connect to vCenter
    Import-Module VMware.VimAutomation.Core
    Connect-VIServer -Server $VIConnection.Server -User $VIConnection.User -Password $VIConnection.Password | Out-Null
    
    $Results = @()
    # Process VMs in smaller batches
    for ($i = 0; $i -lt $VMBatch.Count; $i += $BatchSize) {
        $CurrentBatchNames = $VMBatch[$i..([Math]::Min($i + $BatchSize - 1, $VMBatch.Count - 1))]
        $CurrentBatchVMs = Get-VM -Name $CurrentBatchNames
        
        $BatchResults = Get-VIEvent -Entity $CurrentBatchVMs -Finish $CutoffDate -Types Info | 
            Where-Object {$_.FullFormattedMessage -like $MessagePattern} |
            Group-Object -Property {$_.VM.Name} |
            ForEach-Object {
                $lastEvent = $_.Group | Sort-Object CreatedTime -Descending | Select-Object -First 1
                [PSCustomObject]@{
                    VM = $lastEvent.VM.Name
                    "Last $State Date" = $lastEvent.CreatedTime
                }
            }
        $Results += $BatchResults
    }
    
    # Disconnect from vCenter
    Disconnect-VIServer -Server $VIConnection.Server -Confirm:$false
    $Results
}

# Start jobs for each batch of VMs
$Jobs = foreach ($batch in $VMBatches) {
    if ($batch) {
        Start-Job -ScriptBlock $JobScriptBlock -ArgumentList $batch, $CutoffDate, $MessagePattern, $State, $BatchSize, $VIConnection
    }
}

# Wait for all jobs to complete and get results
$PowerStateEvents = $Jobs | Wait-Job | Receive-Job

# Clean up jobs
$Jobs | Remove-Job

# Display results
if ($PowerStateEvents) {
    $PowerStateEvents | Format-Table -AutoSize
} else {
    Write-Host "No VMs found $State for $DaysAgo days or more"
}