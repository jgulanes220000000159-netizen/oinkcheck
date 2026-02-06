/* Cloud Functions for OinkCheck notifications */

const functions = require("firebase-functions/v1");
const { defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

// Initialize admin SDK once
try {
  admin.app();
} catch (e) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

// Email configuration using environment parameters (v7 compatible)
const gmailEmail = defineString("GMAIL_EMAIL", {
  default: "your-email@gmail.com",
});
const gmailPassword = defineString("GMAIL_PASSWORD", {
  default: "your-app-password",
});

// Function to get transporter (lazy initialization to avoid calling .value() at module level)
function getTransporter() {
  return nodemailer.createTransport({
    service: "gmail", // You can change this to other services
    auth: {
      user: gmailEmail.value(),
      pass: gmailPassword.value(),
    },
  });
}

// Function to send email notification
async function sendEmailNotification(to, subject, htmlContent) {
  try {
    const transporter = getTransporter();
    const mailOptions = {
      from: gmailEmail.value(),
      to: to,
      subject: subject,
      html: htmlContent,
    };

    const result = await transporter.sendMail(mailOptions);
    console.log("Email sent successfully:", result.messageId);
    return { success: true, messageId: result.messageId };
  } catch (error) {
    console.error("Error sending email:", error);
    return { success: false, error: error.message };
  }
}

// Utility: send a notification to a list of device tokens
async function sendToTokens(tokens, payload) {
  if (!tokens || tokens.length === 0)
    return { successCount: 0, failureCount: 0 };
  const response = await messaging.sendEachForMulticast(
    { tokens, ...payload },
    false
  );
  return response;
}

// Utility: Save notification to Firestore
async function saveNotificationToFirestore(userId, notificationData) {
  try {
    const notificationId = db.collection("notifications").doc().id;
    await db
      .collection("notifications")
      .doc(notificationId)
      .set({
        id: notificationId,
        userId: userId,
        type: notificationData.type || "general",
        title: notificationData.title || "",
        body: notificationData.body || "",
        data: notificationData.data || {},
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        readAt: null,
      });
    return notificationId;
  } catch (error) {
    console.error("Error saving notification to Firestore:", error);
    return null;
  }
}

// Utility: Get all expert user IDs
async function getAllExpertUserIds() {
  try {
    const expertsSnapshot = await db
      .collection("users")
      .where("role", "in", ["expert", "head_veterinarian"])
      .get();
    return expertsSnapshot.docs.map((doc) => doc.id);
  } catch (error) {
    console.error("Error getting expert user IDs:", error);
    return [];
  }
}

// Trigger 1: When a new scan request is created → notify experts
exports.notifyExpertsOnNewRequest = functions.firestore
  .document("scan_requests/{requestId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const status = data.status || "pending";
    if (status !== "pending" && status !== "pending_review") return null;

    // If already notified for experts, skip
    if (data.expertsNotified === true) return null;

    const userName = data.userName || "A farmer";
    const requestId = context.params.requestId;

    const title = "New Review Request";
    const body = `${userName} submitted a pig disease scan for expert review.`;

    // Broadcast to all expert devices via topic
    await messaging.send({
      topic: "experts",
      notification: {
        title,
        body,
      },
      data: {
        type: "scan_request_created",
        requestId: String(requestId || ""),
        userName: String(userName || ""),
      },
    });

    // Save notification to Firestore for all experts
    const expertUserIds = await getAllExpertUserIds();
    const notificationPromises = expertUserIds.map((expertId) =>
      saveNotificationToFirestore(expertId, {
        type: "scan_request_created",
        title,
        body,
        data: {
          requestId: String(requestId || ""),
          userName: String(userName || ""),
        },
      })
    );
    await Promise.all(notificationPromises);

    // Mark as notified to prevent duplicates
    try {
      await db
        .collection("scan_requests")
        .doc(requestId)
        .set({ expertsNotified: true }, { merge: true });
    } catch (_) {}

    return null;
  });

