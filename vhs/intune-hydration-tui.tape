Output media/demo.gif

Set Shell pwsh
Set Width 1200
Set Height 720
Set FontSize 22
Set TypingSpeed 35ms
Set Theme "Catppuccin Frappe"
Set Padding 20

Hide
Type "Import-Module ./IntuneHydrationKit.psd1 -Force"
Enter
Type "Clear-Host"
Enter
Show

Type "Invoke-IntuneHydration"
Enter
Sleep 2s

# Environment: Global.
Enter
Sleep 1s

# Operation mode: Dry-run create.
Down
Sleep 1s
Enter
Sleep 1s

# Import targets: Dynamic Groups, Device Filters, Conditional Access.
Space
Sleep 1s
Down 2
Space
Sleep 1s
Down 7
Space
Sleep 1s
Enter
Sleep 1s

# Platform filter: All.
Space
Sleep 1s
Enter
Sleep 1s

# Microsoft Graph consent prompt: default No.
Sleep 1s
Enter
Sleep 1s

# Verbose logging: default No.
Sleep 1s
Enter
Sleep 2s

# Final confirmation: run the dry-run hydration flow.
Type "y"
Enter

# Browser auth: keep the run alive while the renderer completes sign-in/MFA.
Sleep 10s
