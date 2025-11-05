# Import Tool Guide

The **Import Tool** is a guided wizard that helps you add new CLI tools to the HemSoft CLI Tools ecosystem. This document provides detailed instructions and examples for importing different types of tools.

## Accessing the Import Tool

1. Launch the CLI Tools application
2. Select the first option: **⊕ Import New Tool** (highlighted in yellow)
3. Follow the interactive wizard

## Import Process Overview

The import wizard consists of 7 steps:

1. **Basic Information** - Name, description, and version
2. **Tool Type** - Script, executable on PATH, or executable with full path
3. **Verification** - Test tool execution
4. **Interactivity** - Configure console behavior
5. **Parameters** - Static values passed to the tool
6. **Runtime Arguments** - User prompts before running
7. **Review & Confirm** - Final configuration review

## Tool Types

### PowerShell Script (.ps1)

Import a PowerShell script that will be copied to the `scripts` directory.

**Example: Custom Deployment Script**
```
Tool Name: Deploy App
Description: Deploy application to staging environment
Version: 1.0.0
Tool Type: PowerShell Script (.ps1)
Script Path: C:\Projects\deploy-app.ps1
```

**What happens:**
- Script is copied to `scripts\deploy-app.ps1`
- Script becomes available in the CLI Tools menu
- Can be executed with parameters and runtime arguments

### Executable on PATH

Import a command-line tool that's already installed and available on your system PATH.

**Example: Git Command**
```
Tool Name: Git Status
Description: Show working tree status
Version: 2.45.0
Tool Type: Executable on PATH
Executable Name: git
Parameters:
  - subcommand: status
  - options: --short
```

**What happens:**
- Tool is verified on PATH
- No copying required
- Parameters are appended to the command

### Executable with Full Path

Import a tool from a specific location on your system.

**Example: Custom Binary**
```
Tool Name: Custom Analyzer
Description: Analyze log files
Version: 3.2.1
Tool Type: Executable with full path
Executable Path: F:\Tools\analyzer.exe
```

**What happens:**
- Full path is stored in configuration
- Tool is verified at that location
- Executes from the specified path

## Interactivity Settings

### Interactive Tools

Tools that need full console control (examples: vim, lazygit, mc, htop).

**Characteristics:**
- Takes over the entire console
- User interacts directly with the tool
- No output is captured by CLI Tools
- Console is cleared before launching

**Configuration:**
```
Is this an interactive tool? [Y/n]: y
```

### Non-Interactive Tools

Tools that run and return output (examples: scripts, utilities, commands).

**Characteristics:**
- Output is displayed in CLI Tools interface
- User sees execution results
- Can show success/failure messages
- Prompts "Press any key to continue" after execution

**Configuration:**
```
Is this an interactive tool? [Y/n]: n
```

## Parameters

Static values passed to the tool every time it runs. Use parameters for:
- Configuration values
- API endpoints
- Default flags
- File paths
- Environment settings

### Examples

**API-based Tool:**
```
Parameter name: ApiUrl
Parameter value: https://api.example.com/v1

Parameter name: Timeout
Parameter value: 30

Parameter name: Format
Parameter value: json
```

**Script with Configuration:**
```
Parameter name: ConfigPath
Parameter value: C:\Config\app.json

Parameter name: LogLevel
Parameter value: Debug

Parameter name: EnableCache
Parameter value: true
```

**How Parameters are Used:**

For PowerShell scripts:
```powershell
pwsh.exe -ExecutionPolicy Bypass -NoProfile -File "script.ps1" -ApiUrl "https://api.example.com/v1" -Timeout "30"
```

For executables:
```
tool.exe --ApiUrl "https://api.example.com/v1" --Timeout "30"
```

## Runtime Arguments

Values prompted from the user each time the tool is run. Use runtime arguments for:
- File paths that change each execution
- Search queries
- Docker image names
- User-specific inputs
- Dynamic values

### Examples

**Docker Image Explorer:**
```
Argument name: image
Prompt text: Select Docker image to explore
Is required? [Y/n]: y
Default value: (leave empty)
```

