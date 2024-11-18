# powercli-scripts

A collection of PowerShell scripts for managing VMware vSphere environments using PowerCLI.

## Requirements

- VMware PowerCLI module (tested on/upto 13.3.0 build 24145081)
- Windows PowerShell 5.x (tested on/upto 5.1 build 22621)

## Common Parameters

Both scripts support the following common parameters:

- `VSphereServer`: vCenter Server hostname/IP
- `Username`: vCenter authentication username
- `Password`: vCenter authentication password
- `UseExistingConnection`: Use existing PowerCLI connection
- `RetainConnection`: Keep the connection open after script completion
