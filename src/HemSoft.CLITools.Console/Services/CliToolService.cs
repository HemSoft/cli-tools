namespace HemSoft.CLITools.Console.Services;

using HemSoft.CLITools.Console.Models;
using Spectre.Console;
using System.Diagnostics;
using System.Text;

/// <summary>
/// Service for managing CLI tools
/// </summary>
public class CliToolService
{
    private readonly ConfigurationService _configurationService;
    private readonly List<CliTool> _cliTools = new List<CliTool>();

    /// <summary>
    /// Initializes a new instance of the <see cref="CliToolService"/> class.
    /// </summary>
    /// <param name="configurationService">The configuration service</param>
    public CliToolService(ConfigurationService configurationService)
    {
        _configurationService = configurationService;
        LoadCliToolsFromConfiguration();
    }

    /// <summary>
    /// Loads CLI tools from configuration
    /// </summary>
    private void LoadCliToolsFromConfiguration()
    {
        var cliToolConfigs = _configurationService.AppSettings.CliTools;

        foreach (var config in cliToolConfigs)
        {
            _cliTools.Add(new CliTool
            {
                Name = config.Name,
                Description = config.Description,
                Command = config.Command,
                Version = config.Version,
                IsInteractive = config.IsInteractive,
                RuntimeArguments = config.RuntimeArguments
            });
        }
    }

    /// <summary>
    /// Gets all CLI tools in the catalog
    /// </summary>
    /// <returns>A list of CLI tools</returns>
    public IReadOnlyList<CliTool> GetAllCliTools() => _cliTools.AsReadOnly();

