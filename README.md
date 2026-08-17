# PopSnip

PopSnip is a macOS menu bar app for the text you retype every day — greetings, addresses, code fragments, canned replies.

Hit a shortcut anywhere, find the snippet, and it lands in the text field you were just typing in.

![](images/popsnip_sample.png)

## What PopSnip does

**Insert into any app with a shortcut.**
Press `⌥⌘P` in any app to open the search panel over whatever you were doing. Pick a snippet and it is typed into the field that had focus a moment ago — a browser form, a chat box, a code editor, the Terminal. No switching apps, no copy and paste.

**Capture a snippet from any app.**
Select text anywhere and register it as a snippet without leaving the app. The selection is picked up automatically and pre-filled into the snippet body — you just add a title and tags.

**Spotlight-style incremental search.**
Results narrow with every keystroke across titles, bodies, and tag names, with matched characters highlighted. Snippets you use often and used recently rise to the top. `⌘1`–`⌘9` inserts a result straight from the list.

**Loose, tag-based organization.**
No folder hierarchy to maintain. Give a snippet as many tags as you like, then drill into a tag to see only its snippets, and keep searching inside that scope. Tags are colored chips you can navigate with the keyboard alone.

## Requirements

- macOS 14.0 or later
- Accessibility permission — PopSnip needs it to read your selection and to insert text into other apps

## Install

1. Download `PopSnip.zip` from the [latest release](https://github.com/Nihondo/PopSnip/releases/latest).
2. Unzip it and move `PopSnip.app` into your **Applications** folder.
3. Launch it. PopSnip lives in the menu bar only — there is no Dock icon and no window at startup.
4. Grant Accessibility permission when prompted, or later from **Settings → Permission**.

Turn on **Launch at Login** in **Settings → General** so PopSnip is always ready.

## Getting started

1. Press `⌥⌘P` to open the search panel. Prefer a different key? Change it in **Settings → Shortcut**.
2. With the box empty, browse your favorites, tags, and recently used snippets.
3. Start typing to search. `↑` / `↓` to move, `Enter` to insert.
4. Click **Register** to create your first snippet. Had text selected in another app? It is already in the body.
5. Right-click any snippet in the panel to edit or delete it.

## Using PopSnip

### The search panel

The panel opens near your mouse cursor by default, and closes with `Esc` or by clicking away. Whatever you were typing in stays the insertion target, so you can open, search, and insert without ever leaving the app you are in.

| Key | Action |
| --- | --- |
| `↑` / `↓` | Move the selection |
| `Enter` | Insert the snippet, or drill into the selected tag |
| `⌘1`–`⌘9` | Insert the 1st–9th snippet result directly |
| `Tab` / `Shift+Tab`, `←` / `→` | Cycle through tags |
| `Backspace` (empty search box) | Step back one level out of a tag |
| `Esc` | Close the panel |

Other things you can do here:

- **Right-click a snippet** for Edit / Delete.
- **Drag any edge** to resize the panel — the size is remembered next time.
- **Register**, **List**, and **Settings** buttons sit along the bottom.

Japanese input is handled properly: while you are composing with the IME, the arrow and Enter keys go to the input method, not to PopSnip.

### Searching

Type and results appear immediately — titles, bodies, and tag names are all searched, and matching parts are highlighted so you can see why a snippet matched.

Ranking favors title matches over tag matches over body matches, then boosts snippets you use frequently and ones you used recently, so your everyday snippets tend to be the first result. You can switch to a plain sort order in **Settings → Panel**.

Tags that match your query stay listed above the snippet results, so a search can turn into a tag filter with one `Enter`.

### Tags

Tagging in PopSnip is meant to stay loose. Add tags as they occur to you rather than designing a structure up front — a snippet can carry any number of them, and searching works fine even if you tag nothing at all.

- Select a tag and press `Enter` to drill into it. Searching then stays inside that tag, and picking a further tag narrows it again.
- `Backspace` on an empty search box backs out one level.
- Tags display as colored chips in a single scrollable row. Prefer one tag per row? Switch the layout in **Settings → Panel**.
- New tags get a color automatically; click the color circle in the tag manager to choose another.
- Order tags by registration order, most matches first, or most recently used (**Settings → Panel**).
- Rename, recolor, delete, or add tags from the sidebar of the snippet list window.

### Creating snippets from a selection

Two ways, both starting from a text selection in any app:

- **From the panel** — open PopSnip and click **Register**. The selected text is already in the body.
- **Straight to the editor** — assign a shortcut to **Quick Register from Selection** in **Settings → Shortcut**, and one keystroke opens the editor with the selection filled in, skipping the search panel entirely.

In the editor you give the snippet a title, adjust the body, attach tags (existing or new), and optionally mark it as a favorite so it appears in the panel's Favorites section.

### The snippet list window

Open it from the panel's **List** button or the menu bar — and give it a shortcut of its own in **Settings → Shortcut** if you use it often.

- Browse and filter every snippet in one table.
- Select several rows and use **Tags** to add or remove tags in bulk.
- Double-click a row (or right-click → **Edit**) to open the editor.
- Delete selected snippets in bulk.
- Manage the whole tag list from the sidebar.

### Settings

Open from the panel's **Settings** button or **PopSnip Settings...** in the menu bar.

- **General** — launch at login, insertion method (Automatic / Accessibility only / Clipboard only), clipboard restore delay, font size, and where snippets are stored.
- **Panel** — which sections appear and in what order, how many items each shows, search and tag sort order, tag layout, panel position, Enter key behavior, number-key selection, and tag colors.
- **Shortcut** — global shortcuts for opening the panel, quick-registering from a selection, and opening the list.
- **Permission** — check and grant Accessibility access.
- **Update** — check now, toggle automatic checks, see the current version.

### Menu bar

Click the menu bar icon for Show Snippet Panel, Open Snippet List, Check for Updates, Settings, About, and Quit.

## How insertion works

By default PopSnip inserts text directly into the focused field through the macOS Accessibility API, leaving your clipboard untouched. If an app does not support that, it falls back to a clipboard paste and restores your previous clipboard contents afterward. You can force either method in **Settings → General**.

If insertion does nothing, Accessibility permission is almost always the cause — check **Settings → Permission**.

## Where your data lives

Snippets and tags are stored as a plain JSON file at `~/Library/Application Support/PopSnip/snippets.json`. Nothing is sent anywhere. You can move the file to a synced folder from **Settings → General**, back it up like any other file, or edit it by hand — PopSnip picks up external changes the next time the panel opens.

## Updates

PopSnip checks for updates automatically. You can also check any time from the menu bar or **Settings → Update**.
