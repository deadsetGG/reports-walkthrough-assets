let state = loadState();
let deferredInstallPrompt = null;
let toastTimer = null;
let gpsWatchId = null;

const els = {};

document.addEventListener('DOMContentLoaded', init);

function init() {
  cacheElements();
  populateDepartmentFilter();
  bindEvents();
  renderAll();
  registerServiceWorker();
  window.addEventListener('beforeinstallprompt', event => {
    event.preventDefault();
    deferredInstallPrompt = event;
    els.installButton.classList.remove('hidden');
  });
}

function cacheElements() {
  [
    'plannedSubtotal','pickedSubtotal','checkoutEstimate','progressValue','progressBar','verifiedBaseline',
    'budgetHeadline','budgetDetail','budgetToggle','budgetControls','targetBudget','flexBudget','taxCushion',
    'nextItemName','nextItemMeta','verifyItemLink','markNextButton','routeList','departmentFilter','statusFilter','searchInput',
    'departmentRoute','mapConfidence','gpsButton','gpsStatus','loadStatus','loadAdvice','zoneProtected','zoneLight','zoneDense','zoneHeavy','zoneCold','carLoadPlan',
    'suggestionList','extrasRoom','exportButton','importInput','resetStatusesButton','resetAllButton','toast','installButton'
  ].forEach(id => { els[id] = document.getElementById(id); });
}

function bindEvents() {
  document.querySelectorAll('.tab').forEach(button => button.addEventListener('click', () => setActiveView(button.dataset.view)));
  els.budgetToggle.addEventListener('click', () => els.budgetControls.classList.toggle('hidden'));
  ['targetBudget','flexBudget','taxCushion'].forEach(key => {
    els[key].addEventListener('input', () => {
      state.settings[key] = nonNegativeNumber(els[key].value, state.settings[key]);
      saveState();
      renderSummary();
      renderSuggestions();
    });
  });
  els.departmentFilter.addEventListener('change', renderRouteList);
  els.statusFilter.addEventListener('change', renderRouteList);
  els.searchInput.addEventListener('input', renderRouteList);
  els.markNextButton.addEventListener('click', () => {
    const next = getNextItem();
    if (!next) return;
    updateItem(next.id, { status: 'cart' });
    showToast(`${next.name} marked in cart`);
  });
  els.gpsButton.addEventListener('click', toggleGps);
  els.exportButton.addEventListener('click', exportState);
  els.importInput.addEventListener('change', importState);
  els.resetStatusesButton.addEventListener('click', resetProgress);
  els.resetAllButton.addEventListener('click', factoryReset);
  els.installButton.addEventListener('click', installApp);
}

function loadState() {
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (!parsed || parsed.version !== APP_VERSION || !Array.isArray(parsed.items)) return createDefaultState();
    const defaults = createDefaultState();
    const byId = new Map(parsed.items.map(entry => [entry.id, entry]));
    defaults.items = BASE_ITEMS.map(base => ({ ...base, ...(byId.get(base.id) || {}) }));
    const added = parsed.items.filter(entry => !BASE_ITEMS.some(base => base.id === entry.id));
    defaults.items.push(...added);
    defaults.settings = { ...defaults.settings, ...(parsed.settings || {}) };
    defaults.trip = { ...defaults.trip, ...(parsed.trip || {}) };
    return defaults;
  } catch (error) {
    console.warn('State load failed; defaults restored.', error);
    return createDefaultState();
  }
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function renderAll() {
  syncSettingInputs();
  renderSummary();
  renderNextStop();
  renderRouteList();
  renderMap();
  renderLoadOptimizer();
  renderSuggestions();
  setActiveView(state.settings.activeView || 'route', false);
}

function syncSettingInputs() {
  els.targetBudget.value = state.settings.targetBudget;
  els.flexBudget.value = state.settings.flexBudget;
  els.taxCushion.value = state.settings.taxCushion;
}

function renderSummary() {
  const planned = getPlannedSubtotal();
  const picked = getPickedSubtotal();
  const estimatedCheckout = planned * (1 + state.settings.taxCushion / 100);
  const resolvedUnits = state.items.filter(i => i.status !== 'need').reduce((sum, i) => sum + i.qty, 0);
  const totalUnits = state.items.reduce((sum, i) => sum + i.qty, 0);
  const progress = totalUnits ? Math.round(resolvedUnits / totalUnits * 100) : 0;

  els.plannedSubtotal.textContent = money(planned);
  els.pickedSubtotal.textContent = money(picked);
  els.checkoutEstimate.textContent = `${money(estimatedCheckout)} est. checkout`;
  els.progressValue.textContent = `${progress}%`;
  els.progressBar.style.width = `${progress}%`;
  els.verifiedBaseline.textContent = `${getOriginalQuantity()} recorded units · ${money(getOriginalSubtotal())}`;

  const target = state.settings.targetBudget;
  const flex = Math.max(target, state.settings.flexBudget);
  if (estimatedCheckout <= target) {
    els.budgetHeadline.textContent = `Within target by ${money(target - estimatedCheckout)}`;
    els.budgetHeadline.style.color = 'var(--success)';
    els.budgetDetail.textContent = `${money(planned)} pre-tax plan plus a ${trimNumber(state.settings.taxCushion)}% checkout cushion.`;
  } else if (estimatedCheckout <= flex) {
    els.budgetHeadline.textContent = `Using flexible budget`;
    els.budgetHeadline.style.color = 'var(--warning)';
    els.budgetDetail.textContent = `${money(estimatedCheckout - target)} over target, but ${money(flex - estimatedCheckout)} remains below the flexible ceiling.`;
  } else {
    els.budgetHeadline.textContent = `Over flexible ceiling by ${money(estimatedCheckout - flex)}`;
    els.budgetHeadline.style.color = 'var(--danger)';
    els.budgetDetail.textContent = `Skip optional items, correct estimated prices, or raise the flexible ceiling before checkout.`;
  }
}

