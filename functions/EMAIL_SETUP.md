# Email Notification Setup for MangoSense

This guide explains how to set up email notifications for user account approvals.

## Prerequisites

1. A Gmail account (or any SMTP email service)
2. Firebase CLI installed and configured
3. Your Firebase project set up

## Setup Steps

### 1. Configure Email Credentials

Set up your email credentials using Firebase Functions config:

```bash
# For Gmail (recommended)
firebase functions:config:set email.user="your-email@gmail.com" email.password="your-app-password"

# For other SMTP services, you can add more config:
firebase functions:config:set email.host="smtp.your-provider.com" email.port="587"
```

### 2. Gmail App Password Setup

If using Gmail, you need to create an App Password:

1. Go to your Google Account settings
2. Navigate to Security → 2-Step Verification
3. At the bottom, select "App passwords"
4. Generate a new app password for "Mail"
5. Use this password (not your regular Gmail password) in the config

### 3. Deploy the Functions

```bash
cd functions
npm install
firebase deploy --only functions
```

### 4. Test the Email Function

You can test the email function by:

1. Registering a new user account
2. In Firebase Console, go to Firestore
3. Find the user document in the "users" collection
4. Change the "status" field from "pending" to "active"
5. The user should receive an email notification

## Email Template

The system sends a professional HTML email with:

- Welcome message with user's name
- Information about what they can do with the app
- Styled with MangoSense branding
- Call-to-action button

## Troubleshooting

### Common Issues

1. **"Invalid login" error**: Check your email credentials and app password
2. **"Less secure app access"**: Use App Passwords instead of regular passwords
3. **Emails not sending**: Check Firebase Functions logs for error details

### Checking Logs

```bash
firebase functions:log
```

### Alternative Email Services

You can modify the transporter configuration in `functions/index.js` to use other services:

```javascript
// For Outlook
const transporter = nodemailer.createTransporter({
  host: "smtp-mail.outlook.com",
  port: 587,
  secure: false,
  auth: {
    user: "your-email@outlook.com",
    pass: "your-password",
  },
});

// For custom SMTP
const transporter = nodemailer.createTransporter({
  host: "your-smtp-server.com",
  port: 587,
  secure: false,
  auth: {
    user: "your-email@domain.com",
    pass: "your-password",
  },
});
```

## Security Notes

- Never commit email credentials to version control
- Use Firebase Functions config for sensitive data
- Consider using environment variables for production
- Regularly rotate your app passwords

## Monitoring

Monitor email delivery through:

- Firebase Functions logs
- Email service provider dashboards
- User feedback and support tickets
