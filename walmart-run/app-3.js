function renderSuggestions() {
  const checkoutPlan = getPlannedSubtotal() * (1 + state.settings.taxCushion / 100);
  const room = Math.max(0, Math.max(state.settings.targetBudget, state.settings.flexBudget) - checkoutPlan);
  els.extrasRoom.textContent = `${money(room)} flex room`;
  els.suggestionList.innerHTML = SUGGESTIONS.map(extra => {
    const already = state.items.some(entry => entry.id === `extra-${extra.id}`);
    const checkoutCost = extra.unitPrice * (1 + state.settings.taxCushion / 100);
    const fits = checkoutCost <= room + 0.005;
    return `<article class="suggestion-card">
      <div class="suggestion-top"><div><h3>${escapeHtml(extra.name)}</h3><p>${escapeHtml(extra.reason)}</p></div><strong>${money(extra.unitPrice)}</strong></div>
      <button type="button" data-add-extra="${extra.id}" ${already || !fits ? 'disabled' : ''}>${already ? 'Added' : fits ? `Add at stop ${routeNumber(extra.dept)}` : 'Outside flexible budget'}</button>
    </article>`;
  }).join('');
  els.suggestionList.querySelectorAll('[data-add-extra]').forEach(button => button.addEventListener('click', () => addSuggestion(button.dataset.addExtra)));
}

function populateDepartmentFilter() {
  els.departmentFilter.innerHTML = '<option value="all">All stops</option>' + ROUTE.map(stop => `<option value="${stop.dept}">${stop.label}</option>`).join('');
}

function setActiveView(view, persist = true) {
  const valid = ['route','map','load','extras','settings'].includes(view) ? view : 'route';
  document.querySelectorAll('.tab').forEach(button => button.classList.toggle('active', button.dataset.view === valid));
  document.querySelectorAll('.view').forEach(section => section.classList.toggle('hidden', section.id !== `${valid}View`));
  if (persist) {
    state.settings.activeView = valid;
    saveState();
  }
  if (valid === 'load') renderLoadOptimizer();
  if (valid === 'map') renderMap();
}

function updateItem(id, patch) {
  const entry = state.items.find(item => item.id === id);
  if (!entry) return;
  Object.assign(entry, patch);
  saveState();
  renderSummary();
  renderNextStop();
  renderRouteList();
  renderMap();
  renderLoadOptimizer();
  renderSuggestions();
}

function addSuggestion(id) {
  const extra = SUGGESTIONS.find(entry => entry.id === id);
  if (!extra || state.items.some(entry => entry.id === `extra-${id}`)) return;
  state.items.push(item(`extra-${id}`, extra.name, extra.dept, extra.location, 1, extra.unitPrice, {
    estimate: true,
    cold: extra.cold,
    source: 'suggestion'
  }));
  state.items[state.items.length - 1].addedAt = new Date().toISOString();
  saveState();
  renderAll();
  showToast(`${extra.name} added to the route`);
}

