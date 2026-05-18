insert into storage.buckets (id, name, public)
values ('chat-images', 'chat-images', false)
on conflict (id) do update
set public = false;

create policy chat_images_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'chat-images'
    and public.is_current_user_conversation_member(
      ((storage.foldername(name))[1])::uuid
    )
  );

create policy chat_images_insert_member
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'chat-images'
    and public.is_current_user_conversation_member(
      ((storage.foldername(name))[1])::uuid
    )
  );
