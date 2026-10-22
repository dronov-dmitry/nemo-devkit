# Nemo PR: Fix focus loss during inline rename when pressing Alt+Shift (language switch)

## Summary

When renaming a file or folder (F2) in Nemo, pressing Alt+Shift to switch keyboard
layout causes the rename text entry to lose focus. The rename operation is cancelled
and the file returns to its original name. This affects all three view modes:
Icon View, List View, and Compact View.

## Root Cause Analysis

### Key event pipeline during rename

When a key is pressed during rename mode, the event flows through this pipeline:

```
1. nemo_window_key_press_event()          [nemo/src/nemo-window.c:1188]
   |
   +-- is_renaming == TRUE AND keyval != F2?   [line 1209]
   |   YES:
   |     gtk_window_propagate_key_event()       [line 1215]
   |       |
   |       +-- Focused widget handles it? --> return TRUE (consumed)
   |       +-- Focused widget doesn't?    --> return FALSE [line 1222]
   |           [accelerator bindings and Alt-menu logic are ALL skipped]
   |
   v
2. Focused rename widget receives the event
   |
   +-- Icon View: EelEditableLabel            [eel/eel-editable-label.c:2166]
   |     gtk_im_context_filter_keypress()
   |     GTK key bindings (Alt+F, Alt+B for word movement)
   |     bare Alt key is NOT handled --> returns FALSE
   |
   +-- List View: GtkEntry (GtkCellEditable)  [default GTK behavior]
         bare Alt key is NOT handled --> returns FALSE
```

### What happens with Alt+Shift

1. User presses Shift, then Alt (or Alt, then Shift)
2. `nemo_window_key_press_event` sees `is_renaming == TRUE`, propagates event
3. The rename widget (EelEditableLabel / GtkEntry) does NOT handle bare Alt
4. The event is returned as unhandled (return FALSE at line 1222)
5. GTK's default event processing sees an unhandled Alt key press
6. GTK activates the menubar accelerator or performs default Alt handling
7. This causes the rename widget to lose focus
8. Focus-out callback fires:
   - Icon View: `handle_focus_out_event()` at `nemo-icon-container.c:4921`
     calls `nemo_icon_container_end_renaming_mode(container, TRUE)`
   - List View: `cell_renderer_editing_canceled()` at `nemo-list-view.c:1744`
     sets `is_renaming = FALSE`
9. Rename is cancelled, original filename is restored

### Why this is a bug

The rename guard at `nemo-window.c:1209` correctly bypasses Nemo's own accelerator
bindings, but does NOT prevent GTK from processing the unhandled Alt key event.
The unhandled event falls through to GTK's default handler, which interprets bare
Alt as a menubar toggle trigger, causing focus loss.

## Proposed Fix

### Option A: Consume bare Alt key events during rename (Recommended)

**File:** `nemo/src/nemo-window.c`
**Function:** `nemo_window_key_press_event()`
**Location:** Inside the renaming guard block (lines 1209-1223)

**Change:**

Currently (lines 1209-1223):
```c
if (view != NULL && nemo_view_get_is_renaming (view) && event->keyval != GDK_KEY_F2) {
    if (gtk_window_propagate_key_event (GTK_WINDOW (window), event)) {
        return TRUE;
    }
    return FALSE;
}
```

Proposed:
```c
if (view != NULL && nemo_view_get_is_renaming (view) && event->keyval != GDK_KEY_F2) {
    /* Consume bare Alt key presses during rename to prevent GTK from
     * interpreting them as menubar toggle triggers, which would cause
     * the rename entry to lose focus.
     *
     * Alt+letter combinations (Alt+F, Alt+B, etc.) are still passed
     * through for word movement in EelEditableLabel.
     */
    if (event->keyval == GDK_KEY_Alt_L || event->keyval == GDK_KEY_Alt_R) {
        guint modifiers = event->state & gtk_accelerator_get_default_mod_mask();
        if (modifiers == 0) {
            /* Bare Alt press (no other modifiers) - consume it */
            return TRUE;
        }
    }

    if (gtk_window_propagate_key_event (GTK_WINDOW (window), event)) {
        return TRUE;
    }
    return FALSE;
}
```

