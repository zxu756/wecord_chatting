-- The global "online-users" presence channel is gone.
--
-- 202610190070_presence_visibility.sql moved online status to the server:
-- visible_presence() answers only about people the caller shares something
-- with, and the database nudges each viewer on their own private channel
-- presence-updates:<viewer id>. Nothing needs "online-users" any more, and as
-- long as its policies existed any signed-in account could still join it and
-- read the id and status of everyone who is tracked on it (the apps from
-- before 202610190070 still track themselves there, with their status).
--
-- Dropping the policies means a private channel on that topic can not be
-- joined or tracked on by anyone. An older app that still joins it gets a
-- channel error and keeps working: it shows nobody online (apart from the
-- person themselves) until it is updated. Its own heartbeat (touch_presence)
-- keeps going, so updated apps still see that person.
--
-- Deploy order: 202610190070, then the apps (web first, then the stores),
-- then this migration - when the old apps matter little. Running it earlier
-- only makes the old apps show nobody online sooner.

drop policy if exists online_users_receive on realtime.messages;
drop policy if exists online_users_send on realtime.messages;
