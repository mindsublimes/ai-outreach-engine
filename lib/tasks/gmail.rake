# frozen_string_literal: true

namespace :gmail do
  desc 'Instructions to get a new Gmail refresh token (token expired/revoked)'
  task refresh_token: :environment do
    puts <<~INSTRUCTIONS

      Gmail refresh token expired or revoked. Get a new one:

      === Option A: OAuth 2.0 Playground (easiest) ===

      1. In Google Cloud Console → APIs & Services → Credentials → your OAuth 2.0 Client:
         Add "https://developers.google.com/oauthplayground" to Authorized redirect URIs

      2. Go to https://developers.google.com/oauthplayground/

      3. Click the gear icon (top right) → check "Use your own OAuth credentials"

      4. Enter your GMAIL_CLIENT_ID and GMAIL_CLIENT_SECRET

      5. In the left panel, find "Gmail API v1" → check "https://www.googleapis.com/auth/gmail.compose"

      6. Click "Authorize APIs" → sign in with your Gmail account → Allow

      7. Click "Exchange authorization code for tokens"

      8. Copy the "Refresh token" value

      9. Update GMAIL_REFRESH_TOKEN in Render (Environment → edit variable)

      10. Redeploy the web service

      === Option B: Manual OAuth flow ===

      1. Add redirect URI in Google Cloud Console:
         https://developers.google.com/oauthplayground
         (or http://localhost for local testing)

      2. Visit (replace YOUR_CLIENT_ID):
         https://accounts.google.com/o/oauth2/v2/auth?client_id=YOUR_CLIENT_ID&redirect_uri=https://developers.google.com/oauthplayground&response_type=code&scope=https://www.googleapis.com/auth/gmail.compose&access_type=offline&prompt=consent

      3. After authorizing, you'll get a code in the URL. Use the Playground to exchange it.

    INSTRUCTIONS
  end
end
