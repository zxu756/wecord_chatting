# WeCord Image Messages Design

## Goal

Add a first useful image-message milestone for private chats: pick one local image, upload it to Supabase Storage, send it as a chat message, render it inline, and open a larger preview.

## MVP Scope

- Users can pick one image from the system picker on iOS, macOS, and Web.
- The app uploads the selected image to a private Supabase Storage bucket named `chat-images`.
- The app inserts a `messages` row with `type = 'image'` and an `attachment` JSON payload.
- Chat threads render image messages as rounded image bubbles.
- Tapping an image bubble opens a simple full-screen preview.
- Upload/send failures leave the composer usable and show a retryable error.

## Attachment Shape

Image messages use the existing `messages.attachment` JSON column:

```json
{
  "kind": "image",
  "bucket": "chat-images",
  "path": "conversation-id/message-id/file-name.jpg",
  "mime_type": "image/jpeg",
  "size": 123456,
  "width": null,
  "height": null
}
```

`width` and `height` are nullable in this milestone. They are reserved for better layout and aspect-ratio placeholders later.

## Storage And Security

The migration creates a private `chat-images` bucket. Storage object paths start with the conversation id so Storage policies can check membership using the existing `public.is_current_user_conversation_member(uuid)` helper.

Authenticated conversation members can:

- upload objects under a conversation path they belong to
- read objects under a conversation path they belong to

Delete/update policies are intentionally deferred until message deletion/recall exists.

## Future Extensions

- Multiple images per send: either send several image messages or introduce an album message type using the same attachment shape in an array.
- Camera capture: reuse the same repository method after `image_picker` returns camera media.
- Client compression: add a pre-upload image processing step while keeping the upload/send API stable.
- Upload progress: split the current send button state into an upload task state surfaced by the repository.
- Image dimensions: populate `width` and `height` to avoid layout shift.
- Files and videos: generalize attachment models to `kind = file | video | voice` and reuse Storage policies.
- Message actions: delete/recall should remove or orphan Storage objects through a narrow RPC or server-side cleanup job.
- Private realtime channels: when group chat and circles land, move activity and media access toward channel-level authorization.

## Test Strategy

- Schema tests verify the bucket and Storage policies exist.
- Model tests verify image attachment serialization.
- Repository tests verify image upload path construction and image message insertion.
- Widget tests verify image messages render, can be previewed, and picker/send errors surface.
- Full verification uses `rtk flutter analyze` and `rtk flutter test`.
