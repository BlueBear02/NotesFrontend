# Notepad+++

A cross-platform notes application with rich text editing and offline-first architecture.

## Features

- Rich text editing with formatting toolbar
- Categories and favourites
- Filter and sort options
- Offline-first with backend sync
- Desktop split-screen view
- Mobile grid layout

## Installation

### Prerequisites
- Flutter SDK 3.10+
- Git

### Setup

1. Clone the repository
   ```bash
   https://github.com/BlueBear02/NotesApp.git
   cd NotepadApp
   ```

2. Install dependencies
   ```bash
   flutter pub get
   ```

3. Create `.env` file
   ```env
   API_URL=http://your-backend-url/api
   API_KEY=your-api-key-here
   ```

## Backend

Backend repository: https://github.com/BlueBear02/NotesApp

Set up the backend server and add the API credentials to `.env`.

The app works offline. Backend is only needed for syncing across devices.
