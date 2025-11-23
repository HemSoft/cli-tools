# Code Style Instructions:

Place using statements inside of the namespace.
Simplify collection initialization (IDE0028).
Remove unused using statements.

# Code Quality & Standards

This repository enforces strict code quality standards. When writing or modifying C# code, you must adhere to the following:

1.  **Follow .editorconfig**: The project uses `.editorconfig` to enforce styles like file-scoped namespaces, primary constructors, and expression-bodied members.
2.  **SonarQube Analysis**: `SonarAnalyzer.CSharp` is included in the project. Pay attention to warnings, especially regarding **Cognitive Complexity (S3776)**. Refactor methods that exceed the complexity threshold (15).
3.  **Build Enforcement**: Code style is enforced during build (`<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>`).
4.  **Auto-Formatting**: Always run `dotnet format` after making changes to ensure your code complies with the project's style guidelines.

# PowerShell Instructions:

When generating PowerShell commands or scripts, use ';' (semicolon) as a command separator instead of '&&'. PowerShell does not support '&&' for command chaining.

Example:
- ✅ Correct: `command1; command2; command3`
- ❌ Incorrect: `command1 && command2 && command3`

Always run and test PowerShell scripts after creating or modifying them to verify they work as expected in the current environment.
