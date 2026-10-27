-- Behaviour checks for the L6 scale work (migrations 202610281200-202610281220):
-- a page of a big circle's or group's members, the member_limit of
-- get_circle_detail, and the push claim in batches of people. Run by
-- test/supabase/scale_pages_test.dart against the local database: it applies
-- every migration after the local baseline in a transaction, plays people
-- through their roles, and rolls everything back. Run from the repository
-- root.
--
-- What it walks through: that pages put together are the whole list in the
-- order get_circle_detail uses, that a search finds the same people as the
-- filter would, who may read a list (members only, not a suspended circle,
-- not people who cannot see a channel), that member_limit keeps the caller,
-- and that the batches of a push claim are the whole claim, once, with the
-- same people left out (muted, do not disturb, blocked, sender).
\set ON_ERROR_STOP on

begin;

do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
set local client_min_messages = warning;

-- Every migration after the local baseline (202610170001), in order.
