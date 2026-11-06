System Role: You are an expert Senior UI/UX Designer and Frontend Architect specializing in modern media-streaming applications.
Objective: Design a sleek, responsive, and accessible mobile-first app Similar to YouTube application featuring a dark-mode-first aesthetic (with light mode toggle), smooth micro-interactions, and a clean layout.

1. Design System & Tokens

• Color Palette:
	• Background Primary: #0F0F0F (Deep Obsidian / Dark Mode)
	• Background Secondary: #212121 (Card / Surface Gray)
	• Text Primary: #F1F1F1
	• Text Secondary: #AAAAAA
	• Accent Primary: #FF0000 (YouTube Signature Red)
	• Accent Secondary: #3EA6FF (Verified / Action Blue)
• Typography:
	• Heading Font: Inter or Roboto (Bold/Semi-bold)
	• Body Font: Inter (Regular/Medium)
• Spacing & Radius:
	• Base spacing unit: 8px grid
	• Card border radius: 12px
	• Button border radius: 24px (pill-shaped interactive elements)

2. Screen Architecture & Core Layouts

• Top Header (Fixed):
	• Left: MyTube Logo with custom red play-button icon + tiny badge.
	• Center: Expandable search bar with voice-search microphone icon (#212121 background, 1px subtle border #303030).
	• Right: Cast/Airplay icon.
• Horizontal Category Filter Bar (Sticky):
	• Active pill style: Solid white background with dark black text (#0F0F0F); inactive pills use #212121 with #F1F1F1 text.
• Video Feed (Vertical RecyclerView / Grid):
	• Thumbnail Container: 16:9 aspect ratio with rounded corners (12px), bottom-right timestamp badge (04:22 in semi-transparent black pill).
	• Metadata Row: bold video title (max 2 lines with ellipsis), relative publish time (Local • 2 days ago), and a 3-dot menu icon on the far right.
• Bottom Navigation Bar (Fixed Mobile Shell):
	• 5 core tabs with active red highlight and label

3. Key Interactive User Flows

• Video Player Page (Detail View):
	• Top half: Sticky/dockable 16:9 video player with custom playback controls (scrubber bar, playback speed, full-screen toggle).
	• Action Toolbar (Horizontal scrollable row below video): Like/Dislike pill combo, Share, Download, Save to Playlis, etc.
	• Up Next / Recommended Vertical List: Compact horizontal thumbnail cards (120px width) stacked underneath.
• Shorts Feed Flow:
	• Full-screen vertical swipeable video player (9:16).
	• Right-side floating action column: Like, Dislike, Share, etc.
	• Bottom overlay: title and other informations.

4. Micro-interactions & Polish

• Skeleton loading shimmer effect for video grids during network fetch.
• Haptic feedback and scale-down animation (scale(0.95)) on button taps.
• Smooth mini-player dock transition when swiping down from the full video player page.

5. Downloader UI (Download from link)

• Entry points:
	• Library header action "Download from link"; Settings > Downloads; the Android share sheet (opens straight into the flow); the clipboard prompt.
	• No sixth tab. The Downloads list lives under Settings > Downloads.
• Clipboard prompt (bottom sheet, surface #212121, sheet radius 16px):
	• Title "Link found in your clipboard", host and shortened path only, never the query string.
	• Three pill actions (24px radius): Download (primary), Stream (outlined), Dismiss (text).
• Options sheet:
	• Header: 16:9 thumbnail (12px radius, timestamp badge), title (max 2 lines), uploader • duration.
	• Pill switch Video | Audio. Quality rows with radio selection: "Best available" first, then heights; each row shows size or "Size unknown" and a small info note for codecs that may not play (accent secondary #3EA6FF).
	• Destination row, checkbox "Use these settings next time", Download button pinned to the bottom above the safe area.
• Downloads screen (Settings > Downloads):
	• Sections Active, Queued, Completed, Failed. Row: 120px 16:9 thumbnail, title (2 lines), status line (42% • 3.1 MB/s • 1 min left, Merging, Saving, Completed • 120 MB, Failed with reason), 2px red progress line, 3-dot menu (Pause, Resume, Cancel, Retry, Play, Share, Delete file).
	• Skeleton shimmer while loading; empty state with a "Paste a link" action.
• Notification: ongoing progress with title, percentage and speed, actions Pause and Cancel; completion opens the Downloads list.
• Micro-interactions: reuse scale-down (0.95) and haptic on primary buttons; honour reduced motion; no new animation primitives; colours only through theme tokens.

6. Downloader additions (playlists, live, accounts, advanced)

• Playlist sheet (bottom sheet, surface #212121): title and count, "Select all" and range pill, rows with 120px 16:9 thumbnail, title (2 lines), duration and a checkbox, pinned "Download N videos" button above the safe area.
• Options sheet additions: Subtitles row (language chips, "Auto-generated" toggle), "Embed chapters and thumbnail" switch, live badge (red pill, "LIVE") with "Record from start" and "Stop and keep" actions.
• Downloads row: "Part 1/2" label for recordings cut by the service timeout; "Sign in again" action for cookiesExpired; error rows name the next action.
• Settings > Downloads sections: Accounts (site rows with Sign in, Import cookies.txt, Remove), Network (Proxy, Wi-Fi only, Speed limit), Speed (Concurrent downloads, Fragments, aria2c switch), Extras (SponsorBlock, Subtitles), Engine (version, Check for update, Auto-update), Advanced (Extra arguments text field with inline validation errors).
• First-use notice (dialog, once): downloading can breach site terms, you are responsible, account cookies can get the account limited.
• Same rules as above: theme tokens only, scale-down and haptic on primary buttons, reduced motion honoured.
