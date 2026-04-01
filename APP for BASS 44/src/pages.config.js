/**
 * pages.config.js
 * Pages are now lazy-loaded directly in App.jsx via React.lazy.
 * This file only provides the Layout reference consumed by App.jsx's
 * legacy pagesConfig path (kept for compatibility).
 */
import __Layout from './Layout.jsx';

export const pagesConfig = {
  mainPage: "Home",
  Pages: {},
  Layout: __Layout,
};