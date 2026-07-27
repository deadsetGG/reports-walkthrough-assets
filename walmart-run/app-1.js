'use strict';

const APP_VERSION = 2;
const STORAGE_KEY = 'happy-valley-walmart-run:v2';
const STORE = {
  number: '5190',
  name: 'Walmart Supercenter #5190',
  address: '2501 W Happy Valley Rd, Phoenix, AZ 85085',
  latitude: 33.710688,
  longitude: -112.112274,
  arrivalRadiusMeters: 300
};

const ROUTE = [
  { dept: 'Storage', label: 'Storage & seasonal', reason: 'Get the wheeled tote first so it can organize lighter purchases.' },
  { dept: 'Home', label: 'Home', reason: 'Candles are nearby and remain protected near the top.' },
  { dept: 'Paper', label: 'Paper goods', reason: 'Bulky but light; keep above dense groceries.' },
  { dept: 'Pantry', label: 'Dry grocery', reason: 'Canned meals, pasta, sauces, PB&J, chili, and condiments.' },
  { dept: 'Snacks', label: 'Cereal & snacks', reason: 'Crushable packages go after dense pantry items.' },
  { dept: 'Drinks', label: 'Beverages', reason: 'Gatorade and Red Bull before cold items.' },
  { dept: 'Spirits', label: 'Spirits', reason: 'Ketel One may require an unlocked case and ID check.' },
  { dept: 'Dairy', label: 'Dairy wall', reason: 'Keep milk cold; start the cold portion of the trip.' },
  { dept: 'Frozen', label: 'Frozen', reason: 'All frozen meals together immediately before checkout.' },
  { dept: 'Heavy exit', label: 'Water pickup', reason: 'Load the 40-pack last onto the lower rack.' }
];

const BASE_ITEMS = [
  item('bread', "Nature's Own Honey Wheat Bread", 'Pantry', 'Bread', 1, 3.37, { core: true, crushable: true }),
  item('gatorade', 'Gatorade Fruit Punch / Glacier Cherry Variety Pack', 'Drinks', 'Sports drinks', 1, 11.98, { core: true, heavy: true }),
  item('redbull', 'Red Bull Summer Edition 4-pack', 'Drinks', 'Energy drinks', 2, 9.48, { fragile: false }),
  item('milk', 'Great Value Whole Milk, 1 gallon', 'Dairy', 'Dairy wall', 1, 2.26, { core: true, cold: true, heavy: true }),
  item('burritos', 'El Monterey Bean & Cheese Burritos, 32 oz', 'Frozen', 'Frozen meals', 2, 5.47, { core: true, cold: true }),
  item('lasagna', "Stouffer's Family Size Lasagna", 'Frozen', 'Frozen meals', 1, 9.84, { core: true, cold: true, heavy: true }),
  item('ziti', "Stouffer's Family Size Baked Ziti", 'Frozen', 'Frozen meals', 1, 13.48, { cold: true, heavy: true }),
  item('pizza', 'DiGiorno Rising Crust Supreme Pizza', 'Frozen', 'Frozen pizza', 1, 5.97, { cold: true, crushable: true }),
  item('paper-towels', 'Viva Signature Cloth Paper Towels, 6 double rolls', 'Paper', 'Paper towels', 1, 10.98, { core: true, bulky: true, crushable: true }),
  item('toilet-paper', 'Quilted Northern Ultra Plush, 12 mega rolls', 'Paper', 'Toilet paper', 1, 11.67, { core: true, bulky: true, crushable: true }),
  item('hot-sauce', 'Cholula Original Hot Sauce, 5 oz', 'Pantry', 'Condiments', 1, 3.92, { fragile: true }),
  item('mini-ravioli', 'Chef Boyardee Mini Ravioli', 'Pantry', 'Canned meals', 1, 1.00, { core: true, dense: true }),
  item('spaghetti', 'Chef Boyardee Spaghetti & Meatballs', 'Pantry', 'Canned meals', 1, 1.00, { core: true, dense: true }),
  item('mixed-veg', 'Great Value Mixed Vegetables, 15 oz', 'Pantry', 'Canned vegetables', 4, 0.96, { core: true, dense: true }),
  item('mac-cups', 'Kraft Mac & Cheese Cups, 8-pack', 'Pantry', 'Boxed meals', 2, 8.97, { core: true, bulky: true, crushable: true }),
  item('jif', 'Jif Creamy Peanut Butter, 40 oz', 'Pantry', 'Peanut butter & jelly', 1, 6.97, { core: true, dense: true }),
  item('jelly', "Welch's Concord Grape Jelly, 20 oz", 'Pantry', 'Peanut butter & jelly', 1, 2.97, { core: true, fragile: true }),
  item('olive-garlic-sauce', 'Bertolli Olive Oil & Garlic Pasta Sauce', 'Pantry', 'Pasta sauce', 3, 2.88, { core: true, fragile: true, dense: true }),
  item('penne', 'Barilla Penne, 16 oz', 'Pantry', 'Pasta', 6, 1.84, { core: true, dense: true }),
  item('chili', 'Hormel Chili with Beans', 'Pantry', 'Canned chili', 4, 2.67, { core: true, dense: true }),
  item('chipotle-salsa', 'Cholula Smoky Chipotle Salsa, 12 oz', 'Pantry', 'Salsa', 1, 3.28, { fragile: true }),
  item('vodka-sauce', 'Bertolli Vodka Sauce', 'Pantry', 'Pasta sauce', 3, 2.88, { core: true, fragile: true, dense: true }),
  item('water', 'Great Value Purified Water, 40-pack', 'Heavy exit', 'Water wall / final pickup', 1, 5.27, { core: true, heavy: true, bulky: true, deferToExit: true }),
  item('cozy-candle', 'Mainstays Cozy Comfort 3-wick Candle', 'Home', 'Candles', 1, 4.97, { fragile: true }),
  item('pumpkin-candle', 'Mainstays Pumpkin Spice 3-wick Candle', 'Home', 'Candles', 1, 3.96, { fragile: true }),
  item('trubar', 'TRUBAR OHHH Cookie Dough, 5-pack', 'Snacks', 'Nutrition bars', 1, 7.86, { crushable: true }),
  item('goldfish', 'Goldfish Cheddar, 27.3 oz carton', 'Snacks', 'Crackers', 1, 9.24, { crushable: true, bulky: true }),
  item('ritz', 'Ritz Fresh Stacks', 'Snacks', 'Crackers', 1, 5.23, { crushable: true }),
  item('reeses', "Reese's Puffs Mega cereal", 'Snacks', 'Cereal', 2, 5.97, { crushable: true, bulky: true }),
  item('ketel-one', 'Ketel One Vodka, 750 mL, 40% ABV', 'Spirits', 'Vodka / spirits', 1, 21.53, {
    core: true,
    estimate: true,
    fragile: true,
    ageRestricted: true,
    source: 'added',
    productUrl: 'https://www.walmart.com/ip/12167147'
  }),
  item('wheeled-tote', 'HART 50-gallon wheeled storage tote with pull handle', 'Storage', 'Home organization / seasonal', 1, 48.38, {
    core: true,
    estimate: true,
    bulky: true,
    heavy: true,
    source: 'added',
    productUrl: 'https://www.walmart.com/ip/933020477'
  })
];

