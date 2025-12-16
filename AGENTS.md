# Agent Instructions

## Architecture Overview

.NET 10 console application providing an interactive menu for launching CLI tools and PowerShell scripts:

```
Program.cs → MenuHandler → CliToolService → ConfigurationService
                              ↓
                         appsettings.json (tool definitions)
```

- **MenuHandler** (`UI/MenuHandler.cs`): Renders Spectre.Console selection menu, handles user input
- **CliToolService** (`Services/CliToolService.cs`): Loads tools from config, executes commands, collects runtime arguments
- **ConfigurationService** (`Services/ConfigurationService.cs`): Manages `appsettings.json`, resolves script paths, handles embedded resource extraction

## Adding New CLI Tools

Tools are defined in `appsettings.json` under `AppSettings.CliTools`. Each tool requires:

- `Name`, `Description`, `Command`, `Version`
- `IsInteractive`: Set to `true` for tools needing full console control (see below)
- `Parameters`: Static key-value pairs passed every invocation
- `RuntimeArguments`: Prompts shown to users before execution

Use the **Import Tool** wizard (first menu option) to add tools interactively.

### IsInteractive Flag

Set `IsInteractive: true` when a tool:

- Has its own TUI (lazygit, broot, mc, glow, fx)
- Requires raw keyboard input or cursor control
- Should not show "Press any key to continue" after execution

When `IsInteractive` is true, the app clears the screen before launch and returns directly to the menu afterward. When false, output is displayed and the user is prompted before returning.

### Tool Command Paths

The `Command` field supports three formats:

1. **Executable on PATH**: `"Command": "lazygit"` — resolved via system PATH
2. **Full path**: `"Command": "C:\\Tools\\mytool.exe"` — for tools not on PATH
3. **PowerShell script**: `"Command": "myscript.ps1"` — resolved from `/scripts` directory

> **Note**: If system PATH is full, add tools via PowerShell profile aliases or use full paths instead of modifying PATH.

## Code Style Requirements

**Enforced at build time—violations cause warnings:**

1. **File-scoped namespaces**: `namespace Foo;` not `namespace Foo { }`
2. **Using statements inside namespace**: Place `using` after namespace declaration
3. **Primary constructors**: Use `class Foo(IService svc)` pattern
4. **Expression-bodied members**: Prefer `=> expression;` for simple methods
5. **Collection expressions**: Use `[]` not `new List<T>()`
6. **Cognitive Complexity**: Keep methods under 15 (SonarQube S3776). Split complex logic into private helper methods.
7. **XML Documentation**: All public members require `<summary>` comments.

Run `dotnet format` before committing to auto-fix style issues.

## Build & Publish

```powershell
# Development build
dotnet build

# Publish single-file executable to F:\Tools
.\publish.ps1
```

The publish script creates a self-contained `win-x64` executable with embedded scripts.

## PowerShell Scripts

Scripts live in `/scripts` and are:

- Copied to output during build
- Embedded as resources for single-file deployment
- Extracted to temp directory at runtime when running embedded

When writing PowerShell: use `;` for command chaining (not `&&`).

- ✅ Correct: `command1; command2; command3`
- ❌ Incorrect: `command1 && command2 && command3`

## Key Patterns

- **Spectre.Console**: Use for all console output—`AnsiConsole.MarkupLine`, `SelectionPrompt<T>`, `FigletText`
- **Process execution**: See `CliToolService.PrepareProcessStartInfo` for the pattern of splitting complex logic into helper methods
