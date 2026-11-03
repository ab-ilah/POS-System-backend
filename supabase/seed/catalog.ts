import type { Role } from "../../shared/permissions.matrix.ts";

export const LOCAL_SEED_PASSWORD = "local-dev-only";

export const AUTH_INSTANCE_ID = "00000000-0000-0000-0000-000000000000";

export interface SeedUser {
  id: string;
  email: string;
  role: Role;
  fullName: string;
  disposable: boolean;
}

export const USERS: readonly SeedUser[] = [
  {
    id: "11111111-1111-4111-8111-111111111111",
    email: "owner@example.com",
    role: "owner",
    fullName: "Ama Owusu Boateng",
    disposable: false,
  },
  {
    id: "22222222-2222-4222-8222-222222222222",
    email: "manager@example.com",
    role: "manager",
    fullName: "Kwesi Mensah",
    disposable: false,
  },
  {
    id: "33333333-3333-4333-8333-333333333333",
    email: "cashier@example.com",
    role: "cashier",
    fullName: "Akua Sarpong",
    disposable: false,
  },
  {
    id: "44444444-4444-4444-8444-444444444444",
    email: "spare.cashier@example.com",
    role: "cashier",
    fullName: "Yaw Darko",
    disposable: true,
  },
];

export type Category = "shirts" | "dresses" | "kaftans" | "jeans" | "shoes" | "accessories";

export interface VariantInput {
  sku: string;
  sizeName: string;
  colourName: string;
  pricePesewas: number;
  stockQty: number;
  lowStockThreshold: number;
}

export interface ProductInput {
  name: string;
  category: Category;
  description: string;
  imagePath: string | null;
  disposable?: boolean;
  variants: readonly VariantInput[];
}

const LONG_SIZE =
  "Extra Extra Large Relaxed Traditional Fit for Broad Shoulders Mens Ceremonial Kaftan";
const LONG_COLOUR =
  "Kente Gold Forest Green and Deep Crimson Wax Print with a Narrow Black Selvedge";
const LONG_HEADWRAP_SIZE =
  "One Size Wraps Twice on an Adult Head with a Long Tail for a Bow About Two Metres";
const LONG_HEADWRAP_COLOUR =
  "Harmattan Dust Beige Fading to Warm Ivory at the Hem Yarn Dyed Not Printed";

