// The push of a monitoring alert (K3) as a push of the scheduled-dispatch
// function.
//
// claim_ops_alert_pushes (migration 202610260170) hands out the devices of
// the owners and moderators for an alert with severity 'fail', each row
// already worded in the device's language (the alert's own English or Chinese
// text), tag `ops-alert-<id>`, opening the admin console. Quiet hours and Do
// Not Disturb apply as for every push that is not about a message. This only
// reshapes a row into a PushTarget; it is kept out of logic.ts so that file
// stays untouched by this feature.
import type { PushTarget } from "./logic.ts";

/// A row of claim_ops_alert_pushes.
export interface OpsAlertPushRow {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  title: string;
  body: string;
  tag: string;
  url: string;
}

/// An alert as a push: one tag per alert, so a device reached twice shows it
/// once.
export function opsAlertTarget(row: OpsAlertPushRow): PushTarget {
  return {
    subscription_id: row.subscription_id,
    endpoint: row.endpoint,
    p256dh: row.p256dh,
    auth: row.auth,
    conversation_id: null,
    circle_id: null,
    title: row.title,
    body: row.body,
    tag: row.tag,
    url: row.url,
  };
}
