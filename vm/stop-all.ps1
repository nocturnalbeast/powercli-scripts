<#
.SYNOPSIS
    Gracefully shuts down all powered-on virtual machines in a vSphere environment.

.DESCRIPTION
    This script connects to a specified vCenter Server and attempts to gracefully shut down
    all powered-on virtual machines. It skips the vCenter Server VM and provides an option
    for hard power-off if graceful shutdown fails.

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

.PARAMETER ForceShutdown
    If specified, the script will automatically perform a hard power-off when graceful
    shutdown fails, without prompting for confirmation.

.EXAMPLE
    .\stop-all.ps1 -VSphereServer "vcenter.domain.com" -Username "administrator@vsphere.local" -Password "SecurePass123"
    Connects to the specified vCenter Server and attempts to gracefully shut down all VMs.

.EXAMPLE
    .\stop-all.ps1 -UseExistingConnection
    Uses an existing vCenter Server connection to shut down VMs.

.EXAMPLE
    .\stop-all.ps1 -VSphereServer "vcenter.domain.com" -Username "administrator@vsphere.local" -Password "SecurePass123" -ForceShutdown
    Connects to the vCenter Server and shuts down all VMs, forcing power-off when graceful shutdown fails.

.NOTES
    Author: nocturnalbeast
    Version: 1.0.0
    Requires: 
    - PowerCLI module must be installed
    - Windows PowerShell 5.x (This script is not compatible with PowerShell Core/pwsh due to PowerCLI requirements)

.OUTPUTS
    Displays status messages for each VM:
    - Status messages for shutdown attempts
    - Warning messages when graceful shutdown fails
    - Confirmation prompts for force shutdown (unless -ForceShutdown is specified)
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$VSphereServer = $env:VSPHERE_SERVER,

    [Parameter(Mandatory = $false)]
    [string]$Username = $env:VSPHERE_USERNAME,

    [Parameter(Mandatory = $false)]
    [SecureString]$Password = $(if ($env:VSPHERE_PASSWORD) { ConvertTo-SecureString $env:VSPHERE_PASSWORD -AsPlainText -Force }),

    [Parameter(Mandatory = $false)]
    [switch]$UseExistingConnection = $false,

    [Parameter(Mandatory = $false)]
    [switch]$RetainConnection = $false,

    [Parameter(Mandatory = $false)]
    [switch]$ForceShutdown = $false
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
        if (-not $?) {
            Write-Error "Failed to authenticate to $VSphereServer"
            exit 1
        }
    }

    # Get all powered on VMs
    $VMs = Get-VM | Where-Object { $_.PowerState -eq "PoweredOn" }
    
    if ($VMs) {
        foreach ($VM in $VMs) {
            # Skip vCenter VM (identified by Photon OS)
            if ($VM.Name -like "vCenter*" -or $VM.Guest.GuestFullName -like "*Photon*") {
                Write-Host "Skipping vCenter VM: $($VM.Name)" -ForegroundColor Yellow
                continue
            }

            Write-Host "Attempting graceful shutdown of $($VM.Name)..." -ForegroundColor Cyan
            $ShutdownSuccess = $VM | Stop-VMGuest -Confirm:$false
            
            if (-not $ShutdownSuccess) {
                $message = "Graceful shutdown failed for $($VM.Name)"
                if ($ForceShutdown) {
                    Write-Host "$message. Forcing power off..." -ForegroundColor Yellow
                    $VM | Stop-VM -Confirm:$false
                } else {
                    $choice = Read-Host -Prompt "$message. Power off VM? (y/n)"
                    if ($choice -eq 'y') {
                        $VM | Stop-VM -Confirm:$false
                    } else {
                        Write-Host "Skipping power off for $($VM.Name)" -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "Successfully initiated shutdown for $($VM.Name)" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "No powered on VMs found." -ForegroundColor Cyan
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
