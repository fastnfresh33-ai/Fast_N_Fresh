(function () {
  'use strict';

  const API_BASE_URL =
    (window.FNF_CONFIG && window.FNF_CONFIG.API_BASE_URL) || '';

  // Deliberately not defaulted to true: an operator must explicitly flip
  // this in config.js after confirming API_BASE_URL is reachable and
  // correct (see the instructions in config.js). This turns an unverified
  // guess into a hard stop instead of a silent failure in production.
  const API_BASE_URL_VERIFIED =
    !!(window.FNF_CONFIG && window.FNF_CONFIG.VERIFIED === true);

  const ASSET_HOST = API_BASE_URL.endsWith('/api')
    ? API_BASE_URL.slice(0, -4)
    : API_BASE_URL;

  const els = {
    loadingState: document.getElementById('loadingState'),
    loadingSlowHint: document.getElementById('loadingSlowHint'),
    errorState: document.getElementById('errorState'),
    errorTitle: document.getElementById('errorTitle'),
    errorMessage: document.getElementById('errorMessage'),
    retryBtn: document.getElementById('retryBtn'),

    successState: document.getElementById('successState'),
    successHeading: document.getElementById('successHeading'),
    successSubtext: document.getElementById('successSubtext'),
    successTable: document.getElementById('successTable'),
    successOrderNumber: document.getElementById('successOrderNumber'),
    successTotal: document.getElementById('successTotal'),
    successItems: document.getElementById('successItems'),
    successStatus: document.getElementById('successStatus'),
    successStatusText: document.getElementById('successStatusText'),
    doneBtn: document.getElementById('doneBtn'),
    feedbackBox: document.getElementById('feedbackBox'),
    feedbackStars: document.getElementById('feedbackStars'),
    feedbackComment: document.getElementById('feedbackComment'),
    submitFeedbackBtn: document.getElementById('submitFeedbackBtn'),
    feedbackMessage: document.getElementById('feedbackMessage'),

    app: document.getElementById('app'),
    tableBadge: document.getElementById('tableBadge'),

    searchInput: document.getElementById('searchInput'),
    clearSearch: document.getElementById('clearSearch'),

    categoryChips: document.getElementById('categoryChips'),
    productList: document.getElementById('productList'),

    searchEmpty: document.getElementById('searchEmpty'),
    clearSearchBtn: document.getElementById('clearSearchBtn'),

    cartBar: document.getElementById('cartBar'),
    cartCount: document.getElementById('cartCount'),
    cartBarTotal: document.getElementById('cartBarTotal'),

    cartOverlay: document.getElementById('cartOverlay'),
    closeCart: document.getElementById('closeCart'),

    cartLines: document.getElementById('cartLines'),
    cartItemCount: document.getElementById('cartItemCount'),
    cartTotal: document.getElementById('cartTotal'),

    customerName: document.getElementById('customerName'),
    customerPhone: document.getElementById('customerPhone'),
    orderNote: document.getElementById('orderNote'),
    onlinePaymentOption: document.getElementById('onlinePaymentOption'),
    payUpiBtn: document.getElementById('payUpiBtn'),
    upiReferenceGroup: document.getElementById('upiReferenceGroup'),
    upiReferenceInput: document.getElementById('upiReferenceInput'),

    checkoutError: document.getElementById('checkoutError'),
    placeOrderBtn: document.getElementById('placeOrderBtn'),

    upiAppOverlay: document.getElementById('upiAppOverlay'),
    closeUpiAppOverlay: document.getElementById('closeUpiAppOverlay'),
    upiAppGrid: document.getElementById('upiAppGrid'),
  };

  const state = {
    paymentOptions: { onlineUpi: false, upiId: '', cafeName: 'FAST N FRESH CAFE' },
    tableNumber: null,
    tableName: null,

    categories: [],
    items: [],

    activeCategory: 'all',
    searchQuery: '',

    cart: new Map(),

    loading: false,

    // Generated the first time "Place Order" is attempted for the current
    // cart, and reused on retries (e.g. a network blip or a slow response
    // the customer taps through again) so a resend can't create a second
    // order. Cleared whenever the cart itself changes or an order
    // succeeds, since that means a genuinely new order is being started.
    clientRequestId: null,
    tracking: { orderId: null, token: null, timer: null, status: null },
    feedbackRating: 0,
    // Set only after returning from the external UPI app. Returning alone
    // never submits an order; the customer must press Place Order.
    pendingUpiReady: false,
    // The UPI query string (pa=...&pn=...&am=... etc, without the scheme)
    // built for the current checkout attempt, reused for whichever app the
    // customer picks in the UPI app picker.
    pendingUpiQuery: '',
  };

  function generateRequestId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
      return window.crypto.randomUUID();
    }
    // Fallback UUID v4 for browsers/contexts without crypto.randomUUID
    // (e.g. non-HTTPS local development).
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function invalidateClientRequestId() {
    state.clientRequestId = null;
    // A cart change invalidates any previous UPI payment attempt because the
    // amount/items may no longer match what was shown in the UPI app.
    state.pendingUpiReady = false;
  }

  /* =========================================================
     HELPERS
     ========================================================= */

  function formatMoney(value) {
    return '₹' + Number(value || 0).toLocaleString('en-IN', {
      maximumFractionDigits: 2,
    });
  }

  let slowHintTimer = null;

  function startSlowHintTimer() {
    clearSlowHintTimer();
    if (!els.loadingSlowHint) return;
    slowHintTimer = window.setTimeout(() => {
      els.loadingSlowHint.classList.remove('hidden');
    }, 6000);
  }

  function clearSlowHintTimer() {
    if (slowHintTimer) {
      window.clearTimeout(slowHintTimer);
      slowHintTimer = null;
    }
    if (els.loadingSlowHint) els.loadingSlowHint.classList.add('hidden');
  }

  function showState(name) {
    if (name !== 'loadingState') {
      clearSlowHintTimer();
    }

    [
      'loadingState',
      'errorState',
      'successState',
      'app',
    ].forEach((key) => {
      if (!els[key]) return;

      els[key].classList.toggle(
        'hidden',
        key !== name
      );
    });
  }

  function showFatalError(title, message) {
    els.errorTitle.textContent = title;
    els.errorMessage.textContent = message;
    showState('errorState');
  }

  async function apiRequest(path, options = {}) {
    if (
      !API_BASE_URL ||
      API_BASE_URL.includes('your-deployed-api-domain.com')
    ) {
      throw new Error(
        'Cafe menu is not configured correctly.'
      );
    }

    if (!API_BASE_URL_VERIFIED) {
      throw new Error(
        'This menu has not been confirmed to be connected to the ' +
        'right server yet. Please ask staff, or see the instructions ' +
        'in config.js.'
      );
    }

    let response;
    const controller = new AbortController();
    const timeoutId = window.setTimeout(() => controller.abort(), 15000);

    try {
      response = await fetch(
        API_BASE_URL + path,
        {
          headers: {
            'Content-Type': 'application/json',
          },
          ...options,
          signal: controller.signal,
        }
      );
    } catch (error) {
      if (error?.name === 'AbortError') {
        throw new Error(
          'Cafe server took too long to respond. Please try again.'
        );
      }
      throw new Error(
        'Network error. Please check your internet connection.'
      );
    } finally {
      window.clearTimeout(timeoutId);
    }

    let body;

    try {
      body = await response.json();
    } catch {
      throw new Error(
        'Cafe server returned an invalid response.'
      );
    }

    if (!response.ok || !body.success) {
      throw new Error(
        body?.message ||
        'Something went wrong. Please try again.'
      );
    }

    return body;
  }

  function getTableNumberFromUrl() {
    const params = new URLSearchParams(
      window.location.search
    );

    const raw = params.get('table');

    const number = Number(raw);

    if (
      !raw ||
      !Number.isInteger(number) ||
      number < 1
    ) {
      return null;
    }

    return number;
  }

  /* =========================================================
     RETURNING CUSTOMER — RESTORE A PENDING ORDER
     ========================================================= */

  const PENDING_ORDER_KEY = 'fnf_last_order';
  const PENDING_UPI_KEY = 'fnf_pending_upi_payment';

  function clearPendingOrder() {
    try {
      localStorage.removeItem(PENDING_ORDER_KEY);
    } catch (_) {}
  }

  function readPendingOrder() {
    try {
      const raw = localStorage.getItem(PENDING_ORDER_KEY);
      if (!raw) return null;

      const parsed = JSON.parse(raw);

      if (!parsed || !parsed.orderId || !parsed.token) {
        return null;
      }

      return parsed;
    } catch (_) {
      return null;
    }
  }

  function renderOrderItems(items) {
    if (!els.successItems) return;

    els.successItems.innerHTML = '';

    (items || []).forEach((item) => {
      const row = document.createElement('div');
      row.className = 'success-item-row';

      const nameWrap = document.createElement('span');
      nameWrap.className = 'success-item-name';

      const qty = document.createElement('span');
      qty.className = 'success-item-qty';
      qty.textContent = `${item.quantity}× `;

      nameWrap.appendChild(qty);
      nameWrap.appendChild(
        document.createTextNode(item.name || '')
      );

      const price = document.createElement('span');
      price.className = 'success-item-price';

      const lineTotal =
        item.total != null
          ? item.total
          : (item.price || 0) * (item.quantity || 1);

      price.textContent = formatMoney(lineTotal);

      row.appendChild(nameWrap);
      row.appendChild(price);

      els.successItems.appendChild(row);
    });
  }

  // If the customer closes the tab (or the page reloads) after ordering,
  // this restores their order tracking view instead of dropping them back
  // into an empty menu with no memory of what they ordered.
  async function tryRestorePendingOrder() {
    const pending = readPendingOrder();
    if (!pending) return false;

    try {
      const response = await apiRequest(
        `/public/orders/${encodeURIComponent(pending.orderId)}/status?token=${encodeURIComponent(pending.token)}`
      );

      const data = response.data || {};

      if (data.status === 'voided') {
        clearPendingOrder();
        return false;
      }

      if (els.successHeading) {
        els.successHeading.textContent = 'Welcome back!';
      }

      if (els.successSubtext) {
        els.successSubtext.textContent =
          "Here's your order from this table.";
      }

      els.successTable.textContent =
        data.tableName || `Table ${data.tableNumber}`;

      els.successOrderNumber.textContent =
        `#${data.orderNumber}`;

      els.successTotal.textContent =
        formatMoney(data.total);

      renderOrderItems(data.items);

      state.feedbackRating = 0;
      els.feedbackBox.classList.add('hidden');
      els.feedbackMessage.textContent = '';

      startOrderTracking(
        pending.orderId,
        pending.token,
        data.status
      );

      showState('successState');

      return true;
    } catch (_) {
      clearPendingOrder();
      return false;
    }
  }

  /* =========================================================
     INITIAL LOAD
     ========================================================= */

  async function init() {
    showState('loadingState');

    const tableNumber =
      getTableNumberFromUrl();

    if (!tableNumber) {
      showFatalError(
        'Table not found',
        'Please scan the QR code placed on your table.'
      );
      return;
    }

    startSlowHintTimer();

    try {
      const tableResponse =
        await apiRequest(
          `/public/tables/${tableNumber}`
        );

      state.tableNumber =
        tableResponse.data.tableNumber;

      state.tableName =
        tableResponse.data.tableName;

      const [menuResponse, paymentResponse] = await Promise.all([
        apiRequest('/public/menu'),
        apiRequest('/public/payment-options'),
      ]);

      state.categories =
        menuResponse.categories || [];

      state.items =
        menuResponse.items || [];

      state.paymentOptions = paymentResponse.data || state.paymentOptions;
      const configuredUpiId = String(state.paymentOptions.upiId || '').trim();
      const onlineUpiEnabled = Boolean(state.paymentOptions.onlineUpi || configuredUpiId);
      state.paymentOptions.upiId = configuredUpiId;
      state.paymentOptions.onlineUpi = onlineUpiEnabled;
      if (els.onlinePaymentOption) {
        els.onlinePaymentOption.style.display = onlineUpiEnabled ? 'flex' : 'none';
      }
      updatePaymentActions();

      renderApp();

      // Always show the menu first. An old/stale order-status request must
      // never block the customer from seeing the menu.
      showState('app');
      setTimeout(maybeResumePendingUpiPayment, 350);

      const restored = await tryRestorePendingOrder();
      if (restored) return;
    } catch (error) {
      showFatalError(
        'Unable to load menu',
        error.message ||
          'Please try again or ask a staff member for help.'
      );
    }
  }

  /* =========================================================
     MAIN APP
     ========================================================= */

  function renderApp() {
    renderTable();
    renderCategories();
    renderProducts();
    updateCartBar();
  }

  function renderTable() {
    const tableNumber =
      state.tableName
        ? state.tableName.replace(
            /^Table\s*/i,
            ''
          )
        : state.tableNumber;

    els.tableBadge.textContent =
      `Table ${tableNumber}`;
  }

  /* =========================================================
     CATEGORIES
     ========================================================= */

  function renderCategories() {
    els.categoryChips.innerHTML = '';

    els.categoryChips.appendChild(
      createCategoryButton(
        'All',
        'all'
      )
    );

    state.categories.forEach(
      (category) => {
        els.categoryChips.appendChild(
          createCategoryButton(
            category.name,
            category._id
          )
        );
      }
    );
  }

  function createCategoryButton(
    label,
    value
  ) {
    const button =
      document.createElement('button');

    button.type = 'button';

    button.className =
      'chip' +
      (
        state.activeCategory === value
          ? ' active'
          : ''
      );

    button.textContent = label;

    button.addEventListener(
      'click',
      () => {
        state.activeCategory = value;

        renderCategories();
        renderProducts();
      }
    );

    return button;
  }

  /* =========================================================
     SEARCH
     ========================================================= */

  function getFilteredItems() {
    const query =
      state.searchQuery
        .trim()
        .toLowerCase();

    return state.items.filter(
      (item) => {
        const categoryMatch =
          state.activeCategory === 'all' ||
          item.category ===
            state.activeCategory;

        if (!categoryMatch) {
          return false;
        }

        if (!query) {
          return true;
        }

        const name =
          String(item.name || '')
            .toLowerCase();

        const category =
          String(item.categoryName || '')
            .toLowerCase();

        return (
          name.includes(query) ||
          category.includes(query)
        );
      }
    );
  }

  function updateSearchUI() {
    const hasSearch =
      state.searchQuery.trim().length > 0;

    els.clearSearch.classList.toggle(
      'hidden',
      !hasSearch
    );
  }

  /* =========================================================
     PRODUCTS
     ========================================================= */

  function renderProducts() {
    els.productList.innerHTML = '';

    const filteredItems =
      getFilteredItems();

    if (filteredItems.length === 0) {
      els.productList.classList.add(
        'hidden'
      );

      els.searchEmpty.classList.remove(
        'hidden'
      );

      return;
    }

    els.productList.classList.remove(
      'hidden'
    );

    els.searchEmpty.classList.add(
      'hidden'
    );

    const grouped =
      new Map();

    filteredItems.forEach(
      (item) => {
        const categoryName =
          item.categoryName ||
          'Other';

        if (!grouped.has(categoryName)) {
          grouped.set(
            categoryName,
            []
          );
        }

        grouped
          .get(categoryName)
          .push(item);
      }
    );

    grouped.forEach(
      (products, categoryName) => {
        const heading =
          document.createElement('div');

        heading.className =
          'category-heading';

        heading.textContent =
          categoryName;

        els.productList.appendChild(
          heading
        );

        products.forEach(
          (product) => {
            els.productList.appendChild(
              renderProductCard(product)
            );
          }
        );
      }
    );
  }

  function renderProductCard(item) {
    const card =
      document.createElement('div');

    card.className =
      'product-card';

    /* IMAGE */

    if (item.image) {
      const image =
        document.createElement('img');

      image.className =
        'product-image';

      image.loading = 'lazy';

      image.alt =
        item.name || 'Food';

      image.src =
        item.image.startsWith('http')
          ? item.image
          : ASSET_HOST + item.image;

      image.onerror = () => {
        image.style.display = 'none';
      };

      card.appendChild(image);
    } else {
      const placeholder =
        document.createElement('div');

      placeholder.className =
        'product-image placeholder';

      placeholder.textContent =
        String(item.name || 'Food')
          .slice(0, 2)
          .toUpperCase();

      card.appendChild(
        placeholder
      );
    }

    /* INFO */

    const info =
      document.createElement('div');

    info.className =
      'product-info';

    const name =
      document.createElement('div');

    name.className =
      'product-name';

    name.textContent =
      item.name;

    info.appendChild(name);

    if (item.available) {
      const price =
        document.createElement('div');

      price.className =
        'product-price';

      price.textContent =
        formatMoney(item.price);

      info.appendChild(price);
    } else {
      const unavailable =
        document.createElement('div');

      unavailable.className =
        'product-unavailable';

      unavailable.textContent =
        'Currently unavailable';

      info.appendChild(
        unavailable
      );
    }

    card.appendChild(info);

    /* ACTION */

    const action =
      document.createElement('div');

    action.className =
      'product-action';

    action.appendChild(
      renderQuantityControl(item)
    );

    card.appendChild(action);

    return card;
  }

  /* =========================================================
     QUANTITY
     ========================================================= */

  function renderQuantityControl(item) {
    const wrapper =
      document.createElement('div');

    const existing =
      state.cart.get(item._id);

    const quantity =
      existing
        ? existing.quantity
        : 0;

    if (!item.available) {
      const button =
        document.createElement('button');

      button.type = 'button';

      button.className =
        'add-btn';

      button.textContent =
        'Unavailable';

      button.disabled = true;

      wrapper.appendChild(button);

      return wrapper;
    }

    if (quantity === 0) {
      const button =
        document.createElement('button');

      button.type = 'button';

      button.className =
        'add-btn';

      button.textContent =
        'Add';

      button.addEventListener(
        'click',
        () => {
          state.cart.set(
            item._id,
            {
              product: item,
              quantity: 1,
            }
          );

          invalidateClientRequestId();
          renderProducts();
          updateCartBar();
        }
      );

      wrapper.appendChild(button);

      return wrapper;
    }

    const stepper =
      document.createElement('div');

    stepper.className =
      'qty-stepper';

    /* MINUS */

    const minus =
      document.createElement('button');

    minus.type = 'button';

    minus.textContent = '−';

    minus.setAttribute(
      'aria-label',
      `Remove one ${item.name}`
    );

    minus.addEventListener(
      'click',
      () => {
        const line =
          state.cart.get(item._id);

        if (!line) return;

        if (line.quantity <= 1) {
          state.cart.delete(
            item._id
          );
        } else {
          line.quantity -= 1;
        }

        invalidateClientRequestId();
        renderProducts();
        updateCartBar();

        if (
          !els.cartOverlay.classList.contains(
            'hidden'
          )
        ) {
          renderCart();
        }
      }
    );

    /* COUNT */

    const count =
      document.createElement('span');

    count.textContent =
      String(quantity);

    /* PLUS */

    const plus =
      document.createElement('button');

    plus.type = 'button';

    plus.textContent = '+';

    plus.setAttribute(
      'aria-label',
      `Add one more ${item.name}`
    );

    plus.addEventListener(
      'click',
      () => {
        const line =
          state.cart.get(item._id);

        if (!line) return;

        if (line.quantity >= 50) {
          return;
        }

        line.quantity += 1;

        invalidateClientRequestId();
        renderProducts();
        updateCartBar();

        if (
          !els.cartOverlay.classList.contains(
            'hidden'
          )
        ) {
          renderCart();
        }
      }
    );

    stepper.appendChild(minus);
    stepper.appendChild(count);
    stepper.appendChild(plus);

    wrapper.appendChild(stepper);

    return wrapper;
  }

  /* =========================================================
     CART
     ========================================================= */

  function getCartSummary() {
    let total = 0;
    let count = 0;

    state.cart.forEach(
      (line) => {
        total +=
          Number(line.product.price || 0) *
          line.quantity;

        count +=
          line.quantity;
      }
    );

    return {
      total,
      count,
    };
  }

  function updateCartBar() {
    const {
      total,
      count,
    } = getCartSummary();

    els.cartBar.classList.toggle(
      'hidden',
      count === 0
    );

    els.cartCount.textContent =
      count === 1
        ? '1 item'
        : `${count} items`;

    els.cartBarTotal.textContent =
      formatMoney(total);
  }

  function renderCart() {
    els.cartLines.innerHTML = '';
    updatePaymentActions();

    const {
      total,
      count,
    } = getCartSummary();

    els.cartItemCount.textContent =
      String(count);

    els.cartTotal.textContent =
      formatMoney(total);

    if (count === 0) {
      const empty =
        document.createElement('div');

      empty.className =
        'cart-empty';

      empty.textContent =
        'Your cart is empty.';

      els.cartLines.appendChild(
        empty
      );

      return;
    }

    state.cart.forEach(
      (line) => {
        const row =
          document.createElement('div');

        row.className =
          'cart-line';

        const left =
          document.createElement('div');

        left.className =
          'cart-line-left';

        const name =
          document.createElement('div');

        name.className =
          'cart-line-name';

        name.textContent =
          line.product.name;

        const price =
          document.createElement('div');

        price.className =
          'cart-line-price';

        price.textContent =
          `${formatMoney(
            line.product.price
          )} × ${line.quantity}`;

        const lineTotal =
          document.createElement('div');

        lineTotal.className =
          'cart-line-total';

        lineTotal.textContent =
          formatMoney(
            line.product.price *
            line.quantity
          );

        left.appendChild(name);
        left.appendChild(price);
        left.appendChild(lineTotal);

        const right =
          document.createElement('div');

        right.appendChild(
          renderQuantityControl(
            line.product
          )
        );

        row.appendChild(left);
        row.appendChild(right);

        els.cartLines.appendChild(
          row
        );
      }
    );
    updatePaymentActions();
  }

  /* =========================================================
     CART OPEN / CLOSE
     ========================================================= */

  function openCart() {
    if (state.cart.size === 0) {
      return;
    }

    renderCart();

    els.checkoutError.classList.add(
      'hidden'
    );

    els.cartOverlay.classList.remove(
      'hidden'
    );

    document.body.style.overflow =
      'hidden';
  }

  function closeCart() {
    els.cartOverlay.classList.add(
      'hidden'
    );

    document.body.style.overflow =
      '';
  }

  /* =========================================================
     PLACE ORDER
     ========================================================= */

  async function placeOrder() {
    if (state.cart.size === 0) return;

    const customerName = els.customerName.value.trim();
    const customerPhone = els.customerPhone.value.trim();

    if (!customerName && !customerPhone) {
      els.checkoutError.textContent = 'Please enter your name or phone number before placing the order.';
      els.checkoutError.classList.remove('hidden');
      els.customerName.focus();
      return;
    }
    if (customerPhone && !/^[0-9+\-\s]{6,20}$/.test(customerPhone)) {
      els.checkoutError.textContent = 'Please enter a valid phone number.';
      els.checkoutError.classList.remove('hidden');
      els.customerPhone.focus();
      return;
    }

    const { total } = getCartSummary();
    if (total <= 0) return;

    els.checkoutError.classList.add('hidden');
    const selectedPayment = document.querySelector('input[name="paymentMethod"]:checked');
    const paymentMethod = selectedPayment?.value === 'upi' ? 'UPI' : 'CASH';

    if (paymentMethod === 'UPI' && !state.paymentOptions.upiId) {
      els.checkoutError.textContent = 'Online UPI payment is not configured right now. Please choose Pay at Counter.';
      els.checkoutError.classList.remove('hidden');
      return;
    }

    if (!state.clientRequestId) state.clientRequestId = generateRequestId();

    const items = Array.from(state.cart.values()).map((line) => ({
      productId: line.product._id,
      quantity: line.quantity,
    }));

    const payload = {
      tableNumber: state.tableNumber,
      customerName: customerName || undefined,
      customerPhone: customerPhone || undefined,
      note: els.orderNote.value.trim() || undefined,
      items,
      paymentMethod,
    upiReference: paymentMethod === 'UPI' ? els.upiReferenceInput.value.trim() : '',
      clientRequestId: state.clientRequestId,
    };

    if (paymentMethod === 'UPI' && !state.pendingUpiReady) {
      // The main Place Order button also starts UPI checkout. This keeps the
      // customer flow simple: select UPI -> tap Place Order -> choose a UPI app.
      await startUpiPayment();
      return;
    }

    if (paymentMethod === 'UPI' && !els.upiReferenceInput.value.trim()) {
      els.checkoutError.textContent = 'Enter the UPI reference / UTR after successful payment.';
      els.checkoutError.classList.remove('hidden');
      els.upiReferenceInput.focus();
      return;
    }

    els.placeOrderBtn.disabled = true;
    els.placeOrderBtn.textContent = 'Placing order...';
    await submitCreatedOrder(payload);
    els.placeOrderBtn.disabled = false;
    els.placeOrderBtn.textContent = 'Place Order';
  }


  async function startUpiPayment() {
    if (state.cart.size === 0) return;

    const customerName = els.customerName.value.trim();
    const customerPhone = els.customerPhone.value.trim();

    if (!customerName && !customerPhone) {
      els.checkoutError.textContent = 'Please enter your name or phone number before paying.';
      els.checkoutError.classList.remove('hidden');
      els.customerName.focus();
      return;
    }
    if (customerPhone && !/^[0-9+\-\s]{6,20}$/.test(customerPhone)) {
      els.checkoutError.textContent = 'Please enter a valid phone number.';
      els.checkoutError.classList.remove('hidden');
      els.customerPhone.focus();
      return;
    }
    const upiId = String(state.paymentOptions.upiId || '').trim();
    if (!upiId) {
      els.checkoutError.textContent = 'Online UPI payment is not configured right now. Please choose Pay at Counter.';
      els.checkoutError.classList.remove('hidden');
      return;
    }

    const { total } = getCartSummary();
    if (total <= 0) return;

    if (!state.clientRequestId) state.clientRequestId = generateRequestId();

    const payload = {
      tableNumber: state.tableNumber,
      customerName: customerName || undefined,
      customerPhone: customerPhone || undefined,
      note: els.orderNote.value.trim() || undefined,
      items: Array.from(state.cart.values()).map((line) => ({
        productId: line.product._id,
        quantity: line.quantity,
      })),
      paymentMethod: 'UPI',
      clientRequestId: state.clientRequestId,
    };

    state.pendingUpiReady = false;
    if (els.upiReferenceInput) els.upiReferenceInput.value = '';
    if (els.upiReferenceGroup) els.upiReferenceGroup.classList.add('hidden');
    try {
      localStorage.setItem(PENDING_UPI_KEY, JSON.stringify({
        payload,
        cartItems: Array.from(state.cart.values()).map((line) => ({
          product: line.product,
          quantity: line.quantity,
        })),
      }));
    } catch (_) {}

    // Build the standard UPI query string. `tr` ties the payment attempt to
    // this cart/order request while the UTR entered after payment remains
    // the actual proof recorded with the order. This same query string is
    // reused for whichever specific app the customer picks below.
    state.pendingUpiQuery = [
      `pa=${encodeURIComponent(upiId)}`,
      `pn=${encodeURIComponent(state.paymentOptions.cafeName || 'FAST N FRESH CAFE')}`,
      `am=${encodeURIComponent(total.toFixed(2))}`,
      'cu=INR',
      `tr=${encodeURIComponent(state.clientRequestId)}`,
      `tn=${encodeURIComponent(`Order for Table ${state.tableNumber}`)}`,
      'mode=02',
      'purpose=00',
    ].join('&');

    // Let the customer pick which UPI app to pay with instead of guessing;
    // the actual app launch happens in launchUpiApp() once they choose.
    openUpiAppPicker();

    // External UPI navigation never creates the order. The customer must
    // return and explicitly press Place Order after entering the UTR.
  }

  // Scheme prefixes for each UPI app option. "other" uses the generic
  // upi://pay scheme, which on Android hands off to the OS chooser for any
  // installed UPI app not listed explicitly above.
  const UPI_APP_SCHEMES = {
    gpay: 'tez://upi/pay',
    phonepe: 'phonepe://pay',
    paytm: 'paytmmp://pay',
    bhim: 'bhim://pay',
    other: 'upi://pay',
  };

  function openUpiAppPicker() {
    if (!els.upiAppOverlay) return;
    els.upiAppOverlay.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
  }

  function closeUpiAppPicker() {
    if (!els.upiAppOverlay) return;
    els.upiAppOverlay.classList.add('hidden');
    document.body.style.overflow = '';
  }

  function launchUpiApp(appKey) {
    const scheme = UPI_APP_SCHEMES[appKey] || UPI_APP_SCHEMES.other;
    if (!state.pendingUpiQuery) return;
    const upiUrl = `${scheme}?${state.pendingUpiQuery}`;

    // Use a real user-gesture anchor instead of assigning window.location.
    // This is more reliable in Android Chrome/PWA browsers for handing the
    // UPI URI to installed apps such as GPay, PhonePe and Paytm.
    const upiLink = document.createElement('a');
    upiLink.href = upiUrl;
    upiLink.setAttribute('aria-hidden', 'true');
    upiLink.style.display = 'none';
    document.body.appendChild(upiLink);
    upiLink.click();
    window.setTimeout(() => upiLink.remove(), 1500);

    closeUpiAppPicker();
  }

  async function submitCreatedOrder(payload) {
    try {
      const response = await apiRequest('/public/orders', {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      state.cart.clear();
      invalidateClientRequestId();
      try { localStorage.removeItem(PENDING_UPI_KEY); } catch (_) {}

      closeCart();
      updateCartBar();

      if (els.successHeading) els.successHeading.textContent = 'Order placed!';
      if (els.successSubtext) els.successSubtext.textContent = 'Your order has been sent to the cafe.';
      els.successTable.textContent = response.data.tableName || `Table ${response.data.tableNumber}`;
      els.successOrderNumber.textContent = `#${response.data.orderNumber}`;
      els.successTotal.textContent = formatMoney(response.data.total);
      if (typeof renderOrderItems === 'function') renderOrderItems(response.data.items);

      if (true) {
        state.tracking.orderId = response.data.orderId;
        state.tracking.token = response.data.trackingToken;
        state.feedbackRating = 0;
        els.feedbackBox.classList.add('hidden');
        els.feedbackMessage.textContent = '';
        startOrderTracking(response.data.orderId, response.data.trackingToken, response.data.status);
        try { localStorage.setItem(PENDING_ORDER_KEY, JSON.stringify({ orderId: response.data.orderId, token: response.data.trackingToken, orderNumber: response.data.orderNumber })); } catch (_) {}
      }

      showState('successState');
      return true;
    } catch (error) {
      els.checkoutError.textContent = error.message || 'Order failed. Please try again.';
      els.checkoutError.classList.remove('hidden');
      return false;
    }
  }

  function restorePendingUpiCart(draft) {
    if (state.cart.size > 0 || !Array.isArray(draft.cartItems)) return;
    const availableById = new Map((state.items || []).map((item) => [String(item._id), item]));
    draft.cartItems.forEach((saved) => {
      const product = availableById.get(String(saved.product?._id || saved.product?.id || '')) || saved.product;
      const quantity = Number(saved.quantity);
      if (product && Number.isInteger(quantity) && quantity > 0) {
        state.cart.set(product._id, { product, quantity });
      }
    });
    renderProducts();
    updateCartBar();
  }

  let upiResumeBusy = false;

  async function maybeResumePendingUpiPayment() {
    if (upiResumeBusy) return;
    let hasPending = false;
    try { hasPending = !!localStorage.getItem(PENDING_UPI_KEY); } catch (_) {}
    if (!hasPending) return;
    upiResumeBusy = true;
    try { await resumePendingUpiPayment(); } finally { upiResumeBusy = false; }
  }

  async function resumePendingUpiPayment() {
    let draft = null;
    try {
      const raw = localStorage.getItem(PENDING_UPI_KEY);
      if (raw) draft = JSON.parse(raw);
    } catch (_) {}
    if (!draft || !draft.payload) return;
    restorePendingUpiCart(draft);

    // Returning from UPI is NOT proof of payment. Never submit the order or
    // mark it paid here. Restore checkout and require explicit Place Order.
    state.pendingUpiReady = true;
    if (els.upiReferenceGroup) els.upiReferenceGroup.classList.remove('hidden');
    if (els.placeOrderBtn) els.placeOrderBtn.textContent = 'Place Order';
    els.checkoutError.textContent = 'Returned from UPI. If you completed the payment, press “Place Order” to submit your order. If you cancelled, you can simply change the payment method or close checkout.';
    els.checkoutError.classList.remove('hidden');
    openCart();
  }

  function updatePaymentActions() {
    const selected = document.querySelector('input[name="paymentMethod"]:checked');
    const isUpi = selected?.value === 'upi';
    if (els.payUpiBtn) {
      els.payUpiBtn.classList.toggle('hidden', !isUpi);
      els.payUpiBtn.disabled = state.cart.size === 0 || (isUpi && state.pendingUpiReady);
      els.payUpiBtn.textContent = state.pendingUpiReady ? 'UPI PAYMENT STARTED' : 'PAY WITH UPI';
    }
    if (els.upiReferenceGroup) {
      els.upiReferenceGroup.classList.toggle('hidden', !isUpi || !state.pendingUpiReady);
    }
    if (els.placeOrderBtn) {
      els.placeOrderBtn.textContent = isUpi
        ? (state.pendingUpiReady ? 'PLACE ORDER' : 'PLACE ORDER AFTER UPI')
        : 'PLACE ORDER';
    }
  }

  /* =========================================================
     CUSTOMER ORDER TRACKING
     ========================================================= */

  function stopOrderTracking() {
    if (state.tracking.timer) {
      window.clearInterval(state.tracking.timer);
      state.tracking.timer = null;
    }
  }

  function orderStatusLabel(status) {
    switch (status) {
      case 'preparing': return 'Preparing your order';
      case 'ready': return 'Your order is ready';
      case 'completed': return 'Order completed';
      case 'voided': return 'Order cancelled';
      default: return 'Order received';
    }
  }

  function renderOrderStatus(status) {
    if (!els.successStatus || !els.successStatusText) return;
    const safe = status || 'open';
    els.successStatus.className = `order-status-card status-${safe}`;
    els.successStatusText.textContent = orderStatusLabel(safe);
  }

  async function refreshOrderStatus() {
    if (!state.tracking.orderId || !state.tracking.token) return;
    try {
      const response = await apiRequest(
        `/public/orders/${encodeURIComponent(state.tracking.orderId)}/status?token=${encodeURIComponent(state.tracking.token)}`
      );
      const data = response.data || {};
      state.tracking.status = data.status || 'open';
      renderOrderStatus(state.tracking.status);

      if (state.tracking.status === 'completed' || state.tracking.status === 'voided') {
        stopOrderTracking();
        if (state.tracking.status === 'completed' && els.feedbackBox) els.feedbackBox.classList.remove('hidden');
      }
    } catch (_) {
      // Tracking is best-effort; keep the last known status visible.
    }
  }

  function startOrderTracking(orderId, token, status) {
    stopOrderTracking();
    state.tracking.orderId = orderId || null;
    state.tracking.token = token || null;
    state.tracking.status = status || 'open';
    renderOrderStatus(state.tracking.status);
    if (!state.tracking.orderId || !state.tracking.token) return;
    state.tracking.timer = window.setInterval(refreshOrderStatus, 8000);
  }

  /* =========================================================
     EVENTS
     ========================================================= */

  els.cartBar.addEventListener(
    'click',
    openCart
  );

  els.closeCart.addEventListener(
    'click',
    closeCart
  );

  els.cartOverlay.addEventListener(
    'click',
    (event) => {
      if (
        event.target ===
        els.cartOverlay
      ) {
        closeCart();
      }
    }
  );

  els.placeOrderBtn.addEventListener(
    'click',
    placeOrder
  );

  if (els.payUpiBtn) {
    els.payUpiBtn.addEventListener('click', startUpiPayment);
  }

  if (els.closeUpiAppOverlay) {
    els.closeUpiAppOverlay.addEventListener('click', closeUpiAppPicker);
  }

  if (els.upiAppOverlay) {
    els.upiAppOverlay.addEventListener('click', (event) => {
      if (event.target === els.upiAppOverlay) closeUpiAppPicker();
    });
  }

  if (els.upiAppGrid) {
    els.upiAppGrid.addEventListener('click', (event) => {
      const button = event.target.closest('[data-upi-app]');
      if (!button) return;
      launchUpiApp(button.getAttribute('data-upi-app'));
    });
  }

  document.querySelectorAll('input[name="paymentMethod"]').forEach((input) => {
    input.addEventListener('change', () => {
      state.pendingUpiReady = false;
      updatePaymentActions();
    });
  });

  if (els.feedbackStars) {
    els.feedbackStars.querySelectorAll('button').forEach((button) => {
      button.addEventListener('click', () => {
        state.feedbackRating = Number(button.dataset.rating || 0);
        els.feedbackStars.querySelectorAll('button').forEach((b) => b.classList.toggle('selected', Number(b.dataset.rating || 0) <= state.feedbackRating));
      });
    });
  }

  if (els.submitFeedbackBtn) {
    els.submitFeedbackBtn.addEventListener('click', async () => {
      if (!state.tracking.orderId || !state.tracking.token || !state.feedbackRating) {
        els.feedbackMessage.textContent = 'Please select a rating first.';
        return;
      }
      els.submitFeedbackBtn.disabled = true;
      try {
        await apiRequest('/feedback', { method: 'POST', body: JSON.stringify({ orderId: state.tracking.orderId, token: state.tracking.token, rating: state.feedbackRating, comment: els.feedbackComment.value.trim(), customerName: els.customerName?.value?.trim() || '' }) });
        els.feedbackMessage.textContent = 'Thanks! Your feedback was received.';
        els.submitFeedbackBtn.textContent = 'Feedback Sent';
      } catch (error) { els.feedbackMessage.textContent = error.message || 'Could not send feedback.'; }
      finally { els.submitFeedbackBtn.disabled = false; }
    });
  }

  /* SEARCH */

  els.searchInput.addEventListener(
    'input',
    () => {
      state.searchQuery =
        els.searchInput.value;

      updateSearchUI();
      renderProducts();
    }
  );

  function clearSearch() {
    els.searchInput.value = '';

    state.searchQuery = '';

    updateSearchUI();
    renderProducts();

    els.searchInput.focus();
  }

  els.clearSearch.addEventListener(
    'click',
    clearSearch
  );

  els.clearSearchBtn.addEventListener(
    'click',
    clearSearch
  );

  /* RETRY */

  els.retryBtn.addEventListener(
    'click',
    () => {
      init();
    }
  );

  /* DONE */

  els.doneBtn.addEventListener(
    'click',
    () => {
      stopOrderTracking();
      state.tracking.orderId = null;
      state.tracking.token = null;
      clearPendingOrder();
      window.location.reload();
    }
  );

  /* ESC */

  document.addEventListener(
    'keydown',
    (event) => {
      if (
        event.key === 'Escape' &&
        !els.cartOverlay.classList.contains(
          'hidden'
        )
      ) {
        closeCart();
      }
    }
  );

  window.addEventListener('pageshow', () => {
    setTimeout(maybeResumePendingUpiPayment, 350);
  });

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      setTimeout(maybeResumePendingUpiPayment, 350);
    }
  });

  /* START */

  init();
})();