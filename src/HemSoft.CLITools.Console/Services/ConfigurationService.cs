namespace HemSoft.CLITools.Console.Services;

using HemSoft.CLITools.Console.Models;
using Microsoft.Extensions.Configuration;
using System.IO;

/// <summary>
/// Service for managing application configuration
/// </summary>
public class ConfigurationService
{
    private readonly IConfiguration _configuration;
    private readonly AppSettings _appSettings;

    /// <summary>
    /// Initializes a new instance of the <see cref="ConfigurationService"/> class.
    /// </summary>
    public ConfigurationService()
    {
        // Get the base directory of the application
        string basePath = AppContext.BaseDirectory;

        // Build configuration
        _configuration = new ConfigurationBuilder()
            .SetBasePath(basePath)
            .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
            .AddJsonFile("appsettings.user.json", optional: true, reloadOnChange: true)
            .Build();

        // Bind configuration to settings
        _appSettings = _configuration.GetSection("AppSettings").Get<AppSettings>() ?? new AppSettings();

        // Ensure we have at least an empty list if no CLI tools were configured
        if (_appSettings.CliTools == null)
        {
            _appSettings.CliTools = new List<CliToolConfig>();
        }
    }

    /// <summary>
    /// Gets the application settings
    /// </summary>
    public AppSettings AppSettings => _appSettings;

    /// <summary>
    /// Gets a configuration value
    /// </summary>
    /// <param name="key">The configuration key</param>
    /// <returns>The configuration value</returns>
    public string GetValue(string key) => _configuration[key] ?? string.Empty;

    /// <summary>
    /// Gets a configuration section
    /// </summary>
    /// <param name="key">The configuration key</param>
    /// <returns>The configuration section</returns>
    public IConfigurationSection GetSection(string key) => _configuration.GetSection(key);

    /// <summary>
    /// Gets the script path for a command
    /// </summary>
    /// <param name="command">The command</param>
    /// <returns>The script path</returns>
    public string GetScriptPath(string command)
    {
        return Path.Combine(_appSettings.ScriptsDirectory, command);
    }
}
