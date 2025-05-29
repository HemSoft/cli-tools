namespace HemSoft.CLITools.Console.Models;

/// <summary>
/// Represents the configuration for a CLI tool
/// </summary>
public class CliToolConfig
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
    
    /// <summary>
    /// Gets or sets the parameters for the CLI tool
    /// </summary>
    public Dictionary<string, string> Parameters { get; set; } = new Dictionary<string, string>();
}
