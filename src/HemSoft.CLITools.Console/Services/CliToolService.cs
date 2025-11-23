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
    private readonly List<CliTool> _cliTools = [];

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
    private static List<string> GetDockerImages()
    {
        var images = new List<string>();
        try
        {
            string jsonOutput = ExecuteDockerImagesCommand();
            if (!string.IsNullOrWhiteSpace(jsonOutput))
            {
                images.AddRange(ParseDockerImagesOutput(jsonOutput));
            }
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[yellow]Warning: Could not fetch Docker images: {ex.Message}[/]");
        }

        return images;
    }

    private static string ExecuteDockerImagesCommand()
    {
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

        return jsonProcess.ExitCode == 0 ? jsonOutput : string.Empty;
    }

    private static List<string> ParseDockerImagesOutput(string jsonOutput)
    {
        var images = new List<string>();
        var lines = jsonOutput.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries);

        foreach (var line in lines)
        {
            if (TryExtractImageName(line, out var imageName) && !images.Contains(imageName!))
            {
                images.Add(imageName!);
            }
        }

        return images;
    }

    private static bool TryExtractImageName(string line, out string? imageName)
    {
        imageName = null;
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
                        imageName = $"{repo}:{tag}";
                        return true;
                    }
                }
            }
        }
        catch
        {
            // Skip malformed lines
        }
        return false;
    }

    /// <summary>
    /// Runs the import tool script to add a new tool to the ecosystem
    /// </summary>
    public void RunImportTool()
    {
        try
        {
            string importScriptPath = _configurationService.GetScriptPath("import-tool.ps1");

            if (!File.Exists(importScriptPath))
            {
                AnsiConsole.MarkupLine("[red]Error: import-tool.ps1 script not found![/]");
                AnsiConsole.MarkupLine($"[yellow]Expected location: {importScriptPath}[/]");
                AnsiConsole.WriteLine();
                AnsiConsole.WriteLine("Press any key to return to the main menu...");
                System.Console.ReadKey(true);
                return;
            }

            using var process = new Process();
            process.StartInfo = new ProcessStartInfo
            {
                FileName = "pwsh.exe",
                Arguments = $"-ExecutionPolicy Bypass -NoProfile -File \"{importScriptPath}\"",
                UseShellExecute = false,
                CreateNoWindow = false,
                RedirectStandardOutput = false,
                RedirectStandardError = false,
                RedirectStandardInput = false
            };

            process.Start();
            process.WaitForExit();
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Error running import tool: {ex.Message}[/]");
            AnsiConsole.WriteLine();
            AnsiConsole.WriteLine("Press any key to return to the main menu...");
            System.Console.ReadKey(true);
        }
    }

    /// <summary>
    /// Runs a CLI tool and displays its output
    /// </summary>
    /// <param name="cliTool">The CLI tool to run</param>
    /// <returns>True if the tool executed successfully; otherwise, false</returns>
    public bool RunCliTool(CliTool cliTool)
    {
        // Prompt for runtime arguments if needed
        var runtimeArgs = CollectRuntimeArguments(cliTool);

        // Skip console output for interactive tools
        if (!cliTool.IsInteractive)
        {
            AnsiConsole.MarkupLine($"Executing command: [green]{cliTool.Command}[/]");
            AnsiConsole.WriteLine();
        }

        try
        {
            var startInfo = PrepareProcessStartInfo(cliTool, runtimeArgs);
            return ExecuteProcess(startInfo, cliTool.IsInteractive);
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Error running tool: {ex.Message}[/]");
            return false;
        }
    }

    private static Dictionary<string, string> CollectRuntimeArguments(CliTool cliTool)
    {
        Dictionary<string, string> runtimeArgs = [];
        if (cliTool.RuntimeArguments == null || cliTool.RuntimeArguments.Count == 0)
        {
            return runtimeArgs;
        }

        foreach (var arg in cliTool.RuntimeArguments)
        {
            string value;

            // Check if this argument has a data source for dynamic selection
            if (arg.Name == "image" && cliTool.Name == "Docker Image Explorer")
            {
                value = PromptForDockerImage(arg);
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
        return runtimeArgs;
    }

    private static string PromptForDockerImage(RuntimeArgument arg)
    {
        // Fetch Docker images and show selection prompt
        var dockerImages = GetDockerImages();
        if (dockerImages.Count > 0)
        {
            return AnsiConsole.Prompt(
                new SelectionPrompt<string>()
                    .Title($"[yellow]{arg.Prompt}[/]")
                    .AddChoices(dockerImages));
        }
        else
        {
            AnsiConsole.MarkupLine("[red]No Docker images found. Please enter image name manually:[/]");
            return AnsiConsole.Ask<string>($"[yellow]{arg.Prompt}[/]");
        }
    }

    private ProcessStartInfo PrepareProcessStartInfo(CliTool cliTool, Dictionary<string, string> runtimeArgs)
    {
        // Get the tool configuration to access parameters
        var toolConfig = _configurationService.AppSettings.CliTools
            .FirstOrDefault(t => t.Name.Equals(cliTool.Name, StringComparison.OrdinalIgnoreCase));

        string fileName;
        string arguments;

        // Determine if this is a PowerShell script or direct executable
        if (cliTool.Command.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))
        {
            (fileName, arguments) = PreparePowerShellCommand(cliTool, toolConfig);
        }
        else
        {
            (fileName, arguments) = PrepareExecutableCommand(cliTool, toolConfig, runtimeArgs);
        }

        // For interactive tools, we need UseShellExecute = false to run in same console
        // For non-interactive tools, UseShellExecute = true handles PATH resolution better
        bool useShellExecute = !cliTool.IsInteractive && !Path.IsPathRooted(fileName);

        return new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            UseShellExecute = useShellExecute,
            CreateNoWindow = false,
            RedirectStandardOutput = false,
            RedirectStandardError = false,
            RedirectStandardInput = false
        };
    }

    private (string fileName, string arguments) PreparePowerShellCommand(CliTool cliTool, CliToolConfig? toolConfig)
    {
        // PowerShell script execution - run in the current console window
        string scriptPath;

        // Check if the command is a full path
        if (Path.IsPathRooted(cliTool.Command))
        {
            if (File.Exists(cliTool.Command))
            {
                scriptPath = cliTool.Command;
            }
            else
            {
                throw new FileNotFoundException($"PowerShell script not found at specified path: {cliTool.Command}");
            }
        }
        else
        {
            scriptPath = _configurationService.GetScriptPath(cliTool.Command);
        }

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

        return ("pwsh.exe", argumentsBuilder.ToString());
    }

    private static (string fileName, string arguments) PrepareExecutableCommand(CliTool cliTool, CliToolConfig? toolConfig, Dictionary<string, string> runtimeArgs)
    {
        // Direct executable
        string fileName = cliTool.Command;

        // Check if the command is a full path or needs to be resolved
        if (Path.IsPathRooted(fileName) && !File.Exists(fileName))
        {
            // Full path specified but file doesn't exist
            throw new FileNotFoundException($"Executable not found at specified path: {fileName}");
        }

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

        return (fileName, argumentsBuilder.ToString().Trim());
    }

    private static bool ExecuteProcess(ProcessStartInfo startInfo, bool isInteractive)
    {
        using var process = new Process();
        process.StartInfo = startInfo;

        process.Start();
        process.WaitForExit();

        bool success = process.ExitCode == 0;

        if (!isInteractive)
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

        return success;
    }
}