**File Processor:**
```
Argument name: inputFile
Prompt text: Enter path to input file
Is required? [Y/n]: y
Default value: ./input.txt

Argument name: outputFormat
Prompt text: Output format (json, xml, csv)
Is required? [Y/n]: n
Default value: json
```

**Search Tool:**
```
Argument name: query
Prompt text: Enter search query
Is required? [Y/n]: y

Argument name: maxResults
Prompt text: Maximum number of results
Is required? [Y/n]: n
Default value: 10
```

## Complete Import Examples

### Example 1: Simple Utility Script

```
Step 1: Basic Information
Tool Name: System Info
Description: Display system information
Version: 1.0.0

Step 2: Tool Type
Tool Type: PowerShell Script (.ps1)
Script Path: C:\Scripts\system-info.ps1

Step 3: Verification
Test tool execution? [Y/n]: y
✓ Tool execution test passed

Step 4: Interactivity
Is this an interactive tool? [Y/n]: n

Step 5: Parameters
Add static parameters? [y/N]: n

Step 6: Runtime Arguments
Add runtime arguments? [y/N]: n

Step 7: Review Configuration
Proceed with import? [Y/n]: y
✓ Tool 'System Info' imported successfully!
```

### Example 2: Docker Container Manager

```
Step 1: Basic Information
Tool Name: Container Manager
Description: Manage Docker containers with easy commands
Version: 2.1.0

Step 2: Tool Type
Tool Type: PowerShell Script (.ps1)
Script Path: F:\Docker\manage-containers.ps1

Step 3: Verification
Test tool execution? [Y/n]: y
✓ Tool execution test passed

Step 4: Interactivity
Is this an interactive tool? [Y/n]: n

Step 5: Parameters
Add static parameters? [y/N]: y
Parameter name: ApiVersion
Parameter value: v1.43
✓ Parameter added: ApiVersion = v1.43
Add another parameter? [y/N]: n

Step 6: Runtime Arguments
Add runtime arguments? [y/N]: y

Argument name: action
Prompt text: Action (start, stop, restart, remove)
Is required? [Y/n]: y
Default value: start
✓ Runtime argument added: action

Add another runtime argument? [y/N]: y

Argument name: containerName
Prompt text: Container name or ID
Is required? [Y/n]: y
Default value: (leave empty)
✓ Runtime argument added: containerName

Add another runtime argument? [y/N]: n

Step 7: Review Configuration
Tool Configuration Summary:
  Name:        Container Manager
  Description: Manage Docker containers with easy commands
  Command:     manage-containers.ps1
  Version:     2.1.0
  Interactive: False
  Parameters:
    • ApiVersion = v1.43
  Runtime Args:
    • action (required): Action (start, stop, restart, remove)
    • containerName (required): Container name or ID

Proceed with import? [Y/n]: y
✓ Tool 'Container Manager' imported successfully!
```

### Example 3: Interactive Terminal Tool

```
Step 1: Basic Information
Tool Name: File Manager
Description: Midnight Commander file manager
Version: 4.8.30

Step 2: Tool Type
Tool Type: Executable on PATH
Executable Name: mc

Step 3: Verification
Test tool execution? [Y/n]: y
✓ Tool execution test passed

Step 4: Interactivity
Is this an interactive tool? [Y/n]: y

Step 5: Parameters
Add static parameters? [y/N]: n

Step 6: Runtime Arguments
Add runtime arguments? [y/N]: n

Step 7: Review Configuration
Tool Configuration Summary:
  Name:        File Manager
  Description: Midnight Commander file manager
  Command:     mc
  Version:     4.8.30
  Interactive: True

Proceed with import? [Y/n]: y
✓ Tool 'File Manager' imported successfully!
```

## Configuration File Structure

After import, tools are added to `appsettings.json`:

