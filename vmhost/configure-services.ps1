# Service configuration script for VMware ESXi hosts
# Configures services running state and startup policy

# Service configuration hashtables
$ServicesToStart = @{
    'DCUI' = $true
    'lbtd' = $true
    'sfcbd-watchdog' = $true
}

$ServicesToStop = @{
    'lwsmd' = $true
    'ntpd' = $true
    'pcscd' = $true
    'snmpd' = $true
    'TSM' = $true
    'TSM-SSH' = $true
    'vprobed' = $true
    'xorg' = $true
}

function Connect-ToVSphereServer {
    param()
    try {
        # Configure PowerCLI settings
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -DefaultVIServerMode Multiple | Out-Null
        
        # Get server details and credentials
        $VSphereServer = Read-Host "Enter VSphere Server IP/DNS name"
        $VSphereCredential = Get-Credential -Message "Enter VSphere credentials"
        
        # Connect to vCenter
        Connect-VIServer -Server $VSphereServer -Credential $VSphereCredential -ErrorAction Stop
        Write-Host "Successfully connected to vSphere server: $VSphereServer" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to vSphere server: $_"
        exit 1
    }
}

function Set-VMHostServicesState {
    param()
    try {
        $vmHosts = Get-VMHost
        foreach ($vmHost in $vmHosts) {
            Write-Host "Configuring services for host: $($vmHost.Name)" -ForegroundColor Cyan
            
            # Start required services
            foreach ($service in $ServicesToStart.Keys) {
                $hostService = $vmHost | Get-VMHostService | Where-Object {$_.Key -eq $service}
                if ($hostService) {
                    Start-VMHostService -HostService $hostService -Confirm:$false
                    Set-VMHostService -HostService $hostService -Policy "On" -Confirm:$false
                }
            }
            
            # Stop unnecessary services
            foreach ($service in $ServicesToStop.Keys) {
                $hostService = $vmHost | Get-VMHostService | Where-Object {$_.Key -eq $service}
                if ($hostService) {
                    Stop-VMHostService -HostService $hostService -Confirm:$false
                    Set-VMHostService -HostService $hostService -Policy "Off" -Confirm:$false
                }
            }
        }
        Write-Host "Successfully configured all host services" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to configure host services: $_"
        return $false
    }
    return $true
}

function Disconnect-CleanUp {
    param()
    try {
        Disconnect-VIServer -Server * -Confirm:$false
        Write-Host "Successfully disconnected from all vSphere servers" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to disconnect from vSphere servers: $_"
    }
}

# Main execution
try {
    Connect-ToVSphereServer
    $success = Set-VMHostServicesState
    if (-not $success) {
        Write-Warning "Some services may not have been configured correctly"
    }
}
finally {
    Disconnect-CleanUp
}