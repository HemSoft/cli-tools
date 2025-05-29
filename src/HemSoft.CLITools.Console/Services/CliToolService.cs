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
                Version = config.Version
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
    /// Runs a CLI tool and displays its output
    /// </summary>
    /// <param name="cliTool">The CLI tool to run</param>
    /// <returns>True if the tool executed successfully; otherwise, false</returns>
    public bool RunCliTool(CliTool cliTool)
    {
        bool success = false;

        AnsiConsole.MarkupLine($"Executing command: [green]{cliTool.Command}[/]");
        AnsiConsole.WriteLine();

        try
        {
            // Get the tool configuration to access parameters
            var toolConfig = _configurationService.AppSettings.CliTools
                .FirstOrDefault(t => t.Name.Equals(cliTool.Name, StringComparison.OrdinalIgnoreCase));

            string fileName;
            string arguments;

            // Check if it's an interactive tool first
            var interactiveTools = new[] { "edit", "dive", "lazygit" };
            bool isInteractiveTool = !cliTool.Command.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase) &&
                                   interactiveTools.Contains(cliTool.Command.ToLowerInvariant());

            // Determine if this is a PowerShell script or direct executable
            if (cliTool.Command.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))
            {
                // PowerShell script execution
                string scriptPath = _configurationService.GetScriptPath(cliTool.Command);

                // Build arguments string with parameters if available
                StringBuilder argumentsBuilder = new StringBuilder();
                argumentsBuilder.Append($"-ExecutionPolicy Bypass -Command \"& '{scriptPath}'");

                if (toolConfig?.Parameters != null && toolConfig.Parameters.Count > 0)
                {
                    // Add parameters as PowerShell parameters
                    foreach (var param in toolConfig.Parameters)
                    {
                        // Format the parameter correctly for PowerShell
                        argumentsBuilder.Append($" -\"{param.Key}\" '\"{param.Value}\"'");
                    }
                }

                argumentsBuilder.Append("\"");
                fileName = "powershell.exe";
                arguments = argumentsBuilder.ToString();
            }
            else
            {
                // Direct executable
                if (isInteractiveTool)
                {
                    // For interactive tools, launch in a new terminal window
                    AnsiConsole.MarkupLine("[yellow]Launching interactive tool in a new terminal window...[/]");
                    AnsiConsole.MarkupLine("[grey]The tool will open in a separate window. Close it when you're done.[/]");

                    fileName = "cmd.exe";
                    arguments = $"/c start cmd /k \"{cliTool.Command}\"";
                }
                else
                {
                    // Non-interactive executable
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
                    arguments = argumentsBuilder.ToString().Trim();
                }
            }

            // Create a new process
            using var process = new Process();

            process.StartInfo = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = isInteractiveTool,
                RedirectStandardOutput = !isInteractiveTool,
                RedirectStandardError = !isInteractiveTool,
                CreateNoWindow = !isInteractiveTool
            };

            // Set up event handlers only for non-interactive tools
            if (!isInteractiveTool)
            {
                process.OutputDataReceived += (sender, e) =>
                {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        // Escape any markup characters in the output
                        string escapedData = Markup.Escape(e.Data);
                        AnsiConsole.MarkupLine($"[green]{escapedData}[/]");
                    }
                };

                process.ErrorDataReceived += (sender, e) =>
                {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        // Escape any markup characters in the output
                        string escapedData = Markup.Escape(e.Data);
                        AnsiConsole.MarkupLine($"[red]{escapedData}[/]");
                    }
                };
            }

            // Start the process
            process.Start();

            if (!isInteractiveTool)
            {
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();

                // Wait for the process to exit
                process.WaitForExit();

                // Check the exit code
                success = process.ExitCode == 0;
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
            else
            {
                // For interactive tools, just indicate that it was launched
                AnsiConsole.WriteLine();
                AnsiConsole.MarkupLine("[green]Interactive tool launched successfully![/]");
                success = true;
            }
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Error running tool: {ex.Message}[/]");
        }

        return success;
    }
}
