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
    public Dictionary<string, string> Parameters { get; set; } = [];

    /// <summary>
    /// Gets or sets whether the tool is interactive and should be launched in a separate terminal window
    /// </summary>
    public bool IsInteractive { get; set; } = false;

    /// <summary>
    /// Gets or sets the runtime arguments that should be prompted from the user before running the tool
    /// </summary>
    public List<RuntimeArgument> RuntimeArguments { get; set; } = [];
}

/// <summary>
/// Represents a runtime argument that should be prompted from the user
/// </summary>
public class RuntimeArgument
{
    /// <summary>
    /// Gets or sets the name/key of the argument
    /// </summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the prompt text to display to the user
    /// </summary>
    public string Prompt { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets whether the argument is required
    /// </summary>
    public bool Required { get; set; } = true;

    /// <summary>
    /// Gets or sets the default value for the argument
    /// </summary>
    public string? DefaultValue { get; set; }
}
