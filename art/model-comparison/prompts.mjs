// Test set: species with distinctive field marks that are easy to get wrong.
export const SPECIES = [
  {
    code: "norcar",
    name: "Northern Cardinal",
    marks: "male: all-red body, pointed crest, black mask around a thick conical orange-red bill",
  },
  {
    code: "blujay",
    name: "Blue Jay",
    marks: "blue crest, black necklace across a white-gray breast, white wing bars and white tail corners, barred blue wings",
  },
  {
    code: "btbwar",
    name: "Black-throated Blue Warbler",
    marks: "male: deep blue back, black face and throat, white belly, small white square patch on the wing",
  },
  {
    code: "whtspa",
    name: "White-throated Sparrow",
    marks: "crisp white throat patch, black-and-white striped crown, yellow spot between eye and bill, gray breast",
  },
  {
    code: "rethaw",
    name: "Red-tailed Hawk",
    marks: "brick-red tail, pale breast with a dark belly band of streaks, dark leading edge on the wing, hooked bill",
  },
];

export const STYLE = [
  "A single bird drawn by hand in a naturalist's field journal.",
  "Fine dip-pen ink linework with light pencil construction lines, soft translucent watercolor wash.",
  "Muted, slightly faded natural colors as if on old parchment. Visible hand-drawn hatching for shading.",
  "Scientifically accurate anatomy: correct proportions, leg and toe count, bill shape, and field marks.",
  "Only the bird and a small, simply sketched perch. No text, no labels, no border, no frame.",
  "Isolated on a fully transparent background (or plain flat white if transparency is unsupported).",
].join(" ");

export function basePrompt(s) {
  return `${STYLE}\n\nSubject: ${s.name}, perched, three-quarter side view. Field marks to get right: ${s.marks}.`;
}

// Variation edits are applied to each model's own base image.
export function variationPrompt(s) {
  return [
    `Redraw this exact ${s.name} illustration with a small change: the same bird is now perched on a bare late-autumn twig, head turned slightly toward the viewer.`,
    "Keep the identical illustration style, ink linework, watercolor wash, palette, and field marks.",
    "Keep the background transparent (or plain flat white). No text.",
  ].join(" ");
}
