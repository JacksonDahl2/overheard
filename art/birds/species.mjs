// The first set of bird art: 50 birds commonly heard in Central Park.
// `code` is the app's species code (species.json), so art is looked up the same way birds are stored.
// `marks` are the field marks the illustration has to get right; dimorphic species are drawn as
// the adult male in breeding plumage, the bird people picture.
export const SPECIES = [
  {
    code: "norcar",
    name: "Northern Cardinal",
    marks: "adult male: all-red body, pointed crest, black mask around a thick conical orange-red bill",
  },
  {
    code: "blujay",
    name: "Blue Jay",
    marks:
      "blue crest, black necklace across a white-gray breast, white wing bars and white tail corners, black-barred blue wings and tail",
  },
  {
    code: "amerob",
    name: "American Robin",
    marks:
      "brick-orange breast, dark gray-brown back, blackish head with broken white eye-ring, yellow bill, white streaked throat",
  },
  {
    code: "whtspa",
    name: "White-throated Sparrow",
    marks:
      "crisp white throat patch outlined in gray, black-and-white striped crown, yellow spot between eye and bill, gray breast, rusty-brown streaked back",
  },
  {
    code: "houspa",
    name: "House Sparrow",
    marks:
      "adult male: gray crown, chestnut nape and sides of head, black bib, pale gray cheeks, streaky brown back, single white wing bar",
  },
  {
    code: "eursta",
    name: "European Starling",
    marks:
      "breeding: glossy black with purple-green iridescence, sparse pale spots, pointed yellow bill, short square tail, pinkish legs",
  },
  {
    code: "rocpig",
    name: "Rock Pigeon",
    marks:
      "blue-gray body, iridescent green-purple neck, two black bars on the pale gray wing, dark-tipped tail, red-orange eye, pink feet",
  },
  {
    code: "moudov",
    name: "Mourning Dove",
    marks:
      "slender buffy-tan body, small round head, black spots on the wing, long pointed tail with white-edged feathers, dark spot below the eye",
  },
  {
    code: "amecro",
    name: "American Crow",
    marks: "large, entirely glossy black including legs and heavy bill, fan-shaped tail, dark eye",
  },
  {
    code: "fiscro",
    name: "Fish Crow",
    marks:
      "entirely glossy black, slightly smaller and slimmer than American Crow, slender bill, longer tail, sleek glossy feathers",
  },
  {
    code: "comgra",
    name: "Common Grackle",
    marks:
      "long keel-shaped tail, glossy bronze body with iridescent purple-blue head, pale yellow eye, long dark pointed bill",
  },
  {
    code: "rewbla",
    name: "Red-winged Blackbird",
    marks: "adult male: all black with red shoulder patch edged in yellow-buff, conical pointed black bill",
  },
  {
    code: "grycat",
    name: "Gray Catbird",
    marks: "slate-gray all over, black cap, chestnut patch under the tail, long dark tail, slim dark bill",
  },
  {
    code: "normoc",
    name: "Northern Mockingbird",
    marks:
      "gray above, pale below, long dark tail with white outer feathers, white wing patches and two wing bars, yellowish eye, thin dark eyeline",
  },
  {
    code: "brnthr",
    name: "Brown Thrasher",
    marks:
      "rich rufous-brown back and long tail, white underparts heavily streaked with dark brown, long down-curved bill, yellow eye, two pale wing bars",
  },
  {
    code: "tuftit",
    name: "Tufted Titmouse",
    marks:
      "gray upperparts, pointed gray crest, black forehead patch, large dark eye, white underparts with rusty-peach flanks",
  },
  {
    code: "bkcchi",
    name: "Black-capped Chickadee",
    marks:
      "black cap and bib, bright white cheeks, gray back, buffy flanks, white-edged wing feathers, tiny black bill",
  },
  {
    code: "whbnut",
    name: "White-breasted Nuthatch",
    marks:
      "blue-gray back, black cap, white face and breast, chestnut under the tail, long thin slightly upturned bill, clinging head-down on a trunk",
  },
  {
    code: "rebnut",
    name: "Red-breasted Nuthatch",
    marks:
      "blue-gray back, black cap, bold white eyebrow over a black eyeline, rusty-cinnamon underparts, short tail, clinging to bark",
  },
  {
    code: "dowwoo",
    name: "Downy Woodpecker",
    marks:
      "adult male: small, black-and-white, clean pure white underparts with no yellow tint, white stripe down the back, small red patch on the back of the head, short chisel bill, black-spotted white outer tail, clinging to a short section of tree trunk drawn with solid bark and a brown watercolor wash",
  },
  {
    code: "haiwoo",
    name: "Hairy Woodpecker",
    marks:
      "adult male: black-and-white, clean pure white underparts with no yellow tint, white stripe down the back, red patch on the back of the head, long chisel bill nearly as long as the head, clean white outer tail, clinging to a short section of tree trunk drawn with solid bark and a brown watercolor wash",
  },
  {
    code: "rebwoo",
    name: "Red-bellied Woodpecker",
    marks:
      "adult male: red cap from bill to nape, zebra-barred black-and-white back, pale buff face and underparts, faint reddish wash on the belly, clinging to a short section of tree trunk drawn with solid bark and a brown watercolor wash",
  },
  {
    code: "norfli",
    name: "Northern Flicker",
    marks:
      "yellow-shafted: brown barred back, black crescent bib, black-spotted buff breast, gray crown with red nape crescent, male's black mustache, yellow under the wings and tail",
  },
  {
    code: "yebsap",
    name: "Yellow-bellied Sapsucker",
    marks:
      "adult male: red forehead and red throat outlined in black, bold black-and-white striped face, long white wing stripe, pale yellow belly, mottled back, clinging to a short section of tree trunk drawn with solid bark and a brown watercolor wash",
  },
  {
    code: "carwre",
    name: "Carolina Wren",
    marks:
      "rich rusty-brown upperparts, long bold white eyebrow, warm buff underparts, white throat, cocked barred tail, long slightly curved bill",
  },
  {
    code: "y01309",
    name: "House Wren",
    marks:
      "small plain wren, warm medium brown overall (not gray), fine dark barring on the wings and cocked tail, faint pale eyebrow, thin slightly curved bill, pale brownish-buff underparts",
  },
  {
    code: "amegfi",
    name: "American Goldfinch",
    marks:
      "breeding male: bright lemon-yellow body, black forehead cap, black wings with white bars, pink-orange conical bill, notched black-and-white tail",
  },
  {
    code: "houfin",
    name: "House Finch",
    marks:
      "adult male: bright raspberry-red forehead, eyebrow, throat, breast and rump, brown-streaked flanks and back, stubby curved conical bill, notched tail",
  },
  {
    code: "sonspa",
    name: "Song Sparrow",
    marks:
      "brown-streaked breast with a central dark spot, broad dark mustache stripe, gray eyebrow, warm brown streaked back, long rounded tail",
  },
  {
    code: "daejun",
    name: "Dark-eyed Junco",
    marks:
      "slate-colored male: dark slate-gray hood and back, sharply white belly, pale pink conical bill, white outer tail feathers",
  },
  {
    code: "eastow",
    name: "Eastern Towhee",
    marks:
      "adult male: black hood, back and tail, rufous-orange flanks, white belly, red eye, white wing patch and white tail corners",
  },
  {
    code: "chispa",
    name: "Chipping Sparrow",
    marks:
      "breeding: bright rufous cap, white eyebrow, black line through the eye, clean pale gray underparts, streaked brown back, small dark bill",
  },
  {
    code: "herthr",
    name: "Hermit Thrush",
    marks:
      "olive-brown back, reddish-rufous tail it often cocks, white eye-ring, dark-spotted pale breast, pinkish legs",
  },
  {
    code: "woothr",
    name: "Wood Thrush",
    marks:
      "warm cinnamon-brown upperparts brightest on the head, bold round black spots on a white breast and belly, white eye-ring, pinkish legs",
  },
  {
    code: "veery",
    name: "Veery",
    marks:
      "plain, uniform warm tawny-cinnamon upperparts, only faint blurry tawny spots on a buffy upper breast (much fainter than a Wood Thrush), plain pale gray-white belly, faint gray eye-ring",
  },
  {
    code: "cedwax",
    name: "Cedar Waxwing",
    marks:
      "one bird: sleek tan-brown body, pointed crest, black mask edged in white, red waxy tips on the wing feathers, yellow-tipped tail, pale yellow belly",
  },
  {
    code: "balori",
    name: "Baltimore Oriole",
    marks:
      "adult male: black hood and back, flame-orange underparts, rump and shoulder bar, black wings with a white wing bar, orange tail corners, pointed silvery bill",
  },
  {
    code: "scatan",
    name: "Scarlet Tanager",
    marks:
      "breeding male: brilliant saturated scarlet-red body, jet-black wings and tail, slim tanager shape, short thick pale gray bill (not a finch's), dark eye",
  },
  {
    code: "robgro",
    name: "Rose-breasted Grosbeak",
    marks:
      "adult male: black head and back, rose-red triangle on a white breast, large pale conical bill, white wing patches, white belly",
  },
  {
    code: "yelwar",
    name: "Yellow Warbler",
    marks:
      "breeding male: bright yellow all over, olive-yellow back, chestnut-red streaks on the breast, plain face with a beady black eye, yellow wing edgings",
  },
  {
    code: "comyel",
    name: "Common Yellowthroat",
    marks:
      "adult male: broad black mask bordered above in white-gray, bright yellow throat and breast, olive-brown back, often with tail slightly cocked",
  },
  {
    code: "amered",
    name: "American Redstart",
    marks:
      "adult male: black body, bright orange patches on the sides of the breast, wings and tail base, white belly, often fanning its tail",
  },
  {
    code: "ovenbi1",
    name: "Ovenbird",
    marks:
      "olive-brown back, orange crown stripe edged in black, bold white eye-ring, white underparts with bold black streaks, pinkish legs, walking on leaf litter",
  },
  {
    code: "yerwar",
    name: "Yellow-rumped Warbler",
    marks:
      "myrtle form, breeding male: clean WHITE throat (not yellow), blue-gray streaked back, bright yellow rump, yellow crown spot and yellow side patches, black breast streaking, white wing bars",
  },
  {
    code: "btbwar",
    name: "Black-throated Blue Warbler",
    marks:
      "adult male: deep blue back, black face, throat and flanks, white belly, small white square patch on the wing",
  },
  {
    code: "reevir1",
    name: "Red-eyed Vireo",
    marks:
      "olive-green back, gray crown, white eyebrow bordered in black above and below, red eye, white underparts, thick slightly hooked bill",
  },
  {
    code: "easpho",
    name: "Eastern Phoebe",
    marks:
      "gray-brown upperparts darkest on the head, whitish underparts with a pale yellow wash, no eye-ring, small black bill, tail often wagging",
  },
  {
    code: "ruckin",
    name: "Ruby-crowned Kinglet",
    marks:
      "tiny olive-green bird, broken white eye-ring, white wing bar next to a black bar, male's small red crown patch raised, thin bill",
  },
  {
    code: "rethaw",
    name: "Red-tailed Hawk",
    marks:
      "brick-red tail, pale breast with a dark belly band of streaks, dark leading edge on the wing, brown back, hooked yellow-based bill",
  },
  {
    code: "cangoo",
    name: "Canada Goose",
    marks:
      "large, black head and long black neck, white chinstrap patch, brown-gray body with pale barring, white under the tail, black bill and legs, standing on grass",
  },
];

export const STYLE = [
  "A single bird drawn by hand in a naturalist's field journal.",
  "Fine dip-pen ink linework with light pencil construction lines, soft translucent watercolor wash.",
  "True-to-life colors, as in a modern field guide: reds, oranges, yellows and blues are rich, and black feathers are deep black.",
  "Visible hand-drawn hatching for shading.",
  "Scientifically accurate anatomy: correct proportions, leg and toe count, bill shape, and field marks.",
  "Exactly one bird, and a small perch drawn with solid ink and wash (not only faint pencil). No text, no labels, no border, no frame, no paper texture.",
  "The whole bird is in the picture with margin around it, on a plain flat pure white background.",
].join(" ");

export function prompt(s) {
  // Marks that say "clinging", "standing" or "walking" set the pose; everyone else perches.
  const pose = /clinging|standing|walking/.test(s.marks) ? "" : "perched, ";
  return `${STYLE}\n\nSubject: ${s.name}, ${pose}three-quarter side view. Field marks to get right: ${s.marks}.`;
}
