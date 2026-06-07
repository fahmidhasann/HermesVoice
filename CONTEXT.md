# HermesVoice

A macOS menu-bar app for talking or typing to a Hermes agent from a floating
panel, summoned anywhere by a global hotkey. This glossary fixes the shared UI
vocabulary so design and code stay aligned.

## Surfaces

**Panel**:
The floating, fixed-size (540×540) surface the hotkey toggles. Hosts the chat
and history screens.
_Avoid_: window, popup, HUD, overlay

**Chat surface**:
The default screen inside the panel — status pill, conversation thread, input row.
_Avoid_: chat view, main screen

**History**:
The searchable list of past conversations; a second screen reached from the chat
surface and dismissed back to it.
_Avoid_: recents (the menu-bar list is "Recents"; the in-panel screen is "History")

## Layering

**Chrome**:
The framing UI around the conversation — header, status pill, input bar, chips,
buttons. Chrome may use translucent materials.
_Avoid_: controls, frame

**Content**:
What the user reads — message bubbles and the live transcript. Content stays
near-solid for legibility; it is never translucent.
_Avoid_: body, message area

## State

**Status pill**:
The header capsule showing the current lifecycle state (Ready, Listening,
Transcribing, Sending, Responding, Done, Error).
_Avoid_: status badge, indicator

**Listening**:
The user-facing name for the state while the mic is capturing speech.
"Recording" refers to the underlying audio capture, not the UI state.
_Avoid_: recording (for the UI state)

**Tool activity row**:
The ephemeral "Hermes is using…" row shown while a tool step runs; never
persisted in the transcript.
_Avoid_: tool call, step row

## Sessions

**Session**:
One conversation with the agent. Exactly one is the foreground session (mirrored
into the panel); others may keep streaming as background sessions.
_Avoid_: chat, thread (for the unit of conversation)

**Voice flow**:
How dictation becomes a sent message: review-send (edit before sending),
auto-send (sends after a pause), or push-to-talk (hold to record, release to send).
_Avoid_: voice mode, input mode
