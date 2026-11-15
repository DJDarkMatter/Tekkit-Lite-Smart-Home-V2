# File Explorer

On the central computer, install with `inst app file_explorer`. Open **Start → File Explorer** after rebooting. The app starts at `/` and remembers each window's folder across restarts. It shows folders first, then files, in alphabetical order. Use the arrows to page through the list and **Up** to return to the parent folder.

## Files and folders

- Tap a folder to open it. Tap a file for **View text**, **Details**, **Copy**, **Move** and **Send paste**. View text previews up to 8 KB. Details shows the full path and file size.
- **Menu → New folder** creates a directory. **Menu → New file** asks for a name and optional text. **NL** starts a new line. **Save** creates the file. Save with a blank draft to create an empty file.
- Choose **Copy** or **Move** on a file. For folders, open the folder and use **Menu → Copy folder** or **Move folder**. Navigate to the destination folder and tap **Paste** (**Put** on small windows). The clipboard is shared across File Explorer windows.
- Use **Menu → Paste as** to choose a different name. Copying and moving protect existing files against name collisions. A move removes the original after the copy succeeds and needs enough space for the destination copy. Read-only folders and mounted drives can be browsed.

## Pastebin

**Menu → Get paste** accepts a public or unlisted paste ID or a `pastebin.com` link. Confirm a filename to save the paste as a text file in the current folder. The get operation uses HTTP access to `pastebin.com`.

Select a text file and choose **Send paste** to upload it. The first upload asks for your Pastebin developer API key. The touch keyboard masks it, and the app holds it in memory until the last File Explorer window closes. Confirm **Send** to create an unlisted paste. The resulting ID and URL appear in the window. [Get your Pastebin developer key](https://pastebin.com/doc_api)

Anyone with the link can read an unlisted paste. If Pastebin or the server rejects a transfer, the app displays the error and keeps the local source file.
