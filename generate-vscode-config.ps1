# PowerShell script to generate tasks.json and launch.json for learnopengl-zig project

# Define the build targets from zig build -l output
$buildTargets = @()
$lessons = (Get-ChildItem -Path .\src -Filter *.zig | Select-Object -Property Name).Name

foreach($lesson in $lessons) {
    $lessonName = $lesson.Split('.')[0]
    $lessonNumber = $lessonName.Split('_')[0]
    $buildTargets += ($lessonNumber)
}

# Create .vscode directory if it doesn't exist
$vscodePath = Join-Path $PSScriptRoot ".vscode"
if (-not (Test-Path $vscodePath)) {
    New-Item -ItemType Directory -Path $vscodePath | Out-Null
    Write-Host "Created .vscode directory" -ForegroundColor Green
}

# Function to create a friendly label from the build target
function Get-FriendlyLabel {
    param($target)
    # Replace dots and underscores with spaces, then convert to title case
    # $label = $target -replace '[._]', ' '
    # $label = (Get-Culture).TextInfo.ToTitleCase($label.ToLower())
    $label = $target.Split('_')[0]
    return $label
}

# Generate tasks.json with ordered properties
$tasksJson = @"
{
    // See https://go.microsoft.com/fwlink/?LinkId=733558
    // for the documentation about the tasks.json format
    "version": "2.0.0",
    "tasks": [
"@

foreach ($target in $buildTargets) {
    $tasksJson += @"

        {
            "label": "build $target",
            "type": "shell",
            "command": "zig",
            "args": [
                "build",
                "$target"
            ],
            "problemMatcher": [],
            "group": "build"
        },
"@
}

# Add build all task
$tasksJson += @"

        {
            "label": "build all",
            "type": "shell",
            "command": "zig",
            "args": [
                "build",
                "all"
            ],
            "problemMatcher": [],
            "group": {
                "kind": "build",
                "isDefault": true
            }
        }
    ]
}
"@

# Generate launch.json with ordered properties
$launchJson = @"
{
    // Use IntelliSense to learn about possible attributes.
    // Hover to view descriptions of existing attributes.
    // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
    "version": "0.2.0",
    "configurations": [
"@

foreach ($target in $buildTargets) {
    $friendlyName = Get-FriendlyLabel $target
    $launchJson += @"

        {
            "name": "$friendlyName",
            "type": "cppdbg",
            "request": "launch",
            "program": "`${workspaceFolder}/zig-out/bin/$target",
            "args": [],
            "stopAtEntry": false,
            "cwd": "`${workspaceFolder}",
            "environment": [],
            "preLaunchTask": "build $target",
            "osx": {
                "MIMode": "lldb"
            },
            "windows": {
                "type": "cppvsdbg",
                "console": "integratedTerminal"
            }
        },
"@
}

# Remove the trailing comma from the last configuration
$launchJson = $launchJson.TrimEnd(',')

$launchJson += @"

    ]
}
"@

# Write tasks.json
$tasksPath = Join-Path $vscodePath "tasks.json"
$tasksJson | Out-File -FilePath $tasksPath -Encoding UTF8 -NoNewline
Write-Host "Generated tasks.json with $($buildTargets.Count + 1) tasks" -ForegroundColor Green

# Write launch.json  
$launchPath = Join-Path $vscodePath "launch.json"
$launchJson | Out-File -FilePath $launchPath -Encoding UTF8 -NoNewline
Write-Host "Generated launch.json with $($buildTargets.Count) configurations" -ForegroundColor Green

Write-Host "`nConfiguration files generated successfully!" -ForegroundColor Cyan
Write-Host "You can now use VS Code's build tasks (Ctrl+Shift+B) and debug configurations (F5)" -ForegroundColor Yellow