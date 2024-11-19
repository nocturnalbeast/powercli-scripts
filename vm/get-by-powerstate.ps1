<#
.SYNOPSIS
	Lists virtual machines in a vSphere environment filtered by power state with detailed information.

.DESCRIPTION
	This script connects to a specified vCenter Server and retrieves information about virtual machines
	based on their power state (powered-on or powered-off). It provides detailed information including
	configuration details, host information, and power state change history.

.PARAMETER VSphereServer
	The hostname or IP address of the vCenter Server to connect to.
	Can also be set using the VSPHERE_SERVER environment variable.

.PARAMETER Username
	The username to authenticate with the vCenter Server.
	Can also be set using the VSPHERE_USERNAME environment variable.

.PARAMETER Password
	The password for authentication with the vCenter Server.
	Can also be set using the VSPHERE_PASSWORD environment variable.

.PARAMETER State
	The power state to filter VMs by. Valid values are "PoweredOn" or "PoweredOff".
	This parameter is mandatory.

.PARAMETER UseExistingConnection
	If specified, the script will attempt to use an existing connection to the vCenter Server
	instead of creating a new one. Credentials are not required when using this option.

.PARAMETER RetainConnection
	If specified, the script will not disconnect from the vCenter Server after completion.
	This is useful when running multiple scripts in sequence.

.PARAMETER CsvOutput
	Optional path to export results to a CSV file. The directory specified in the path must exist.
	If the file exists, it will be overwritten.

.EXAMPLE
	.\get-vms-by-state.ps1 -VSphereServer "vcenter.domain.com" -Username "administrator@vsphere.local" -Password "SecurePass123" -State PoweredOn
	Connects to the specified vCenter Server and lists all powered-on VMs.

.EXAMPLE
	.\get-vms-by-state.ps1 -UseExistingConnection -State PoweredOff -CsvOutput "C:\reports\poweredoff_vms.csv"
	Uses an existing vCenter Server connection and exports powered-off VM information to CSV.

.NOTES
	Author: nocturnalbeast
	Version: 1.0.0
	Requires: 
	- PowerCLI module must be installed
	- Windows PowerShell 5.x (This script is not compatible with PowerShell Core/pwsh due to PowerCLI requirements)
	
.OUTPUTS
	Outputs a table of VMs with their details including name, cluster, host, resources, and power state history.
	If CsvOutput is specified, also exports the results to a CSV file.
#>

param(
	[Parameter(Mandatory = $false)]
	[string]$VSphereServer = $env:VSPHERE_SERVER,

	[Parameter(Mandatory = $false)]
	[string]$Username = $env:VSPHERE_USERNAME,

	[Parameter(Mandatory = $false)]
	[string]$Password = $env:VSPHERE_PASSWORD,

	[Parameter(Mandatory = $true)]
	[ValidateSet("PoweredOn", "PoweredOff")]
	[string]$State,

	[Parameter(Mandatory = $false)]
	[switch]$UseExistingConnection = $false,

	[Parameter(Mandatory = $false)]
	[switch]$RetainConnection = $false,

	[Parameter(Mandatory = $false)]
	[string]$CsvOutput,

	[Parameter(Mandatory = $false)]
	[int]$ThrottleLimit = 10  # Control parallel job limit
)

