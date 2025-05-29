namespace HemSoft.CLITools.Console.Models;

/// <summary>
/// Represents a CLI tool in the catalog
/// </summary>
public class CliTool
{
    /// <summary>
    /// Gets or sets the name of the CLI tool
    /// </summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>
    /// Gets or sets the description of the CLI tool
    /// </summary>
    public string Description { get; set; } = string.Empty;
    
    /// <summary>
    /// Gets or sets the command to execute the CLI tool
    /// </summary>
    public string Command { get; set; } = string.Empty;
    
    /// <summary>
    /// Gets or sets the version of the CLI tool
    /// </summary>
    public string Version { get; set; } = string.Empty;
}