export const PRODUCT_INPUTS: readonly ProductInput[] = [
  {
    name: "Accra Friday Wear Oxford Shirt",
    category: "shirts",
    description: "Crisp cotton poplin for Friday office wear.",
    imagePath: "catalog/shirts/accra-friday-oxford.jpg",
    variants: [
      { sku: "SHI-01-M-WHT", sizeName: "M", colourName: "Crisp White", pricePesewas: 18000, stockQty: 12, lowStockThreshold: 3 },
      { sku: "SHI-01-L-WHT", sizeName: "L", colourName: "Crisp White", pricePesewas: 18000, stockQty: 8, lowStockThreshold: 3 },
      { sku: "SHI-01-XL-ICE", sizeName: "XL", colourName: "Ice Blue", pricePesewas: 18500, stockQty: 1, lowStockThreshold: 5 },
    ],
  },
  {
    name: "Makola Ankara Shirt with Hidden Placket",
    category: "shirts",
    description: "Wax-print shirt cut for a hot afternoon in Makola.",
    imagePath: "catalog/shirts/makola-ankara.jpg",
    variants: [
      { sku: "SHI-02-M-ANK", sizeName: "M", colourName: LONG_COLOUR, pricePesewas: 24000, stockQty: 6, lowStockThreshold: 2 },
      { sku: "SHI-02-L-ANK", sizeName: "L", colourName: LONG_COLOUR, pricePesewas: 24000, stockQty: 5, lowStockThreshold: 2 },
      { sku: "SHI-02-XL-ANK", sizeName: "XL", colourName: LONG_COLOUR, pricePesewas: 24500, stockQty: 0, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Osu Linen Camp Shirt",
    category: "shirts",
    description: "Stonewashed linen camp shirt.",
    imagePath: "catalog/shirts/osu-linen.jpg",
    variants: [
      { sku: "SHI-03-M-SND", sizeName: "M", colourName: "Stonewashed Sand", pricePesewas: 22000, stockQty: 5, lowStockThreshold: 2 },
      { sku: "SHI-03-L-SND", sizeName: "L", colourName: "Stonewashed Sand", pricePesewas: 22000, stockQty: 4, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Kumasi Ceremony Shirt",
    category: "shirts",
    description: "Embroidered collar for visiting.",
    imagePath: "catalog/shirts/kumasi-ceremony.jpg",
    variants: [
      { sku: "SHI-04-M-CRM", sizeName: "M", colourName: "Ceremony Cream", pricePesewas: 28000, stockQty: 3, lowStockThreshold: 5 },
      { sku: "SHI-04-L-CRM", sizeName: "L", colourName: "Ceremony Cream", pricePesewas: 28000, stockQty: 6, lowStockThreshold: 2 },
    ],
  },
  {
    name: "East Legon Office Shirt",
    category: "shirts",
    description: "Slim office shirt. Picture not yet taken.",
    imagePath: null,
    variants: [
      { sku: "SHI-05-M-BLU", sizeName: "M", colourName: "Ice Blue", pricePesewas: 16000, stockQty: 10, lowStockThreshold: 3 },
      { sku: "SHI-05-L-BLU", sizeName: "L", colourName: "Ice Blue", pricePesewas: 16000, stockQty: 9, lowStockThreshold: 3 },
    ],
  },
  {
    name: "Cape Coast Beach Shirt",
    category: "shirts",
    description: "Short sleeve cotton for the coast.",
    imagePath: "catalog/shirts/cape-coast-beach.jpg",
    variants: [
      { sku: "SHI-06-M-SEA", sizeName: "M", colourName: "Sea Green", pricePesewas: 14000, stockQty: 7, lowStockThreshold: 2 },
      { sku: "SHI-06-L-SEA", sizeName: "L", colourName: "Sea Green", pricePesewas: 14000, stockQty: 0, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Tamale Market Stripe Shirt",
    category: "shirts",
    description: "Relaxed stripe, breathable cotton.",
    imagePath: "catalog/shirts/tamale-stripe.jpg",
    variants: [
      { sku: "SHI-07-M-STR", sizeName: "M", colourName: "Indigo Stripe", pricePesewas: 15000, stockQty: 11, lowStockThreshold: 3 },
      { sku: "SHI-07-XL-STR", sizeName: "XL", colourName: "Indigo Stripe", pricePesewas: 15500, stockQty: 2, lowStockThreshold: 5 },
    ],
  },
  {
    name: "Labadi Sunset Camp Collar Shirt",
    category: "shirts",
    description: "Camp collar in a warm sunset dye.",
    imagePath: "catalog/shirts/labadi-sunset.jpg",
    variants: [
      { sku: "SHI-08-S-SUN", sizeName: "S", colourName: "Sunset Clay", pricePesewas: 17000, stockQty: 4, lowStockThreshold: 2 },
      { sku: "SHI-08-M-SUN", sizeName: "M", colourName: "Sunset Clay", pricePesewas: 17000, stockQty: 8, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Kente Inspired Fit and Flare Dress",
    category: "dresses",
    description: "Fit and flare with a kente-inspired border.",
    imagePath: "catalog/dresses/kente-fit-flare.jpg",
    variants: [
      { sku: "DRS-09-S-KEN", sizeName: "S", colourName: "Kente Border", pricePesewas: 45000, stockQty: 4, lowStockThreshold: 2 },
      { sku: "DRS-09-M-KEN", sizeName: "M", colourName: "Kente Border", pricePesewas: 45000, stockQty: 0, lowStockThreshold: 2 },
      { sku: "DRS-09-L-KEN", sizeName: "L", colourName: "Kente Border", pricePesewas: 45000, stockQty: 3, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Adinkra Motif Midi Dress",
    category: "dresses",
    description: "Midi dress with a deep indigo ground.",
    imagePath: "catalog/dresses/adinkra-midi.jpg",
    variants: [
      { sku: "DRS-10-M-IND", sizeName: "M", colourName: "Deep Indigo", pricePesewas: 52000, stockQty: 3, lowStockThreshold: 2 },
      { sku: "DRS-10-L-IND", sizeName: "L", colourName: "Deep Indigo", pricePesewas: 52000, stockQty: 4, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Accra Garden Party Dress",
    category: "dresses",
    description: "Tiered cotton for an afternoon gathering.",
    imagePath: "catalog/dresses/accra-garden.jpg",
    variants: [
      { sku: "DRS-11-S-GRN", sizeName: "S", colourName: "Garden Green", pricePesewas: 38000, stockQty: 6, lowStockThreshold: 2 },
      { sku: "DRS-11-M-GRN", sizeName: "M", colourName: "Garden Green", pricePesewas: 38000, stockQty: 5, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Takoradi Wrap Dress",
    category: "dresses",
    description: "Wrap dress. Picture not yet taken.",
    imagePath: null,
    variants: [
      { sku: "DRS-12-M-WAX", sizeName: "M", colourName: "Takoradi Wax", pricePesewas: 36000, stockQty: 2, lowStockThreshold: 5 },
      { sku: "DRS-12-L-WAX", sizeName: "L", colourName: "Takoradi Wax", pricePesewas: 36000, stockQty: 7, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Aburi Hills Linen Shirt Dress",
    category: "dresses",
    description: "Linen shirt dress for cooler hills weather.",
    imagePath: "catalog/dresses/aburi-linen.jpg",
    variants: [
      { sku: "DRS-13-S-LIN", sizeName: "S", colourName: "Hill Linen", pricePesewas: 41000, stockQty: 5, lowStockThreshold: 2 },
      { sku: "DRS-13-M-LIN", sizeName: "M", colourName: "Hill Linen", pricePesewas: 41000, stockQty: 5, lowStockThreshold: 2 },
      { sku: "DRS-13-L-LIN", sizeName: "L", colourName: "Hill Linen", pricePesewas: 41000, stockQty: 4, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Independence Square Evening Dress",
    category: "dresses",
    description: "Floor length evening dress.",
    imagePath: "catalog/dresses/independence-evening.jpg",
    variants: [
      { sku: "DRS-14-M-EVE", sizeName: "M", colourName: "Midnight", pricePesewas: 95000, stockQty: 2, lowStockThreshold: 4 },
      { sku: "DRS-14-L-EVE", sizeName: "L", colourName: "Midnight", pricePesewas: 95000, stockQty: 1, lowStockThreshold: 4 },
    ],
  },
  {
    name: "Ho Market Day Dress",
    category: "dresses",
    description: "Easy day dress in printed cotton.",
    imagePath: "catalog/dresses/ho-market.jpg",
    variants: [
      { sku: "DRS-15-M-DAY", sizeName: "M", colourName: "Market Print", pricePesewas: 25000, stockQty: 9, lowStockThreshold: 3 },
      { sku: "DRS-15-L-DAY", sizeName: "L", colourName: "Market Print", pricePesewas: 25000, stockQty: 8, lowStockThreshold: 3 },
    ],
  },
  {
    name: "Auntie Efua's Independence Weekend Visiting Kaftan with Hand Guided Neck Embroidery, Side Vents, and a Full Sweep Hem Cut for Accra Harmattan Evenings",
    category: "kaftans",
    description: "Ceremonial visiting kaftan with a full hem.",
    imagePath: "catalog/kaftans/auntie-efua-visiting.jpg",
    variants: [
      { sku: "KAF-16-CER-GLD", sizeName: LONG_SIZE, colourName: LONG_COLOUR, pricePesewas: 180000, stockQty: 2, lowStockThreshold: 3 },
      { sku: "KAF-16-M-GLD", sizeName: "M", colourName: "Cream and Gold", pricePesewas: 175000, stockQty: 1, lowStockThreshold: 3 },
    ],
  },
  {
    name: "Northern Star Kaftan",
    category: "kaftans",
    description: "Hand guided embroidery at the neck.",
    imagePath: "catalog/kaftans/northern-star.jpg",
    variants: [
      { sku: "KAF-17-M-STR", sizeName: "M", colourName: "Star White", pricePesewas: 75000, stockQty: 4, lowStockThreshold: 2 },
      { sku: "KAF-17-L-STR", sizeName: "L", colourName: "Star White", pricePesewas: 75000, stockQty: 0, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Friday Kaftan Agbada Cut",
    category: "kaftans",
    description: "Wide sleeve agbada cut for Friday.",
    imagePath: "catalog/kaftans/friday-agbada.jpg",
    variants: [
      { sku: "KAF-18-L-CRM", sizeName: "L", colourName: "Cream and Gold", pricePesewas: 120000, stockQty: 3, lowStockThreshold: 1 },
      { sku: "KAF-18-XL-CRM", sizeName: "XL", colourName: "Cream and Gold", pricePesewas: 120000, stockQty: 3, lowStockThreshold: 1 },
    ],
  },
  {
    name: "Bolgatanga Ease Kaftan",
    category: "kaftans",
    description: "Light cotton. Picture not yet taken.",
    imagePath: null,
    variants: [
      { sku: "KAF-19-M-COT", sizeName: "M", colourName: "Ease Cotton", pricePesewas: 48000, stockQty: 6, lowStockThreshold: 2 },
      { sku: "KAF-19-L-COT", sizeName: "L", colourName: "Ease Cotton", pricePesewas: 48000, stockQty: 5, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Eid Visiting Kaftan",
    category: "kaftans",
    description: "Wide sleeve for Eid visits.",
    imagePath: "catalog/kaftans/eid-visiting.jpg",
    variants: [
      { sku: "KAF-20-M-EID", sizeName: "M", colourName: "Eid Ivory", pricePesewas: 88000, stockQty: 2, lowStockThreshold: 1 },
      { sku: "KAF-20-L-EID", sizeName: "L", colourName: "Eid Ivory", pricePesewas: 88000, stockQty: 4, lowStockThreshold: 1 },
    ],
  },
  {
    name: "Coastal Breeze Indigo Kaftan",
    category: "kaftans",
    description: "Indigo dip dye, lighter at the hem.",
    imagePath: "catalog/kaftans/coastal-indigo.jpg",
    variants: [
      { sku: "KAF-21-M-IND", sizeName: "M", colourName: "Indigo Dip", pricePesewas: 64000, stockQty: 7, lowStockThreshold: 2 },
      { sku: "KAF-21-L-IND", sizeName: "L", colourName: "Indigo Dip", pricePesewas: 64000, stockQty: 1, lowStockThreshold: 5 },
    ],
  },
  {
    name: "Osu Straight Jeans",
    category: "jeans",
    description: "Raw indigo straight leg.",
    imagePath: "catalog/jeans/osu-straight.jpg",
    variants: [
      { sku: "JEA-22-32-IND", sizeName: "32", colourName: "Raw Indigo", pricePesewas: 42000, stockQty: 5, lowStockThreshold: 2 },
      { sku: "JEA-22-34-IND", sizeName: "34", colourName: "Raw Indigo", pricePesewas: 42000, stockQty: 6, lowStockThreshold: 2 },
      { sku: "JEA-22-36-IND", sizeName: "36", colourName: "Raw Indigo", pricePesewas: 42000, stockQty: 2, lowStockThreshold: 4 },
    ],
  },
  {
    name: "Kaneshie Relaxed Jeans",
    category: "jeans",
    description: "Mid wash relaxed leg.",
    imagePath: "catalog/jeans/kaneshie-relaxed.jpg",
    variants: [
      { sku: "JEA-23-32-MID", sizeName: "32", colourName: "Mid Wash", pricePesewas: 28000, stockQty: 8, lowStockThreshold: 2 },
      { sku: "JEA-23-34-MID", sizeName: "34", colourName: "Mid Wash", pricePesewas: 28000, stockQty: 0, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Airport City Slim Jeans",
    category: "jeans",
    description: "Black slim jeans.",
    imagePath: "catalog/jeans/airport-slim.jpg",
    variants: [
      { sku: "JEA-24-30-BLK", sizeName: "30", colourName: "Black", pricePesewas: 32000, stockQty: 4, lowStockThreshold: 2 },
      { sku: "JEA-24-32-BLK", sizeName: "32", colourName: "Black", pricePesewas: 32000, stockQty: 9, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Tema Workwear Jeans",
    category: "jeans",
    description: "Reinforced seam for workwear.",
    imagePath: "catalog/jeans/tema-workwear.jpg",
    variants: [
      { sku: "JEA-25-34-WRK", sizeName: "34", colourName: "Work Indigo", pricePesewas: 30000, stockQty: 10, lowStockThreshold: 3 },
      { sku: "JEA-25-36-WRK", sizeName: "36", colourName: "Work Indigo", pricePesewas: 30000, stockQty: 7, lowStockThreshold: 3 },
    ],
  },
  {
    name: "Legon Campus Wide Leg Jeans",
    category: "jeans",
    description: "Wide leg. Picture not yet taken.",
    imagePath: null,
    variants: [
      { sku: "JEA-26-30-WDE", sizeName: "30", colourName: "Soft Wash", pricePesewas: 26000, stockQty: 3, lowStockThreshold: 2 },
      { sku: "JEA-26-32-WDE", sizeName: "32", colourName: "Soft Wash", pricePesewas: 26000, stockQty: 11, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Madina Crop Jeans",
    category: "jeans",
    description: "Cropped leg in a soft denim.",
    imagePath: "catalog/jeans/madina-crop.jpg",
    variants: [
      { sku: "JEA-27-28-CRP", sizeName: "28", colourName: "Crop Wash", pricePesewas: 24000, stockQty: 1, lowStockThreshold: 5 },
      { sku: "JEA-27-30-CRP", sizeName: "30", colourName: "Crop Wash", pricePesewas: 24000, stockQty: 6, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Kejetia Leather Loafer",
    category: "shoes",
    description: "Polished brown leather loafer.",
    imagePath: "catalog/shoes/kejetia-loafer.jpg",
    variants: [
      { sku: "SHO-28-41-BRN", sizeName: "41", colourName: "Polished Brown", pricePesewas: 55000, stockQty: 3, lowStockThreshold: 1 },
      { sku: "SHO-28-42-BRN", sizeName: "42", colourName: "Polished Brown", pricePesewas: 55000, stockQty: 4, lowStockThreshold: 1 },
      { sku: "SHO-28-43-BRN", sizeName: "43", colourName: "Polished Brown", pricePesewas: 55000, stockQty: 0, lowStockThreshold: 1 },
    ],
  },
  {
    name: "Accra Rain Sandal",
    category: "shoes",
    description: "Buckle sandal for the rains.",
    imagePath: "catalog/shoes/accra-rain.jpg",
    variants: [
      { sku: "SHO-29-40-RAIN", sizeName: "40", colourName: "Rain Black", pricePesewas: 18000, stockQty: 8, lowStockThreshold: 2 },
      { sku: "SHO-29-42-RAIN", sizeName: "42", colourName: "Rain Black", pricePesewas: 18000, stockQty: 5, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Kumasi Brogue",
    category: "shoes",
    description: "Closed lacing brogue.",
    imagePath: "catalog/shoes/kumasi-brogue.jpg",
    variants: [
      { sku: "SHO-30-42-BRG", sizeName: "42", colourName: "Brogue Tan", pricePesewas: 48000, stockQty: 2, lowStockThreshold: 4 },
      { sku: "SHO-30-43-BRG", sizeName: "43", colourName: "Brogue Tan", pricePesewas: 48000, stockQty: 3, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Labone Court Shoe",
    category: "shoes",
    description: "Low heel court shoe.",
    imagePath: "catalog/shoes/labone-court.jpg",
    variants: [
      { sku: "SHO-31-38-CRT", sizeName: "38", colourName: "Court Black", pricePesewas: 36000, stockQty: 6, lowStockThreshold: 2 },
      { sku: "SHO-31-39-CRT", sizeName: "39", colourName: "Court Black", pricePesewas: 36000, stockQty: 4, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Hohoe Trail Shoe",
    category: "shoes",
    description: "Canvas and rubber. Picture not yet taken.",
    imagePath: null,
    variants: [
      { sku: "SHO-32-41-TRL", sizeName: "41", colourName: "Trail Olive", pricePesewas: 27000, stockQty: 9, lowStockThreshold: 2 },
      { sku: "SHO-32-42-TRL", sizeName: "42", colourName: "Trail Olive", pricePesewas: 27000, stockQty: 2, lowStockThreshold: 5 },
    ],
  },
  {
    name: "Osu Evening Slip On",
    category: "shoes",
    description: "Evening slip on.",
    imagePath: "catalog/shoes/osu-evening.jpg",
    variants: [
      { sku: "SHO-33-40-EVE", sizeName: "40", colourName: "Evening Black", pricePesewas: 33000, stockQty: 5, lowStockThreshold: 2 },
      { sku: "SHO-33-41-EVE", sizeName: "41", colourName: "Evening Black", pricePesewas: 33000, stockQty: 5, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Cape Coast Fisherman Sandal",
    category: "shoes",
    description: "Simple leather sandal.",
    imagePath: "catalog/shoes/cape-coast-sandal.jpg",
    variants: [
      { sku: "SHO-34-42-FSH", sizeName: "42", colourName: "Natural Leather", pricePesewas: 15000, stockQty: 12, lowStockThreshold: 3 },
      { sku: "SHO-34-43-FSH", sizeName: "43", colourName: "Natural Leather", pricePesewas: 15000, stockQty: 0, lowStockThreshold: 3 },
    ],
  },
  {
    name: "Kente Strip Headwrap",
    category: "accessories",
    description: "Extra long kente strip for a full wrap.",
    imagePath: "catalog/accessories/kente-headwrap.jpg",
    variants: [
      { sku: "ACC-35-OS-KNT", sizeName: LONG_HEADWRAP_SIZE, colourName: LONG_HEADWRAP_COLOUR, pricePesewas: 15000, stockQty: 6, lowStockThreshold: 2 },
      { sku: "ACC-35-OS-GLD", sizeName: LONG_HEADWRAP_SIZE, colourName: "Kente Gold Strip", pricePesewas: 14000, stockQty: 1, lowStockThreshold: 4 },
    ],
  },
  {
    name: "Adinkra Bead Necklace",
    category: "accessories",
    description: "Brass and glass beads.",
    imagePath: "catalog/accessories/adinkra-beads.jpg",
    variants: [
      { sku: "ACC-36-OS-BDS", sizeName: "One Size", colourName: "Brass and Glass", pricePesewas: 8000, stockQty: 15, lowStockThreshold: 4 },
    ],
  },
  {
    name: "Bolgatanga Straw Tote",
    category: "accessories",
    description: "Woven straw tote.",
    imagePath: "catalog/accessories/bolga-tote.jpg",
    variants: [
      { sku: "ACC-37-OS-TTE", sizeName: "One Size", colourName: "Natural Straw", pricePesewas: 12000, stockQty: 4, lowStockThreshold: 6 },
    ],
  },
  {
    name: "Waist Beads Set",
    category: "accessories",
    description: "Tie waist beads. Picture not yet taken.",
    imagePath: null,
    variants: [
      { sku: "ACC-38-OS-WST", sizeName: "One Size", colourName: "Mixed Glass", pricePesewas: 3500, stockQty: 20, lowStockThreshold: 5 },
    ],
  },
  {
    name: "Accra Tannery Leather Belt",
    category: "accessories",
    description: "Hand cut leather belt.",
    imagePath: "catalog/accessories/accra-belt.jpg",
    variants: [
      { sku: "ACC-39-M-BLT", sizeName: "M", colourName: "Tan Leather", pricePesewas: 9000, stockQty: 7, lowStockThreshold: 2 },
      { sku: "ACC-39-L-BLT", sizeName: "L", colourName: "Tan Leather", pricePesewas: 9000, stockQty: 0, lowStockThreshold: 2 },
    ],
  },
  {
    name: "Staff Mending Kit Scrap Ribbon",
    category: "accessories",
    description: "Shop mending ribbon kept off the sales floor. Safe to delete in tests.",
    imagePath: null,
    disposable: true,
    variants: [
      { sku: "ACC-40-OS-RBN", sizeName: "One Size", colourName: "Scrap Ribbon", pricePesewas: 2000, stockQty: 4, lowStockThreshold: 1 },
    ],
  },
];

export interface SeedCustomer {
  id: string;
  fullName: string;
  phone: string;
  creditBalancePesewas: number;
  disposable: boolean;
}

export const CUSTOMERS: readonly SeedCustomer[] = [
  {
    id: "30000000-0000-4000-8000-000000000001",
    fullName: "Akosua Mensah",
    phone: "0244001101",
    creditBalancePesewas: 0,
    disposable: false,
  },
  {
    id: "30000000-0000-4000-8000-000000000002",
    fullName: "Kwame Boateng",
    phone: "0244001102",
    creditBalancePesewas: 15000,
    disposable: false,
  },
  {
    id: "30000000-0000-4000-8000-000000000003",
    fullName: "Ama Serwaa Darko",
    phone: "0244001103",
    creditBalancePesewas: 2500000,
    disposable: false,
  },
  {
    id: "30000000-0000-4000-8000-000000000004",
    fullName: "Yaw Owusu",
    phone: "0557001104",
    creditBalancePesewas: 0,
    disposable: true,
  },
  {
    id: "30000000-0000-4000-8000-000000000005",
    fullName: "Efua Addison",
    phone: "0208001105",
    creditBalancePesewas: 45000,
    disposable: false,
  },
  {
    id: "30000000-0000-4000-8000-000000000006",
    fullName: "Kojo Antwi",
    phone: "0279001106",
    creditBalancePesewas: 0,
    disposable: false,
  },
  {
    id: "30000000-0000-4000-8000-000000000007",
    fullName: "Abena Poku",
    phone: "0244001107",
    creditBalancePesewas: 8000,
    disposable: false,
  },
  {
    id: "30000000-0000-4000-8000-000000000008",
    fullName: "Nana Yaa Asantewaa",
    phone: "0244001108",
    creditBalancePesewas: 120000,
    disposable: false,
  },
];

export interface SaleLineInput {
  sku: string;
  qty: number;
}

export interface SaleInput {
  id: string;
  receiptNo: string;
  cashierEmail: string;
  customerId: string | null;
  tenderedPesewas: number;
  creditAppliedPesewas: number;
  lines: readonly SaleLineInput[];
}

export const SALE_INPUTS: readonly SaleInput[] = [
  {
    id: "40000000-0000-4000-8000-000000000001",
    receiptNo: "POS-0001",
    cashierEmail: "cashier@example.com",
    customerId: null,
    tenderedPesewas: 35000,
    creditAppliedPesewas: 0,
    lines: [
      { sku: "SHI-01-M-WHT", qty: 1 },
      { sku: "ACC-35-OS-KNT", qty: 1 },
    ],
  },
  {
    id: "40000000-0000-4000-8000-000000000002",
    receiptNo: "POS-0002",
    cashierEmail: "cashier@example.com",
    customerId: "30000000-0000-4000-8000-000000000003",
    tenderedPesewas: 20000,
    creditAppliedPesewas: 25000,
    lines: [{ sku: "DRS-09-S-KEN", qty: 1 }],
  },
  {
    id: "40000000-0000-4000-8000-000000000003",
    receiptNo: "POS-0003",
    cashierEmail: "manager@example.com",
    customerId: "30000000-0000-4000-8000-000000000002",
    tenderedPesewas: 100000,
    creditAppliedPesewas: 0,
    lines: [
      { sku: "JEA-22-32-IND", qty: 1 },
      { sku: "SHO-28-41-BRN", qty: 1 },
    ],
  },
  {
    id: "40000000-0000-4000-8000-000000000004",
    receiptNo: "POS-0004",
    cashierEmail: "cashier@example.com",
    customerId: "30000000-0000-4000-8000-000000000005",
    tenderedPesewas: 120000,
    creditAppliedPesewas: 0,
    lines: [{ sku: "KAF-18-L-CRM", qty: 1 }],
  },
];

export interface SeedVariant {
  id: string;
  productId: string;
  sku: string;
  sizeName: string;
  colourName: string;
  pricePesewas: number;
  stockQty: number;
  lowStockThreshold: number;
}

export interface SeedProduct {
  id: string;
  name: string;
  category: Category;
  description: string;
  imagePath: string | null;
  disposable: boolean;
  variants: readonly SeedVariant[];
}

export interface SeedSaleItem {
  id: string;
  saleId: string;
  variantId: string;
  productName: string;
  sizeName: string;
  colourName: string;
  qty: number;
  unitPricePesewas: number;
  lineTotalPesewas: number;
}

export interface SeedSale {
  id: string;
  receiptNo: string;
  customerId: string | null;
  cashierId: string;
  status: "completed";
  subtotalPesewas: number;
  totalPesewas: number;
  tenderedPesewas: number;
  changePesewas: number;
  creditAppliedPesewas: number;
  items: readonly SeedSaleItem[];
}

export interface SeedTargets {
  disposableProfileId: string;
  disposableProductId: string;
  disposableVariantId: string;
  disposableCustomerId: string;
  updateProductId: string;
  updateVariantId: string;
  updateCustomerId: string;
  updateSaleId: string;
  updateSaleItemId: string;
  probeSaleId: string;
  probeVariantId: string;
}

export interface SeedModel {
  users: readonly SeedUser[];
  products: readonly SeedProduct[];
  customers: readonly SeedCustomer[];
  sales: readonly SeedSale[];
  targets: SeedTargets;
}

function uuid(prefix: string, n: number): string {
  return `${prefix}${n.toString(16).padStart(12, "0")}`;
}

function userByEmail(email: string): SeedUser {
  const user = USERS.find((candidate) => candidate.email === email);
  if (!user) {
    throw new Error(`unknown seed user ${email}`);
  }
  return user;
}

export function userForRole(role: Role): SeedUser {
  const user = USERS.find((candidate) => candidate.role === role && !candidate.disposable);
  if (!user) {
    throw new Error(`no primary seed user for ${role}`);
  }
  return user;
}

export function buildSeed(): SeedModel {
  let productNumber = 1;
  let variantNumber = 1;
  const products: SeedProduct[] = PRODUCT_INPUTS.map((product) => {
    const id = uuid("10000000-0000-4000-8000-", productNumber);
    productNumber += 1;
    const variants: SeedVariant[] = product.variants.map((variant) => {
      const variantId = uuid("20000000-0000-4000-8000-", variantNumber);
      variantNumber += 1;
      return {
        id: variantId,
        productId: id,
        sku: variant.sku,
        sizeName: variant.sizeName,
        colourName: variant.colourName,
        pricePesewas: variant.pricePesewas,
        stockQty: variant.stockQty,
        lowStockThreshold: variant.lowStockThreshold,
      };
    });
    return {
      id,
      name: product.name,
      category: product.category,
      description: product.description,
      imagePath: product.imagePath,
      disposable: product.disposable === true,
      variants,
    };
  });

  const variantsBySku = new Map<string, { product: SeedProduct; variant: SeedVariant }>();
  for (const product of products) {
    for (const variant of product.variants) {
      if (variantsBySku.has(variant.sku)) {
        throw new Error(`duplicate sku ${variant.sku}`);
      }
      variantsBySku.set(variant.sku, { product, variant });
    }
  }

  let itemNumber = 1;
  const sales: SeedSale[] = SALE_INPUTS.map((sale) => {
    const cashier = userByEmail(sale.cashierEmail);
    const items: SeedSaleItem[] = sale.lines.map((line) => {
      const match = variantsBySku.get(line.sku);
      if (!match) {
        throw new Error(`sale ${sale.receiptNo} references unknown sku ${line.sku}`);
      }
      if (!Number.isSafeInteger(line.qty) || line.qty <= 0) {
        throw new Error(`sale ${sale.receiptNo} qty must be a positive integer`);
      }
      const lineTotal = line.qty * match.variant.pricePesewas;
      const item: SeedSaleItem = {
        id: uuid("50000000-0000-4000-8000-", itemNumber),
        saleId: sale.id,
        variantId: match.variant.id,
        productName: match.product.name,
        sizeName: match.variant.sizeName,
        colourName: match.variant.colourName,
        qty: line.qty,
        unitPricePesewas: match.variant.pricePesewas,
        lineTotalPesewas: lineTotal,
      };
      itemNumber += 1;
      return item;
    });
    const total = items.reduce((sum, item) => sum + item.lineTotalPesewas, 0);
    const change = sale.tenderedPesewas + sale.creditAppliedPesewas - total;
    if (!Number.isSafeInteger(change) || change < 0) {
      throw new Error(`sale ${sale.receiptNo} does not settle in whole pesewas`);
    }
    return {
      id: sale.id,
      receiptNo: sale.receiptNo,
      customerId: sale.customerId,
      cashierId: cashier.id,
      status: "completed",
      subtotalPesewas: total,
      totalPesewas: total,
      tenderedPesewas: sale.tenderedPesewas,
      changePesewas: change,
      creditAppliedPesewas: sale.creditAppliedPesewas,
      items,
    };
  });

  const disposableProduct = products.find((product) => product.disposable);
  const firstProduct = products[0];
  const firstVariant = firstProduct?.variants[0];
  const probeVariant = products
    .flatMap((product) => product.variants)
    .find((variant) => variant.sku === "SHI-01-L-WHT");
  const disposableCustomer = CUSTOMERS.find((customer) => customer.disposable);
  const updateCustomer = CUSTOMERS.find((customer) => customer.id === "30000000-0000-4000-8000-000000000001");
  const firstSale = sales[0];
  const firstItem = firstSale?.items[0];
  const disposableProfile = USERS.find((user) => user.disposable);

  if (
    !disposableProduct ||
    !disposableProduct.variants[0] ||
    !firstProduct ||
    !firstVariant ||
    !probeVariant ||
    !disposableCustomer ||
    !updateCustomer ||
    !firstSale ||
    !firstItem ||
    !disposableProfile
  ) {
    throw new Error("seed targets could not be resolved");
  }

  return {
    users: USERS,
    products,
    customers: CUSTOMERS,
    sales,
    targets: {
      disposableProfileId: disposableProfile.id,
      disposableProductId: disposableProduct.id,
      disposableVariantId: disposableProduct.variants[0].id,
      disposableCustomerId: disposableCustomer.id,
      updateProductId: firstProduct.id,
      updateVariantId: firstVariant.id,
      updateCustomerId: updateCustomer.id,
      updateSaleId: firstSale.id,
      updateSaleItemId: firstItem.id,
      probeSaleId: firstSale.id,
      probeVariantId: probeVariant.id,
    },
  };
}
