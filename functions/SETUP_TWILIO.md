# Setting Up Twilio in Firebase

## Step 1: Get Twilio Credentials

1. Go to https://console.twilio.com
2. Sign up or log in (free trial available with $15.50 credit)
3. From the Dashboard, copy:
   - **Account SID** (starts with `AC...`)
   - **Auth Token** (click to reveal)
4. Go to **Phone Numbers** → **Manage** → **Active numbers**
   - Copy your Twilio phone number (format: `+1234567890`)

## Step 2: Set Configuration in Firebase

Run these commands in your terminal (from project root):

```bash
# Set Twilio Account SID
firebase functions:config:set twilio.account_sid="YOUR_ACCOUNT_SID_HERE"

# Set Twilio Auth Token
firebase functions:config:set twilio.auth_token="YOUR_AUTH_TOKEN_HERE"

# Set Twilio Phone Number
firebase functions:config:set twilio.phone_number="+1234567890"
```

**Example:**
```bash
firebase functions:config:set twilio.account_sid="AC1234567890abcdef1234567890"
firebase functions:config:set twilio.auth_token="your_auth_token_here"
firebase functions:config:set twilio.phone_number="+15551234567"
```

## Step 3: Verify Configuration

Check that your config was set correctly:

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

## Step 4: Deploy Functions

After setting config, deploy your functions:

```bash
firebase deploy --only functions
```

## Important Notes

- **Security**: Config values are encrypted and only accessible in Cloud Functions
- **Updates**: If you change config, you need to redeploy functions:
  ```bash
  firebase functions:config:set twilio.auth_token="new_token"
  firebase deploy --only functions
  ```
- **Viewing Config**: You can also view config in Firebase Console:
  - Go to Firebase Console → Functions → Configuration

## Alternative: Using Environment Variables (Firebase Functions v2+)

If you're using Firebase Functions v2, you can also use environment variables:

```bash
firebase functions:secrets:set TWILIO_ACCOUNT_SID
firebase functions:secrets:set TWILIO_AUTH_TOKEN
firebase functions:secrets:set TWILIO_PHONE_NUMBER
```

But the `functions:config:set` method (shown above) works for both v1 and v2.
