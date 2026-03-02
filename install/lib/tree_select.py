#!/usr/bin/env python3
"""Tree-checkbox package selector with curses.

Reads a JSON array of groups from stdin, presents an interactive TUI with
tri-state group checkboxes, expand/collapse, and fuzzy search.

Output: TSV lines on stdout — "group_id<TAB>package_name" per selected package.
Exit code 0 = confirmed, 1 = cancelled.
"""

import curses
import json
import locale
import sys
from dataclasses import dataclass, field

locale.setlocale(locale.LC_ALL, "")

# ── Data model ──────────────────────────────────────────────────────────────

CHECK_ALL = "x"
CHECK_PARTIAL = "-"
CHECK_NONE = " "


@dataclass
class Package:
    name: str
    desc: str
    selected: bool = True


@dataclass
class Group:
    id: str
    name: str
    icon: str
    packages: list = field(default_factory=list)
    expanded: bool = True

    @property
    def check_state(self):
        if not self.packages:
            return CHECK_NONE
        sel = sum(1 for p in self.packages if p.selected)
        if sel == len(self.packages):
            return CHECK_ALL
        if sel > 0:
            return CHECK_PARTIAL
        return CHECK_NONE

    @property
    def selected_count(self):
        return sum(1 for p in self.packages if p.selected)

    @property
    def total_count(self):
        return len(self.packages)


# ── Helpers ─────────────────────────────────────────────────────────────────


def fuzzy_match(query, text):
    """Simple subsequence fuzzy match (case-insensitive)."""
    qi = 0
    text_lower = text.lower()
    query_lower = query.lower()
    for ch in text_lower:
        if qi < len(query_lower) and ch == query_lower[qi]:
            qi += 1
    return qi == len(query_lower)


def build_visible_rows(groups, filter_query=""):
    """Return list of (type, group_index, [pkg_index]) tuples for visible rows."""
    rows = []
    for gi, g in enumerate(groups):
        if filter_query:
            # In filter mode: show group header if any child matches
            matching = [
                pi
                for pi, p in enumerate(g.packages)
                if fuzzy_match(filter_query, p.name + " " + p.desc)
            ]
            if not matching:
                continue
            rows.append(("group", gi, None))
            for pi in matching:
                rows.append(("pkg", gi, pi))
        else:
            rows.append(("group", gi, None))
            if g.expanded:
                for pi in range(len(g.packages)):
                    rows.append(("pkg", gi, pi))
    return rows


def total_selected(groups):
    return sum(p.selected for g in groups for p in g.packages)


def total_packages(groups):
    return sum(len(g.packages) for g in groups)


# ── Curses TUI ──────────────────────────────────────────────────────────────