function renderNextStop() {
  const next = getNextItem();
  if (!next) {
    els.nextItemName.textContent = 'Route resolved';
    els.nextItemMeta.textContent = 'Review unavailable items, then proceed to checkout.';
    els.markNextButton.textContent = 'Complete';
    els.markNextButton.disabled = true;
    els.verifyItemLink.classList.add('hidden');
    return;
  }
  els.nextItemName.textContent = `${next.qty > 1 ? `${next.qty}× ` : ''}${next.name}`;
  els.nextItemMeta.textContent = `${routeNumber(next.dept)} · ${next.dept} · ${next.aisle ? `Aisle ${next.aisle}` : next.location}${next.deferToExit ? ' · load last' : ''}`;
  els.markNextButton.textContent = 'Put in cart';
  els.markNextButton.disabled = false;
  els.verifyItemLink.href = walmartLink(next);
  els.verifyItemLink.classList.remove('hidden');
}

function renderRouteList() {
  const query = els.searchInput.value.trim().toLowerCase();
  const dept = els.departmentFilter.value;
  const status = els.statusFilter.value;
  const filtered = sortedItems().filter(entry => {
    if (dept !== 'all' && entry.dept !== dept) return false;
    if (status === 'active' && !['need','cart'].includes(entry.status)) return false;
    if (status !== 'active' && status !== 'all' && entry.status !== status) return false;
    if (query && !`${entry.name} ${entry.dept} ${entry.location} ${entry.aisle}`.toLowerCase().includes(query)) return false;
    return true;
  });

  if (!filtered.length) {
    els.routeList.innerHTML = '<div class="panel empty-state">No items match this filter.</div>';
    return;
  }

  const groups = new Map();
  filtered.forEach(entry => {
    if (!groups.has(entry.dept)) groups.set(entry.dept, []);
    groups.get(entry.dept).push(entry);
  });

  els.routeList.innerHTML = Array.from(groups.entries()).map(([department, entries]) => {
    const remaining = entries.filter(i => i.status === 'need').reduce((sum, i) => sum + i.qty, 0);
    return `<section class="dept-group">
      <div class="dept-heading"><h3>${escapeHtml(routeLabel(department))}</h3><span>${remaining} left</span></div>
      ${entries.map(renderItemCard).join('')}
    </section>`;
  }).join('');

  els.routeList.querySelectorAll('[data-status-action]').forEach(button => {
    button.addEventListener('click', () => updateItem(button.dataset.itemId, { status: button.dataset.statusAction }));
  });
  els.routeList.querySelectorAll('[data-edit-toggle]').forEach(button => {
    button.addEventListener('click', () => {
      const panel = document.getElementById(`edit-${button.dataset.editToggle}`);
      panel.classList.toggle('hidden');
    });
  });
  els.routeList.querySelectorAll('[data-field]').forEach(input => {
    input.addEventListener('change', () => {
      const patch = {};
      const field = input.dataset.field;
      patch[field] = field === 'qty' || field === 'unitPrice' ? nonNegativeNumber(input.value, 0) : input.value.trim().toUpperCase();
      const editingId = input.dataset.itemId;
      updateItem(editingId, patch);
      document.getElementById(`edit-${editingId}`)?.classList.remove('hidden');
    });
  });
}

