# Code Style Instructions:

Place using statements inside of the namespace.
Simplify collection initialization (IDE0028).
Remove unused using statements.

# PowerShell Instructions:

When generating PowerShell commands or scripts, use ';' (semicolon) as a command separator instead of '&&'. PowerShell does not support '&&' for command chaining.

Example:
- ✅ Correct: `command1; command2; command3`
- ❌ Incorrect: `command1 && command2 && command3`
