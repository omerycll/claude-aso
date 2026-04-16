# Add your app to the Wall

Listing is a single-line pull request — no form, no account, no gatekeeping.

## Requirements

- Your app must be live on the **iOS or macOS App Store**.
- That's it.

## How to add your app

1. Find your **App Store numeric ID**. It's the `id1234567890` part of your App Store URL:
   ```
   https://apps.apple.com/us/app/your-app/id1234567890
                                        ^^^^^^^^^^^^
   ```

2. Open [`site/apps.json`](./apps.json) on GitHub and add an entry to the array:

   ```json
   [
     { "id": "1234567890" }
   ]
   ```

   Optional fields:

   ```json
   { "id": "1234567890", "submitter": "yourgithub", "note": "uses /aso check weekly" }
   ```

3. Open a pull request. Once merged, Vercel redeploys and your app appears on
   `/apps` within a minute or two.

## How data is fetched

Name, developer, category, icon, price, and rating count are pulled live from
Apple's public [iTunes Search API](https://performance-partners.apple.com/search-api)
when the page loads. You don't submit those fields — they always reflect your
current App Store listing.

## Removal

To remove your app from the wall, open a PR deleting your entry from
`site/apps.json`. We do not require an explanation.

## Ordering

Apps render in the order they appear in `apps.json` — i.e. by submission date.
Keep your entry at the end of the array when editing.

## Quality bar

There isn't one beyond "app is live on the App Store." The wall exists to show
what real teams ship with ASO Toolkit, not to curate.
