# Use Firebase Trigger Email extension (no Gmail App Password)

Instead of Gmail + App Password, you can use the official **Trigger Email** extension. It sends email when you add a document to a Firestore collection. You configure it with **SendGrid** or **Mailgun** (API key only — no App Password).

## 1. Install the extension

1. Open **Firebase Console** → your project → **Extensions**.
2. Click **Install extension** and find **“Trigger Email from Firestore”** (or search “send email”).
3. Click **Install** and follow the steps:
   - **Cloud Functions location:** e.g. `us-central1` (match your other functions).
   - **Firestore collection for emails:** e.g. `mail` (remember this name).
   - **Email provider:** Choose **SendGrid** or **Mailgun**.
   - For **SendGrid:** create an API key at sendgrid.com and paste it when asked.
   - For **Mailgun:** enter your domain and API key.
4. Finish the install. The extension will listen to the collection you chose (e.g. `mail`).

## 2. Set the collection name in your function config

Your Cloud Function must write to the **same** collection the extension uses. Set that name when deploying:

```bash
cd functions
npx firebase functions:config:set trigger_email.collection="mail"
npx firebase deploy --only functions
```

(Firebase requires a **2-part key** like `trigger_email.collection`.) Use the exact collection name you set in the extension (e.g. `mail`). You do **not** need to set `GMAIL_PASSWORD` for the ML→developer email anymore when using this path.

## 3. Document format (already used by your function)

The function writes documents in this shape (the extension expects this):

- `to` – developer email
- `replyTo` – ML Expert’s email (so “Reply” goes to them)
- `message.subject` – subject line
- `message.html` – HTML body

After you set `TRIGGER_EMAIL_COLLECTION` and redeploy, when an ML Expert sends a message the function will add a doc to `mail` and the extension will send the email.

## 4. Switching back to Gmail

To use Gmail (Nodemailer) again, clear the param and redeploy:

```bash
npx firebase functions:config:set trigger_email.collection=""
npx firebase deploy --only functions
```

Then the function will use `GMAIL_EMAIL` and `GMAIL_PASSWORD` (App Password) again.
