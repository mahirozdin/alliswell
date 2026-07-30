/**
 * The legal identity behind AllisWell, in one place.
 *
 * The privacy policy, the support page and the store listings must all name the
 * SAME entity with the SAME contact route — Apple and Google both fetch these
 * pages during review, and a policy that names one company while the store
 * listing names another is a rejection. Keeping it here means it is changed
 * once, not in four places that drift.
 */
export const company = {
  /** Registered name, reproduced exactly as it appears on the trade register. */
  legalName: 'BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI',
  /** What we call ourselves in prose. */
  tradingName: 'BubiApps',
  address: {
    line1: 'Mevlana Mah. Karasu Cad. No: 14, İç Kapı No: 16',
    line2: 'Talas / Kayseri',
    country: 'Türkiye',
  },
  email: 'info@bubiapps.com',
  phone: '+90 505 493 1041',
  phoneAlt: '+44 7586 553454',
  site: 'https://bubiapps.com',
};

export const addressLines = [
  company.address.line1,
  company.address.line2,
  company.address.country,
];

/** ISO date the legal pages were last substantively changed. */
export const LEGAL_UPDATED = '31 July 2026';