// Trigger 1b: When status transitions into pending/pending_review → notify experts
exports.notifyExpertsOnPendingUpdate = functions.firestore
  .document("scan_requests/{requestId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const beforeStatus = before.status || "";
    const afterStatus = after.status || "";

    const becamePending =
      beforeStatus !== afterStatus &&
      (afterStatus === "pending" || afterStatus === "pending_review");

    if (!becamePending) return null;

    // If experts already notified, skip
    if (after.expertsNotified === true) return null;

    const userName = after.userName || before.userName || "A farmer";
    const requestId = context.params.requestId;

    const title = "New Review Request";
    const body = `${userName} submitted a pig disease scan for expert review.`;

    await messaging.send({
      topic: "experts",
      notification: { title, body },
      data: {
        type: "scan_request_created",
        requestId: String(requestId || ""),
        userName: String(userName || ""),
      },
    });

    // Save notification to Firestore for all experts
    const expertUserIds = await getAllExpertUserIds();
    const notificationPromises = expertUserIds.map((expertId) =>
      saveNotificationToFirestore(expertId, {
        type: "scan_request_created",
        title,
        body,
        data: {
          requestId: String(requestId || ""),
          userName: String(userName || ""),
        },
      })
    );
    await Promise.all(notificationPromises);

    // Mark as notified to prevent duplicates
    try {
      await db
        .collection("scan_requests")
        .doc(requestId)
        .set({ expertsNotified: true }, { merge: true });
    } catch (_) {}

    return null;
  });

// Trigger 2: When a scan request is reviewed/completed → notify the farmer
exports.notifyUserOnReviewCompleted = functions.firestore
  .document("scan_requests/{requestId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const beforeStatus = before.status || "";
    const afterStatus = after.status || "";

    // Only proceed when transitioning into completed/reviewed
    if (
      beforeStatus === afterStatus ||
      (afterStatus !== "completed" && afterStatus !== "reviewed")
    ) {
      return null;
    }

    // If already notified user for completion, skip
    if (after.userNotifiedCompleted === true) return null;

    const userId = after.userId || before.userId;
    if (!userId) return null;

    // Get farmer token and notification preference
    const userDoc = await db.collection("users").doc(userId).get();
    const user = userDoc.exists ? userDoc.data() || {} : {};
    const token = user.fcmToken;
    const enabled = user.enableNotifications;
    if (!token || enabled === false) return null;

    const expertName = after.expertName || "An expert";
    const title = "Your review is ready";
    const body = `${expertName} has completed the analysis of your pig disease scan.`;

    const requestId = context.params.requestId;

    const payload = {
      notification: {
        title,
        body,
      },
      data: {
        type: "scan_request_completed",
        requestId: String(requestId || ""),
        expertName: String(expertName || ""),
      },
    };

    await sendToTokens([token], payload);

    // Save notification to Firestore for the farmer
    await saveNotificationToFirestore(userId, {
      type: "scan_request_completed",
      title,
      body,
      data: {
        requestId: String(requestId || ""),
        expertName: String(expertName || ""),
      },
    });

    // Mark as notified to prevent duplicates
    try {
      await db
        .collection("scan_requests")
        .doc(requestId)
        .set({ userNotifiedCompleted: true }, { merge: true });
    } catch (_) {}
    return null;
  });

