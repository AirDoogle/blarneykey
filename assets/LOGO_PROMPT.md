# Logo prompt

BlarneyKey's icon has to sit beside the Cork AI Consulting mark without looking like a
different company made it. That mark is a flat, single-colour Action Blue crest: two
crenellated towers and a sailboat, framed by camera-shutter aperture blades, with the
detail knocked out as negative space rather than drawn in a second colour.

The design system this follows lives at
`cork_ai_consulting/jobs_to_be_done/06_website/01_design/design.md`. The rules that bind
an icon:

- **One colour.** Action Blue `#0066cc`. There is no second brand colour, and the doc is
  explicit that any solid blue on a logo is Action Blue, not the wash blue.
- **No gradients.** The system has zero gradient tokens. Atmosphere comes from photography,
  which an icon does not have.
- **No shadows.** The single drop shadow in the whole system is reserved for product
  photography. Not for marks.
- **Detail as negative space.** Windows, water and arcs are gaps in the blue, the way the
  arrow slits are on the crest's towers.
- **No text.** It would be illegible at the 16pt the menu bar renders, and image models
  mangle lettering anyway.

## The concept

Blarney Castle's keep, which happens to rhyme with the two towers already in the Cork
crest, with sound rising off the battlements. The stone gives you the gab; the app carries
it into whatever you are typing.

## Primary prompt

> A macOS app icon on a rounded-square (squircle) tile. Flat vector illustration, one
> single flat colour only: strong medium blue #0066cc on a pure white background. The
> subject is the silhouette of Blarney Castle's square stone keep: a tall narrow tower with
> crenellated battlements along the top, drawn as one solid blue shape. Its two arrow-slit
> windows are knocked out as clean white negative space, not drawn in another colour.
> Rising from the centre of the battlements are three concentric curved arcs of increasing
> width, like a sound wave broadcasting upward, each a smooth solid blue band separated by
> white space. Heraldic and geometric, in the manner of a civic crest reduced to a single
> ink colour. Bold simplified shapes that stay legible at 16 pixels. Perfectly centred with
> generous even padding. No gradients, no shading, no drop shadows, no outlines, no
> texture, no second colour, no gold, no green, no text, no letters, no shamrocks. Crisp
> hard vector edges, 1024x1024.

## Dark variant

Ask for the same mark inverted, since the app uses dark tiles and the design system
requires an on-dark asset:

> Identical mark, inverted: the castle keep and sound arcs in pure white #ffffff on a flat
> near-black #272729 background. Same shapes, same proportions, same negative-space
> windows, no gradients, no shadows, no second colour, 1024x1024.

## Alternates worth generating

**The stone itself**, if the castle reads as too fussy at small sizes:

> A macOS app icon on a rounded-square tile. Flat vector, single flat colour #0066cc on
> pure white. One rough-hewn rectangular stone block seen straight on, drawn as a solid
> blue shape with chipped irregular edges. Three concentric curved sound-wave arcs knocked
> out of the stone as white negative space, spreading from its centre. Geometric, heraldic,
> legible at 16 pixels, centred with generous padding. No gradients, no shadows, no second
> colour, no text. 1024x1024.

**Battlement as waveform**, the most abstract and the most likely to survive scaling:

> A macOS app icon on a rounded-square tile. Flat vector, single flat colour #0066cc on
> pure white. A row of five solid blue vertical bars of alternating height, reading
> simultaneously as castle crenellations and as an audio level meter, sitting on a single
> solid blue horizontal base. Absolutely flat and geometric. Centred, generous padding, no
> gradients, no shadows, no second colour, no text. 1024x1024.

## Once you have a PNG

Nothing is wired up yet: `build.sh` creates a `Resources` folder but copies no icon, and
`Info.plist` has no `CFBundleIconFile`, so the app currently shows the generic placeholder.
Drop the light 1024x1024 at `assets/icon.png` and the plumbing to generate all ten required
sizes with `iconutil` still needs adding to `build.sh`.

The menu bar is a separate matter and needs no artwork: menu bar icons must be single-colour
template images that invert with light and dark mode, so the app uses the `waveform` SF
Symbol, which is already correct. Leave it.
