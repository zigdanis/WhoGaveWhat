# App Store creative assets (header and search results)

Apple's product page header and search results placements, introduced in App Store Connect on
5 October 2026 with the Asset Library. Specifications: Apple's
[creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/)
and [asset best practices](https://developer.apple.com/app-store/asset-best-practices/).

| File | Placement | Size | Notes |
|---|---|---|---|
| `header_3840x1646.png` | Product page header | 3840 × 1646 (21:9) | Centre band of `source_header_1536x1024.png`, cropped to 1536 × 658 at y=183 and scaled ×2.5 with Lanczos. |
| `search_3840x2560.png` | Search results | 3840 × 2560 (3:2) | `source_search_1536x1024.png` scaled ×2.5 with Lanczos. |
| `source_*_1536x1024.png` | — | 1536 × 1024 | Originals generated with ChatGPT image generation on 25 October 2026 from the prompts below. |

Both uploads are RGB without an alpha channel. They contain no text, so the same files serve the
English and Russian listings. Uploaded by hand in App Store Connect (version page, Product Page
Information, Header and Search Results tab, once per language); fastlane does not support these
placements yet. The assets go to App Review with the version.

Regenerate the uploads from the originals with ffmpeg:

```sh
ffmpeg -i source_header_1536x1024.png -vf "crop=1536:658:0:183,scale=3840:1646:flags=lanczos,format=rgb24" header_3840x1646.png
ffmpeg -i source_search_1536x1024.png -vf "scale=3840:2560:flags=lanczos,format=rgb24" search_3840x2560.png
```

## Prompts

Header:

```
Create a wide landscape (3:2) marketing banner for an iOS app called "Who Gave What", a gift tracker that remembers who gave you what and what you gave back. The banner will be cropped to a very wide 21:9 strip, so keep ALL important content inside the middle horizontal band (the central 65% of the height) and keep the left and right edges calm.

Style: minimal, flat, premium Apple-like design. Background is a deep near-black navy (#12161C) with a very subtle radial glow in the center. The hero element is the app's logo mark: two solid triangles with a small gap between them, stacked vertically in the exact center of the image — a white triangle pointing up above an emerald green (#1FA971) triangle pointing down. The mark is large and crisp, with clean geometric edges.

Around the mark, to the left and right, float a few small abstract gift-tracking elements in the same flat style: rounded white cards with soft shadows, thin emerald and white arrows (one pointing up-right for "given", one pointing down-left for "received"), small circular avatars with thin colored rings, and a couple of tiny wrapped gift-box icons in emerald and white. These elements are sparse, elegant, slightly blurred toward the edges, so the logo mark stays the clear focal point.

Strict rules: no text, no letters, no numbers, no logos of other brands, no phones or device frames, no people's faces, no transparency. Clean vector-like rendering, high contrast, no noise, no gradients heavier than a soft glow. Final look: calm, confident, dark, with emerald as the only accent color.
```

Search results:

```
Create a landscape 3:2 image for the App Store search results card of an iOS app called "Who Gave What", a gift tracker that remembers who gave you what and what you gave back. This image is seen at a small size next to the app name, so it must read instantly at a glance: one clear idea, large shapes, strong contrast, nothing fine or detailed. Keep the focal point centered with generous margins.

Style: minimal, flat, premium Apple-like design, matching the app's icon. Background is a deep near-black navy (#12161C). In the center, show a simple scene of gift exchange: two large flat gift boxes facing each other — a white gift box with an emerald green (#1FA971) ribbon on the left, and an emerald green gift box with a white ribbon on the right. Between them, two bold rounded arrows crossing in opposite directions: a white arrow pointing right and an emerald arrow pointing left, echoing the app's two-triangle logo mark. Optionally place the app's logo mark (a white triangle pointing up above an emerald triangle pointing down, with a small gap) small and subtle in the lower center.

Strict rules: no text, no letters, no numbers, no other brand logos, no phones or device frames, no faces, no transparency. Clean vector-like rendering, soft shadows only, emerald as the single accent color on a dark background.
```
