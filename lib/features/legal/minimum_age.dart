/// The youngest age WeCord accepts, in years. This is the ONE place the
/// number lives: the sign-up checkbox ("I am at least 13 ..."), the prompt
/// for existing accounts and the `{minimumAge}` in the Terms of Service and
/// the Privacy Policy (assets/legal/) all read it.
///
/// The owner confirmed 13+ on 2026-10-18, with no teen mode. Changing the age
/// is changing this number; the database stores only that a person confirmed
/// their age (profiles.age_confirmed_at, migration 202610220130), not which
/// age, so no migration is needed. The policy texts themselves are still
/// drafts pending the owner's review.
const minimumAge = 13;
