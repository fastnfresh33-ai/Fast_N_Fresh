(function () {
  'use strict';

  const API_BASE_URL =
    (window.FNF_CONFIG && window.FNF_CONFIG.API_BASE_URL) || '';

  const ASSET_HOST = API_BASE_URL.endsWith('/api')
    ? API_BASE_URL.slice(0, -4)
    : API_BASE_URL;

  const els = {
    loadingState: document.getElementById('loadingState'),
    errorState: document.getElementById('errorState'),
    errorTitle: document.getElementById('errorTitle'),
    errorMessage: document.getElementById('errorMessage'),
    retryBtn: document.getElementById('retryBtn'),

    successState: document.getElementById('successState'),
    successTable: document.getElementById('successTable'),
    successOrderNumber: document.getElementById('successOrderNumber'),
    successTotal: document.getElementById('successTotal'),
    doneBtn: document.getElementById('doneBtn'),

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

    checkoutError: document.getElementById('checkoutError'),
    placeOrderBtn: document.getElementById('placeOrderBtn'),
  };

  const state = {
    tableNumber: null,
    tableName: null,

    categories: [],
    items: [],

    activeCategory: 'all',
    searchQuery: '',

    cart: new Map(),

    loading: false,
  };

  /* =========================================================
     HELPERS
     ========================================================= */

  function formatMoney(value) {
    return '₹' + Number(value || 0).toLocaleString('en-IN', {
      maximumFractionDigits: 2,
    });
  }

  function showState(name) {
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

    let response;

    try {
      response = await fetch(
        API_BASE_URL + path,
        {
          headers: {
            'Content-Type': 'application/json',
          },
          ...options,
        }
      );
    } catch (error) {
      throw new Error(
        'Network error. Please check your internet connection.'
      );
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

    try {
      const tableResponse =
        await apiRequest(
          `/public/tables/${tableNumber}`
        );

      state.tableNumber =
        tableResponse.data.tableNumber;

      state.tableName =
        tableResponse.data.tableName;

      const menuResponse =
        await apiRequest('/public/menu');

      state.categories =
        menuResponse.categories || [];

      state.items =
        menuResponse.items || [];

      renderApp();

      showState('app');
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
    if (state.cart.size === 0) {
      return;
    }

    const customerName =
      els.customerName.value.trim();

    if (!customerName) {
      els.checkoutError.textContent =
        'Please enter your name before placing the order.';

      els.checkoutError.classList.remove(
        'hidden'
      );

      els.customerName.focus();

      return;
    }

    const {
      total,
    } = getCartSummary();

    if (total <= 0) {
      return;
    }

    els.checkoutError.classList.add(
      'hidden'
    );

    els.placeOrderBtn.disabled =
      true;

    els.placeOrderBtn.textContent =
      'Placing order...';

    const items =
      Array.from(
        state.cart.values()
      ).map(
        (line) => ({
          productId:
            line.product._id,

          quantity:
            line.quantity,
        })
      );

    const payload = {
      tableNumber:
        state.tableNumber,

      customerName,

      customerPhone:
        els.customerPhone.value.trim() ||
        undefined,

      note:
        els.orderNote.value.trim() ||
        undefined,

      items,
    };

    try {
      const response =
        await apiRequest(
          '/public/orders',
          {
            method: 'POST',

            body:
              JSON.stringify(
                payload
              ),
          }
        );

      state.cart.clear();

      closeCart();

      updateCartBar();

      els.successTable.textContent =
        response.data.tableName ||
        `Table ${response.data.tableNumber}`;

      els.successOrderNumber.textContent =
        `#${response.data.orderNumber}`;

      els.successTotal.textContent =
        formatMoney(
          response.data.total
        );

      showState(
        'successState'
      );
    } catch (error) {
      els.checkoutError.textContent =
        error.message ||
        'Order failed. Please try again.';

      els.checkoutError.classList.remove(
        'hidden'
      );
    } finally {
      els.placeOrderBtn.disabled =
        false;

      els.placeOrderBtn.textContent =
        'Place Order';
    }
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

  /* START */

  init();
})();