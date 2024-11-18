# Define the list of hosts to patch
$hosts = @(
	"10.20.48.24",
	"10.20.48.35",
	"10.20.48.45",
	"10.20.48.53",
	"10.20.49.21",
	"10.20.56.20",
	"10.20.56.37",
	"10.20.56.38",
	"10.20.58.179",
	"10.20.58.189",
	"10.20.58.219",
	"10.20.59.102",
	"10.20.59.108",
	"10.20.59.113",
	"10.20.59.117",
	"10.20.59.118",
	"10.20.59.127",
	"10.20.59.129",
	"10.20.59.130",
	"10.20.59.131"
)

# Credentials
$credentials = @{
	User = "root"
	Password = "hunter2"
}

# Process each host
foreach ($hostAddress in $hosts) {
	try {
		Write-Host "Processing host: $hostAddress" -ForegroundColor Cyan
		
		# Connect to the host
		$vmhost = Connect-VIServer -Server $hostAddress -User $credentials.User -Password $credentials.Password -ErrorAction Stop
		Write-Host "Connected to $hostAddress successfully" -ForegroundColor Green

		# Set host to maintenance mode
		Write-Host "Setting host to maintenance mode..." -ForegroundColor Yellow
		Set-VMHost -Server $vmhost -State Maintenance -ErrorAction Stop
		
		# Apply baseline patches
		Write-Host "Applying baseline patches..." -ForegroundColor Yellow
		Get-Baseline | Where-Object { $_.TargetType -eq 'Host' } | Remediate-Inventory -Server $vmhost -RunAsync -Confirm:$false
		
		Write-Host "Successfully initiated patching for $hostAddress" -ForegroundColor Green
	}
	catch {
		Write-Error "Failed to process host $hostAddress : $_"
	}
	finally {
		# Disconnect from the current host before moving to next
		if ($vmhost) {
			Disconnect-VIServer -Server $vmhost -Confirm:$false -ErrorAction SilentlyContinue
		}
	}
}

Write-Host "Patch operation initiated for all hosts" -ForegroundColor Green
