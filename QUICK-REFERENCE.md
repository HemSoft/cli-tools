# Import Tool - Quick Reference

## Access
Select **⊕ Import New Tool** (first option in yellow) from the main menu

## 7 Steps

### 1️⃣ Basic Information
- **Tool Name**: Display name in menu
- **Description**: Brief explanation
- **Version**: Version tracking

### 2️⃣ Tool Type
Choose one:
- **PowerShell Script** → Copies to `scripts/`
- **Executable on PATH** → Verifies availability
- **Full Path Executable** → Validates location

### 3️⃣ Verification
- Test tool execution (optional)
- Validates tool works

### 4️⃣ Interactivity
- **Interactive**: Full console control (vim, mc)
- **Non-interactive**: Captured output

### 5️⃣ Parameters
Static values for every run:
- API URLs
- Config paths
- Default flags

### 6️⃣ Runtime Arguments
User prompts before each run:
- File paths
- Search queries
- Dynamic values

### 7️⃣ Review
- Confirm configuration
- Auto-creates backup
- Saves to `appsettings.json`

## Quick Tips

✅ **DO**
- Test tool execution
- Use descriptive names
- Add helpful prompts
- Keep parameters simple

❌ **DON'T**
- Store sensitive data in parameters
- Use complex parameter structures initially
- Skip verification step
- Forget to set interactivity correctly

## Common Use Cases

### Import Script
```
Type: PowerShell Script
Path: C:\Scripts\my-tool.ps1
Interactive: No
```

### Import Command-Line Tool
```
Type: Executable on PATH
Name: ripgrep
Interactive: No
```

### Import Interactive Tool
```
Type: Executable on PATH
Name: vim
Interactive: Yes
```

## After Import

✅ Tool appears in menu immediately
✅ Backup saved to `appsettings.json.backup`
✅ Manual edits possible in `appsettings.json`
✅ Re-import to update existing tool

## Documentation
📖 Full guide: [IMPORT-GUIDE.md](IMPORT-GUIDE.md)
