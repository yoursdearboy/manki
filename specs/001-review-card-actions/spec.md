# Feature Specification: Review Screen Actions and Card Management

**Feature Branch**: `[001-review-card-actions]`

**Created**: 2026-09-24

**Status**: Draft

**Input**: User description: "Add to topright menu on review screen options: Add new card - navigate to new card screen, Edit card - navigate to edit card screen, Flag card - dropdown menu as now, Deck settings - navigate to deck settings screen. Add new card screen displays Front and Back fields. Edit card screen displays the same screen but prefilled."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Add New Card from Review Screen (Priority: P1)

While reviewing cards or when viewing a deck's study session, a learner identifies a new concept they want to memorize. The learner opens the top-right menu, selects "Add new card", enters text into the Front and Back fields on the card creation screen, and saves it. The new card is added to the active deck, and the user returns seamlessly to their review session.

**Why this priority**: Quick card capture during active review is essential for knowledge retention. Learners frequently realize missing prerequisite knowledge or related concepts while testing themselves.

**Independent Test**: Can be tested independently by navigating to a deck's review screen, choosing "Add new card" from the menu, typing text into Front and Back fields, saving, and verifying the new card exists in the deck.

**Acceptance Scenarios**:

1. **Given** a user is on the review screen for a deck, **When** they open the top-right menu and select "Add new card", **Then** the card creation screen is displayed with empty Front and Back text fields and Save/Cancel controls.
2. **Given** a user is on the card creation screen, **When** they fill in valid content for the Front and Back fields and tap Save, **Then** the new card is saved to the current deck and the user returns to the review screen.
3. **Given** a user is on the card creation screen, **When** they tap Cancel without saving, **Then** no card is created and the user returns to the review screen in the exact prior state.
4. **Given** a user is on the card creation screen with empty Front content, **When** they attempt to tap Save, **Then** saving is prevented and the user is prompted to provide content for the Front of the card.

---

### User Story 2 - Edit Current Card from Review Screen (Priority: P1)

While reviewing a card, a learner spots a typo, outdated information, or an incomplete explanation on the card. The learner opens the top-right menu, taps "Edit card", sees the card editing screen prefilled with the current card's Front and Back content, modifies the text, and saves. Upon returning to the review screen, the displayed card immediately reflects the edited text.

**Why this priority**: Correcting cards at the moment of review is one of the most critical maintenance actions in spaced repetition. Friction in fixing cards degrades long-term study quality.

**Independent Test**: Can be fully tested by starting a review session on an existing card, selecting "Edit card" from the top-right menu, modifying either field, saving, and confirming the current card displays the updated content.

**Acceptance Scenarios**:

1. **Given** a card is actively displayed on the review screen, **When** the user opens the top-right menu and taps "Edit card", **Then** the card editing screen is presented with the Front and Back fields prefilled with the current card's content.
2. **Given** a user modifies text in the Front or Back fields on the editing screen, **When** they tap Save, **Then** the card updates in the collection, the editing screen dismisses, and the current review card displays the updated text immediately.
3. **Given** a user modifies content on the editing screen, **When** they tap Cancel, **Then** modifications are discarded, the card remains unchanged, and the user returns to the review screen.

---

### User Story 3 - Access Deck Settings from Review Screen (Priority: P2)

While reviewing cards, a learner wishes to adjust settings for the current deck (such as app icon count inclusion, study reminders, or card sizing). The learner opens the top-right menu, selects "Deck settings", makes any adjustments on the deck settings screen, and returns to their review.

**Why this priority**: Providing direct access to deck configuration without exiting back to the main deck dashboard saves navigation steps and improves usability.

**Independent Test**: Can be tested by starting a review session, opening the menu, selecting "Deck settings", confirming the deck settings screen for the active deck appears, and returning to the review screen.

**Acceptance Scenarios**:

1. **Given** a user is on the review screen, **When** they open the top-right menu and select "Deck settings", **Then** the deck settings screen for the current deck is presented.
2. **Given** a user is on the deck settings screen, **When** they finish reviewing or modifying deck settings and navigate back, **Then** they return to the review screen with their session intact.

---

### User Story 4 - Flag Current Card from Review Screen (Priority: P2)

While reviewing a card, a learner wants to mark the card with a colored flag (e.g., Red, Orange, Blue, etc.) or clear its flag. The learner opens the top-right menu, selects "Flag card", picks a flag color from the dropdown submenu, and the flag status is updated with the active flag indicated.