**Rationale:**
- Only blocks bare Alt presses (no modifiers) during rename
- Alt+letter combinations (Alt+F, Alt+B for word movement) still work
- Ctrl+Alt, Shift+Alt combinations still propagate normally
- The change is minimal and contained to a single location
- No impact on non-rename behavior

### Option B: Also handle key-release for Alt during rename

If Option A alone is insufficient (e.g., GTK processes Alt release to toggle menu),
also add a release guard:

**File:** `nemo/src/nemo-window.c`
**Function:** `nemo_window_key_release_event()`
**Location:** Add renaming guard at the start of the function

```c
static gboolean
nemo_window_key_release_event (GtkWidget *widget, GdkEventKey *event)
{
    NemoWindow *window = NEMO_WINDOW (widget);
    NemoWindowPane *pane;
    NemoView *view;

    pane = nemo_window_get_current_pane (window);
    view = nemo_windowPane_get_current_view (pane);

    /* Consume bare Alt key release during rename */
    if (view != NULL && nemo_view_get_is_renaming (view)) {
        if (event->keyval == GDK_KEY_Alt_L || event->keyval == GDK_KEY_Alt_R) {
            guint modifiers = event->state & gtk_accelerator_get_default_mod_mask();
            if (modifiers == 0) {
                return TRUE;
            }
        }
    }

    /* existing release handler code... */
    if (is_alt_key_event (event)) {
        /* ... */
    }
    /* ... */
}
```

### Option C: Handle at the EelEditableLabel level

**File:** `eel/eel-editable-label.c`
**Function:** `eel_editable_label_key_press()`
**Location:** Before the IM context filter

```c
static gboolean
eel_editable_label_key_press (GtkWidget *widget, GdkEventKey *event)
{
    /* Block bare Alt key presses to prevent focus loss from GTK menubar toggle */
    if ((event->keyval == GDK_KEY_Alt_L || event->keyval == GDK_KEY_Alt_R) &&
        (event->state & gtk_accelerator_get_default_mod_mask()) == 0) {
        return TRUE;
    }

    /* existing code... */
    if (gtk_im_context_filter_keypress (...)) {
        return TRUE;
    }
    /* ... */
}
```

**Note:** This only fixes Icon View (which uses EelEditableLabel). List View uses
GtkEntry and would need a separate fix. Option A is preferred as it covers all views.

## Testing

### Manual test steps

1. Open Nemo in Icon View, List View, and Compact View
2. Select a file and press F2 to rename
3. While the rename text entry is focused, press Alt+Shift
4. **Expected:** The keyboard layout switches, rename field keeps focus
5. **Actual (before fix):** Rename field loses focus, rename is cancelled

### Additional test cases

- Alt+F / Alt+B should still move cursor by word in rename field (Icon View)
- Alt+Tab should work normally when NOT in rename mode
- Alt+F4 should close Nemo when NOT in rename mode
- Ctrl+A should select all text in rename field
- Escape should cancel rename
- Enter should confirm rename
- The fix should work in Icon View, List View, and Compact View

### Build and test

```bash
# Clone and build
git clone https://github.com/linuxmint/nemo.git
cd nemo
meson setup builddir
ninja -C builddir

# Run locally for testing
./builddir/src/nemo --no-desktop

# Run tests
ninja -C builddir test
```

## Affected files

| File | Change |
|------|--------|
| `nemo/src/nemo-window.c` | Add bare Alt key consumption in rename guard |

## Related issues

- GTK3 bug: bare Alt key press activates menubar accelerator
- Affects all GTK3 applications with inline editing
- Similar issues reported in Nautilus, Thunar, PCManFM
- Ubuntu/GNOME has similar fix in Nautilus (commit by Ubuntu developers)
