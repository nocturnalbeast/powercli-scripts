<#
.SYNOPSIS
	Identifies and lists invalid or inaccessible virtual machines in a vSphere environment.

.DESCRIPTION
	This script connects to a specified vCenter Server and retrieves a list of all virtual machines
	that are in an invalid or inaccessible state. This can help identify VMs that might need
	attention or cleanup in the environment.

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

.EXAMPLE
	.\get-invalid-vms.ps1 -VSphereServer "vcenter.domain.com" -Username "administrator@vsphere.local" -Password "SecurePass123"
	Connects to the specified vCenter Server using provided credentials and lists invalid VMs.

.EXAMPLE
	.\get-invalid-vms.ps1 -UseExistingConnection
	Uses an existing vCenter Server connection to list invalid VMs.

.EXAMPLE
	.\get-invalid-vms.ps1 -VSphereServer "vcenter.domain.com" -Username "administrator@vsphere.local" -Password "SecurePass123" -RetainConnection
	Connects to the vCenter Server and keeps the connection open after completion.

.NOTES
	Author: nocturnalbeast
	Version: 1.0.0
	Requires: 
	- PowerCLI module must be installed
	- Windows PowerShell 5.x (This script is not compatible with PowerShell Core/pwsh due to PowerCLI requirements)
	
.OUTPUTS
	Outputs a table of invalid/inaccessible VMs with their names and connection states.
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
		$Server = Connect-VIServer -Server $VSphereServer -Credential $Credential -ErrorAction Stop 2>&1 | Out-Null
		if (-not $?) {
			Write-Error "Failed to authenticate to $VSphereServer"
			exit 1
		}
	}

	# Get invalid VMs
	$InvalidVMs = (Get-View -ViewType VirtualMachine) | Where-Object {
		$_.Runtime.ConnectionState -eq "invalid" -or $_.Runtime.ConnectionState -eq "inaccessible"
	}

	# Format and output the results
	if ($InvalidVMs) {
		$InvalidVMs | Select-Object @{N = 'Name'; E = { $_.Name } }, @{N = 'ConnectionState'; E = { $_.Runtime.ConnectionState } } | Format-Table -AutoSize
	} else {
		Write-Host "No invalid or inaccessible VMs found."
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
