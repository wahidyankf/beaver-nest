# Backup Integrity UI Design Assets

Design assets for the integrity label that the owner added to the Schedules & backups page (OD-3), produced under
[Plan UI Design](../../../../repo-governance/conventions/plan-ui-design.md). The comparison, the selection and its
rationale are in the [UI Design section](../tech-docs.md#ui-design) of [`tech-docs.md`](../tech-docs.md); this directory
holds only the images. The plan [`README.md`](../README.md) shows one selected preview.

## What the Assets Show

Every asset draws the same representative task on the real page structure of `/admin/settings/schedules`: the
administrator opens Schedules & backups and learns that two of seven retained backups need attention. The page frame
follows `admin_schedule_settings_live.ex`: breadcrumb, `DAILY OPERATIONS` kicker, title, the Family schedules group
(empty), the Admin/system schedules group with two schedule rows, and the two settings cards.

- **Stage one, lo-fi (nine assets).** Three distinct placements, each on desktop, tablet and mobile: `row`, `banner` and
  `card`. Grey wireframes: dashed outlines are existing, unchanged page parts; the solid heavy outline with a `NEW` tag
  is the proposed label. Headings are bold here for scanning.
- **Stage two, hi-fi (three assets).** The selected alternative, `row`, on desktop, tablet and mobile, drawn with the
  app stylesheet's existing tokens and the page's computed styles, followed by a sheet of the same component in all six
  label states. The page's headings are drawn at their computed style (the page's stylesheet resets their size and
  weight), which this plan does not change.
- **Widths.** Desktop 1440 px, tablet 768 px and mobile 393 px, the manual viewport classes of the plan. The frames show
  the whole page, so they are taller than one screen.

## Synthetic Content

All content is fictional. The dates are in 2030, the folder shown in the override field is the placeholder
`/example/backup-folder`, and no real account, family member, credential, filesystem path, digest, destination
identifier or run identifier appears. The colour-theme control fixed to the page's top right belongs to the root layout,
is unchanged by this plan and is not drawn.

## Accessibility

- Every SVG has `role="img"`, one unique `<title>` and one `<desc>` that states the layout, the copy and the device
  behaviour, so the image is understandable without seeing it. Every Markdown embed carries alt text, and the UI Design
  section adds a text alternative for each image group.
- No state relies on colour alone: each state has its own marker shape (check circle, warning triangle, dotted circle,
  question square, dash circle, arrow diamond) and its own words.
- Text is the page ink on the page paper at 10.99:1; the status strips use the page's existing coral and green borders at
  3.24:1 and 3.26:1 against the paper. No new colour token is introduced. The measurements are in the UI Design section.

## Directory Map

- [`ui-row-lofi-desktop.svg`](ui-row-lofi-desktop.svg) is the lo-fi `row` alternative on desktop (selected).
- [`ui-row-lofi-tablet.svg`](ui-row-lofi-tablet.svg) is the lo-fi `row` alternative on tablet (selected).
- [`ui-row-lofi-mobile.svg`](ui-row-lofi-mobile.svg) is the lo-fi `row` alternative on mobile (selected).
- [`ui-banner-lofi-desktop.svg`](ui-banner-lofi-desktop.svg) is the lo-fi `banner` alternative on desktop (not selected).
- [`ui-banner-lofi-tablet.svg`](ui-banner-lofi-tablet.svg) is the lo-fi `banner` alternative on tablet (not selected).
- [`ui-banner-lofi-mobile.svg`](ui-banner-lofi-mobile.svg) is the lo-fi `banner` alternative on mobile (not selected).
- [`ui-card-lofi-desktop.svg`](ui-card-lofi-desktop.svg) is the lo-fi `card` alternative on desktop (not selected).
- [`ui-card-lofi-tablet.svg`](ui-card-lofi-tablet.svg) is the lo-fi `card` alternative on tablet (not selected).
- [`ui-card-lofi-mobile.svg`](ui-card-lofi-mobile.svg) is the lo-fi `card` alternative on mobile (not selected).
- [`ui-row-hifi-desktop.svg`](ui-row-hifi-desktop.svg) is the hi-fi selected `row` alternative on desktop, with the state
  sheet.
- [`ui-row-hifi-tablet.svg`](ui-row-hifi-tablet.svg) is the hi-fi selected `row` alternative on tablet, with the state
  sheet.
- [`ui-row-hifi-mobile.svg`](ui-row-hifi-mobile.svg) is the hi-fi selected `row` alternative on mobile, with the state
  sheet.
