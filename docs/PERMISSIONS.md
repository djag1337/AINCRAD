# Permissions and quick commands

> **Short version:** AINCRAD works with **no permissions at all**. Every feature that needs one is
> either **off until you turn it on**, or only asks the **first time you use it**. Nothing is ever
> asked for at launch or while you're typing. Nothing is sent, posted or deleted for you.
> You can see and change all of this in **AINCRAD Settings**, and take any permission back in
> **System Settings › Privacy & Security** at any time.

## Every permission AINCRAD can ask for

| Permission | Asked when | Used for | Without it |
|---|---|---|---|
| **Accessibility** | You turn on a feature that needs it | Mouse gesture; reading app menus for the top bar; windows in the dock and Windows menu; arranging windows; the ⌘-Tab switcher (opt-in); mirroring notifications as SAO bubbles | Those features stay off; everything else works |
| **Calendar** | You add the Quest log widget, or run `event` | Quest log; `event` quick command | No calendar quests |
| **Reminders** | You add the Quest log widget, or run `remind` | Quest log; `remind`; Complete/Snooze | No reminder quests |
| **Contacts** | You run `contact`, `message`, `mail` or `facetime` (all **off by default**) | Finding the person you typed | Type a phone number or email instead |
| **Location** | You open System › Wi-Fi › Networks | macOS only shows Wi-Fi *network names* to apps with Location access. AINCRAD never reads your location | Networks list is hidden |
| **Bluetooth** | You open System › Bluetooth | Listing and connecting paired devices | No device list |
| **Automation → Notes** | You run `applenote` (**off by default**) | Creating the note | — |
| **Automation → Music / Spotify** | You run `play`/`next`… (**off by default**) or use Now Playing | Player controls | — |
| **Automation → System Events** | You run `dark`/`light` (**off by default**) or the Display menu's appearance switch | Switching appearance | — |
| **Automation → Finder** | You choose Empty Trash… (and confirm) | Emptying the Trash | — |

AINCRAD never asks for **Full Disk Access**, **Screen Recording**, the **camera** or the **microphone**.

## Things AINCRAD changes on your Mac, and how they come back

| Option | Off by default? | What changes | Undo |
|---|---|---|---|
| Hide Apple's Dock / menu bar | Yes | Dock and menu bar auto-hide preferences | Restored when you turn it off or quit AINCRAD (Safe Mode also restores) |
| Mac Settings menu | — (you choose each switch) | The same preferences System Settings writes | Switch it back, in AINCRAD or System Settings |
| Theme-coloured dock folder icon | Yes (per folder) | That folder's Finder icon | Turn the option off; remove the icon in Finder › Get Info |
| ⌘-Tab switcher / ⌘-Space | Yes | Nothing system-wide; AINCRAD listens for the keys while it runs | Turn off; quitting AINCRAD gives the keys back |

**Notifications:** AINCRAD reads banners to draw SAO bubbles. It **never closes, clears or dismisses**
a notification (an early version did, which removed them from synced devices; that was a bug and is
gone, with a test that guards against it).

## Quick commands

Type these in the launcher's search and press Return. Each one has its own switch in
**Settings › Quick Commands**. Type `commands` in the launcher to see them all with their status.
Messages and emails open as **drafts**: you always press Send yourself.

| Command | Example | Does | Permission | Default |
|---|---|---|---|---|
| `remind` | `remind call mom tomorrow 5pm` | Adds a reminder with an alert | Reminders | On |
| `event` | `event lunch with Sam friday 1pm` | Adds a calendar event | Calendar | On |
| `note` | `note pick up the 3D prints` | Saves a Markdown note to `~/AINCRAD Notes` | none | On |
| `applenote` | `applenote gift ideas` | Creates an Apple Notes note | Automation → Notes | **Off** |
| `contact` | `contact sam` | Opens their card in Contacts | Contacts | **Off** |
| `message` | `message mom on my way` | Opens Messages with the text ready (not sent) | Contacts | **Off** |
| `mail` | `mail sam about the build` | Opens an email draft (not sent) | Contacts | **Off** |
| `facetime` | `facetime sam` | Starts FaceTime; macOS asks before calling | Contacts | **Off** |
| `play` `pause` `next` `previous` | `next` | Controls Music or Spotify | Automation → that app | **Off** |
| `volume` `mute` `unmute` | `volume 40` | Sound | none | On |
| `dark` `light` | `dark` | Appearance | Automation → System Events | **Off** |
| `define` | `define ephemeral` | Opens the Dictionary | none | On |
| `window` | `window left` | Arranges the window you were using | Accessibility | On |
| `timer` / `capture` | `timer 25` | Focus timer / Quick Capture inbox | none | On |

Typing a command that's switched off shows a row saying it's off, which permission it needs, and
where to turn it on. It never runs.
