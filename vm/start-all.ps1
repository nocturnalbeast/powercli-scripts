<#
.SYNOPSIS
    Powers on all virtual machines in a vSphere environment.

.DESCRIPTION
    This script connects to a specified vCenter Server and powers on all virtual machines
    that are currently powered off, excluding any VMs specified in an exclusion list CSV file.

.PARAMETER VSphereServer
    The hostname or IP address of the vCenter Server to connect to.
    Can also be set using the VSPHERE_SERVER environment variable.

.PARAMETER Username
    The username to authenticate with the vCenter Server.
    Can also be set using the VSPHERE_USERNAME environment variable.

.PARAMETER Password
    The password for authentication with the vCenter Server.
    Can also be set using the VSPHERE_PASSWORD environment variable.

.PARAMETER ExcludeCSV
    The path to the CSV file containing the list of VMs to exclude from powering on.
    The CSV should have a column named 'VMName'.

.PARAMETER UseExistingConnection
    If specified, the script will attempt to use an existing connection to the vCenter Server
    instead of creating a new one. Credentials are not required when using this option.

.PARAMETER RetainConnection
    If specified, the script will not disconnect from the vCenter Server after completion.
    This is useful when running multiple scripts in sequence.

.EXAMPLE
    .\start-all.ps1 -VSphereServer "vcenter.domain.com" -Username "administrator@vsphere.local" -Password "SecurePass123" -ExcludeCSV "exclude.csv"
    Connects to the specified vCenter Server and powers on all powered-off VMs except those listed in exclude.csv.

.EXAMPLE
    .\start-all.ps1 -UseExistingConnection -ExcludeCSV "exclude.csv"
    Uses an existing vCenter Server connection to power on VMs.

.NOTES
    Author: nocturnalbeast
    Version: 1.0.0
    Requires: 
    - PowerCLI module must be installed
    - Windows PowerShell 5.x (This script is not compatible with PowerShell Core/pwsh due to PowerCLI requirements)

.OUTPUTS
    Displays status messages for each VM:
    - Green messages for VMs being powered on
    - Yellow messages for VMs in the exclude list that are skipped
    - Cyan message if no powered off VMs are found
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$VSphereServer = $env:VSPHERE_SERVER,

    [Parameter(Mandatory = $false)]
    [string]$Username = $env:VSPHERE_USERNAME,

    [Parameter(Mandatory = $false)]
    [SecureString]$Password = $(if ($env:VSPHERE_PASSWORD) { ConvertTo-SecureString $env:VSPHERE_PASSWORD -AsPlainText -Force }),

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExcludeCSV,

    [Parameter(Mandatory = $false)]
    [switch]$UseExistingConnection = $false,

    [Parameter(Mandatory = $false)]
    [switch]$RetainConnection = $false
)

# Validate exclude CSV file exists
if (!(Test-Path -Path $ExcludeCSV)) {
    Write-Error "Exclude CSV file does not exist: $ExcludeCSV"
    exit 1
}

# Configure PowerCLI to ignore invalid certificates quietly
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -DefaultVIServerMode Multiple -Scope Session 2>&1 | Out-Null

$Server = $null
try {
    # Import the exclude list
    $ExcludeList = Import-Csv $ExcludeCSV | ForEach-Object { $_.VMName }
    
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
        if (-not $?) {
            Write-Error "Failed to authenticate to $VSphereServer"
            exit 1
        }
    }

    # Get all powered off VMs
    $VMs = Get-VM | Where-Object { $_.PowerState -eq "PoweredOff" }
    
    if ($VMs) {
        foreach ($VM in $VMs) {
            $vmname = $VM.Name
            if ($ExcludeList -contains $vmname) {
                Write-Host "$vmname is in exclude list, skipping power on!" -ForegroundColor Yellow
            } else {
                Write-Host "Powering on $vmname..." -ForegroundColor Green
                $VM | Start-VM -Confirm:$false -RunAsync
            }
        }
    } else {
        Write-Host "No powered off VMs found." -ForegroundColor Cyan
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
