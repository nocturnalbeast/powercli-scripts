<#
.SYNOPSIS
    Adds multiple ESXi hosts to a vCenter Server instance.

.DESCRIPTION
    This script connects to a specified vCenter Server and adds multiple ESXi hosts
    to a designated location. It processes a list of hosts from a specified input file
    and adds them using the provided credentials.

.PARAMETER VSphereServer
    The hostname or IP address of the vCenter Server to connect to.
    Can also be set using the VSPHERE_SERVER environment variable.

.PARAMETER Username
    The username to authenticate with the vCenter Server.
    Can also be set using the VSPHERE_USERNAME environment variable.

.PARAMETER Password
    The password for authentication with the vCenter Server.
    Can also be set using the VSPHERE_PASSWORD environment variable.

.PARAMETER HostLocation
    The location/folder in vCenter where the hosts will be added.

.PARAMETER HostsFile
    Path to a text file containing ESXi host IP addresses or hostnames, one per line.

.PARAMETER ESXiUsername
    The username for authenticating with the ESXi hosts (must be the same for all hosts).
    Default: root

.PARAMETER ESXiPassword
    The password for authenticating with the ESXi hosts (must be the same for all hosts).

.PARAMETER UseExistingConnection
    If specified, the script will attempt to use an existing connection to the vCenter Server
    instead of creating a new one. Credentials are not required when using this option.

.PARAMETER RetainConnection
    If specified, the script will not disconnect from the vCenter Server after completion.
    This is useful when running multiple scripts in sequence.

.EXAMPLE
    .\add-hosts.ps1 -VSphereServer "vcenter.domain.com" -Username "administrator@vsphere.local" -Password "SecurePass123" -HostLocation "Datacenter/folder" -HostsFile "hosts.txt" -ESXiUsername "root" -ESXiPassword "password123"
    Connects to the specified vCenter Server and adds all hosts from hosts.txt to the specified location.

.EXAMPLE
    .\add-hosts.ps1 -UseExistingConnection -HostLocation "Datacenter/folder" -HostsFile "hosts.txt" -ESXiUsername "root" -ESXiPassword "password123"
    Uses an existing vCenter Server connection to add the hosts from hosts.txt.

.NOTES
    Author: nocturnalbeast
    Version: 1.0.0
    Requires: 
    - PowerCLI module must be installed
    - Windows PowerShell 5.x
    - Network connectivity to vCenter Server and all ESXi hosts
    - Appropriate permissions to add hosts to vCenter
    
.OUTPUTS
    None. The script adds hosts to vCenter but does not return any objects.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$VSphereServer = $env:VSPHERE_SERVER,

    [Parameter(Mandatory = $false)]
    [string]$Username = $env:VSPHERE_USERNAME,

    [Parameter(Mandatory = $false)]
    [SecureString]$Password = $(if ($env:VSPHERE_PASSWORD) { ConvertTo-SecureString $env:VSPHERE_PASSWORD -AsPlainText -Force }),

    [Parameter(Mandatory = $true)]
    [string]$HostLocation,

    [Parameter(Mandatory = $true)]
    [string]$HostsFile,

    [Parameter(Mandatory = $false)]
    [string]$ESXiUsername = "root",

    [Parameter(Mandatory = $true)]
    [string]$ESXiPassword,

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
        $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential($Username, $SecurePassword)
        $Server = Connect-VIServer -Server $VSphereServer -Credential $Credential -ErrorAction Stop
    }

    # Validate and read hosts file
    if (-not (Test-Path $HostsFile)) {
        Write-Error "Hosts file not found: $HostsFile"
        exit 1
    }

    # Read hosts from file, removing empty lines and trimming whitespace
    $hostList = Get-Content $HostsFile | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }

    if ($hostList.Count -eq 0) {
        Write-Error "No hosts found in $HostsFile"
        exit 1
    }

    # Process each host in the file
    $hostList | ForEach-Object {
        Add-VMHost -Server $Server -Location $HostLocation -Name $_ -User $ESXiUsername -Password $ESXiPassword -Force -Confirm:$False
    }
} catch [VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidLogin] {
    Write-Error "Authentication failed for $VSphereServer"
    exit 1
    # Disconnect only if we created a new connection (not using existing), don't have RetainConnection flag, and have a server object
    if ($Server -and -not $UseExistingConnection -and -not $RetainConnection) {
        exit 1
    }
} finally {
    # Disconnect only if we created a new connection (not using existing) and have a server object
    if ($Server -and -not $UseExistingConnection) {
        Disconnect-VIServer -Server $Server -Confirm:$false -Force
    }
}
