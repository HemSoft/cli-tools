namespace HemSoft.CLITools.Console;

using HemSoft.CLITools.Console.Services;
using HemSoft.CLITools.Console.UI;
using Microsoft.Extensions.DependencyInjection;
using Spectre.Console;

public class Program
{
    public static void Main(string[] args)
    {
        try
        {
            // Set up dependency injection
            var serviceProvider = ConfigureServices();

            // Get the menu handler from the service provider
            var menuHandler = serviceProvider.GetRequiredService<MenuHandler>();

            // Show the main menu
            menuHandler.ShowMainMenu();
        }
        catch (Exception ex)
        {
            AnsiConsole.WriteException(ex);
            return;
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
