# WhoGaveWhat privacy policy

_Last updated: October 2026_

WhoGaveWhat keeps your gifts, people, photos and settings on your device. The app has
no accounts, advertising, analytics or tracking.

## Cloud icon suggestions (optional)

WhoGaveWhat can suggest an icon for a gift using TypeSafe AI's Jev model. This feature
is off until you allow it in the Add Gift sheet or turn on **Settings → Cloud icon
suggestions**. You can turn it off there at any time; the app then picks icons on your
device, as it does without the feature.

When the feature is on, after you pause typing a gift name the app sends:

- the gift name you typed (at most 80 characters), and
- a random installation identifier, used only to limit the number of requests. A new
  identifier is created when you turn the feature off.

The app never sends people, contacts, dates, amounts, notes or photos.

The request goes to the WhoGaveWhat server, a Cloudflare Worker operated by the
developer, which forwards only the gift name to TypeSafe AI. TypeSafe processes it to
choose an icon under its [Master Customer Agreement](https://typesafe.ai/legal/mca) and
privacy policy, which allow it to keep request data to operate its service, prevent
abuse and meet legal obligations, and do not allow it to train models on that data
without consent. Cloudflare processes network metadata such as IP addresses to deliver
and protect the service.

The WhoGaveWhat server does not store gift names, identifiers or IP addresses. To avoid
repeat requests it keeps the chosen icon for up to 30 days under a one-way hash of the
gift name. It keeps short-lived request counters under one-way hashes of the identifier
and IP address; these expire within a day.

Gift names can contain personal information. If you'd rather not share a name, leave
the feature off or choose an icon yourself.

## Contact

Questions about privacy: open an issue at
<https://github.com/zigdanis/WhoGaveWhat/issues>.
