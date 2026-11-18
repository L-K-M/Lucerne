# Changelog

## Unreleased

- When GitHub's rate limit stops a Check for Updates, the alert says when to
  try again instead of showing a bare HTTP 403 (Updraft 0.2.0).
- Share classic controls, window/palette chrome, the status bar, and live pickers
  through RigiUI. Preserve Lucerne's document targeting and formatting undo.

- The floating Typefaces, Styles and Lists palettes are Rigi palettes now. Drop
  one palette's title bar on another's to share a panel as tabs; palettes snap,
  dock into columns, collapse with a double-click, and keep their arrangement
  across launches.

- The AppImage now ships the notices of the libraries it bundles: each
  Ubuntu package's `copyright` file, the license texts they reference,
  `usr/share/doc/lucerne/Third-Party-Notices.txt` and `SOURCES.txt` with the
  exact source packages, plus the AppImage runtime's licenses. The Linux
  About box credits Qt under the GNU LGPL and the Help menu gains About Qt.

- Update checks move to the shared Updraft package. Lucerne now offers the
  disk image built for this Mac's architecture instead of whichever one was
  uploaded first, stamps downloads with the quarantine attribute so Gatekeeper
  evaluates them on first open, always checks that the downloaded file is the
  promised size, and keeps honouring "Skip This Version" across a retag. A
  Check Now click made while a background check is running is queued and
  reported rather than dropped. An unparseable installed version or release
  tag shows a "Couldn't compare versions" alert naming it (an unreadable
  installed version used to report "You're up to date"), the download-failure
  alert comes to the front, the daily check runs at 90% of the interval so a
  punctual timer no longer skips a day, and a failed download's temporary
  file is deleted.

Earlier history lives in the commit log and the GitHub releases.