function sortedItems() {
  return [...state.items].sort((a, b) => {
    const rank = routeIndex(a.dept) - routeIndex(b.dept);
    if (rank) return rank;
    const aisle = aisleSortValue(a.aisle) - aisleSortValue(b.aisle);
    if (aisle) return aisle;
    if (a.core !== b.core) return a.core ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
}

function getNextItem() {
  return sortedItems().find(entry => entry.status === 'need' && entry.qty > 0) || null;
}

function getPlannedSubtotal() {
  return state.items.filter(entry => ['need','cart'].includes(entry.status)).reduce((sum, entry) => sum + entry.qty * entry.unitPrice, 0);
}

function getPickedSubtotal() {
  return state.items.filter(entry => entry.status === 'cart').reduce((sum, entry) => sum + entry.qty * entry.unitPrice, 0);
}

function getOriginalSubtotal() {
  return BASE_ITEMS.filter(entry => entry.source === 'recording').reduce((sum, entry) => sum + entry.qty * entry.unitPrice, 0);
}

function getOriginalQuantity() {
  return BASE_ITEMS.filter(entry => entry.source === 'recording').reduce((sum, entry) => sum + entry.qty, 0);
}

function routeIndex(dept) {
  const index = ROUTE.findIndex(stop => stop.dept === dept);
  return index === -1 ? 999 : index;
}

function routeNumber(dept) {
  const index = routeIndex(dept);
  return index === 999 ? 'Extra stop' : `Stop ${index + 1}`;
}

function routeLabel(dept) {
  return ROUTE.find(stop => stop.dept === dept)?.label || dept;
}

function mapDepartment(dept) {
  if (dept === 'Heavy exit') return 'Heavy exit';
  return dept;
}

function aisleSortValue(value) {
  if (!value) return 99999;
  const match = value.toUpperCase().match(/([A-Z]*)(\d+)/);
  if (!match) return 99998;
  const letters = [...match[1]].reduce((sum, letter) => sum * 26 + letter.charCodeAt(0) - 64, 0);
  return letters * 1000 + Number(match[2]);
}

function loadZone(entry) {
  if (entry.cold) return 'cold';
  if (entry.heavy || entry.deferToExit) return 'heavy';
  if (entry.fragile || entry.ageRestricted) return 'protected';
  if (entry.crushable || entry.bulky) return 'light';
  return 'dense';
}

function loadScore(entry) {
  if (entry.bulky) return 5;
  if (entry.heavy) return 4;
  if (entry.cold) return 3;
  return 1.5;
}

function walmartLink(entry) {
  if (entry.productUrl) return entry.productUrl;
  return `https://www.walmart.com/search?q=${encodeURIComponent(entry.name)}`;
}

function toggleGps() {
  if (gpsWatchId !== null) {
    navigator.geolocation.clearWatch(gpsWatchId);
    gpsWatchId = null;
    els.gpsButton.textContent = 'Start GPS';
    els.gpsStatus.textContent = 'GPS stopped. Your shopping progress remains saved.';
    return;
  }
  if (!navigator.geolocation) {
    els.gpsStatus.textContent = 'This browser does not provide geolocation.';
    return;
  }
  els.gpsButton.textContent = 'Stop GPS';
  els.gpsStatus.textContent = 'Requesting your location…';
  gpsWatchId = navigator.geolocation.watchPosition(position => {
    const distance = haversineMeters(position.coords.latitude, position.coords.longitude, STORE.latitude, STORE.longitude);
    state.trip.lastGps = {
      latitude: position.coords.latitude,
      longitude: position.coords.longitude,
      accuracy: position.coords.accuracy,
      distance,
      at: new Date().toISOString()
    };
    if (distance <= STORE.arrivalRadiusMeters && !state.trip.arrivedAt) state.trip.arrivedAt = new Date().toISOString();
    saveState();
    if (distance <= STORE.arrivalRadiusMeters) {
      els.gpsStatus.textContent = `At Happy Valley Towne Center · GPS accuracy about ${Math.round(position.coords.accuracy)} m. Use aisle codes and manual check-offs indoors.`;
    } else {
      els.gpsStatus.textContent = `${formatDistance(distance)} from the store · GPS accuracy about ${Math.round(position.coords.accuracy)} m.`;
    }
  }, error => {
    els.gpsStatus.textContent = `Location unavailable: ${error.message}. The rest of the app works without GPS.`;
    if (gpsWatchId !== null) navigator.geolocation.clearWatch(gpsWatchId);
    gpsWatchId = null;
    els.gpsButton.textContent = 'Start GPS';
  }, { enableHighAccuracy: true, maximumAge: 5000, timeout: 15000 });
}

function exportState() {
  const blob = new Blob([JSON.stringify(state, null, 2)], { type: 'application/json' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = `happy-valley-walmart-trip-${new Date().toISOString().slice(0,10)}.json`;
  link.click();
  URL.revokeObjectURL(link.href);
  showToast('Trip state exported');
}

async function importState(event) {
  const file = event.target.files?.[0];
  if (!file) return;
  try {
    const imported = JSON.parse(await file.text());
    if (imported.version !== APP_VERSION || !Array.isArray(imported.items)) throw new Error('Unsupported trip file');
    state = imported;
    saveState();
    renderAll();
    showToast('Trip state imported');
  } catch (error) {
    showToast(`Import failed: ${error.message}`);
  } finally {
    event.target.value = '';
  }
}

function resetProgress() {
  if (!confirm('Reset every item to Need while keeping prices, quantities, aisle codes, and budgets?')) return;
  state.items.forEach(entry => { entry.status = 'need'; });
  state.trip.startedAt = new Date().toISOString();
  state.trip.arrivedAt = null;
  saveState();
  renderAll();
  showToast('Progress reset');
}

function factoryReset() {
  if (!confirm('Erase all progress, edits, added extras, aisle codes, and budget settings?')) return;
  state = createDefaultState();
  saveState();
  renderAll();
  showToast('App restored to verified defaults');
}

async function installApp() {
  if (!deferredInstallPrompt) return;
  deferredInstallPrompt.prompt();
  await deferredInstallPrompt.userChoice;
  deferredInstallPrompt = null;
  els.installButton.classList.add('hidden');
}

function registerServiceWorker() {
  if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
    navigator.serviceWorker.register('./sw.js').catch(error => console.warn('Service worker registration failed', error));
  }
}

function showToast(message) {
  clearTimeout(toastTimer);
  els.toast.textContent = message;
  els.toast.classList.remove('hidden');
  toastTimer = setTimeout(() => els.toast.classList.add('hidden'), 2600);
}

function money(value) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(Number(value) || 0);
}

function nonNegativeNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : fallback;
}

function trimNumber(value) {
  return Number(value).toLocaleString('en-US', { maximumFractionDigits: 1 });
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const radius = 6371000;
  const toRad = degrees => degrees * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * radius * Math.asin(Math.sqrt(a));
}

function formatDistance(meters) {
  if (meters < 1000) return `${Math.round(meters)} m`;
  return `${(meters / 1609.344).toFixed(1)} mi`;
}

function shortName(name) {
  return name.replace(/,.*$/, '').replace(/Great Value |Mainstays |Nature's Own /g, '');
}

function compactNames(names, limit) {
  if (names.length <= limit) return names.join(', ');
  return `${names.slice(0, limit).join(', ')} +${names.length - limit} more`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>'"]/g, char => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', "'":'&#39;', '"':'&quot;' }[char]));
}

function escapeAttribute(value) {
  return escapeHtml(value);
}
