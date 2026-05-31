# VHS Demo Recording

Regenerate the README terminal demo with [VHS](https://github.com/charmbracelet/vhs).

Prerequisites: `vhs`, `ffmpeg`, and `ttyd` on `PATH`.

## Render

```powershell
vhs vhs/intune-hydration-tui.tape
```

Output:

```plaintext
media/demo.gif
```

## Troubleshooting

If rendering fails, verify `vhs --version`, `ttyd --version`, and `ffmpeg -version`, then retry from the repository root.

## Notes

- The tape imports the local module and launches `Invoke-IntuneHydration`.
- It selects Global, dry-run create, Dynamic Groups, Device Filters, Conditional Access, and All platforms.
- It confirms the final prompt and starts the dry-run hydration flow.
- Dry-run mode prevents Graph write calls, but the run still reaches authentication and read-only checks.
- Keep a browser session ready when rendering; the tape waits 10 seconds for sign-in/MFA to complete.