function renderItemCard(entry) {
  const chips = [];
  if (entry.core) chips.push('<span class="chip">Core</span>');
  if (entry.estimate) chips.push('<span class="chip estimate">Verify price/stock</span>');
  if (entry.cold) chips.push('<span class="chip cold">Cold last</span>');
  if (entry.ageRestricted) chips.push('<span class="chip age">21+ ID</span>');
  if (entry.aisle) chips.push(`<span class="chip">Aisle ${escapeHtml(entry.aisle)}</span>`);
  const linePrice = entry.qty * entry.unitPrice;
  return `<article class="item-card" data-status="${entry.status}">
    <div class="item-top">
      <div>
        <h3 class="item-name">${entry.qty > 1 ? `<span aria-label="quantity ${entry.qty}">${entry.qty}×</span> ` : ''}${escapeHtml(entry.name)}</h3>
        <div class="item-meta"><span>${escapeHtml(entry.location)}</span>${chips.join('')}</div>
      </div>
      <div class="item-price"><strong>${money(linePrice)}</strong><small>${entry.qty > 1 ? `${money(entry.unitPrice)} each` : entry.estimate ? 'working price' : 'recorded price'}</small></div>
    </div>
    <div class="item-actions" role="group" aria-label="Status for ${escapeHtml(entry.name)}">
      ${statusButton(entry, 'need', 'Need')}
      ${statusButton(entry, 'cart', 'In cart')}
      ${statusButton(entry, 'unavailable', 'No stock')}
      ${statusButton(entry, 'skip', 'Skip')}
    </div>
    <div class="item-footer">
      <a href="${escapeAttribute(walmartLink(entry))}" target="_blank" rel="noopener">Open Walmart search</a>
      <button class="edit-toggle" type="button" data-edit-toggle="${entry.id}">Edit qty, price, aisle</button>
    </div>
    <div id="edit-${entry.id}" class="item-edit hidden">
      <label>Quantity<input data-item-id="${entry.id}" data-field="qty" type="number" min="0" step="1" value="${entry.qty}"></label>
      <label>Unit price<input data-item-id="${entry.id}" data-field="unitPrice" type="number" min="0" step="0.01" value="${entry.unitPrice.toFixed(2)}"></label>
      <label>Walmart aisle code<input data-item-id="${entry.id}" data-field="aisle" type="text" maxlength="8" placeholder="Example: A12" value="${escapeAttribute(entry.aisle)}"></label>
    </div>
  </article>`;
}

function statusButton(entry, status, label) {
  return `<button type="button" class="status-button ${status} ${entry.status === status ? 'active' : ''}" data-item-id="${entry.id}" data-status-action="${status}" aria-pressed="${entry.status === status}">${label}</button>`;
}

function renderMap() {
  const next = getNextItem();
  document.querySelectorAll('[data-map-dept]').forEach(zone => {
    zone.classList.toggle('active', Boolean(next && mapDepartment(next.dept) === zone.dataset.mapDept));
  });
  els.departmentRoute.innerHTML = ROUTE.map((stop, index) => {
    const members = state.items.filter(item => item.dept === stop.dept && item.status !== 'skip');
    const unresolved = members.filter(item => item.status === 'need').reduce((sum, item) => sum + item.qty, 0);
    const done = members.length > 0 && unresolved === 0;
    return `<li><span class="route-number">${index + 1}</span><span><strong>${escapeHtml(stop.label)}</strong><br><small>${escapeHtml(stop.reason)}</small></span><span class="${done ? 'done' : ''}">${done ? 'Done' : `${unresolved} left`}</span></li>`;
  }).join('');
}

function renderLoadOptimizer() {
  const picked = state.items.filter(entry => entry.status === 'cart');
  const zones = { protected: [], light: [], dense: [], heavy: [], cold: [] };
  picked.forEach(entry => zones[loadZone(entry)].push(entry));
  renderLoadZone(els.zoneProtected, zones.protected);
  renderLoadZone(els.zoneLight, zones.light);
  renderLoadZone(els.zoneDense, zones.dense);
  renderLoadZone(els.zoneHeavy, zones.heavy);
  renderLoadZone(els.zoneCold, zones.cold);

  const score = picked.reduce((sum, entry) => sum + loadScore(entry) * Math.min(entry.qty, 4), 0);
  const totePicked = picked.some(entry => entry.id === 'wheeled-tote');
  els.loadStatus.textContent = score < 18 ? 'Light load' : score < 36 ? 'Balanced' : 'High load';
  if (!picked.length) {
    els.loadAdvice.textContent = 'Nothing is marked in cart yet. Start with the wheeled tote, then use these zones as items are added.';
  } else if (totePicked) {
    els.loadAdvice.textContent = 'If the tote fits safely in the basket, keep it open as a cargo bay for boxed pantry and snacks. Keep glass, milk, and frozen items separate and upright.';
  } else {
    els.loadAdvice.textContent = 'Keep heavy items low, crushable packages high, and leave one protected upright zone for sauces, jelly, candles, and vodka.';
  }

  const active = state.items.filter(entry => ['need','cart'].includes(entry.status));
  const byRule = {
    'Against seatbacks / trunk floor': active.filter(entry => entry.heavy || entry.bulky).map(entry => entry.name),
    'Upright protected tote': active.filter(entry => entry.fragile || entry.ageRestricted).map(entry => entry.name),
    'Top layer': active.filter(entry => entry.crushable && !entry.cold).map(entry => entry.name),
    'Carry inside first': active.filter(entry => entry.cold).map(entry => entry.name)
  };
  els.carLoadPlan.innerHTML = Object.entries(byRule).map(([label, names]) => `<div class="car-load-row"><strong>${escapeHtml(label)}</strong><span>${names.length ? escapeHtml(compactNames(names, 4)) : 'No current items'}</span></div>`).join('');
}

function renderLoadZone(element, entries) {
  element.innerHTML = entries.length
    ? entries.map(entry => `<p>${entry.qty > 1 ? `${entry.qty}× ` : ''}${escapeHtml(shortName(entry.name))}</p>`).join('')
    : '<p class="muted">Empty</p>';
}