# Check CSV directory existence early if CSV output is specified
if ($CsvOutput) {
	$directory = Split-Path -Parent $CsvOutput
	if ($directory -and !(Test-Path -Path $directory)) {
		Write-Error "Output directory does not exist: $directory"
		exit 1
	}
}

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
		$Credential = New-Object System.Management.Automation.PSCredential($Username, (ConvertTo-SecureString $Password -AsPlainText -Force))

		$Server = Connect-VIServer -Server $VSphereServer -Credential $Credential -ErrorAction Stop 2>&1 | Out-Null
		if (-not $?) {
			Write-Error "Failed to authenticate to $VSphereServer"
			exit 1
		}
	}

	# Initialize report array
	$Report = @()

	# Get VMs based on power state
	$VMs = Get-VM | Where-Object { $_.PowerState -eq $State }
	
	if ($VMs) {
		# Get all required data upfront
		$Datastores = Get-Datastore | Select-Object Name, Id
		$PowerEvents = Get-VIEvent -Entity $VMs -MaxSamples ([int]::MaxValue) | 
			Where-Object { 
				($State -eq "PoweredOn" -and $_ -is [VMware.Vim.VmPoweredOffEvent]) -or
				($State -eq "PoweredOff" -and $_ -is [VMware.Vim.VmPoweredOffEvent])
			} | 
			Group-Object -Property { $_.Vm.Name }
		
		# Pre-fetch hard disk information for all VMs
		$VMDisks = @{}
		foreach ($VM in $VMs) {
			$VMDisks[$VM.Id] = [math]::Round((Get-HardDisk -VM $VM | Measure-Object -Property CapacityGB -Sum).Sum, 2)
		}

		# Create a script block for processing each VM
		$ProcessVM = {
			param($VM, $Datastores, $PowerEvents, $DiskInfo)
			
			$lastEvent = ($PowerEvents | Where-Object { $_.Group[0].Vm.Vm -eq $VM.Id }).Group | 
				Sort-Object -Property CreatedTime -Descending | 
				Select-Object -First 1

			[PSCustomObject]@{
				VMName = $VM.Name
				PowerState = $VM.PowerState
				OS = $VM.Guest.OSFullName
				Host = $VM.VMHost.Name
				Cluster = $VM.VMHost.Parent.Name
				Datastore = ($Datastores | Where-Object { $_.Id -eq ($VM.DatastoreIdList | Select-Object -First 1) }).Name
				NumCPU = $VM.NumCPU
				MemMb = $VM.MemoryMB
				DiskGb = $DiskInfo
				LastStateChangeTime = $lastEvent.CreatedTime
				LastStateChangeBy = $lastEvent.UserName
			}
		}

		# Initialize report array
		$Report = @()

		# Process VMs in parallel using jobs
		$Jobs = @()
		
		# Create all jobs at once
		foreach ($VM in $VMs) {
			$Jobs += Start-Job -ScriptBlock $ProcessVM -ArgumentList $VM, $Datastores, $PowerEvents, $VMDisks[$VM.Id]
			
			# Wait if we've hit the throttle limit
			while ((Get-Job -State Running).Count -ge $ThrottleLimit) {
				$CompletedJobs = $Jobs | Where-Object { $_.State -eq "Completed" }
				if ($CompletedJobs) {
					$Report += Receive-Job -Job $CompletedJobs
					Remove-Job -Job $CompletedJobs
					$Jobs = $Jobs | Where-Object { $_.State -ne "Completed" }
				}
				Start-Sleep -Milliseconds 100
			}
		}

		# Wait for remaining jobs and collect results
		while ($Jobs) {
			$CompletedJobs = $Jobs | Where-Object { $_.State -eq "Completed" }
			if ($CompletedJobs) {
				$Report += Receive-Job -Job $CompletedJobs
				Remove-Job -Job $CompletedJobs
				$Jobs = $Jobs | Where-Object { $_.State -ne "Completed" }
			}
			if ($Jobs) {
				Start-Sleep -Milliseconds 100
			}
		}

		# Sort and display results
		$Report | Sort-Object Cluster, Host, VMName | 
			Format-Table -AutoSize VMName, PowerState, Cluster, Host, NumCPU, MemMb, DiskGb, LastStateChangeTime, LastStateChangeBy

		# Export to CSV if specified
		if ($CsvOutput) {
			$Report | Sort-Object Cluster, Host, VMName | 
				Export-Csv -Path $CsvOutput -NoTypeInformation -UseCulture
			Write-Host "Results exported to: $CsvOutput" -ForegroundColor Green
		}
	} else {
		Write-Host "No VMs found in state: $State"
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