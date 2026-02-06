/**
 * Firebase Cloud Function to send password reset OTP via SMS (Twilio).
 * 
 * Setup:
 * 1. Install dependencies: npm install twilio
 * 2. Set environment variables:
 *    - TWILIO_ACCOUNT_SID
 *    - TWILIO_AUTH_TOKEN
 *    - TWILIO_PHONE_NUMBER (your Twilio phone number, e.g., +1234567890)
 * 3. Deploy: firebase deploy --only functions:sendPasswordResetOTP
 * 
 * Usage:
 * POST https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/sendPasswordResetOTP
 * Body: { "phoneNumber": "+639123456789", "otp": "123456" }
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const twilio = require('twilio');

admin.initializeApp();

const twilioClient = twilio(
  functions.config().twilio.account_sid,
  functions.config().twilio.auth_token
);

exports.sendPasswordResetOTP = functions.https.onCall(async (data, context) => {
  const { phoneNumber, otp } = data;

  if (!phoneNumber || !otp) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'phoneNumber and otp are required'
    );
  }

  // Format phone number (ensure it starts with +)
  const formattedPhone = phoneNumber.startsWith('+')
    ? phoneNumber
    : `+63${phoneNumber.replace(/^0/, '')}`; // Philippines country code

  try {
    // Send SMS via Twilio
    const message = await twilioClient.messages.create({
      body: `Your OinkCheck password reset code is: ${otp}. This code expires in 10 minutes.`,
      from: functions.config().twilio.phone_number,
      to: formattedPhone,
    });

    console.log(`OTP sent to ${formattedPhone}: ${message.sid}`);
    return { success: true, messageSid: message.sid };
  } catch (error) {
    console.error('Error sending SMS:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to send OTP. Please try again later.'
    );
  }
});

/**
 * Cloud Function to reset password using Admin SDK (for phone-based reset).
 * 
 * Usage:
 * POST https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/resetPasswordByPhone
 * Body: { "userId": "user123", "newPassword": "newPassword123" }
 */
exports.resetPasswordByPhone = functions.https.onCall(async (data, context) => {
  const { userId, newPassword } = data;

  if (!userId || !newPassword) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'userId and newPassword are required'
    );
  }

  if (newPassword.length < 8) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Password must be at least 8 characters'
    );
  }

  try {
    // Get user's email from Firestore (even if it's a placeholder)
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User not found');
    }

    const userData = userDoc.data();
    const phoneNumber = userData.phoneNumber;
    
    // Find the Firebase Auth user by email (placeholder format)
    const phoneDigits = phoneNumber.replace(/\D/g, '');
    const placeholderEmail = `phone_${phoneDigits}@oinkcheck.local`;

    // Get user by email
    const userRecord = await admin.auth().getUserByEmail(placeholderEmail);
    
    // Update password using Admin SDK
    await admin.auth().updateUser(userRecord.uid, {
      password: newPassword,
    });

    console.log(`Password reset for user ${userId} (${placeholderEmail})`);
    return { success: true };
  } catch (error) {
    console.error('Error resetting password:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to reset password. Please try again later.'
    );
  }
});
