# How to Deploy Firebase Cloud Functions

## Prerequisites

1. **Firebase CLI installed**: `npm install -g firebase-tools`
2. **Logged in to Firebase**: `firebase login`
3. **Twilio account** (for SMS): Sign up at https://www.twilio.com

## Step 1: Install Dependencies

```bash
cd functions
npm install
```

This will install `twilio` and other dependencies.

## Step 2: Set Twilio Configuration

You need to set your Twilio credentials as Firebase config:

```bash
firebase functions:config:set twilio.account_sid="YOUR_TWILIO_ACCOUNT_SID"
firebase functions:config:set twilio.auth_token="YOUR_TWILIO_AUTH_TOKEN"
firebase functions:config:set twilio.phone_number="+1234567890"
```

**Where to find Twilio credentials:**
1. Go to https://console.twilio.com
2. Dashboard → Account SID and Auth Token
3. Phone Numbers → Get your Twilio phone number (format: +1234567890)

## Step 3: Deploy Functions

### Deploy all functions:
```bash
firebase deploy --only functions
```

### Deploy specific functions only:
```bash
firebase deploy --only functions:sendPasswordResetOTP,functions:resetPasswordByPhone
```

## Step 4: Verify Deployment

After deployment, check Firebase Console:
1. Go to https://console.firebase.google.com
2. Select your project
3. Functions → You should see `sendPasswordResetOTP` and `resetPasswordByPhone`

## Testing

The functions are now callable from your Flutter app. The app will automatically use the deployed functions.

## Troubleshooting

### Error: "Twilio credentials not configured"
- Make sure you ran the `firebase functions:config:set` commands
- Verify with: `firebase functions:config:get`

### Error: "Function deployment failed"
- Check Firebase Console → Functions → Logs for error details
- Make sure Node.js version matches (should be 20 based on package.json)

### SMS not sending
- Verify Twilio account has credits
- Check Twilio Console → Monitor → Logs for SMS delivery status
- Verify phone number format (must include country code, e.g., +639123456789)

## Updating Functions

To update functions after making changes:

1. Edit `functions/index.js`
2. Run: `firebase deploy --only functions`

Or deploy specific function:
```bash
firebase deploy --only functions:sendPasswordResetOTP
```
