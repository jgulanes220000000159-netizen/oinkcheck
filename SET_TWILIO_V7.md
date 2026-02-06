# Set Twilio Credentials for Firebase Functions v7

## The Problem
Firebase Functions v7 removed `functions.config()`. We need to use environment variables instead.

## Step 1: Set Twilio Credentials as Secrets

Run these commands (replace with your actual values):

```bash
# Set Twilio Account SID
firebase functions:secrets:set TWILIO_ACCOUNT_SID

# Set Twilio Auth Token  
firebase functions:secrets:set TWILIO_AUTH_TOKEN

# Set Twilio Phone Number
firebase functions:secrets:set TWILIO_PHONE_NUMBER
```

**When prompted, paste your values:**
- `TWILIO_ACCOUNT_SID`: Your Account SID (starts with `AC...`)
- `TWILIO_AUTH_TOKEN`: Your Auth Token
- `TWILIO_PHONE_NUMBER`: Your Twilio phone number (e.g., `+639486334369`)

## Step 2: Grant Access to Secrets

After setting secrets, grant access to your functions:

```bash
firebase functions:secrets:access TWILIO_ACCOUNT_SID --project YOUR_PROJECT_ID
firebase functions:secrets:access TWILIO_AUTH_TOKEN --project YOUR_PROJECT_ID  
firebase functions:secrets:access TWILIO_PHONE_NUMBER --project YOUR_PROJECT_ID
```

Or update your `functions/index.js` to grant access automatically (already done in code).

## Step 3: Redeploy Functions

```bash
firebase deploy --only functions:sendPasswordResetOTP,functions:resetPasswordByPhone
```

Or deploy all functions:
```bash
firebase deploy --only functions
```

## Alternative: Set as Environment Variables (Non-Secret)

If you prefer not to use secrets (less secure), you can set them as regular environment variables in Firebase Console:

1. Go to https://console.firebase.google.com
2. Select your project
3. Functions → Configuration → Environment variables
4. Add:
   - `TWILIO_ACCOUNT_SID` = `YOUR_TWILIO_ACCOUNT_SID`
   - `TWILIO_AUTH_TOKEN` = `YOUR_TWILIO_AUTH_TOKEN`
   - `TWILIO_PHONE_NUMBER` = `+1234567890`

Then redeploy functions.

## Verify

After deployment, test sending an OTP. Check logs:
```bash
firebase functions:log --only sendPasswordResetOTP
```

You should see: `✅ OTP sent to +63...`