```json
{
  "AppSettings": {
    "ApplicationName": "HemSoft CLI Tools",
    "ApplicationVersion": "V1.1",
    "ScriptsDirectory": "scripts",
    "CliTools": [
      {
        "Name": "System Info",
        "Description": "Display system information",
        "Command": "system-info.ps1",
        "Version": "1.0.0",
        "IsInteractive": false,
        "Parameters": {}
      },
      {
        "Name": "Container Manager",
        "Description": "Manage Docker containers with easy commands",
        "Command": "manage-containers.ps1",
        "Version": "2.1.0",
        "IsInteractive": false,
        "Parameters": {
          "ApiVersion": "v1.43"
        },
        "RuntimeArguments": [
          {
            "Name": "action",
            "Prompt": "Action (start, stop, restart, remove)",
            "Required": true,
            "DefaultValue": "start"
          },
          {
            "Name": "containerName",
            "Prompt": "Container name or ID",
            "Required": true
          }
        ]
      },
      {
        "Name": "File Manager",
        "Description": "Midnight Commander file manager",
        "Command": "mc",
        "Version": "4.8.30",
        "IsInteractive": true,
        "Parameters": {}
      }
    ]
  }
}
```

## Manual Configuration Edits

After importing, you can manually edit `appsettings.json` to:

- Adjust parameter values
- Modify runtime argument prompts
- Change tool descriptions
- Update versions
- Reorder tools in the menu
- Add complex parameter structures

**Backup**: The import tool automatically creates `appsettings.json.backup` before making changes.

## Troubleshooting

### Tool Not Found

**Problem**: Import wizard reports tool not found
**Solution**:
- Verify the executable is on PATH: `Get-Command <tool-name>`
- Use full path instead of PATH-based import
- Install the tool before importing

### Script Copy Failed

**Problem**: Script cannot be copied to scripts directory
**Solution**:
- Check file permissions
- Verify source script path is correct
- Ensure scripts directory exists

### Tool Execution Test Failed

**Problem**: Test execution fails
**Solution**:
- Some tools don't support `--help` flag
- Choose "Continue anyway" if you know the tool works
- Verify tool has execute permissions

### Runtime Arguments Not Showing

**Problem**: Runtime arguments aren't prompted when running the tool
**Solution**:
- Verify `RuntimeArguments` array is in configuration
- Check argument names don't conflict with parameters
- Ensure configuration was saved properly

## Best Practices

1. **Naming**: Use clear, descriptive names for tools
2. **Descriptions**: Write concise, helpful descriptions (1-2 sentences)
3. **Versions**: Track versions to know when updates are needed
4. **Parameters**: Use parameters for values that rarely change
5. **Runtime Args**: Use runtime arguments for values that change often
6. **Testing**: Always test tool execution during import
7. **Documentation**: Add README entries for complex tools
8. **Backups**: Keep backups before making configuration changes

## Advanced Topics

### Custom Script Parameters

For PowerShell scripts with advanced parameter handling:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$ApiUrl,

    [Parameter(Mandatory=$false)]
    [int]$Timeout = 30,

    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)
```

Import configuration:
```
Parameters:
  - ApiUrl: https://api.example.com
  - Timeout: 60
  - Verbose: true
```

### Dynamic Parameter Values

For tools that need environment-specific values, use PowerShell environment variables:

```powershell
$apiUrl = $env:API_URL ?? $ApiUrl
```

This allows overriding via environment while maintaining defaults.

### Handling Tool Updates

When a tool is updated:

1. Run import wizard again with same name
2. Choose "Update existing tool" when prompted
3. Update version number
4. Review configuration changes
5. Test the updated tool

## Security Considerations

- **Script Source**: Only import scripts from trusted sources
- **Permissions**: Verify scripts have appropriate file permissions
- **Parameters**: Avoid storing sensitive data in parameters
- **Validation**: Review generated configuration before saving
- **Backups**: Keep configuration backups for rollback

## Support

For issues or questions:
- Check configuration in `appsettings.json`
- Review import tool output for error messages
- Verify tool exists and is accessible
- Test tool manually before importing
- Check CLI Tools logs for detailed error information
