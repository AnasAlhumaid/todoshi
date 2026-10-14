# Deferred / billing note — Cloud Functions

## Status

`deleteMyAccount` (and the earlier `createSharedProject` scaffold) live under
`firebase/functions/`.

**Deploying Cloud Functions requires the Firebase Blaze (pay-as-you-go) plan.**

This project must **not** silently enable billing. Until Blaze is explicitly approved
by the project owner:

1. Do **not** run `firebase deploy --only functions`
2. Do **not** enable Google Cloud billing from automation
3. Client builds may compile against `FirebaseFunctions`, but calls to
   `deleteMyAccount` will fail until the function is deployed

## When Blaze is enabled

```bash
cd firebase/functions && npm install && npm run build
firebase deploy --only functions:deleteMyAccount
```

Wire `functions` into `firebase.json` at that time if not already present.
