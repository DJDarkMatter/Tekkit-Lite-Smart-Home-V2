# Project maintenance

Keep distributed files in the repository root and use the established filename prefixes.

When changing menus, dialogs, settings, app names, or the screensaver catalog, review the corresponding paths in `documentation_menu_tree.md` against the Lua code. Include each optional app in its own branch. System overview belongs under Settings.

Regenerate `documentation_menu_tree.pdf` after reviewing those paths and whenever the OS version changes. Keep the clickable hub, complete overview, linked branch details, portrait pages and fully visible labels. The PDF builder reads the OS version and screensaver names directly from Lua.

Before packaging a release, run `python3 tools_build_menu_tree.py --check` and `python3 tools_build_installer.py --check`, then run the Lua integration suite. Include the menu source, PDF and builder in every full release. Review every rendered PDF page after changing the tree or its layout.