    /// <summary>
    /// Gets a CLI tool by name
    /// </summary>
    /// <param name="name">The name of the CLI tool</param>
    /// <returns>The CLI tool if found; otherwise, null</returns>
    public CliTool? GetCliToolByName(string name) =>
        _cliTools.FirstOrDefault(t => t.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Gets Docker images available on the system
    /// </summary>
    /// <returns>A list of Docker image names</returns>
    private List<string> GetDockerImages()
    {
        var images = new List<string>();
        try
        {
            using var process = new Process();
            process.StartInfo = new ProcessStartInfo
            {
                FileName = "docker",
                Arguments = "images --format \"table {{.Repository}}:{{.Tag}}\\t{{.Size}}\"",
                UseShellExecute = true,
                CreateNoWindow = true
            };

            // Use UseShellExecute = true for proper command formatting
            process.Start();
            process.WaitForExit();

            // Alternatively, use JSON output which is more reliable
            using var jsonProcess = new Process();
            jsonProcess.StartInfo = new ProcessStartInfo
            {
                FileName = "docker",
                Arguments = "images --format json",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            jsonProcess.Start();
            string jsonOutput = jsonProcess.StandardOutput.ReadToEnd();
            jsonProcess.WaitForExit();

            if (jsonProcess.ExitCode == 0 && !string.IsNullOrWhiteSpace(jsonOutput))
            {
                // Parse JSON output
                var lines = jsonOutput.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries);
                foreach (var line in lines)
                {
                    try
                    {
                        // Simple JSON parsing to extract Repository and Tag
                        if (line.Contains("\"Repository\"") && line.Contains("\"Tag\""))
                        {
                            var repoMatch = System.Text.RegularExpressions.Regex.Match(line, @"""Repository""\s*:\s*""([^""]*)""");
                            var tagMatch = System.Text.RegularExpressions.Regex.Match(line, @"""Tag""\s*:\s*""([^""]*)""");

                            if (repoMatch.Success && tagMatch.Success)
                            {
                                string repo = repoMatch.Groups[1].Value;
                                string tag = tagMatch.Groups[1].Value;

                                if (!repo.Contains("<none>") && !tag.Contains("<none>") && !string.IsNullOrWhiteSpace(repo))
                                {
                                    string imageName = $"{repo}:{tag}";
                                    if (!images.Contains(imageName))
                                    {
                                        images.Add(imageName);
                                    }
                                }
                            }
                        }
                    }
                    catch
                    {
                        // Skip malformed lines
                    }
                }
            }
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[yellow]Warning: Could not fetch Docker images: {ex.Message}[/]");
        }

        return images;
    }

    /// <summary>
    /// Runs a CLI tool and displays its output
    /// </summary>
    /// <param name="cliTool">The CLI tool to run</param>
    /// <returns>True if the tool executed successfully; otherwise, false</returns>
    public bool RunCliTool(CliTool cliTool)
    {
        bool success = false;

        // Prompt for runtime arguments if needed
        Dictionary<string, string> runtimeArgs = new Dictionary<string, string>();
        if (cliTool.RuntimeArguments != null && cliTool.RuntimeArguments.Count > 0)
        {
            foreach (var arg in cliTool.RuntimeArguments)
            {
                string value;

                // Check if this argument has a data source for dynamic selection
                if (arg.Name == "image" && cliTool.Name == "Docker Image Explorer")
                {
                    // Fetch Docker images and show selection prompt
                    var dockerImages = GetDockerImages();
                    if (dockerImages.Count > 0)
                    {
                        value = AnsiConsole.Prompt(
                            new SelectionPrompt<string>()
                                .Title($"[yellow]{arg.Prompt}[/]")
                                .AddChoices(dockerImages));
                    }
                    else
                    {
                        AnsiConsole.MarkupLine("[red]No Docker images found. Please enter image name manually:[/]");
                        value = AnsiConsole.Ask<string>($"[yellow]{arg.Prompt}[/]");
                    }
                }
                else if (!string.IsNullOrEmpty(arg.DefaultValue))
                {
                    value = AnsiConsole.Ask<string>($"[yellow]{arg.Prompt}[/]", arg.DefaultValue);
                }
                else if (arg.Required)
                {
                    value = AnsiConsole.Ask<string>($"[yellow]{arg.Prompt}[/]");
                }
                else
                {
                    value = AnsiConsole.Prompt(
                        new TextPrompt<string>($"[yellow]{arg.Prompt}[/]")
                            .AllowEmpty());
                }

                if (!string.IsNullOrEmpty(value))
                {
                    runtimeArgs[arg.Name] = value;
                }
            }
        }

        // Skip console output for interactive tools
        if (!cliTool.IsInteractive)
        {
            AnsiConsole.MarkupLine($"Executing command: [green]{cliTool.Command}[/]");
            AnsiConsole.WriteLine();
        }

        try
        {
            // Get the tool configuration to access parameters
            var toolConfig = _configurationService.AppSettings.CliTools
                .FirstOrDefault(t => t.Name.Equals(cliTool.Name, StringComparison.OrdinalIgnoreCase));

            string fileName;
            string arguments;

            // Check if it's an interactive tool based on configuration
            bool isInteractiveTool = cliTool.IsInteractive;

            // Determine if this is a PowerShell script or direct executable
            if (cliTool.Command.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))
            {
                // PowerShell script execution - run in the current console window
                string scriptPath = _configurationService.GetScriptPath(cliTool.Command);

                // Build arguments string with parameters if available
                StringBuilder argumentsBuilder = new StringBuilder();
                argumentsBuilder.Append($"-ExecutionPolicy Bypass -NoProfile -File \"{scriptPath}\"");

                if (toolConfig?.Parameters != null && toolConfig.Parameters.Count > 0)
                {
                    // Add parameters as PowerShell parameters
                    foreach (var param in toolConfig.Parameters)
                    {
                        argumentsBuilder.Append($" -{param.Key} \"{param.Value}\"");
                    }
                }

                fileName = "pwsh.exe";
                arguments = argumentsBuilder.ToString();
            }
            else
            {
                // Direct executable
                fileName = cliTool.Command;

                // Build arguments for direct executables
                StringBuilder argumentsBuilder = new StringBuilder();
                if (toolConfig?.Parameters != null && toolConfig.Parameters.Count > 0)
                {
                    foreach (var param in toolConfig.Parameters)
                    {
                        argumentsBuilder.Append($" --{param.Key} \"{param.Value}\"");
                    }
                }

                // Add runtime arguments
                if (runtimeArgs.Count > 0)
                {
                    foreach (var arg in runtimeArgs)
                    {
                        argumentsBuilder.Append($" {arg.Value}");
                    }
                }

                arguments = argumentsBuilder.ToString().Trim();
            }

            // Create a new process
            using var process = new Process();

            // Run in the same console window - do NOT use UseShellExecute = true as it creates new windows
            process.StartInfo = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = false,
                RedirectStandardOutput = false,
                RedirectStandardError = false,
                RedirectStandardInput = false
            };

            // Start the process
            process.Start();

            // Wait for the process to exit
            process.WaitForExit();

            // Check the exit code
            success = process.ExitCode == 0;

            // Skip success/failure messages for interactive tools
            if (!isInteractiveTool)
            {
                if (success)
                {
                    AnsiConsole.WriteLine();
                    AnsiConsole.MarkupLine("[green]Tool executed successfully![/]");
                }
                else
                {
                    AnsiConsole.WriteLine();
                    AnsiConsole.MarkupLine($"[red]Tool execution failed (exit code: {process.ExitCode})[/]");
                    AnsiConsole.MarkupLine("[yellow]Check the output above for more details about the error.[/]");
                }
            }
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Error running tool: {ex.Message}[/]");
        }

        return success;
    }
}
