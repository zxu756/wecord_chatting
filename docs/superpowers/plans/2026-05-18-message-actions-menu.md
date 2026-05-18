# Message Actions Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-pass message action menu with copy, preview image, and delete own message.

**Architecture:** Keep message actions local to the chat thread UI and expose only one new repository method, `recallMessage`. Deletion is a soft delete through `messages.recalled_at`, performed by a narrow Supabase RPC so clients cannot broadly update message rows.

**Tech Stack:** Flutter/Riverpod, Flutter Clipboard API, Supabase RPC/migrations, existing widget and repository tests.

---

### Task 1: Soft Delete Backend Contract

**Files:**
- Modify: `lib/features/chats/chats_repository.dart`
- Modify: `test/features/chats/chats_repository_test.dart`
- Create: `supabase/migrations/202605180004_recall_messages.sql`
- Modify: `test/supabase/private_chat_schema_test.dart`

- [ ] Write a failing repository test that `recallMessage(messageId: 'message-1')` calls RPC `recall_message` with `target_message_id`.
- [ ] Write a failing schema test that migrations contain `create or replace function public.recall_message`, check `sender_id = auth.uid()`, set `recalled_at = now()`, and do not add broad `messages_update_*` policies.
- [ ] Implement `ChatsRepository.recallMessage`, `ChatsDataSource.rpc` call, and `_UninitializedChatsRepository` behavior.
- [ ] Add migration `202605180004_recall_messages.sql` with a security definer RPC that only recalls messages sent by `auth.uid()` in conversations where the caller is a member.
- [ ] Run `rtk flutter test test/features/chats/chats_repository_test.dart test/supabase/private_chat_schema_test.dart`.

### Task 2: Message Action Menu UI

**Files:**
- Modify: `lib/features/chats/chat_thread_screen.dart`
- Modify: `test/features/chats/chat_thread_screen_test.dart`

- [ ] Write failing widget tests for long-pressing a text message to show `Copy`, copying text, and not showing `Delete` for peer messages.
- [ ] Write failing widget tests for right-click/secondary tap or long-pressing an outgoing message to show `Delete`, call `recallMessage`, and refresh the thread.
- [ ] Write failing widget test that recalled messages render `Message deleted` and expose no copy/delete actions.
- [ ] Write failing widget test that image messages expose `Preview` in the action menu and open the same preview dialog.
- [ ] Implement the menu with `showModalBottomSheet`, using long press and secondary tap on the bubble.
- [ ] Use `Clipboard.setData` for text copy and `chatsRepositoryProvider.recallMessage` for delete.
- [ ] Run `rtk flutter test test/features/chats/chat_thread_screen_test.dart`.

### Task 3: Verification

**Files:**
- Affected Flutter, test, and migration files from Tasks 1-2.

- [ ] Run `rtk dart format ...` on touched Dart files.
- [ ] Run `rtk flutter analyze`.
- [ ] Run `rtk flutter test`.
- [ ] Run `rtk supabase db push` to apply `202605180004_recall_messages.sql`.
