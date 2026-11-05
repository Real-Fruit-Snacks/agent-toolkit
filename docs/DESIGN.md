# Design: the agent-toolkit page (docs/) and README load plan

## Concept

Every Sunday the weekly-release workflow packs one consignment: about 10 GiB in 41 assets, each labelled with the folder it goes to (`windows--`, `linux--`, `wsl--`, `caches--`), sealed with `SHA256SUMS.txt`, and checked by digest before it leaves. So the page is that consignment's load plan and manifest. A visitor should leave knowing what is in the box, that every piece of it is accounted for to the byte, and how to unpack it.

## Audience and primary action

Me, setting up another machine, and anyone curious how a whole agentic coding setup fits in one GitHub release. They need the install flow, what the latest release pins, and enough proof (digests, the smoke test) to trust it. Primary action: get the latest release.

## Type

- Display: Red Hat Display 800 and 900, for the headline and the quantities. Its numerals are wide and steady, which a manifest of counts and sizes needs.
- Text: Red Hat Text 400 to 700, the same superfamily drawn for reading sizes.
- Mono: Red Hat Mono 400 and 500, for asset names, commands, digests and the install log. Asset names are the labels on the crates, so they get the mono.
- All three are variable latin subsets from Google Fonts, self-hosted in `fonts/` with `OFL-Red-Hat.txt`.
- Scale: `scale.mjs`, 16px to 18px, ratio 1.2 to 1.333. The headline is a hand-set clamp up to about 4.6rem.

## Color

The RFS Nightshift and Dayshift values and nothing else. The OS setting picks the theme, the Night/Day switch overrides it, and the choice is saved as `rfs-theme`.

| Role | Night | Day | Use |
|---|---|---|---|
| bg / surface / raised | `#0C0D10` / `#13151A` / `#1A1D24` | `#F6F5F2` / `#FFFFFF` / `#ECEAE4` | Page, tables, the log |
| code-bg | `#070809` | `#FFFFFF` | Commands and the log |
| line / line-strong | `#262A33` / `#636872` | `#D6D3CB` / `#89867F` | Rules, the 2 GiB line, the asset columns |
| ink / mute | `#E8E6E1` / `#8A8F99` | `#1A1B1E` / `#666A73` | Text |
| Ember | `#FF6A3D` | `#C03B0A` | What the toolkit itself does: the parts it cuts, the primary button, focus |
| Mint | `#3DDC97` | `#15794D` | A digest that matched ("consistent", the column tops, `ok` in the log) |
| Raspberry | `#F06292` | `#B0306A` | Over the limit: the 2 GiB line while the distro is too big |
| Amber | `#FFC247` | `#925F00` | `WARNING` lines in the install log |

Every colour that means a state carries a word next to it: "over GitHub's 2 GiB limit", "consistent", `ok`, `WARNING`.

## Layout

A 1200px wrap. The hero is the load plan: the headline and install link sit in the plan's headroom, above the 2 GiB line, and the 41 columns stand along the bottom of the first screen, grouped by the folder each one unpacks to. Below it each section takes its own form: a two-column install flow with the real log beside it, the pin table with the quantities set large, a single statement for why, an itinerary for the build, and a plain list of what was tested and what is known to be wrong.

## Signature

The load plan. One column per release asset, drawn to scale against a dashed line at 2 GiB, the largest file GitHub accepts. Every column carries its real name, size, digest and destination, read out under the plan on hover, tap or arrow keys.

## Wow moment

On load the plan packs itself: the columns grow group by group, then the provisioned Ubuntu distro (3.95 GiB in v1.0.2) grows as one column straight through the 2 GiB line, which turns Raspberry while the readout says it is over the limit. It is then cut where `package-release.ps1` cuts it, at 1900 MiB, and the three parts drop into their own slots. Last, the tops turn Mint one by one as the readout counts the digests, and it ends on the real line `verify-release.ps1` printed for that release. "Replay the build" runs it again. It is a replay of what the workflow did, not a live check, and the caption says so.

- **No JS:** the CSS animation still plays; the readout shows the final line.
- **Reduced motion:** nothing moves. The plan shows the finished state: three parts under the line, every top Mint.
- **Phone:** the same plan under the headline, with the headroom kept clear for the overshoot and a note about the split in it.

## The data

`scripts/write-page.py --tag vX` reads the published release (names, sizes and GitHub's SHA-256 digests) and `VERSIONS.md`, writes `docs/release.json`, and rewrites the blocks between `<!-- gen:NAME -->` comments in `index.html`. The weekly-release workflow runs it after it publishes, so the page always shows the latest release. Everything outside those blocks is hand-written. The `<h2>Pinned in vX</h2>` heading is kept in this exact form because the workflow also rewrites it with a regex.

## README load plan

`docs/art/make-plan.py` draws the same plan from `docs/release.json` as `assets/plan-{dark,light}.svg`, with text turned to paths from `fonts/` (an `<img>` can't load fonts). A 14s CSS loop: pack, overshoot, cut, seal, hold. Its base styles are the finished frame, which is what reduced motion and the social card show. CI regenerates both the page blocks and the SVGs and fails on any difference. `card.html` puts the finished frame under the name for the 1280 × 640 social preview (`assets/social.png`).

Don't wrap the README's `<picture>` in a link: GitHub then shows the light image in dark mode.

## Motion

Columns grow from the ground with `cubic-bezier(.2, .7, .2, 1)`; the distro grows at a steady rate, the way a file fills. The cut parts slide 500ms. Everything else on the page is a 150 to 200ms colour change. Nothing loops on the page.

## Voice

First person, plain and exact, like the README. Real script names, real counts, real log lines. Known issues stay near the top of their section.

## Files

- `index.html`, `styles.css`, `script.js`, `fonts/`, the icons and `manifest.webmanifest`. The favicon is the cut distro: two tall Ember parts and a short one under a pale line.
- `release.json` is generated; edit `scripts/write-page.py` instead.
- `assets/cover-*`, `assets/social-*.png` and `assets/cover.toml` are the older RFS brand cover. The page no longer uses them, but the rfs-brand site's cover gallery loads `cover-{dark,light}.svg` from here, so they stay.
- `reference/t3code/` is T3 Code's own documentation, copied in by the release workflow.

## Alternatives considered

- A bill of lading: the page set as one long shipping document with boxed fields and a stamped seal. Strong on the manifest, but it hides the most interesting fact (the 2 GiB cut) in a table.
- An air-gapped machine: a network meter that stays at zero bytes through the install. It's the toolkit's purpose, but the page can't prove zero bytes, so it would be a claim drawn as a fact.
