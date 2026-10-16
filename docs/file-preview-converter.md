# Office previews on the web: the Gotenberg converter

The iOS and macOS apps show Word, Excel, PowerPoint, OpenDocument, RTF and
iWork files natively with Quick Look. Browsers can't, so the web app asks the
`office-preview` Edge Function for a PDF version and shows it in its PDF
viewer. The function converts with [Gotenberg](https://gotenberg.dev)
(LibreOffice behind an HTTP API), keeps the PDF in the private
`file-previews` bucket (`<message id>/preview.pdf`) and returns a one-hour
signed link. Later requests for the same message reuse the stored PDF.

Until a converter is set up the function answers
`503 {"error": "preview_not_configured"}` and the web app says "Preview
isn't available here" with a Download button. Nothing else breaks.

## How the pieces talk

```
browser ──(user JWT)──▶ office-preview ──(Basic auth)──▶ Gotenberg on Cloud Run
                           │  reads the message as the user (RLS decides)
                           │  downloads the file with the service role
                           └─ stores the PDF in file-previews, signs a link
```

The function reads three secrets:

| Secret | Value |
| --- | --- |
| `GOTENBERG_URL` | The service's base URL, e.g. `https://gotenberg-xxxxx.a.run.app` (no path) |
| `GOTENBERG_USERNAME` | The Basic auth user you gave Gotenberg |
| `GOTENBERG_PASSWORD` | The Basic auth password you gave Gotenberg |

It POSTs the file to `<GOTENBERG_URL>/forms/libreoffice/convert` with the
header `Authorization: Basic base64(GOTENBERG_USERNAME:GOTENBERG_PASSWORD)`.
If any of the three is missing it answers `preview_not_configured`.

**Why Basic auth on Gotenberg rather than Cloud Run IAM:** Gotenberg 8 has
Basic auth built in (`--api-enable-basic-auth`), so the service checks a
long random password itself and needs no proxy. Cloud Run IAM would make the
Edge Function mint Google ID tokens from a service account key, which is
more moving parts and another secret to rotate. Cloud Run therefore allows
unauthenticated invocations at the HTTP level, and every request without
the right password gets `401` from Gotenberg. Use a password of 32+ random
characters and keep it only in Secret Manager and Supabase secrets.

We also turn off the features the function doesn't use, so a leaked
password can't make the service fetch URLs: webhooks
(`--webhook-disable`), remote downloads (`--api-disable-download-from`) and
the Chromium routes (`--chromium-disable-routes`).

## Google Cloud Run (recommended)

Cloud Run scales to zero when nobody previews anything, so it costs nothing
while idle; the first preview after a quiet spell waits a few seconds for
LibreOffice to start.

Settings: region `australia-southeast1`, memory `2Gi`, CPU `2`,
min instances `0`, max instances `2`, container port `3000`, request
timeout `120s`. Replace every `<…>` below with your own values.

1. Pick the project and enable the APIs:

   ```sh
   gcloud config set project <your-gcp-project-id>
   gcloud services enable run.googleapis.com secretmanager.googleapis.com
   ```

2. Keep the password in Secret Manager (generate it, don't type it):

   ```sh
   openssl rand -base64 36 | tr -d '\n' > /tmp/gotenberg-password
   gcloud secrets create gotenberg-password --data-file=/tmp/gotenberg-password
   ```

   Let Cloud Run's runtime service account read it (by default
   `<project-number>-compute@developer.gserviceaccount.com`):

   ```sh
   gcloud secrets add-iam-policy-binding gotenberg-password \
     --member="serviceAccount:<project-number>-compute@developer.gserviceaccount.com" \
     --role="roles/secretmanager.secretAccessor"
   ```

3. Deploy the official image straight from Docker Hub:

   ```sh
   gcloud run deploy gotenberg \
     --image=docker.io/gotenberg/gotenberg:8 \
     --region=australia-southeast1 \
     --port=3000 \
     --memory=2Gi \
     --cpu=2 \
     --min-instances=0 \
     --max-instances=2 \
     --concurrency=4 \
     --timeout=120s \
     --allow-unauthenticated \
     --set-env-vars=GOTENBERG_API_BASIC_AUTH_USERNAME=<username> \
     --set-secrets=GOTENBERG_API_BASIC_AUTH_PASSWORD=gotenberg-password:latest \
     --args=gotenberg,--api-enable-basic-auth,--api-timeout=110s,--webhook-disable,--api-disable-download-from,--chromium-disable-routes,--libreoffice-auto-start
   ```

   `--args` replaces the image's command (`gotenberg`) and keeps its entry
   point, as Gotenberg's docs ask ("override the command, not the
   entrypoint"), so the list starts with `gotenberg` itself.
   `--api-timeout=110s` stays under the 120 s request timeout, and the
   function gives up at 110 s as well.

4. Check it (`/health` answers without a password; a conversion without
   it must fail with 401):

   ```sh
   URL=$(gcloud run services describe gotenberg --region=australia-southeast1 --format='value(status.url)')
   curl -s "$URL/health"
   curl -s -o /dev/null -w '%{http_code}\n' -X POST "$URL/forms/libreoffice/convert"   # 401
   curl -s -u '<username>:<password>' -F files=@sample.docx \
     "$URL/forms/libreoffice/convert" -o sample.pdf                                  # a PDF
   ```

5. Give the function the converter (placeholders, from your shell, not
   committed anywhere):

   ```sh
   supabase secrets set \
     GOTENBERG_URL=https://<your-gotenberg-service>.a.run.app \
     GOTENBERG_USERNAME=<username> \
     GOTENBERG_PASSWORD=<password>
   ```

To rotate the password: add a new version of `gotenberg-password`, deploy a
new revision (`gcloud run services update gotenberg --region=australia-southeast1`)
and run `supabase secrets set GOTENBERG_PASSWORD=<new password>`.

## Fly.io (alternative)

Fly machines can also stop when idle. With `flyctl` signed in:

```sh
fly launch --image gotenberg/gotenberg:8 --name <your-app-name> \
  --region syd --internal-port 3000 --no-deploy
fly secrets set GOTENBERG_API_BASIC_AUTH_USERNAME=<username> \
  GOTENBERG_API_BASIC_AUTH_PASSWORD=<password> --app <your-app-name>
```

In the generated `fly.toml` set the command line and let machines stop
when idle:

```toml
[experimental]
  cmd = ["gotenberg", "--api-enable-basic-auth", "--api-timeout=110s",
         "--webhook-disable", "--api-disable-download-from",
         "--chromium-disable-routes", "--libreoffice-auto-start"]

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0

[[vm]]
  memory = "2gb"
  cpus = 2
```

Then `fly deploy --app <your-app-name>` and:

```sh
supabase secrets set \
  GOTENBERG_URL=https://<your-app-name>.fly.dev \
  GOTENBERG_USERNAME=<username> \
  GOTENBERG_PASSWORD=<password>
```

## Deploying the Supabase side

```sh
supabase db push                          # adds the file-previews bucket and policies
supabase functions deploy office-preview  # verify_jwt is on (supabase/config.toml)
```

## What the function answers

| Status | Body | When |
| --- | --- | --- |
| 200 | `{"status": "ok", "url": "<signed link>", "cached": true \| false}` | Converted now or earlier |
| 400 | `{"error": "invalid_body" \| "invalid_message_id"}` | No `message_id` UUID |
| 401 | `{"error": "unauthorized"}` | No or bad session |
| 404 | `{"error": "not_found"}` | The caller can't see the message, it isn't a file, or the file is gone |
| 413 | `{"error": "file_too_large"}` | Over 50 MB |
| 415 | `{"error": "unsupported_type"}` | Not an Office/iWork file |
| 502 | `{"error": "conversion_failed"}` | Gotenberg failed or timed out (the app offers Retry) |
| 503 | `{"error": "preview_not_configured"}` | A Gotenberg secret is missing |

## Clean-up

A preview stops being readable as soon as its message is deleted (the
bucket's read policy checks the message as the caller). Storage objects
can't be deleted from SQL, so `stale_file_previews()` lists previews whose
message is gone and each call of the function removes up to 20 of them in
the background.