def run_tui(stdscr, groups):
    curses.curs_set(0)
    curses.use_default_colors()

    # Light color scheme — single accent, like gum
    curses.init_pair(1, curses.COLOR_MAGENTA, -1)  # accent (cursor indicator)

    COL_ACCENT = curses.color_pair(1) | curses.A_BOLD
    COL_DIM = curses.A_DIM

    cursor = 0
    scroll_offset = 0
    filter_query = ""
    filter_mode = False

    while True:
        stdscr.erase()
        max_y, max_x = stdscr.getmaxyx()

        # Terminal too small guard
        if max_y < 6 or max_x < 30:
            stdscr.addstr(0, 0, "Terminal too small!", curses.A_BOLD)
            stdscr.refresh()
            key = stdscr.getch()
            if key in (ord("q"), 27):
                return False
            continue

        rows = build_visible_rows(groups, filter_query)

        # Clamp cursor
        if len(rows) == 0:
            cursor = 0
        elif cursor >= len(rows):
            cursor = len(rows) - 1

        # Header (line 0)
        sel_count = total_selected(groups)
        tot_count = total_packages(groups)
        header = "  Select packages to install"
        counter = f"{sel_count}/{tot_count} selected"
        padding = max_x - len(header) - len(counter) - 1
        if padding < 1:
            padding = 1
        try:
            stdscr.addstr(0, 0, header, curses.A_BOLD)
            stdscr.addstr(0, len(header) + padding, counter, COL_DIM)
        except curses.error:
            pass

        # Filter bar (line 1) or blank separator
        if filter_mode:
            filter_line = f"  / {filter_query}█"
            try:
                stdscr.addstr(1, 0, filter_line[:max_x - 1], curses.A_BOLD)
            except curses.error:
                pass
        else:
            try:
                stdscr.addstr(1, 0, "")
            except curses.error:
                pass

        # Content area: lines 2 .. max_y-2
        content_height = max_y - 3  # header + filter + status bar
        if content_height < 1:
            content_height = 1

        # Scroll to keep cursor visible
        if cursor < scroll_offset:
            scroll_offset = cursor
        if cursor >= scroll_offset + content_height:
            scroll_offset = cursor - content_height + 1

        for i in range(content_height):
            ri = scroll_offset + i
            if ri >= len(rows):
                break

            row_type, gi, pi = rows[ri]
            y = 2 + i
            is_cursor = ri == cursor

            # Cursor row: magenta accent; other rows: default
            row_attr = COL_ACCENT if is_cursor else 0

            if row_type == "group":
                g = groups[gi]
                arrow = "▼" if g.expanded else "▶"
                state = g.check_state
                if state == CHECK_ALL:
                    check_str = "[x]"
                elif state == CHECK_PARTIAL:
                    check_str = "[-]"
                else:
                    check_str = "[ ]"

                # Count string
                if state == CHECK_PARTIAL:
                    cnt = f"({g.selected_count}/{g.total_count})"
                else:
                    cnt = f"({g.total_count} packages)"

                try:
                    stdscr.addstr(y, 2, arrow, row_attr)
                    stdscr.addstr(y, 4, check_str, row_attr)
                    label = f" {g.icon} {g.name} "
                    stdscr.addnstr(y, 8, label, max_x - 9, row_attr | curses.A_BOLD)
                    cnt_x = 8 + min(len(label), max_x - 9)
                    stdscr.addnstr(y, cnt_x, cnt, max_x - cnt_x - 1, COL_DIM if not is_cursor else row_attr)
                except curses.error:
                    pass

            else:  # package row
                p = groups[gi].packages[pi]
                check_str = "[x]" if p.selected else "[ ]"

                try:
                    stdscr.addstr(y, 6, check_str, row_attr)
                    name_str = p.name
                    stdscr.addnstr(y, 10, name_str, max_x - 11, row_attr)
                    if p.desc:
                        desc_x = 10 + min(len(name_str), max_x - 11)
                        desc_str = f" — {p.desc}"
                        stdscr.addnstr(y, desc_x, desc_str, max_x - desc_x - 1, COL_DIM if not is_cursor else row_attr)
                except curses.error:
                    pass

        # Status bar (last line)
        if filter_mode:
            status = " Type to filter | Space: toggle | Esc: clear filter | Enter: confirm"
        else:
            status = " Space: toggle  ←→: collapse/expand  /: search  a/n: all/none  Enter: confirm  Esc: cancel"
        try:
            stdscr.addstr(max_y - 1, 0, status[: max_x - 1], curses.A_DIM)
        except curses.error:
            pass

        stdscr.refresh()

        # ── Input handling ──────────────────────────────────────────────
        key = stdscr.getch()

        if filter_mode:
            if key == 27:  # Esc — clear filter
                filter_query = ""
                filter_mode = False
                cursor = 0
                scroll_offset = 0
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                if filter_query:
                    filter_query = filter_query[:-1]
                    cursor = 0
                    scroll_offset = 0
                else:
                    filter_mode = False
            elif key in (10, 13, curses.KEY_ENTER):  # Enter — confirm
                return True
            elif key == ord(" "):
                # Toggle current item
                if rows and cursor < len(rows):
                    _toggle_row(groups, rows[cursor])
            elif key == curses.KEY_UP:
                cursor = max(0, cursor - 1)
            elif key == curses.KEY_DOWN:
                cursor = min(len(rows) - 1, cursor + 1)
            elif 32 <= key <= 126:
                filter_query += chr(key)
                cursor = 0
                scroll_offset = 0
            continue

        # Normal mode
        if key == curses.KEY_UP or key == ord("k"):
            cursor = max(0, cursor - 1)
        elif key == curses.KEY_DOWN or key == ord("j"):
            if rows:
                cursor = min(len(rows) - 1, cursor + 1)
        elif key == curses.KEY_PPAGE:  # Page Up
            cursor = max(0, cursor - content_height)
        elif key == curses.KEY_NPAGE:  # Page Down
            if rows:
                cursor = min(len(rows) - 1, cursor + content_height)
        elif key == curses.KEY_HOME:
            cursor = 0
        elif key == curses.KEY_END:
            if rows:
                cursor = len(rows) - 1

        elif key == ord(" "):
            if rows and cursor < len(rows):
                _toggle_row(groups, rows[cursor])

        elif key == curses.KEY_RIGHT or key == ord("l"):
            if rows and cursor < len(rows):
                row_type, gi, _ = rows[cursor]
                if row_type == "group":
                    groups[gi].expanded = True

        elif key == curses.KEY_LEFT or key == ord("h"):
            if rows and cursor < len(rows):
                row_type, gi, _ = rows[cursor]
                if row_type == "group":
                    groups[gi].expanded = False
                elif row_type == "pkg":
                    # Jump to parent group
                    for ri2, (t2, gi2, _) in enumerate(rows):
                        if t2 == "group" and gi2 == gi:
                            cursor = ri2
                            break

        elif key == ord("/"):
            filter_mode = True
            filter_query = ""
            cursor = 0
            scroll_offset = 0

        elif key == ord("a"):  # Select all
            for g in groups:
                for p in g.packages:
                    p.selected = True

        elif key == ord("n"):  # Deselect all
            for g in groups:
                for p in g.packages:
                    p.selected = False

        elif key in (10, 13, curses.KEY_ENTER):  # Enter — confirm
            return True

        elif key == 27:  # Esc — cancel
            return False

        elif key == ord("q"):
            return False


