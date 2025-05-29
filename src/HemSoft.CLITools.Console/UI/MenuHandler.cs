namespace HemSoft.CLITools.Console.UI;

using HemSoft.CLITools.Console.Models;
using HemSoft.CLITools.Console.Services;
using Spectre.Console;

/// <summary>
/// Handles the CLI tools menu
/// </summary>
public class MenuHandler
{
    private readonly CliToolService _cliToolService;

    /// <summary>
    /// Initializes a new instance of the <see cref="MenuHandler"/> class.
    /// </summary>
    /// <param name="cliToolService">The CLI tool service</param>
    public MenuHandler(CliToolService cliToolService)
    {
        _cliToolService = cliToolService;
    }

    /// <summary>
    /// Shows the main menu
    /// </summary>
    public void ShowMainMenu()
    {
        bool exitRequested = false;

        while (!exitRequested)
        {
            AnsiConsole.Clear();
            DisplayHeader();

            var cliTools = _cliToolService.GetAllCliTools();
            var selection = ShowSelectionPrompt(cliTools);

            if (selection == "Exit")
            {
                exitRequested = true;
            }
            else
            {
                var selectedTool = _cliToolService.GetCliToolByName(selection);
                if (selectedTool != null)
                {
                    // Run the tool directly without confirmation
                    AnsiConsole.Status()
                        .Start($"Running {selectedTool.Name}...", ctx =>
                        {
                            _cliToolService.RunCliTool(selectedTool);
                        });
                }

                AnsiConsole.WriteLine();
                AnsiConsole.WriteLine("Press any key to return to the main menu...");
                System.Console.ReadKey(true);
            }
        }
    }

    /// <summary>
    /// Displays the header
    /// </summary>
    private static void DisplayHeader()
    {
        AnsiConsole.Write(
            new FigletText("HemSoft CLI Tools")
                .Centered()
                .Color(Color.Blue));

        AnsiConsole.WriteLine();
    }

    /// <summary>
    /// Shows the selection prompt with tool descriptions
    /// </summary>
    /// <param name="cliTools">The CLI tools</param>
    /// <returns>The selected option</returns>
    private static string ShowSelectionPrompt(IReadOnlyList<CliTool> cliTools)
    {
        // Create a dictionary to map display strings to tool names
        var displayMap = new Dictionary<string, string>();
        var choices = new List<string>();

        // Create formatted display strings with descriptions
        foreach (var tool in cliTools)
        {
            string displayText = $"[green]{tool.Name}[/] - [grey]{tool.Description}[/]";
            displayMap[displayText] = tool.Name;
            choices.Add(displayText);
        }

        // Add exit option
        choices.Add("[red]Exit[/]");
        displayMap["[red]Exit[/]"] = "Exit";

        var prompt = new SelectionPrompt<string>()
            .Title("Select a CLI tool to run:")
            .PageSize(10)
            .HighlightStyle(new Style(Color.Blue))
            .MoreChoicesText("[grey](Move up and down to reveal more tools)[/]")
            .AddChoices(choices);

        // Get the selected display string and map it back to the tool name
        string selectedDisplay = AnsiConsole.Prompt(prompt);
        return displayMap[selectedDisplay];
    }

    /// <summary>
    /// Displays the details of a CLI tool
    /// </summary>
    /// <param name="cliTool">The CLI tool</param>
    private static void DisplayToolDetails(CliTool cliTool)
    {
        AnsiConsole.Clear();

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Blue)
            .AddColumn(new TableColumn("Property").Centered())
            .AddColumn(new TableColumn("Value").Centered());

        table.AddRow("[yellow]Name[/]", cliTool.Name);
        table.AddRow("[yellow]Description[/]", cliTool.Description);
        table.AddRow("[yellow]Command[/]", cliTool.Command);
        table.AddRow("[yellow]Version[/]", cliTool.Version);

        AnsiConsole.Write(table);
        AnsiConsole.WriteLine();
    }
}
