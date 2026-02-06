# Twilio Setup - Quick Guide

## Step 1: Get Your Twilio Credentials

1. Go to https://console.twilio.com
2. **Dashboard** → Copy:
   - **Account SID** (starts with `AC...`)
   - **Auth Token** (click eye icon to reveal)
3. **Phone Numbers** → **Manage** → **Active numbers**
   - Copy your Twilio phone number (format: `+1234567890`)

## Step 2: Set Firebase Configuration

Run these commands (replace with your actual values):

```bash
firebase functions:config:set twilio.account_sid="YOUR_ACCOUNT_SID"
firebase functions:config:set twilio.auth_token="YOUR_AUTH_TOKEN"
firebase functions:config:set twilio.phone_number="+1234567890"
```

**Example:**
```bash
firebase functions:config:set twilio.account_sid="AC1234567890abcdef1234567890"
firebase functions:config:set twilio.auth_token="your_auth_token_here"
firebase functions:config:set twilio.phone_number="+15551234567"
```

## Step 3: Install Dependencies

```bash
cd functions
npm install
cd ..
```

## Step 4: Deploy Firestore Rules

```bash
firebase deploy --only firestore:rules
```

## Step 5: Deploy Cloud Functions

```bash
firebase deploy --only functions
```

Or deploy specific functions:
```bash
firebase deploy --only functions:sendPasswordResetOTP,functions:resetPasswordByPhone
```

## Step 6: Test

1. Open your app
2. Go to Login → Forgot Password
3. Enter phone number
4. Click "Send OTP"
5. Check your phone for SMS with OTP code
6. Enter OTP and reset password

## Verify Configuration

Check your config is set correctly:
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

## Troubleshooting

### "Twilio credentials not configured"
- Make sure you ran `firebase functions:config:set` commands
- Verify with `firebase functions:config:get`

### "Permission denied" error
- Deploy Firestore rules: `firebase deploy --only firestore:rules`

### SMS not received
- Check Twilio Console → Monitor → Logs
- Verify phone number format (must include country code: `+639123456789`)
- Check Twilio account has credits
