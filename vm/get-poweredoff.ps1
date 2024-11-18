<#
.SYNOPSIS
    Lists all powered-off virtual machines in a vSphere environment with detailed information.

.DESCRIPTION
    This script connects to a specified vCenter Server and retrieves information about all
    powered-off virtual machines, including their configuration details and when/by whom
    they were powered off. The information can be displayed on screen and exported to CSV.

.PARAMETER VSphereServer
    The hostname or IP address of the vCenter Server to connect to.
    Can also be set using the VSPHERE_SERVER environment variable.

.PARAMETER Username
    The username to authenticate with the vCenter Server.
    Can also be set using the VSPHERE_USERNAME environment variable.

.PARAMETER Password
    The password for authentication with the vCenter Server.
    Can also be set using the VSPHERE_PASSWORD environment variable.

.PARAMETER UseExistingConnection
    If specified, the script will attempt to use an existing connection to the vCenter Server
    instead of creating a new one. Credentials are not required when using this option.

.PARAMETER RetainConnection
    If specified, the script will not disconnect from the vCenter Server after completion.
    This is useful when running multiple scripts in sequence.

.PARAMETER OutputFile
    Path to the CSV file where the results should be exported.
    If not specified, results will only be displayed on screen.

.EXAMPLE
    .\get-poweredoff-vms.ps1 -VSphereServer "vcenter.domain.com" -Username "administrator@vsphere.local" -Password "SecurePass123"
    Connects to the specified vCenter Server and displays powered-off VM information.

.EXAMPLE
    .\get-poweredoff-vms.ps1 -UseExistingConnection -OutputFile "C:\reports\poweredoff_vms.csv"
    Uses an existing vCenter Server connection and exports results to the specified CSV file.

.NOTES
    Author: nocturnalbeast
    Version: 1.0.0
    Requires: 
    - PowerCLI module must be installed
    - Windows PowerShell 5.x (This script is not compatible with PowerShell Core/pwsh due to PowerCLI requirements)
    
.OUTPUTS
    Outputs a table of powered-off VMs with their details and optionally exports to CSV.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$VSphereServer = $env:VSPHERE_SERVER,

    [Parameter(Mandatory = $false)]
    [string]$Username = $env:VSPHERE_USERNAME,

    [Parameter(Mandatory = $false)]
    [string]$Password = $env:VSPHERE_PASSWORD,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile,

    [Parameter(Mandatory = $false)]
    [switch]$UseExistingConnection = $false,

    [Parameter(Mandatory = $false)]
    [switch]$RetainConnection = $false
)

# Configure PowerCLI to ignore invalid certificates quietly
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -DefaultVIServerMode Multiple -Scope Session 2>&1 | Out-Null

$Server = $null
try {
    if ($UseExistingConnection) {
        # Try to get existing connection
        $Server = $global:DefaultVIServer
        if (-not $Server) {
            Write-Error "No existing vCenter connection found. Please connect first or provide credentials."
            exit 1
        }
        if ($VSphereServer -and $Server.Name -ne $VSphereServer) {
            Write-Error "Existing connection is to a different server ($($Server.Name)) than specified ($VSphereServer)"
            exit 1
        }
    } else {
        # Validate required parameters for new connection
        if (-not $VSphereServer) {
            Write-Error "VSphere Server must be provided either as parameter or VSPHERE_SERVER environment variable"
            exit 1
        }
        if (-not $Username -or -not $Password) {
            Write-Error "Credentials must be provided either as parameters or VSPHERE_USERNAME/VSPHERE_PASSWORD environment variables"
            exit 1
        }

        # Create new connection
        $Credential = New-Object System.Management.Automation.PSCredential($Username, $Password)
        $Server = Connect-VIServer -Server $VSphereServer -Credential $Credential -ErrorAction Stop
    }

    # Initialize report array
    $Report = @()

    # Get all powered off VMs
    $VMs = Get-VM | Where-Object { $_.PowerState -eq "PoweredOff" }
    
    if ($VMs) {
        # Get datastores and power off events for efficiency
        $Datastores = Get-Datastore | Select-Object Name, Id
        $PowerOffEvents = Get-VIEvent -Entity $VMs -MaxSamples ([int]::MaxValue) | 
            Where-Object { $_ -is [VMware.Vim.VmPoweredOffEvent] } | 
            Group-Object -Property { $_.Vm.Name }

        # Process each powered off VM
        foreach ($VM in $VMs) {
            $lastPO = ($PowerOffEvents | Where-Object { $_.Group[0].Vm.Vm -eq $VM.Id }).Group | 
                Sort-Object -Property CreatedTime -Descending | 
                Select-Object -First 1

            $row = [PSCustomObject]@{
                VMName = $VM.Name
                Powerstate = $VM.PowerState
                OS = $VM.Guest.OSFullName
                Host = $VM.VMHost.Name
                Cluster = $VM.VMHost.Parent.Name
                Datastore = ($Datastores | Where-Object { $_.Id -eq ($VM.DatastoreIdList | Select-Object -First 1) }).Name
                NumCPU = $VM.NumCPU
                MemMb = $VM.MemoryMB
                DiskGb = [math]::Round((Get-HardDisk -VM $VM | Measure-Object -Property CapacityGB -Sum).Sum, 2)
                PoweredOffTime = $lastPO.CreatedTime
                PoweredOffBy = $lastPO.UserName
            }
            $Report += $row
        }

        # Sort and display results
        $Report | Sort-Object Cluster, Host, VMName | 
            Format-Table -AutoSize VMName, Cluster, Host, NumCPU, MemMb, DiskGb, PoweredOffTime, PoweredOffBy

        # Export to CSV if specified
        if ($OutputFile) {
            $Report | Sort-Object Cluster, Host, VMName | 
                Export-Csv -Path $OutputFile -NoTypeInformation -UseCulture
            Write-Host "Results exported to $OutputFile"
        }
    } else {
        Write-Host "No powered-off VMs found."
    }

} catch [VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidLogin] {
    Write-Error "Authentication failed for $VSphereServer"
    exit 1
} catch {
    Write-Error "An error occurred: $_"
    exit 1
} finally {
    # Disconnect only if we created a new connection (not using existing), don't have RetainConnection flag, and have a server object
    if ($Server -and -not $UseExistingConnection -and -not $RetainConnection) {
        Disconnect-VIServer -Server $Server -Confirm:$false -Force 2>&1 | Out-Null
    }
}