**Why this priority**: Preserves existing functionality while consolidating all card and deck actions under a single unified menu.

**Independent Test**: Can be tested by opening the review menu on a card, selecting "Flag card", choosing a color, and verifying the card's flag status updates and shows a checkmark next to the active flag.

**Acceptance Scenarios**:

1. **Given** a card is displayed on the review screen, **When** the user opens the top-right menu, **Then** "Flag card" appears as a submenu option with all flag choices (No Flag, Red, Orange, Green, Blue, Pink, Turquoise, Purple) and an indicator for the currently assigned flag.
2. **Given** the user selects a flag color from the "Flag card" submenu, **When** the choice is tapped, **Then** the card's flag is updated immediately.

---

### Edge Cases

- **No Active Card / All Caught Up**: When a deck has no cards scheduled or due (showing "all caught up"), "Edit card" and "Flag card" MUST be disabled or hidden, while "Add new card" and "Deck settings" remain accessible.
- **Empty Field Submission**: If a user attempts to save a new or edited card with an empty Front field, the system MUST prevent submission and alert the user.
- **Discarding Unsaved Changes**: If a user makes changes in the card creation or editing screen and navigates back or cancels, the system MUST discard unsaved changes without corrupting existing card data.
- **Answer Shown State**: If the user is currently viewing the answer side of a card when opening "Edit card", saving edits and returning MUST maintain the appropriate side view without resetting the study timer or unexpected rating advances.
- **Audio/Media in Existing Card Content**: When editing cards that have media or formatting attached, textual Front and Back contents are editable without corrupting underlying references.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The review screen MUST provide a top-right action menu containing four options: "Add new card", "Edit card", "Flag card", and "Deck settings".
- **FR-002**: Selecting "Add new card" MUST open a card creation screen containing editable "Front" and "Back" fields.
- **FR-003**: The card creation screen MUST provide an action to save the new card into the current deck and an action to cancel without saving.
- **FR-004**: Selecting "Edit card" MUST open a card editing screen with the current card's Front and Back content prefilled into the respective fields.
- **FR-005**: Saving an edited card MUST persist the updated Front and Back content and immediately refresh the current card displayed on the review screen.
- **FR-006**: Selecting "Flag card" MUST present a submenu allowing the user to select from available flag colors or remove the flag, indicating the currently active flag.
- **FR-007**: Selecting "Deck settings" MUST navigate the user to the settings screen for the deck currently being reviewed.
- **FR-008**: "Edit card" and "Flag card" actions MUST only be active when there is a card currently being reviewed in the session.
- **FR-009**: The system MUST validate that the Front field is not blank before allowing a new or edited card to be saved.
- **FR-010**: Navigating away from or cancelling the card creation or card editing screen without saving MUST discard modifications and return the user to the review screen without altering collection data.

### Key Entities *(include if feature involves data)*

- **Review Menu**: The primary action menu accessible from the review screen navigation bar offering contextual actions for the session, the current card, and the deck.
- **Card**: A flashcard item in the collection containing a "Front" (prompt/question) and a "Back" (response/answer), associated with a specific deck, an optional flag color, and scheduling history.
- **Card Flag**: A color attribute assigned to a card (No Flag, Red, Orange, Green, Blue, Pink, Turquoise, Purple) used by learners to categorize or highlight cards during study.
- **Deck Settings**: The configuration parameters associated with a specific deck, including app icon badge inclusion, study reminder notifications, and display preferences.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can initiate adding a new card from the review screen in a single tap on the menu.
- **SC-002**: Card creation and card editing screens load with ready-to-type input fields within 1 second.
- **SC-003**: Saving an edited card updates the displayed card content on the review screen with zero required app or session restarts.
- **SC-004**: 100% of existing card flagging and deck settings configurations remain functional when accessed through the new unified menu.
- **SC-005**: 0% data loss or accidental overwriting occurs when canceling or dismissing card editing without saving.

## Assumptions

- **Default Note Type**: Adding a new card via the basic Front/Back interface creates a standard Basic note/card in the currently active deck.
- **Navigation Style**: Card creation, editing, and deck settings are presented as standard navigation views or modal sheets that permit clear save and dismiss interactions.
- **State Preservation**: Opening and returning from any menu option preserves the current review session position and deck queue.
- **Validation**: Front field non-emptiness is the sole mandatory validation rule required before saving; Back field may optionally be left empty if the user desires a prompt-only card.
