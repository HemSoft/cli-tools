namespace HemSoft.CLITools.Console.Models;

/// <summary>
/// Represents the application settings
/// </summary>
public class AppSettings
{
    /// <summary>
    /// Gets or sets the application name
    /// </summary>
    public string ApplicationName { get; set; } = "HemSoft CLI Tools";
    
    /// <summary>
    /// Gets or sets the application version
    /// </summary>
    public string ApplicationVersion { get; set; } = "1.0.0";
    
    /// <summary>
    /// Gets or sets the default scripts directory
    /// </summary>
    public string ScriptsDirectory { get; set; } = "scripts";
    
    /// <summary>
    /// Gets or sets the CLI tools
    /// </summary>
    public List<CliToolConfig> CliTools { get; set; } = new List<CliToolConfig>();
}
