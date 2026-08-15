(function () {
  'use strict';

  const API_BASE_URL = (window.FNF_CONFIG && window.FNF_CONFIG.API_BASE_URL) || '';

  // Derived from API_BASE_URL (which ends in /api) so relative product image
  // paths like "/uploads/products/x.jpg" resolve to the real backend host.
  const ASSET_HOST = API_BASE_URL.endsWith('/api') ? API_BASE_URL.slice(0, -4) : API_BASE_URL;

  const els = {
    loadingState: document.getElementById('loadingState'),
    errorState: document.getElementById('errorState'),
    errorTitle: document.getElementById('errorTitle'),
    errorMessage: document.getElementById('errorMessage'),
    successState: document.getElementById('successState'),
    successTable: document.getElementById('successTable'),
    successOrderNumber: document.getElementById('successOrderNumber'),
    successTotal: document.getElementById('successTotal'),
    app: document.getElementById('app'),
    tableBadge: document.getElementById('tableBadge'),
    categoryChips: document.getElementById('categoryChips'),
    productList: document.getElementById('productList'),
    cartBar: document.getElementById('cartBar'),
    cartCount: document.getElementById('cartCount'),
    cartBarTotal: document.getElementById('cartBarTotal'),
    cartOverlay: document.getElementById('cartOverlay'),
    closeCart: document.getElementById('closeCart'),
    cartLines: document.getElementById('cartLines'),
    cartTotal: document.getElementById('cartTotal'),
    customerName: document.getElementById('customerName'),
    customerPhone: document.getElementById('customerPhone'),
    orderNote: document.getElementById('orderNote'),
    checkoutError: document.getElementById('checkoutError'),
    placeOrderBtn: document.getElementById('placeOrderBtn'),
  };

  const state = {
    tableNumber: null,
    tableName: null,
    categories: [],
    items: [],
    activeCategory: 'all',
    cart: new Map(), // productId -> { product, quantity }
  };

  function formatMoney(n) {
    return '₹' + Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 });
  }

  function showState(name) {
    ['loadingState', 'errorState', 'successState', 'app'].forEach((key) => {
      els[key].classList.toggle('hidden', key !== name);
    });
  }

  function showFatalError(title, message) {
    els.errorTitle.textContent = title;
    els.errorMessage.textContent = message;
    showState('errorState');
  }

  async function apiRequest(path, options) {
    if (!API_BASE_URL || API_BASE_URL.includes('your-deployed-api-domain.com')) {
      throw new Error('This menu is not configured yet. Please contact the cafe.');
    }
    let res;
    try {
      res = await fetch(API_BASE_URL + path, {
        headers: { 'Content-Type': 'application/json' },
        ...options,
      });
    } catch (networkErr) {
      throw new Error('Network error. Please check your connection and try again.');
    }
    let body;
    try {
      body = await res.json();
    } catch (parseErr) {
      throw new Error('The cafe server returned an unexpected response. Please try again.');
    }
    if (!res.ok || !body.success) {
      throw new Error((body && body.message) || 'Something went wrong. Please try again.');
    }
    return body;
  }

  function getTableNumberFromUrl() {
    const params = new URLSearchParams(window.location.search);
    const raw = params.get('table');
    const num = Number(raw);
    if (!raw || !Number.isInteger(num) || num < 1) return null;
    return num;
  }

  async function init() {
    const tableNumber = getTableNumberFromUrl();
    if (!tableNumber) {
      showFatalError('No table selected', 'Please scan the QR code on your table to open the menu.');
      return;
    }

    try {
      const tableRes = await apiRequest(`/public/tables/${tableNumber}`);
      state.tableNumber = tableRes.data.tableNumber;
      state.tableName = tableRes.data.tableName;

      const menuRes = await apiRequest('/public/menu');
      state.categories = menuRes.categories || [];
      state.items = menuRes.items || [];

      renderApp();
      showState('app');
    } catch (err) {
      showFatalError('Invalid table', err.message || 'This table QR code is not recognized. Please ask staff for help.');
    }
  }

  function renderApp() {
    els.tableBadge.textContent = `Table ${state.tableName ? state.tableName.replace(/^Table\s*/i, '') : state.tableNumber}`;

    // Category chips
    els.categoryChips.innerHTML = '';
    const allChip = makeChip('All', 'all');
    els.categoryChips.appendChild(allChip);
    state.categories.forEach((c) => {
      els.categoryChips.appendChild(makeChip(c.name, c._id));
    });

    renderProductList();
  }

  function makeChip(label, value) {
    const btn = document.createElement('button');
    btn.className = 'chip' + (state.activeCategory === value ? ' active' : '');
    btn.textContent = label;
    btn.addEventListener('click', () => {
      state.activeCategory = value;
      renderApp();
    });
    return btn;
  }

  function renderProductList() {
    els.productList.innerHTML = '';

    const grouped = new Map();
    state.items.forEach((item) => {
      if (state.activeCategory !== 'all' && item.category !== state.activeCategory) return;
      const key = item.categoryName || 'Other';
      if (!grouped.has(key)) grouped.set(key, []);
      grouped.get(key).push(item);
    });

    if (grouped.size === 0) {
      const empty = document.createElement('div');
      empty.className = 'cart-empty';
      empty.textContent = 'No items available right now.';
      els.productList.appendChild(empty);
      return;
    }

    grouped.forEach((productsInCategory, categoryName) => {
      const heading = document.createElement('div');
      heading.className = 'category-heading';
      heading.textContent = categoryName;
      els.productList.appendChild(heading);

      productsInCategory.forEach((item) => {
        els.productList.appendChild(renderProductCard(item));
      });
    });
  }

  function renderProductCard(item) {
    const card = document.createElement('div');
    card.className = 'product-card';

    const img = document.createElement('div');
    if (item.image) {
      const imgEl = document.createElement('img');
      imgEl.className = 'product-image';
      imgEl.loading = 'lazy';
      imgEl.alt = item.name;
      imgEl.src = item.image.startsWith('http') ? item.image : ASSET_HOST + item.image;
      img.appendChild(imgEl);
    } else {
      const placeholder = document.createElement('div');
      placeholder.className = 'product-image placeholder';
      placeholder.textContent = item.name.slice(0, 2).toUpperCase();
      img.appendChild(placeholder);
    }
    card.appendChild(img.firstChild);

    const info = document.createElement('div');
    info.className = 'product-info';
    const name = document.createElement('div');
    name.className = 'product-name';
    name.textContent = item.name;
    info.appendChild(name);

    if (item.available) {
      const price = document.createElement('div');
      price.className = 'product-price';
      price.textContent = formatMoney(item.price);
      info.appendChild(price);
    } else {
      const unavailable = document.createElement('div');
      unavailable.className = 'product-unavailable';
      unavailable.textContent = 'Currently unavailable';
      info.appendChild(unavailable);
    }
    card.appendChild(info);

    const action = document.createElement('div');
    action.className = 'product-action';
    action.appendChild(renderQuantityControl(item));
    card.appendChild(action);

    return card;
  }

  function renderQuantityControl(item) {
    const wrapper = document.createElement('div');
    const cartLine = state.cart.get(item._id);
    const qty = cartLine ? cartLine.quantity : 0;

    if (!item.available) {
      const btn = document.createElement('button');
      btn.className = 'add-btn';
      btn.textContent = 'Add';
      btn.disabled = true;
      wrapper.appendChild(btn);
      return wrapper;
    }

    if (qty === 0) {
      const btn = document.createElement('button');
      btn.className = 'add-btn';
      btn.textContent = 'Add';
      btn.addEventListener('click', () => {
        state.cart.set(item._id, { product: item, quantity: 1 });
        renderProductList();
        updateCartBar();
      });
      wrapper.appendChild(btn);
    } else {
      const stepper = document.createElement('div');
      stepper.className = 'qty-stepper';

      const minus = document.createElement('button');
      minus.textContent = '−';
      minus.addEventListener('click', () => {
        const line = state.cart.get(item._id);
        if (!line) return;
        if (line.quantity <= 1) {
          state.cart.delete(item._id);
        } else {
          line.quantity -= 1;
        }
        renderProductList();
        updateCartBar();
      });

      const countEl = document.createElement('span');
      countEl.textContent = String(qty);

      const plus = document.createElement('button');
      plus.textContent = '+';
      plus.addEventListener('click', () => {
        const line = state.cart.get(item._id);
        if (line.quantity >= 50) return;
        line.quantity += 1;
        renderProductList();
        updateCartBar();
      });

      stepper.appendChild(minus);
      stepper.appendChild(countEl);
      stepper.appendChild(plus);
      wrapper.appendChild(stepper);
    }

    return wrapper;
  }

  function cartTotal() {
    let total = 0;
    let count = 0;
    state.cart.forEach((line) => {
      total += line.product.price * line.quantity;
      count += line.quantity;
    });
    return { total, count };
  }

  function updateCartBar() {
    const { total, count } = cartTotal();
    els.cartBar.classList.toggle('hidden', count === 0);
    els.cartCount.textContent = String(count);
    els.cartBarTotal.textContent = formatMoney(total);
  }

  function renderCartSheet() {
    els.cartLines.innerHTML = '';
    if (state.cart.size === 0) {
      const empty = document.createElement('div');
      empty.className = 'cart-empty';
      empty.textContent = 'Your cart is empty.';
      els.cartLines.appendChild(empty);
    } else {
      state.cart.forEach((line, productId) => {
        const row = document.createElement('div');
        row.className = 'cart-line';

        const left = document.createElement('div');
        const name = document.createElement('div');
        name.className = 'cart-line-name';
        name.textContent = line.product.name;
        const price = document.createElement('div');
        price.className = 'cart-line-price';
        price.textContent = `${formatMoney(line.product.price)} × ${line.quantity}`;
        left.appendChild(name);
        left.appendChild(price);

        const right = document.createElement('div');
        right.appendChild(renderQuantityControl(line.product));

        row.appendChild(left);
        row.appendChild(right);
        els.cartLines.appendChild(row);
      });
    }

    const { total } = cartTotal();
    els.cartTotal.textContent = formatMoney(total);
    els.checkoutError.classList.add('hidden');
  }

  els.cartBar.addEventListener('click', () => {
    if (state.cart.size === 0) return;
    renderCartSheet();
    els.cartOverlay.classList.remove('hidden');
  });

  els.closeCart.addEventListener('click', () => {
    els.cartOverlay.classList.add('hidden');
  });

  els.cartOverlay.addEventListener('click', (e) => {
    if (e.target === els.cartOverlay) els.cartOverlay.classList.add('hidden');
  });

  els.placeOrderBtn.addEventListener('click', async () => {
    if (state.cart.size === 0) return;

    els.checkoutError.classList.add('hidden');
    els.placeOrderBtn.disabled = true;
    els.placeOrderBtn.textContent = 'Placing order…';

    const items = Array.from(state.cart.values()).map((line) => ({
      productId: line.product._id,
      quantity: line.quantity,
    }));

    const payload = {
      tableNumber: state.tableNumber,
      customerName: els.customerName.value.trim() || undefined,
      customerPhone: els.customerPhone.value.trim() || undefined,
      note: els.orderNote.value.trim() || undefined,
      items,
    };

    try {
      const res = await apiRequest('/public/orders', {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      // Only clear the cart once the backend has confirmed success.
      state.cart.clear();
      els.cartOverlay.classList.add('hidden');

      els.successTable.textContent = res.data.tableName || `Table ${res.data.tableNumber}`;
      els.successOrderNumber.textContent = `#${res.data.orderNumber}`;
      els.successTotal.textContent = formatMoney(res.data.total);
      showState('successState');
    } catch (err) {
      els.checkoutError.textContent = err.message || 'Order failed. Please try again.';
      els.checkoutError.classList.remove('hidden');
    } finally {
      els.placeOrderBtn.disabled = false;
      els.placeOrderBtn.textContent = 'Place Order';
    }
  });

  init();
})();