def _toggle_row(groups, row):
    row_type, gi, pi = row
    if row_type == "group":
        g = groups[gi]
        # If any selected, deselect all; otherwise select all
        if g.check_state in (CHECK_ALL, CHECK_PARTIAL):
            for p in g.packages:
                p.selected = False
        else:
            for p in g.packages:
                p.selected = True
    else:
        groups[gi].packages[pi].selected = not groups[gi].packages[pi].selected


# ── Main ────────────────────────────────────────────────────────────────────


def main():
    import os

    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(2)

    groups = []
    for item in data:
        pkgs = [Package(name=p["name"], desc=p.get("desc", "")) for p in item.get("packages", [])]
        groups.append(
            Group(
                id=item["id"],
                name=item.get("name", item["id"]),
                icon=item.get("icon", ""),
                packages=pkgs,
                expanded=True,
            )
        )

    def _output_all():
        for g in groups:
            for p in g.packages:
                sys.stdout.write(f"{g.id}\t{p.name}\n")

    # Open /dev/tty for curses since stdin/stdout are pipes
    try:
        tty_fd = os.open("/dev/tty", os.O_RDWR)
    except OSError:
        _output_all()
        sys.exit(0)

    # Check terminal size via the tty fd
    try:
        size = os.get_terminal_size(tty_fd)
        if size.lines < 10 or size.columns < 40:
            print("Terminal too small for interactive mode, selecting all.", file=sys.stderr)
            os.close(tty_fd)
            _output_all()
            sys.exit(0)
    except (OSError, ValueError):
        pass

    # Save original stdin/stdout fds, then redirect to /dev/tty for curses
    saved_stdin = os.dup(0)
    saved_stdout = os.dup(1)
    os.dup2(tty_fd, 0)
    os.dup2(tty_fd, 1)
    os.close(tty_fd)

    try:
        confirmed = curses.wrapper(lambda stdscr: run_tui(stdscr, groups))
    finally:
        # Restore original stdout for TSV output
        os.dup2(saved_stdin, 0)
        os.dup2(saved_stdout, 1)
        os.close(saved_stdin)
        os.close(saved_stdout)

    if not confirmed:
        sys.exit(1)

    # Output selected packages as TSV to the original stdout (pipe)
    for g in groups:
        for p in g.packages:
            if p.selected:
                sys.stdout.write(f"{g.id}\t{p.name}\n")

    sys.exit(0)


if __name__ == "__main__":
    main()
