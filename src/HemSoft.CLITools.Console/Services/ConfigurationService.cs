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
    private readonly bool _isEmbeddedMode;
    private readonly string _resolvedScriptsDirectory;
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
            _appSettings.CliTools = [];
        }

        // Determine scripts directory: prefer physical 'scripts' folder next to app
        // This supports both 'dotnet run' (bin/.../) and published output (publish/ or F:\Tools)
        _resolvedScriptsDirectory = Path.GetFullPath(Path.Combine(basePath, _appSettings.ScriptsDirectory));

        bool hasPhysicalScripts = Directory.Exists(_resolvedScriptsDirectory) &&
                      Directory.EnumerateFiles(_resolvedScriptsDirectory, "*.ps1").Any();

        // Check if we're running as a single-file/embedded deployment requiring extraction
        _isEmbeddedMode = !hasPhysicalScripts && IsRunningAsEmbeddedDeployment();

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

        // Prefer resolved scripts directory next to the app
        string candidate = Path.Combine(_resolvedScriptsDirectory, command);
        if (File.Exists(candidate))
        {
            return candidate;
        }

        // Fallback to AppSettings.ScriptsDirectory relative to current working dir (legacy behavior)
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

            // Derive the expected filename (e.g., update-n8n.ps1) from resource name
            // Prefer segment after ".scripts." if present, otherwise take the substring after the
            // last dot before the extension. This handles typical resource names like:
            //   HemSoft.CLITools.Console.scripts.update-n8n.ps1  => update-n8n.ps1
            //   HemSoft.CLITools.Console.update-openwebui.ps1    => update-openwebui.ps1
            string scriptFileName;
            const string scriptsMarker = ".scripts.";
            int markerIndex = resourceName.IndexOf(scriptsMarker, StringComparison.OrdinalIgnoreCase);
            if (markerIndex >= 0)
            {
                scriptFileName = resourceName[(markerIndex + scriptsMarker.Length)..];
            }
            else
            {
                int extIndex = resourceName.LastIndexOf(".ps1", StringComparison.OrdinalIgnoreCase);
                if (extIndex > 0)
                {
                    int prevDot = resourceName.LastIndexOf('.', extIndex - 1);
                    scriptFileName = prevDot >= 0
                        ? resourceName[(prevDot + 1)..]
                        : resourceName; // Fallback: use full name (unlikely)
                }
                else
                {
                    scriptFileName = resourceName; // Fallback
                }
            }

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
