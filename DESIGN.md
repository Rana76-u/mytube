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