// Trigger 3: When a user's status changes to "active" → send email notification
exports.notifyUserOnApproval = functions.firestore
  .document("users/{userId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const beforeStatus = before.status || "";
    const afterStatus = after.status || "";

    // Only proceed when status changes to "active"
    if (beforeStatus === afterStatus || afterStatus !== "active") {
      return null;
    }

    // If already notified for approval, skip
    if (after.emailNotifiedApproval === true) return null;

    const userEmail = after.email;
    const userName = after.fullName || "User";

    if (!userEmail) {
      console.log("No email found for user approval notification");
      return null;
    }

    const subject = "🎉 Welcome to OinkCheck - Your Account is Approved!";
    const htmlContent = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Account Approved - OinkCheck</title>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #4CAF50, #45a049); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
          .button { display: inline-block; background: #4CAF50; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }
          .footer { text-align: center; margin-top: 30px; color: #666; font-size: 14px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>🎉 Welcome to OinkCheck!</h1>
            <p>Your account has been approved and is now active</p>
          </div>
          <div class="content">
            <h2>Hello ${userName}!</h2>
            <p>Great news! Your OinkCheck account has been reviewed and approved by our team. You can now access all the features of our pig disease detection app.</p>
            
            <h3>What you can do now:</h3>
            <ul>
              <li>🔍 Scan pigs for disease detection</li>
              <li>📊 View detailed analysis reports</li>
              <li>👨‍⚕️ Get expert recommendations for treatment</li>
              <li>📱 Access your scan history and progress</li>
            </ul>
            
            <p>Simply log in to your account using the same credentials you used during registration to start using OinkCheck.</p>
            
            <p><strong>Next Steps:</strong></p>
            <ul>
              <li>Open the OinkCheck app on your device</li>
              <li>Log in with your registered email and password</li>
              <li>Start detecting pig diseases and getting expert advice</li>
            </ul>
            
            <p><strong>Need help?</strong> If you have any questions or need assistance, feel free to contact our support team.</p>
          </div>
          <div class="footer">
            <p>Best regards,<br>The OinkCheck Team</p>
            <p>This is an automated message. Please do not reply to this email.</p>
          </div>
        </div>
      </body>
      </html>
    `;

    // Send email notification
    const emailResult = await sendEmailNotification(
      userEmail,
      subject,
      htmlContent
    );

    if (emailResult.success) {
      console.log(`Approval email sent to ${userEmail}`);

      // Mark as notified to prevent duplicates
      try {
        await db
          .collection("users")
          .doc(context.params.userId)
          .set({ emailNotifiedApproval: true }, { merge: true });
      } catch (error) {
        console.error("Error updating email notification status:", error);
      }
    } else {
      console.error(
        `Failed to send approval email to ${userEmail}:`,
        emailResult.error
      );
    }

    return null;
  });

// ============================================
// Password Reset Functions (OTP via SMS)
// ============================================

const twilio = require('twilio');

// Initialize Twilio client (lazy initialization)
let twilioClient = null;

function getTwilioClient() {
  if (!twilioClient) {
    const accountSid = functions.config().twilio?.account_sid;
    const authToken = functions.config().twilio?.auth_token;
    
    if (!accountSid || !authToken) {
      throw new Error('Twilio credentials not configured. Set firebase functions:config:set twilio.account_sid and twilio.auth_token');
    }
    
    twilioClient = twilio(accountSid, authToken);
  }
  return twilioClient;
}

/**
 * Send password reset OTP via SMS (Twilio)
 * 
 * Usage from Flutter:
 * final callable = FirebaseFunctions.instance.httpsCallable('sendPasswordResetOTP');
 * await callable.call({'phoneNumber': '+639123456789', 'otp': '123456'});
 */
exports.sendPasswordResetOTP = functions.https.onCall(async (data, context) => {
  const { phoneNumber, otp } = data;

  if (!phoneNumber || !otp) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'phoneNumber and otp are required'
    );
  }

  // Format phone number (ensure it starts with +)
  let formattedPhone = phoneNumber.trim();
  if (!formattedPhone.startsWith('+')) {
    // Assume Philippines if no country code
    formattedPhone = `+63${formattedPhone.replace(/^0/, '')}`;
  }

  try {
    const client = getTwilioClient();
    const twilioPhoneNumber = functions.config().twilio?.phone_number;
    
    if (!twilioPhoneNumber) {
      throw new Error('Twilio phone number not configured. Set firebase functions:config:set twilio.phone_number');
    }

    // Send SMS via Twilio
    const message = await client.messages.create({
      body: `Your OinkCheck password reset code is: ${otp}. This code expires in 10 minutes.`,
      from: twilioPhoneNumber,
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
 * Reset password using Admin SDK (for phone-based reset)
 * 
 * Usage from Flutter:
 * final callable = FirebaseFunctions.instance.httpsCallable('resetPasswordByPhone');
 * await callable.call({'userId': 'user123', 'newPassword': 'newPassword123'});
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
    // Get user's phone number from Firestore
    const userDoc = await db.collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User not found');
    }

    const userData = userDoc.data();
    const phoneNumber = userData.phoneNumber;
    
    if (!phoneNumber) {
      throw new functions.https.HttpsError('not-found', 'Phone number not found for user');
    }

    // Find the Firebase Auth user by email (placeholder format)
    const phoneDigits = phoneNumber.replace(/\D/g, '');
    const placeholderEmail = `phone_${phoneDigits}@oinkcheck.local`;

    // Get user by email
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(placeholderEmail);
    } catch (error) {
      // If user not found by placeholder email, try to find by UID
      if (error.code === 'auth/user-not-found') {
        // Try to get user by UID if userId matches Firebase UID
        try {
          userRecord = await admin.auth().getUser(userId);
        } catch (uidError) {
          throw new functions.https.HttpsError('not-found', 'Firebase Auth user not found');
        }
      } else {
        throw error;
      }
    }
    
    // Update password using Admin SDK
    await admin.auth().updateUser(userRecord.uid, {
      password: newPassword,
    });

    console.log(`Password reset for user ${userId} (${placeholderEmail})`);
    return { success: true };
  } catch (error) {
    console.error('Error resetting password:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
      'internal',
      'Failed to reset password. Please try again later.'
    );
  }
});