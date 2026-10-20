import type { ShotKey } from './timeline';

// Real screenshots come from the portfolio itself (assets/img/work/*). Copy = the site's own "Before / Now"
// lines, translated to Russian, nothing invented. Accent words are wrapped in *…*.
export type CaseDef = {
  key: ShotKey;
  n: number;
  name: string;
  meta: string;
  room: { bg: string; glow: string; ink: string; ink2: string };
  cover: string;
  second?: string;
  mob: string;
  variant: 'tilt' | 'push' | 'scroll' | 'phone';
  phoneSide: 'left' | 'right';
  before: string;
  now: string;
  widget: 'form' | 'wa' | 'search' | 'steps' | 'time' | 'bubble';
};

const img = (f: string) => `site/assets/img/work/${f}.webp`;

export const CASES: CaseDef[] = [
  {
    key: 'jbdj', n: 1, name: 'J/B', meta: 'Дубай · сайт диджей-дуэта',
    room: { bg: '#0E0B24', glow: 'rgba(156,140,255,0.30)', ink: '#EEECE1', ink2: '#B9B3E0' },
    cover: img('jbdj-cover'), mob: img('jbdj-mob'), variant: 'tilt', phoneSide: 'right',
    before: 'Букинги диджеев теряются в директе',
    now: 'Все заявки на выступление — *в одну форму*',
    widget: 'form',
  },
  {
    key: 'velour', n: 2, name: 'Velour Décor', meta: 'Дубай · ателье штор и текстиля',
    room: { bg: '#E8D2C8', glow: 'rgba(255,255,255,0.55)', ink: '#2A1A16', ink2: '#5C4038' },
    cover: img('velour-cover'), second: img('velour-2'), mob: img('velour-mob'), variant: 'push', phoneSide: 'left',
    before: 'Ткань нужно потрогать, а продаётся через экран',
    now: 'Прогулка по ателье — и заявка сразу *в WhatsApp* владельцу',
    widget: 'wa',
  },
  {
    key: 'bil', n: 3, name: 'Bil Perfume', meta: 'Душанбе · каталог парфюмерии',
    room: { bg: '#1A120B', glow: 'rgba(210,168,92,0.22)', ink: '#EEECE1', ink2: '#C8B9A6' },
    cover: img('bil-cover'), second: img('bil-2'), mob: img('bil-mob'), variant: 'scroll', phoneSide: 'left',
    before: '«Есть в наличии?» — в директ, снова и снова',
    now: 'Поиск находит аромат даже *с опечаткой*',
    widget: 'search',
  },
  {
    key: 'romashka', n: 4, name: 'Ромашка', meta: 'Душанбе · донер-хаус с конструктором',
    room: { bg: '#EFE6D6', glow: 'rgba(255,255,255,0.6)', ink: '#1B120C', ink2: '#5A4636' },
    cover: img('romashka-cover'), second: img('romashka-2'), mob: img('romashka-mob'), variant: 'phone', phoneSide: 'right',
    before: 'Заказы по телефону и очередь у кассы',
    now: 'Собрал донер, выбрал время — забрал *горячим*',
    widget: 'steps',
  },
  {
    key: 'coffeemoose', n: 5, name: 'Coffee Moose', meta: 'Душанбе · предзаказ кофе, 5 филиалов',
    room: { bg: '#45B5A3', glow: 'rgba(255,255,255,0.28)', ink: '#04130D', ink2: '#0D3A31' },
    cover: img('coffeemoose-cover'), second: img('coffeemoose-2'), mob: img('coffeemoose-mob'), variant: 'scroll', phoneSide: 'right',
    before: 'Утренняя очередь ради одного латте',
    now: 'Заказ по дороге: *зашёл и забрал*',
    widget: 'time',
  },
  {
    key: 'tandis', n: 6, name: 'TANDIS', meta: 'Душанбе · студия мужского ухода',
    room: { bg: '#0A0B0A', glow: 'rgba(63,180,138,0.22)', ink: '#EEECE1', ink2: '#A9B2AC' },
    cover: img('tandis-2'), mob: img('tandis-mob'), variant: 'push', phoneSide: 'right',
    before: 'Прайс в виде фото, которое никто не прочитает',
    now: 'Запись на любую услугу — сразу *в WhatsApp*',
    widget: 'bubble',
  },
];
