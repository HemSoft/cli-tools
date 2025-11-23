namespace HemSoft.CLITools.Console;

using HemSoft.CLITools.Console.Services;
using HemSoft.CLITools.Console.UI;
using Microsoft.Extensions.DependencyInjection;
using Spectre.Console;

/// <summary>
/// The main entry point for the application.
/// </summary>
public static class Program
{
    /// <summary>
    /// The main entry point for the application.
    /// </summary>
    /// <param name="args">The command-line arguments.</param>
    public static void Main(string[] args)
    {
        try
        {
            // Set up dependency injection
            using var serviceProvider = ConfigureServices();

            // Get the menu handler from the service provider
            var menuHandler = serviceProvider.GetRequiredService<MenuHandler>();

            // Show the main menu
            menuHandler.ShowMainMenu();
        }
        catch (Exception ex)
        {
            AnsiConsole.WriteException(ex);
        }
    }

    /// <summary>
    /// Configures the services for dependency injection
    /// </summary>
    /// <returns>The service provider</returns>
    private static ServiceProvider ConfigureServices()
    {
        var services = new ServiceCollection();

        // Register services
        services.AddSingleton<ConfigurationService>();
        services.AddSingleton<CliToolService>();
        services.AddSingleton<MenuHandler>();

        return services.BuildServiceProvider();
    }
}
