namespace HemSoft.CLITools.Console.Services;

using HemSoft.CLITools.Console.Models;
using Microsoft.Extensions.Configuration;
using System.IO;
using System.Reflection;

/// <summary>
/// Service for managing application configuration
/// </summary>
public class ConfigurationService : IDisposable
{
    private readonly IConfiguration _configuration;
    private readonly AppSettings _appSettings;
    private readonly string _tempScriptsDirectory;
    private readonly bool _isEmbeddedMode;    /// <summary>
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

        // Check if we're running as a single-file/embedded deployment
        _isEmbeddedMode = IsRunningAsEmbeddedDeployment();

        if (_isEmbeddedMode)
        {
            // Create a temporary directory for extracted scripts
            _tempScriptsDirectory = Path.Combine(Path.GetTempPath(), "HemSoftCLITools", "scripts");
            Directory.CreateDirectory(_tempScriptsDirectory);
            ExtractEmbeddedScripts();
        }
        else
        {
            _tempScriptsDirectory = string.Empty;
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
    public IConfigurationSection GetSection(string key) => _configuration.GetSection(key);    /// <summary>
                                                                                              /// Gets the script path for a command
                                                                                              /// </summary>
                                                                                              /// <param name="command">The command</param>
                                                                                              /// <returns>The script path</returns>
    public string GetScriptPath(string command)
    {
        if (_isEmbeddedMode)
        {
            return Path.Combine(_tempScriptsDirectory, command);
        }

        return Path.Combine(_appSettings.ScriptsDirectory, command);
    }

    /// <summary>
    /// Checks if the application is running as an embedded/single-file deployment
    /// </summary>
    /// <returns>True if running as embedded deployment</returns>
    private static bool IsRunningAsEmbeddedDeployment()
    {
        // Check if we're running from a single file by looking for embedded resources
        var assembly = Assembly.GetExecutingAssembly();
        var resourceNames = assembly.GetManifestResourceNames();

        // Look for any embedded .ps1 scripts
        return resourceNames.Any(name => name.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Extracts embedded scripts to the temporary directory
    /// </summary>
    private void ExtractEmbeddedScripts()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var resourceNames = assembly.GetManifestResourceNames()
            .Where(name => name.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase));
        foreach (var resourceName in resourceNames)
        {
            using var stream = assembly.GetManifestResourceStream(resourceName);
            if (stream == null)
            {
                continue;
            }

            // Extract the script filename from the resource name
            var scriptFileName = Path.GetFileName(resourceName);
            var outputPath = Path.Combine(_tempScriptsDirectory, scriptFileName);

            using var fileStream = File.Create(outputPath);
            stream.CopyTo(fileStream);
        }
    }

    /// <summary>
    /// Cleans up temporary script files when the service is disposed
    /// </summary>
    public void Dispose()
    {
        if (_isEmbeddedMode && Directory.Exists(_tempScriptsDirectory))
        {
            try
            {
                Directory.Delete(_tempScriptsDirectory, recursive: true);
            }
            catch
            {
                // Ignore errors when cleaning up temp files
            }
        }
    }
}
