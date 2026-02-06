# Quick Fix: SMS Not Sending

## The Error
```
❌ Failed to send SMS: [firebase_functions/internal] Failed to send OTP. Please try again later.
```

## Most Likely Causes:
1. **Cloud Function not deployed** ❌
2. **Twilio credentials not configured** ❌

## Step-by-Step Fix:

### Step 1: Set Twilio Credentials

Get your Twilio credentials from https://console.twilio.com:
- **Account SID** (starts with `AC...`)
- **Auth Token** (click eye icon to reveal)
- **Phone Number** (from Phone Numbers → Active numbers)

Then run these commands:

```bash
firebase functions:config:set twilio.account_sid="YOUR_ACCOUNT_SID"
firebase functions:config:set twilio.auth_token="YOUR_AUTH_TOKEN"
firebase functions:config:set twilio.phone_number="+1234567890"
```

**Example:**
```bash
firebase functions:config:set twilio.account_sid="AC1234567890abcdef"
firebase functions:config:set twilio.auth_token="your_auth_token_here"
firebase functions:config:set twilio.phone_number="+15551234567"
```

### Step 2: Verify Config is Set

```bash
firebase functions:config:get
```

You should see:
```json
{
  "twilio": {
    "account_sid": "AC...",
    "auth_token": "...",
    "phone_number": "+1234567890"
  }
}
```

### Step 3: Install Dependencies (if not done)

```bash
cd functions
npm install
cd ..
```

### Step 4: Deploy Cloud Functions

```bash
firebase deploy --only functions:sendPasswordResetOTP,functions:resetPasswordByPhone
```

Or deploy all functions:
```bash
firebase deploy --only functions
```

### Step 5: Test Again

1. Open your app
2. Go to Login → Forgot Password
3. Enter phone number
4. Click "Send OTP"
5. Check your phone for SMS

## Check Function Logs

If it still fails, check the logs:

```bash
firebase functions:log --only sendPasswordResetOTP
```

Or check in Firebase Console:
1. Go to https://console.firebase.google.com
2. Select your project
3. Functions → Logs
4. Look for `sendPasswordResetOTP` errors

## Common Issues:

### "Twilio credentials not configured"
- Make sure you ran `firebase functions:config:set` commands
- Verify with `firebase functions:config:get`
- Redeploy functions after setting config

### "Function not found"
- Make sure you deployed: `firebase deploy --only functions`
- Check Firebase Console → Functions → should see `sendPasswordResetOTP`

### "Network error" or "Connection abort"
- Check your internet connection
- Make sure Firebase project is correct
- Try again after a few seconds