const SUGGESTIONS = [
  suggestion('trash-bags', 'Heavy-duty trash bags', 'Paper', 'Trash bags', 8.97, 'High-value move-out cleanup and soft-item packing.'),
  suggestion('packing-tape', 'Packing tape with dispenser', 'Storage', 'Moving supplies', 4.48, 'Prevents a second trip when boxes or the tote need securing.'),
  suggestion('paper-plates', 'Disposable plates or bowls', 'Paper', 'Disposable tableware', 3.48, 'Reduces dishes while moving and works with the frozen meals.'),
  suggestion('parmesan', 'Shredded Parmesan cheese', 'Dairy', 'Cheese', 3.98, 'One low-effort flavor upgrade for pasta, lasagna, and baked ziti.', { cold: true }),
  suggestion('lime-seltzer', 'Lime sparkling water, 8-pack', 'Drinks', 'Sparkling water', 3.57, 'Simple zero-prep mixer for the Ketel One; also useful on its own.'),
  suggestion('orange-juice', 'Orange juice, 6-pack', 'Dairy', 'Juice', 5.76, 'Another easy mixer and breakfast drink.', { cold: true })
];

function item(id, name, dept, location, qty, unitPrice, flags = {}) {
  return {
    id,
    name,
    dept,
    location,
    qty,
    unitPrice,
    aisle: '',
    status: 'need',
    source: flags.source || 'recording',
    core: Boolean(flags.core),
    estimate: Boolean(flags.estimate),
    cold: Boolean(flags.cold),
    heavy: Boolean(flags.heavy),
    bulky: Boolean(flags.bulky),
    fragile: Boolean(flags.fragile),
    dense: Boolean(flags.dense),
    crushable: Boolean(flags.crushable),
    ageRestricted: Boolean(flags.ageRestricted),
    deferToExit: Boolean(flags.deferToExit),
    productUrl: flags.productUrl || '',
    addedAt: null
  };
}

function suggestion(id, name, dept, location, unitPrice, reason, flags = {}) {
  return { id, name, dept, location, unitPrice, reason, ...flags };
}

function createDefaultState() {
  return {
    version: APP_VERSION,
    items: structuredClone(BASE_ITEMS),
    settings: {
      targetBudget: 325,
      flexBudget: 350,
      taxCushion: 9,
      activeView: 'route'
    },
    trip: {
      startedAt: new Date().toISOString(),
      arrivedAt: null,
      lastGps: null
    }
  };
}
