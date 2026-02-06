# Quick Fix: Update Twilio for Firebase Functions v7

## ✅ Code Updated
I've updated the code to use Firebase Functions v7 compatible environment variables.

## 🔧 Set Twilio Credentials

You have **2 options**:

### Option 1: Using Firebase Console (Easiest)

1. Go to: https://console.firebase.google.com
2. Select your project: **oinkcheck-d07df**
3. Click **Functions** → **Configuration** → **Environment variables**
4. Click **Add variable** and add these 3:

   | Variable Name | Value |
   |--------------|-------|
   | `TWILIO_ACCOUNT_SID` | `YOUR_TWILIO_ACCOUNT_SID` |
   | `TWILIO_AUTH_TOKEN` | `YOUR_TWILIO_AUTH_TOKEN` |
   | `TWILIO_PHONE_NUMBER` | `+1234567890` |

5. Click **Save**
6. Redeploy functions:
   ```bash
   firebase deploy --only functions:sendPasswordResetOTP,functions:resetPasswordByPhone
   ```

### Option 2: Using Firebase CLI Secrets (More Secure)

Run these commands one by one (you'll be prompted to enter the value):

```bash
echo "YOUR_TWILIO_ACCOUNT_SID" | firebase functions:secrets:set TWILIO_ACCOUNT_SID
echo "YOUR_TWILIO_AUTH_TOKEN" | firebase functions:secrets:set TWILIO_AUTH_TOKEN
echo "+1234567890" | firebase functions:secrets:set TWILIO_PHONE_NUMBER
```

Then redeploy:
```bash
firebase deploy --only functions
```

## ✅ Test

After deployment, try sending OTP again. It should work now!

Check logs if needed:
```bash
firebase functions:log --only sendPasswordResetOTP
```
